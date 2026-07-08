#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$PKG_ROOT/scripts/ensure-local-completion-forwarders.sh"
latest_session_handoff_output() {
  local session_path="$1"
  python3 - "$session_path" <<'PY'
import json
import re
import sys
from pathlib import Path

session_path = Path(sys.argv[1])
if not session_path.exists():
    raise SystemExit(0)
entries = []
with session_path.open('r', encoding='utf-8') as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
for entry in reversed(entries):
    if entry.get('type') != 'message':
        continue
    message = entry.get('message') or {}
    if message.get('role') != 'assistant':
        continue
    content = message.get('content')
    if not isinstance(content, str):
        continue
    matches = re.findall(r"```cook_handoff\s*[\s\S]*?```", content, re.MULTILINE)
    if matches:
        print(matches[-1])
        break
PY
}
pi() {
  local session_path=""
  local prompt=""
  local prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--session" ]]; then
      session_path="$arg"
      prev=""
      continue
    fi
    if [[ "$prev" == "-p" ]]; then
      prompt="$arg"
      prev=""
      continue
    fi
    if [[ "$arg" == "--session" || "$arg" == "-p" ]]; then
      prev="$arg"
    fi
  done
  local -a extra_env=()
  if [[ -z "${PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT:-}" && -n "$session_path" && "$prompt" =~ ^/cook([[:space:]]*)$ ]]; then
    local handoff
    handoff="$(latest_session_handoff_output "$session_path")"
    if [[ -n "$handoff" ]]; then
      extra_env+=("PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT=$handoff")
    fi
  fi
  local -a forwarded_env=()
  while IFS= read -r name; do
    [[ "$name" == "PI_COMPLETION_ROLE" ]] && continue
    forwarded_env+=("$name=${!name}")
  done < <(compgen -v | grep -E '^PI_(COMPLETION|HELPER)_' || true)
  local pi_cmd
  pi_cmd="$(command -v pi)"
  set +u
  env -u PI_COMPLETION_ROLE "${forwarded_env[@]}" "${extra_env[@]}" "$pi_cmd" --no-extensions "$@"
  local status=$?
  set -u
  return $status
}
TMPDIR="$(mktemp -d)"
CURRENT_EVIDENCE_BACKUP=""

