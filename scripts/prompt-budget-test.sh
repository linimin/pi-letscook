#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
cleanup() {
  local status=$?
  rm -rf "$TMPDIR"
  return $status
}
trap cleanup EXIT

pi() {
  env \
    -u PI_COMPLETION_ROLE \
    -u PI_COMPLETION_HELPER \
    -u PI_COMPLETION_CALLER_ROLE \
    -u PI_COMPLETION_HELPER_ROOT \
    -u PI_COMPLETION_HELPER_CWD \
    -u PI_COMPLETION_ROLE_MODEL \
    command pi --no-extensions "$@"
}

write_active_workflow_fixture() {
  local root="$1"
  mkdir -p "$root/.agent/current/tmp"
  (
    cd "$root"
    git init -q
    printf '# prompt budget fixture\n' > README.md
  )

  python3 - "$root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
current = root / '.agent' / 'current'
current.mkdir(parents=True, exist_ok=True)

state = {
    'schema_version': 1,
    'mission_anchor': 'Measure prompt budget regression surfaces.',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'current_phase': 'implement',
    'continuation_policy': 'continue',
    'continuation_reason': 'Prompt-budget fixture keeps the active workflow reminder startable.',
    'project_done': False,
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 0,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': ['PROMPT-BUDGET-01'],
    'release_blocker_ids': [],
    'next_mandatory_action': 'Run completion-reviewer for the latest slice.',
    'next_mandatory_role': 'completion-reviewer',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 1,
    'last_reground_at': '2026-01-01T00:00:00.000Z',
    'last_auditor_verdict': None,
    'contract_status': 'in_progress',
    'latest_completed_slice': 'prompt-budget-slice',
    'latest_verified_slice': 'prompt-budget-slice',
    'workflow_entry_status': 'active',
    'workflow_session_id': 'prompt-budget-session',
}
plan = {
    'schema_version': 1,
    'mission_anchor': state['mission_anchor'],
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
    'last_reground_at': state['last_reground_at'],
    'plan_basis': 'prompt_budget_fixture',
    'candidate_slices': [
        {
            'slice_id': 'prompt-budget-slice',
            'goal': 'Keep prompt reminders compact while preserving canonical routing truth.',
            'acceptance_criteria': [
                'Ordinary chat reminder stays available outside /cook.',
                'Active workflow system reminder stays concise and truthful.'
            ],
            'contract_ids': ['PROMPT-BUDGET-01'],
            'priority': 1,
            'status': 'selected',
            'why_now': 'Prompt-budget regressions should fail before broader workflow coverage runs.',
            'blocked_on': [],
            'evidence': ['Fixture selected for prompt-budget regression coverage.'],
        }
    ],
}
active = {
    'schema_version': 1,
    'mission_anchor': state['mission_anchor'],
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
    'status': 'selected',
    'slice_id': 'prompt-budget-slice',
    'goal': 'Keep prompt reminders compact while preserving canonical routing truth.',
    'contract_ids': ['PROMPT-BUDGET-01'],
    'acceptance_criteria': [
        'Ordinary chat reminder stays available outside /cook.',
        'Active workflow system reminder stays concise and truthful.'
    ],
    'priority': 1,
    'why_now': 'Prompt-budget regressions should fail before broader workflow coverage runs.',
    'blocked_on': [],
    'locked_notes': ['Keep the completion reminder anchored to canonical state only.'],
    'must_fix_findings': [],
    'implementation_surfaces': ['extensions/completion/prompt-surfaces.ts', 'extensions/completion/role-runner.ts'],
    'verification_commands': ['bash scripts/prompt-budget-test.sh', 'bash scripts/role-runner-contract-test.sh'],
    'basis_commit': 'prompt-budget-basis',
    'remaining_contract_ids_before': ['PROMPT-BUDGET-01'],
    'release_blocker_count_before': 0,
    'high_value_gap_count_before': 1,
}
startup_brief = {
    'kind': 'startup_brief',
    'source': 'recent_discussion',
    'confirmed': True,
    'captured_at': '2026-01-01T00:00:00.000Z',
    'goal_text': state['mission_anchor'],
    'mission': state['mission_anchor'],
    'scope': ['Measure prompt budgets for ordinary chat, /cook startup, and active workflow reminders.'],
    'constraints': ['Keep reminder copy concise without changing workflow semantics.'],
    'acceptance': ['Prompt budget regression checks pass.'],
    'risks': ['Over-trimming prompt text could hide critical workflow routing guidance.'],
    'notes': ['This fixture exists only for prompt-budget regression coverage.'],
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
}
verification_evidence = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'prompt-budget-slice',
    'goal': active['goal'],
    'contract_ids': active['contract_ids'],
    'basis_commit': active['basis_commit'],
    'head_sha': 'prompt-budget-head',
    'verification_commands': active['verification_commands'],
    'outcome': 'passed',
    'recorded_at': '2026-01-01T00:00:00.000Z',
    'summary': 'Prompt-budget fixture verification evidence remains aligned with the selected slice.',
}