write_session() {
  local session_path="$1"
  local cwd="$2"
  local text="$3"
  python3 - "$session_path" "$cwd" "$text" <<'PY'
import json
import sys
from pathlib import Path

session_path = Path(sys.argv[1])
cwd = sys.argv[2]
text = sys.argv[3]
session_path.parent.mkdir(parents=True, exist_ok=True)
entries = [
    {
        "type": "session",
        "version": 3,
        "id": "11111111-1111-4111-8111-111111111111",
        "timestamp": "2026-01-01T00:00:00.000Z",
        "cwd": cwd,
    },
    {
        "type": "message",
        "id": "a1b2c3d4",
        "parentId": None,
        "timestamp": "2026-01-01T00:00:01.000Z",
        "message": {
            "role": "user",
            "content": text,
            "timestamp": 1767225601000,
        },
    },
]
with session_path.open('w', encoding='utf-8') as fh:
    for entry in entries:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

write_session_messages() {
  local session_path="$1"
  local cwd="$2"
  local messages_json="$3"
  python3 - "$session_path" "$cwd" "$messages_json" <<'PY'
import json
import sys
from pathlib import Path

session_path = Path(sys.argv[1])
cwd = sys.argv[2]
messages = json.loads(sys.argv[3])
session_path.parent.mkdir(parents=True, exist_ok=True)
entries = [
    {
        "type": "session",
        "version": 3,
        "id": "11111111-1111-4111-8111-111111111111",
        "timestamp": "2026-01-01T00:00:00.000Z",
        "cwd": cwd,
    },
]
parent_id = None
for index, message in enumerate(messages, start=1):
    entry_id = f"m{index:04d}"
    entries.append({
        "type": "message",
        "id": entry_id,
        "parentId": parent_id,
        "timestamp": f"2026-01-01T00:00:{index:02d}.000Z",
        "message": {
            "role": message["role"],
            "content": message["content"],
            "timestamp": 1767225600000 + index * 1000,
        },
    })
    parent_id = entry_id
with session_path.open('w', encoding='utf-8') as fh:
    for entry in entries:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

cleanup() {
  if [[ -n "$CURRENT_EVIDENCE_BACKUP" && -f "$CURRENT_EVIDENCE_BACKUP" ]]; then
    cp "$CURRENT_EVIDENCE_BACKUP" "$PKG_ROOT/.agent/current/verification-evidence.json"
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

cd "$PKG_ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required canonical-evidence text: ${snippet}`);
  }
};
const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const readSection = (file, heading) => {
  const text = read(file);
  const match = text.match(new RegExp(`^${escapeRegex(heading)}\\s*$\\n([\\s\\S]*?)(?=^##\\s+|\\Z)`, 'm'));
  if (!match) {
    throw new Error(`${file} is missing required section: ${heading}`);
  }
  return match[1];
};
const assertSectionIncludes = (file, heading, snippet) => {
  const section = readSection(file, heading);
  if (!section.includes(snippet)) {
    throw new Error(`${file} section ${heading} is missing required canonical-evidence text: ${snippet}`);
  }
};

assertIncludes('docs/maintainer/protocol.md', '.agent/current/verification-evidence.json');
assertIncludes('docs/maintainer/protocol.md', 'Fresh scaffolds create an idle placeholder');
assertIncludes('docs/maintainer/protocol.md', 'bash scripts/canonical-evidence-artifact-test.sh');
assertIncludes('docs/maintainer/protocol.md', '`evidence_quality`');
assertIncludes('docs/maintainer/protocol.md', '`command_results`');
assertIncludes('docs/maintainer/protocol.md', '`basis_regression_artifact_paths`');
assertIncludes('docs/maintainer/protocol.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('docs/maintainer/protocol.md', 'failed_on_basis');
assertIncludes('docs/maintainer/protocol.md', 'not_run');
assertIncludes('docs/maintainer/protocol.md', 'not_applicable');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Canonical Files', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Canonical Inputs', '- package defaults for task_type, evaluation_profile, and stop policy');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Canonical Inputs', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Structured Verification Evidence', '- `evidence_quality`');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Structured Verification Evidence', '- `command_results`');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Structured Verification Evidence', '- `basis_regression_required`, `basis_regression_status`, `basis_regression_reason`, and `basis_regression_artifact_paths`');
assertIncludes('skills/completion-protocol/SKILL.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('skills/completion-protocol/SKILL.md', 'Do not treat `not_run` or `not_applicable` as implicit passes.');
assertIncludes('skills/completion-protocol/SKILL.md', 'package defaults');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Compaction And Recovery', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/SKILL.md', '## Compaction And Recovery', '`completion-implementer` must also re-read canonical `.agent/current/state.json`, `.agent/current/plan.json`, `.agent/current/active-slice.json`, and `.agent/current/verification-evidence.json` before resuming work.');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Ignored Canonical Execution State', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Canonical Inputs', '- package defaults for task_type, evaluation_profile, and stop policy');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Canonical Inputs', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Structured Verification Evidence', '- `evidence_quality`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Structured Verification Evidence', '- `command_results`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Structured Verification Evidence', '- `basis_regression_required`, `basis_regression_status`, `basis_regression_reason`, and `basis_regression_artifact_paths`');
assertIncludes('skills/completion-protocol/references/completion.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('skills/completion-protocol/references/completion.md', 'Do not treat `not_run` or `not_applicable` as implicit passes.');
assertIncludes('skills/completion-protocol/references/completion.md', 'package defaults plus runtime `.agent/current/state.json`, `.agent/current/plan.json`, and `.agent/current/active-slice.json`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Compaction And Recovery', '- `.agent/current/verification-evidence.json`');
assertSectionIncludes('skills/completion-protocol/references/completion.md', '## Compaction And Recovery', '`completion-implementer` must also re-read canonical `.agent/current/state.json`, `.agent/current/plan.json`, `.agent/current/active-slice.json`, and `.agent/current/verification-evidence.json` before resuming work.');
assertIncludes('agents/completion-implementer.md', '`evidence_quality`');
assertIncludes('agents/completion-implementer.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('agents/completion-implementer.md', '`not_run` or `not_applicable`');
assertIncludes('agents/completion-reviewer.md', '`command_results`');
assertIncludes('agents/completion-reviewer.md', '`not_run`');
assertIncludes('agents/completion-reviewer.md', '`not_applicable`');
assertIncludes('agents/completion-auditor.md', '`command_results`');
assertIncludes('agents/completion-stop-judge.md', '`command_results`');
assertIncludes('helpers/critic.md', '`basis_regression_*`');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Verification evidence artifact: ${args.evidence.path} (${args.evidence.status})');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Verification evidence structured: ${args.evidence.structuredSummary}');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Verification evidence summary: ${args.evidence.summary}');
assertIncludes('extensions/completion/index.ts', 'Canonical verification evidence artifact is currently: ${evidence.path} (${evidence.status})');
assertIncludes('extensions/completion/index.ts', 'Canonical verification evidence structured summary is currently: ${evidence.structuredSummary}');
assertIncludes('extensions/completion/prompt-surfaces.ts', '`- verification_evidence_path: ${evidence.path}`');
assertIncludes('extensions/completion/prompt-surfaces.ts', '`- verification_evidence_focus: read structured evidence fields directly from ${evidence.path}`');
assertIncludes('extensions/completion/prompt-surfaces.ts', '`- verification_evidence_structured: ${evidence.structuredSummary}`');
assertIncludes('extensions/completion/prompt-surfaces.ts', '`- verification_evidence_summary: ${evidence.summary}`');
assertIncludes('extensions/completion/index.ts', 'Consume .agent/current/verification-evidence.json instead of temp-only verification summaries when it is populated.');
assertIncludes('scripts/release-check.sh', 'npm run verify-completion-control-plane');
assertIncludes('scripts/release-check.sh', 'bash ./scripts/basis-regression-proof-test.sh');
assertIncludes('scripts/release-check.sh', 'bash ./scripts/canonical-evidence-artifact-test.sh');
assertIncludes('.agent/verify_completion_control_plane.sh', 'verify-completion-control-plane.js');
assertIncludes('scripts/verify-completion-control-plane.js', '.agent/current/verification-evidence.json');
assertIncludes('scripts/verify-completion-control-plane.js', 'command_results');
assertIncludes('scripts/verify-completion-control-plane.js', 'basis_regression_artifact_paths');
assertIncludes('scripts/verify-completion-control-plane.js', 'basis_regression_status must not be not_applicable when basis_regression_required=true');
assertIncludes('scripts/verify-completion-control-plane.js', 'basis_regression_artifact_paths must not be empty when basis_regression_status records an executed basis check');
assertIncludes('scripts/verify-completion-control-plane.js', 'subject_type must be selected_slice when active slice exact handoff requires verification evidence');
assertIncludes('scripts/verify-completion-stop.sh', 'verify-completion-control-plane.js');
NODE

if [[ -f .agent/current/verification-evidence.json ]]; then
  bash .agent/verify_completion_control_plane.sh >/dev/null

  CURRENT_EVIDENCE_BACKUP="$TMPDIR/current-verification-evidence.json"
  cp .agent/current/verification-evidence.json "$CURRENT_EVIDENCE_BACKUP"

  CURRENT_EVIDENCE_SUBJECT_TYPE="$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('.agent/current/verification-evidence.json').read_text()).get('subject_type', ''))
PY
)"

  python3 - <<'PY'
import json
from pathlib import Path
path = Path('.agent/current/verification-evidence.json')
evidence = json.loads(path.read_text())
evidence['head_sha'] = 'stale-head'
path.write_text(json.dumps(evidence, indent=2) + '\n')
PY

  if [[ "$CURRENT_EVIDENCE_SUBJECT_TYPE" == "selected_slice" ]]; then
    if PI_COMPLETION_SKIP_CANONICAL_EVIDENCE_ARTIFACT_TEST=1 bash ./scripts/release-check.sh >/dev/null 2>&1; then
      echo "expected release-check to fail when current repo verification-evidence.json is stale even when canonical-evidence self-test recursion is disabled" >&2
      exit 1
    fi

    if bash .agent/verify_completion_stop.sh >/dev/null 2>&1; then
      echo "expected verify_completion_stop.sh to fail when current repo verification-evidence.json is stale" >&2
      exit 1
    fi
  fi

  cp "$CURRENT_EVIDENCE_BACKUP" .agent/current/verification-evidence.json
  bash .agent/verify_completion_control_plane.sh >/dev/null
fi

ROOT="$TMPDIR/repo"
SYSTEM_REMINDER="$TMPDIR/system-reminder.txt"
BOOTSTRAP_SESSION="$TMPDIR/session-canonical-evidence-bootstrap.jsonl"
BOOTSTRAP_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Exercise canonical evidence fixture bootstrap.",
    "scope": [
        "Materialize canonical completion files for the evidence artifact fixture.",
        "Keep the verification-evidence bootstrap on the supported explicit-handoff startup path."
    ],
    "constraints": [
        "Use supported bare /cook startup only."
    ],
    "acceptance": [
        "Write the workflow control-plane files under .agent, including profile.json, state.json, active-slice.json, verification-evidence.json, and the slice backlog file, before the fixture rewrites them.",
        "Keep scripts/canonical-evidence-artifact-test.sh aligned with packaged bootstrap behavior."
    ],
    "risks": [
        "Evidence-artifact bootstrap must stay anchored to the fresh explicit handoff."
    ],
    "notes": [
        "This fixture exists only to scaffold canonical files before rewriting them for evidence parity coverage."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Scaffold canonical evidence-artifact fixture files before rewriting them for parity checks.",
    "first_slice_non_goals": [
        "Do not broaden the bootstrap fixture beyond the evidence-artifact surfaces."
    ],
    "implementation_surfaces": [
        ".agent/current/verification-evidence.json",
        "scripts/canonical-evidence-artifact-test.sh"
    ],
    "verification_commands": [
        "bash ./scripts/canonical-evidence-artifact-test.sh"
    ],
    "why_this_slice_first": "The evidence-artifact fixture cannot validate fail-closed parity until canonical files exist.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The fixture bootstrap is concrete enough to create canonical control-plane files."
}
messages = [
    {"role": "user", "content": "Prepare the canonical evidence bootstrap fixture and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "The canonical evidence bootstrap fixture is ready for /cook. Run /cook to confirm it.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
mkdir -p "$ROOT"
cd "$ROOT"
git init -q
write_session_messages "$BOOTSTRAP_SESSION" "$ROOT" "$BOOTSTRAP_MESSAGES"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$BOOTSTRAP_SESSION" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-canonical-evidence-bootstrap.out" 2>"$TMPDIR/pi-canonical-evidence-bootstrap.err"

for file in .agent/current/state.json .agent/current/plan.json .agent/current/active-slice.json .agent/current/verification-evidence.json; do
  [[ -f "$file" ]] || { echo "missing canonical bootstrap file: $file" >&2; exit 1; }
done

bash .agent/verify_completion_control_plane.sh >/dev/null
PI_COMPLETION_RUNNING_RELEASE_CHECK=1 bash .agent/verify_completion_stop.sh >/dev/null

python3 - <<'PY'
import json
from pathlib import Path

evidence = json.loads(Path('.agent/current/verification-evidence.json').read_text())
assert evidence['artifact_type'] == 'completion-verification-evidence', evidence
assert evidence['subject_type'] == 'none', evidence
assert evidence['verification_commands'] == [], evidence
assert evidence['outcome'] == 'not_recorded', evidence
assert evidence['recorded_at'] is None, evidence
assert evidence['head_sha'] is None, evidence
assert evidence['evidence_quality']['status'] == 'not_recorded', evidence
assert evidence['command_results'] == [], evidence
assert evidence['acceptance_coverage'] == [], evidence
assert evidence['flake_signals'] == [], evidence
assert evidence['open_gaps'] == [], evidence
assert evidence['basis_regression_required'] is False, evidence
assert evidence['basis_regression_status'] == 'not_applicable', evidence
PY

git add .
git -c user.name='Test' -c user.email='test@example.com' commit -qm 'bootstrap fixture'
HEAD_SHA="$(git rev-parse HEAD)"

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
mission = 'Exercise canonical verification evidence parity.'
task_type = 'completion-workflow'
evaluation_profile = 'completion-rubric-v1'
verification_commands = [
    'bash .agent/verify_completion_control_plane.sh',
    'bash .agent/verify_completion_stop.sh',
]
implementation_surfaces = [
    '.agent/current/verification-evidence.json',
    '.agent/verify_completion_control_plane.sh',
    '.agent/verify_completion_stop.sh',
]
acceptance = [
    'Canonical verification evidence is recorded for the selected slice.',
    'Fail-closed verification rejects missing or stale evidence.',
]
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-05-03T00:00:00Z',
    'workflow_session_id': 'evidence-fixture-session',
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': 'implement',
    'continuation_policy': 'continue',
    'continuation_reason': 'Fixture for canonical evidence artifact regression coverage.',
    'project_done': False,
    'task_type': task_type,
    'evaluation_profile': evaluation_profile,
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 0,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'release_blocker_ids': [],
    'next_mandatory_action': 'Implement selected slice evidence-fixture.',
    'next_mandatory_role': 'completion-implementer',
    'remaining_stop_judges': 2,
    'last_reground_at': '2026-05-03T00:00:00Z',
    'last_auditor_verdict': None,
    'contract_status': 'selected_slice_pending_implementation',
    'latest_completed_slice': head_sha,
    'latest_verified_slice': head_sha,
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': task_type,
    'evaluation_profile': evaluation_profile,
    'last_reground_at': '2026-05-03T00:00:00Z',
    'plan_basis': 'canonical_evidence_fixture',
    'candidate_slices': [
        {
            'slice_id': 'evidence-fixture',
            'goal': 'Persist canonical verification evidence for the selected slice.',
            'acceptance_criteria': acceptance,
            'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
            'priority': 70,
            'status': 'selected',
            'why_now': 'Exercise fail-closed evidence parity.',
            'blocked_on': [],
            'evidence': [],
            'locked_notes': ['Keep the fixture scoped to canonical verification evidence parity.'],
            'must_fix_findings': [],
            'implementation_surfaces': implementation_surfaces,
            'verification_commands': verification_commands,
            'basis_commit': head_sha,
            'remaining_contract_ids_before': ['CANONICAL-EVIDENCE-ARTIFACTS'],
            'release_blocker_count_before': 0,
            'high_value_gap_count_before': 1,
        }
    ],
}
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': task_type,
    'evaluation_profile': evaluation_profile,
    'status': 'selected',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'acceptance_criteria': acceptance,
    'blocked_on': [],
    'locked_notes': ['Keep the fixture scoped to canonical verification evidence parity.'],
    'must_fix_findings': [],
    'implementation_surfaces': implementation_surfaces,
    'verification_commands': verification_commands,
    'basis_commit': head_sha,
    'remaining_contract_ids_before': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'release_blocker_count_before': 0,
    'high_value_gap_count_before': 1,
    'priority': 70,
    'why_now': 'Exercise fail-closed evidence parity.',
}