(current / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
(current / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
(current / 'active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
(current / 'startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
(current / 'verification-evidence.json').write_text(json.dumps(verification_evidence, indent=2) + '\n')
(current / 'slice-history.jsonl').write_text('')
(current / 'stop-check-history.jsonl').write_text('')
PY
}

write_startup_repo() {
  local root="$1"
  mkdir -p "$root"
  (
    cd "$root"
    git init -q
    printf '# prompt budget startup fixture\n' > README.md
  )
}

WORKFLOW_ROOT="$TMPDIR/workflow-repo"
STARTUP_ROOT="$TMPDIR/startup-repo"
ORDINARY_REMINDER="$TMPDIR/ordinary-reminder.txt"
PRIMARY_HANDOFF_PROMPT="$TMPDIR/primary-handoff-prompt.txt"
REGROUNDER_ROLE_PROMPT_BUNDLE="$TMPDIR/regrounder-role-prompt.json"
REVIEWER_ROLE_PROMPT_BUNDLE="$TMPDIR/reviewer-role-prompt.json"
AUDITOR_ROLE_PROMPT_BUNDLE="$TMPDIR/auditor-role-prompt.json"
STOP_JUDGE_ROLE_PROMPT_BUNDLE="$TMPDIR/stop-judge-role-prompt.json"
IMPLEMENTER_ROLE_PROMPT_BUNDLE="$TMPDIR/implementer-role-prompt.json"

write_active_workflow_fixture "$WORKFLOW_ROOT"
write_startup_repo "$STARTUP_ROOT"

(
  cd "$WORKFLOW_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH="$ORDINARY_REMINDER" \
  pi -e "$PKG_ROOT" -p "Summarize the repo briefly." \
    >"$TMPDIR/ordinary.out" 2>"$TMPDIR/ordinary.err"
)

BOOTSTRAP_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    'kind': 'cook_handoff',
    'source': 'primary_agent',
    'captured_at': '2026-01-01T00:00:00.000Z',
    'source_turn_id': 'prompt-budget',
    'mission': 'Measure primary-agent handoff prompt budget coverage.',
    'scope': [
        'Capture the startup prompt used for same-entry /cook handoff synthesis.',
        'Keep prompt-budget regression coverage deterministic.'
    ],
    'constraints': [
        'Do not depend on live model output during prompt-budget regression tests.'
    ],
    'acceptance': [
        'The primary-agent handoff prompt snapshot is written deterministically during the test.'
    ],
    'risks': [
        'Prompt growth could reintroduce unnecessary token burn during /cook startup.'
    ],
    'notes': [
        'This handoff exists only to let prompt-budget coverage bypass live model calls.'
    ],
    'handoff_kind': 'implementation_workflow_handoff',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'why_cook_now': 'The startup prompt budget should stay under deterministic regression limits.'
}
print('```cook_handoff\n' + json.dumps(capsule, ensure_ascii=False, indent=2) + '\n```')
PY
)"

(
  cd "$STARTUP_ROOT"
  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$BOOTSTRAP_HANDOFF" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_PRIMARY_HANDOFF_PROMPT_PATH="$PRIMARY_HANDOFF_PROMPT" \
  pi -e "$PKG_ROOT" -p "/cook add prompt budget coverage and keep the startup prompt compact" \
    >"$TMPDIR/handoff.out" 2>"$TMPDIR/handoff.err"
)

capture_role_prompt_bundle() {
  local role="$1"
  local bundle_path="$2"
  local system_prompt_file="$TMPDIR/${role}-capture-system.md"
  local events_file="$TMPDIR/${role}-capture-events.jsonl"
  local stderr_file="$TMPDIR/${role}-capture-stderr.txt"
  cat >"$system_prompt_file" <<EOF
You are running a completion role prompt-budget probe.
Call the completion_role tool exactly once with role ${role} and task "Capture the real ${role} role prompt budget.".
After the tool returns, respond with exactly the tool result text and nothing else.
Do not add commentary.
EOF
  (
    cd "$WORKFLOW_ROOT"
    PI_COMPLETION_TEST_CAPTURE_ROLE_PROMPT_ONLY=1 \
    PI_COMPLETION_TEST_ROLE_PROMPT_BUNDLE_PATH="$bundle_path" \
    PI_COMPLETION_TEST_FORCE_COMPLETION_ROLE="$role" \
    PI_COMPLETION_TEST_FORCE_COMPLETION_TASK="Capture the real ${role} role prompt budget." \
    pi \
      --mode json \
      -p \
      --thinking off \
      --no-session \
      --no-extensions \
      --no-builtin-tools \
      --no-skills \
      --no-prompt-templates \
      --no-context-files \
      -e "$PKG_ROOT" \
      --tools completion_role \
      --append-system-prompt "$system_prompt_file" \
      "Continue the completion workflow and run ${role} now." \
      >"$events_file" 2>"$stderr_file"
  )
}

capture_role_prompt_bundle "completion-regrounder" "$REGROUNDER_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-reviewer" "$REVIEWER_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-auditor" "$AUDITOR_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-stop-judge" "$STOP_JUDGE_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-implementer" "$IMPLEMENTER_ROLE_PROMPT_BUNDLE"

python3 - "$PKG_ROOT" "$ORDINARY_REMINDER" "$PRIMARY_HANDOFF_PROMPT" "$REGROUNDER_ROLE_PROMPT_BUNDLE" "$REVIEWER_ROLE_PROMPT_BUNDLE" "$AUDITOR_ROLE_PROMPT_BUNDLE" "$STOP_JUDGE_ROLE_PROMPT_BUNDLE" "$IMPLEMENTER_ROLE_PROMPT_BUNDLE" <<'PY'
import re
import sys
from pathlib import Path

pkg_root = Path(sys.argv[1])
ordinary_path = Path(sys.argv[2])
primary_path = Path(sys.argv[3])
regrounder_bundle_path = Path(sys.argv[4])
reviewer_bundle_path = Path(sys.argv[5])
auditor_bundle_path = Path(sys.argv[6])
stop_judge_bundle_path = Path(sys.argv[7])
implementer_bundle_path = Path(sys.argv[8])
source_path = pkg_root / 'extensions' / 'completion' / 'prompt-surfaces.ts'
runtime_quick_path = pkg_root / 'skills' / 'completion-protocol' / 'references' / 'runtime-quick.md'

for path in (ordinary_path, primary_path, regrounder_bundle_path, reviewer_bundle_path, auditor_bundle_path, stop_judge_bundle_path, implementer_bundle_path, source_path, runtime_quick_path):
    if not path.exists():
        raise SystemExit(f'[prompt-budget-test] missing expected prompt-budget surface: {path}')

ordinary = ordinary_path.read_text().strip()
primary = primary_path.read_text().strip()
regrounder_bundle = __import__('json').loads(regrounder_bundle_path.read_text())
reviewer_bundle = __import__('json').loads(reviewer_bundle_path.read_text())
auditor_bundle = __import__('json').loads(auditor_bundle_path.read_text())
stop_judge_bundle = __import__('json').loads(stop_judge_bundle_path.read_text())
implementer_bundle = __import__('json').loads(implementer_bundle_path.read_text())
source = source_path.read_text()
runtime_quick = runtime_quick_path.read_text().strip()
match = re.search(r'export function buildSystemReminder\([\s\S]*?\n}\n\nexport function buildResumeCapsule', source)
if not match:
    raise SystemExit('[prompt-budget-test] could not locate buildSystemReminder source block')
system_source = match.group(0)

text_checks = [
    ('ordinary_reminder', ordinary, 1800),
    ('primary_handoff_prompt', primary, 700),
    ('runtime_quick_reference', runtime_quick, 3400),
    ('buildSystemReminder_source', system_source, 3100),
]
for name, text, limit in text_checks:
    size = len(text)
    if size > limit:
        raise SystemExit(f'[prompt-budget-test] {name} exceeded budget: {size} > {limit}')
    print(f'{name}={size} chars (limit {limit})')

bundle_checks = [
    ('regrounder_role_prompt_combined', regrounder_bundle, 6200),
    ('reviewer_role_prompt_combined', reviewer_bundle, 5400),
    ('auditor_role_prompt_combined', auditor_bundle, 6000),
    ('stop_judge_role_prompt_combined', stop_judge_bundle, 5800),
    ('implementer_role_prompt_combined', implementer_bundle, 7000),
]
for name, bundle, limit in bundle_checks:
    size = bundle.get('combined_prompt_chars')
    if not isinstance(size, int):
        raise SystemExit(f'[prompt-budget-test] {name} bundle did not report combined_prompt_chars')
    if size > limit:
        raise SystemExit(f'[prompt-budget-test] {name} exceeded budget: {size} > {limit}')
    print(f'{name}={size} chars (limit {limit})')

if regrounder_bundle.get('role') != 'completion-regrounder':
    raise SystemExit(f"[prompt-budget-test] regrounder bundle role mismatch: {regrounder_bundle.get('role')!r}")
if reviewer_bundle.get('role') != 'completion-reviewer':
    raise SystemExit(f"[prompt-budget-test] reviewer bundle role mismatch: {reviewer_bundle.get('role')!r}")
if auditor_bundle.get('role') != 'completion-auditor':
    raise SystemExit(f"[prompt-budget-test] auditor bundle role mismatch: {auditor_bundle.get('role')!r}")
if stop_judge_bundle.get('role') != 'completion-stop-judge':
    raise SystemExit(f"[prompt-budget-test] stop-judge bundle role mismatch: {stop_judge_bundle.get('role')!r}")
if implementer_bundle.get('role') != 'completion-implementer':
    raise SystemExit(f"[prompt-budget-test] implementer bundle role mismatch: {implementer_bundle.get('role')!r}")
if any(bundle.get('repair_mode') is not False for bundle in (regrounder_bundle, reviewer_bundle, auditor_bundle, stop_judge_bundle, implementer_bundle)):
    raise SystemExit('[prompt-budget-test] prompt-budget role capture should stay outside repair mode')
PY

echo "prompt budget test passed: $TMPDIR"