startup_brief = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'primary_agent',
    'confirmed': True,
    'confirmed_at': '2026-05-03T00:00:00Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': ['Exercise canonical verification evidence artifact parity.'],
    'constraints': ['Keep the fixture scoped to verification evidence coverage.'],
    'acceptance': acceptance,
    'risks': ['Fixture drift can hide evidence-parity regressions.'],
    'notes': ['Fixture startup brief for canonical evidence artifact regression coverage.'],
    'task_type': task_type,
    'evaluation_profile': evaluation_profile,
}

Path('.agent/current/state.json').write_text(json.dumps(state, indent=2) + '\n')
Path('.agent/current/startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
Path('.agent/current/plan.json').write_text(json.dumps(plan, indent=2) + '\n')
Path('.agent/current/active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
PY

if bash .agent/verify_completion_control_plane.sh >/dev/null 2>&1; then
  echo "expected control-plane verification to fail while selected-slice evidence remains at idle placeholder state" >&2
  exit 1
fi

rm .agent/current/verification-evidence.json
if bash .agent/verify_completion_control_plane.sh >/dev/null 2>&1; then
  echo "expected control-plane verification to fail when verification-evidence.json is missing" >&2
  exit 1
fi

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
verification_commands = [
    'bash .agent/verify_completion_control_plane.sh',
    'bash .agent/verify_completion_stop.sh',
]
invalid = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': 'stale-head',
    'verification_commands': verification_commands,
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'summary': 'Stale selected-slice evidence.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(invalid, indent=2) + '\n')
PY

HEAD_OUTPUT="$(bash .agent/verify_completion_control_plane.sh 2>&1 || true)"
[[ "$HEAD_OUTPUT" == *"head_sha"* ]] || { echo "expected stale-head verification failure to mention head_sha, got: $HEAD_OUTPUT" >&2; exit 1; }

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
invalid = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': ['bash .agent/verify_completion_control_plane.sh'],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'summary': 'Out-of-parity command set.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(invalid, indent=2) + '\n')
PY

COMMAND_OUTPUT="$(bash .agent/verify_completion_control_plane.sh 2>&1 || true)"
[[ "$COMMAND_OUTPUT" == *"verification_commands"* ]] || {
  echo "expected verification-command parity failure to mention verification_commands, got: $COMMAND_OUTPUT" >&2
  exit 1
}

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
legacy_valid = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': [
        'bash .agent/verify_completion_control_plane.sh',
        'bash .agent/verify_completion_stop.sh',
    ],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'summary': 'Legacy selected-slice verification evidence still matches the active slice and current HEAD.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(legacy_valid, indent=2) + '\n')
PY

bash .agent/verify_completion_control_plane.sh >/dev/null

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
unsafe = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': [
        'bash .agent/verify_completion_control_plane.sh',
        'bash .agent/verify_completion_stop.sh',
    ],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'evidence_quality': {
        'status': 'structured_complete',
        'summary': 'Structured evidence is present but carries an unsafe artifact path.',
    },
    'command_results': [
        {
            'command': 'bash .agent/verify_completion_control_plane.sh',
            'outcome': 'passed',
            'summary': 'Control-plane verifier passed.',
            'artifact_paths': ['../unsafe.log'],
        },
        {
            'command': 'bash .agent/verify_completion_stop.sh',
            'outcome': 'passed',
            'summary': 'Stop verifier passed.',
            'artifact_paths': ['.agent/verify_completion_stop.sh'],
        },
    ],
    'acceptance_coverage': [
        {
            'criterion': 'Canonical verification evidence is recorded for the selected slice.',
            'status': 'covered',
            'summary': 'Selected-slice evidence is populated for current HEAD.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
        {
            'criterion': 'Fail-closed verification rejects missing or stale evidence.',
            'status': 'covered',
            'summary': 'The fixture already exercises stale-evidence rejection.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
    ],
    'flake_signals': [],
    'open_gaps': [],
    'basis_regression_required': False,
    'basis_regression_status': 'not_applicable',
    'basis_regression_reason': 'Basis regression is outside this fixture scope.',
    'basis_regression_artifact_paths': [],
    'summary': 'Structured evidence carries an unsafe artifact path and should fail closed.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(unsafe, indent=2) + '\n')
PY

ARTIFACT_OUTPUT="$(bash .agent/verify_completion_control_plane.sh 2>&1 || true)"
[[ "$ARTIFACT_OUTPUT" == *"artifact_paths"* ]] || {
  echo "expected unsafe-artifact verification failure to mention artifact_paths, got: $ARTIFACT_OUTPUT" >&2
  exit 1
}

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
required_not_applicable = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': [
        'bash .agent/verify_completion_control_plane.sh',
        'bash .agent/verify_completion_stop.sh',
    ],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'evidence_quality': {
        'status': 'structured_complete',
        'summary': 'Required basis regression must not be recorded as not_applicable.',
    },
    'command_results': [
        {
            'command': 'bash .agent/verify_completion_control_plane.sh',
            'outcome': 'passed',
            'summary': 'Control-plane verifier passed.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
        {
            'command': 'bash .agent/verify_completion_stop.sh',
            'outcome': 'passed',
            'summary': 'Stop verifier passed.',
            'artifact_paths': ['.agent/verify_completion_stop.sh'],
        },
    ],
    'acceptance_coverage': [
        {
            'criterion': 'Canonical verification evidence is recorded for the selected slice.',
            'status': 'covered',
            'summary': 'Selected-slice evidence is populated for current HEAD.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
        {
            'criterion': 'Fail-closed verification rejects missing or stale evidence.',
            'status': 'covered',
            'summary': 'The fixture already exercised missing and stale evidence rejection earlier in this script.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
    ],
    'flake_signals': [],
    'open_gaps': [],
    'basis_regression_required': True,
    'basis_regression_status': 'not_applicable',
    'basis_regression_reason': 'This should fail closed because the slice marked basis regression required.',
    'basis_regression_artifact_paths': [],
    'summary': 'Required basis regression was incorrectly treated as not_applicable.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(required_not_applicable, indent=2) + '\n')
PY

REQUIRED_STATUS_OUTPUT="$(bash .agent/verify_completion_control_plane.sh 2>&1 || true)"
[[ "$REQUIRED_STATUS_OUTPUT" == *"basis_regression_status"* ]] || {
  echo "expected required-basis-status verification failure to mention basis_regression_status, got: $REQUIRED_STATUS_OUTPUT" >&2
  exit 1
}

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
missing_basis_artifacts = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': [
        'bash .agent/verify_completion_control_plane.sh',
        'bash .agent/verify_completion_stop.sh',
    ],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'evidence_quality': {
        'status': 'structured_complete',
        'summary': 'Executed basis regression results must keep artifact paths.',
    },
    'command_results': [
        {
            'command': 'bash .agent/verify_completion_control_plane.sh',
            'outcome': 'passed',
            'summary': 'Control-plane verifier passed.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
        {
            'command': 'bash .agent/verify_completion_stop.sh',
            'outcome': 'passed',
            'summary': 'Stop verifier passed.',
            'artifact_paths': ['.agent/verify_completion_stop.sh'],
        },
    ],
    'acceptance_coverage': [
        {
            'criterion': 'Canonical verification evidence is recorded for the selected slice.',
            'status': 'covered',
            'summary': 'Selected-slice evidence is populated for current HEAD.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
        {
            'criterion': 'Fail-closed verification rejects missing or stale evidence.',
            'status': 'covered',
            'summary': 'The fixture already exercised missing and stale evidence rejection earlier in this script.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
    ],
    'flake_signals': [],
    'open_gaps': [],
    'basis_regression_required': True,
    'basis_regression_status': 'failed_on_basis',
    'basis_regression_reason': 'The basis command failed, but the artifact paths were dropped.',
    'basis_regression_artifact_paths': [],
    'summary': 'Executed basis regression metadata is missing its artifact paths and should fail closed.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(missing_basis_artifacts, indent=2) + '\n')
PY

MISSING_BASIS_ARTIFACTS_OUTPUT="$(bash .agent/verify_completion_control_plane.sh 2>&1 || true)"
[[ "$MISSING_BASIS_ARTIFACTS_OUTPUT" == *"basis_regression_artifact_paths"* ]] || {
  echo "expected executed-basis verification failure to mention basis_regression_artifact_paths, got: $MISSING_BASIS_ARTIFACTS_OUTPUT" >&2
  exit 1
}

python3 - "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

head_sha = sys.argv[1]
valid = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'evidence-fixture',
    'goal': 'Persist canonical verification evidence for the selected slice.',
    'contract_ids': ['CANONICAL-EVIDENCE-ARTIFACTS'],
    'basis_commit': head_sha,
    'head_sha': head_sha,
    'verification_commands': [
        'bash .agent/verify_completion_control_plane.sh',
        'bash .agent/verify_completion_stop.sh',
    ],
    'outcome': 'passed',
    'recorded_at': '2026-05-03T00:00:00Z',
    'evidence_quality': {
        'status': 'structured_complete',
        'summary': 'Selected-slice structured evidence matches the active slice and current HEAD.',
    },
    'command_results': [
        {
            'command': 'bash .agent/verify_completion_control_plane.sh',
            'outcome': 'passed',
            'summary': 'Control-plane verifier passed.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
        {
            'command': 'bash .agent/verify_completion_stop.sh',
            'outcome': 'passed',
            'summary': 'Stop verifier passed.',
            'artifact_paths': ['.agent/verify_completion_stop.sh'],
        },
    ],
    'acceptance_coverage': [
        {
            'criterion': 'Canonical verification evidence is recorded for the selected slice.',
            'status': 'covered',
            'summary': 'Selected-slice evidence is populated for current HEAD.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
        {
            'criterion': 'Fail-closed verification rejects missing or stale evidence.',
            'status': 'covered',
            'summary': 'The fixture already exercised missing and stale evidence rejection earlier in this script.',
            'artifact_paths': ['.agent/verify_completion_control_plane.sh'],
        },
    ],
    'flake_signals': [],
    'open_gaps': [],
    'basis_regression_required': False,
    'basis_regression_status': 'not_applicable',
    'basis_regression_reason': 'Basis regression is outside this canonical evidence fixture.',
    'basis_regression_artifact_paths': [],
    'summary': 'Selected-slice structured verification evidence matches the active slice and current HEAD.',
}
Path('.agent/current/verification-evidence.json').write_text(json.dumps(valid, indent=2) + '\n')
PY

bash .agent/verify_completion_control_plane.sh >/dev/null
PI_COMPLETION_RUNNING_RELEASE_CHECK=1 bash .agent/verify_completion_stop.sh >/dev/null

rm -f "$SYSTEM_REMINDER"
PI_COMPLETION_TEST_SYSTEM_REMINDER_PATH="$SYSTEM_REMINDER" \
pi -e "$PKG_ROOT" -p "Summarize the completion reminder briefly." \
  >"$TMPDIR/pi-canonical-evidence-reminder.out" 2>"$TMPDIR/pi-canonical-evidence-reminder.err"

python3 - "$SYSTEM_REMINDER" <<'PY'
import sys
from pathlib import Path

reminder = Path(sys.argv[1])
assert not reminder.exists(), 'ordinary non-/cook turn should not inject completion reminder solely from selected-slice canonical state'
PY

python3 - <<'PY'
import json
from pathlib import Path

state_path = Path('.agent/current/state.json')
plan_path = Path('.agent/current/plan.json')
active_path = Path('.agent/current/active-slice.json')

state = json.loads(state_path.read_text())
state.update({
    'current_phase': 'done',
    'continuation_policy': 'done',
    'continuation_reason': 'Fixture is complete; ordinary primary-agent turns should stay outside completion until /cook runs again.',
    'project_done': True,
    'remaining_high_value_gaps': 0,
    'unsatisfied_contract_ids': [],
    'next_mandatory_action': None,
    'next_mandatory_role': None,
    'remaining_stop_judges': 0,
    'contract_status': 'done',
})
state_path.write_text(json.dumps(state, indent=2) + '\n')

plan = json.loads(plan_path.read_text())
for slice_data in plan.get('candidate_slices', []):
    if slice_data.get('slice_id') == 'evidence-fixture':
        slice_data['status'] = 'done'
plan_path.write_text(json.dumps(plan, indent=2) + '\n')

active = json.loads(active_path.read_text())
active['status'] = 'done'
active_path.write_text(json.dumps(active, indent=2) + '\n')
PY

rm -f "$SYSTEM_REMINDER"
PI_COMPLETION_TEST_SYSTEM_REMINDER_PATH="$SYSTEM_REMINDER" \
pi -e "$PKG_ROOT" -p "Summarize the latest release briefly." \
  >"$TMPDIR/pi-canonical-evidence-done-reminder.out" 2>"$TMPDIR/pi-canonical-evidence-done-reminder.err"

python3 - "$SYSTEM_REMINDER" <<'PY'
import sys
from pathlib import Path

reminder = Path(sys.argv[1])
assert not reminder.exists(), 'ordinary non-/cook turn should not inject closed-workflow boundary routing before /cook reactivation'
PY

echo "canonical evidence artifact test passed: $TMPDIR"
