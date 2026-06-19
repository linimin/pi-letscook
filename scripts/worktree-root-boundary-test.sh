#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
trap 'rm -rf "$TMPDIR"' EXIT

write_minimal_completion_state() {
  local root="$1"
  local mission="$2"
  mkdir -p "$root/.agent/current/tmp"
  python3 - "$root" "$mission" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
mission = sys.argv[2]
current = root / '.agent' / 'current'
current.mkdir(parents=True, exist_ok=True)

def write_json(name, payload):
    (current / name).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')

state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-01-01T00:00:00.000Z',
    'workflow_session_id': 'wf-ancestor-leak-test',
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': 'implement',
    'continuation_policy': 'continue',
    'continuation_reason': 'Ancestor workflow fixture should not be visible from nested worktree roots.',
    'project_done': False,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'requires_reground': False,
    'slices_since_last_reground': 1,
    'remaining_release_blockers': 0,
    'remaining_high_value_gaps': 0,
    'unsatisfied_contract_ids': [],
    'release_blocker_ids': [],
    'next_mandatory_action': 'Continue ancestor workflow only from the ancestor repo root',
    'next_mandatory_role': 'completion-implementer',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 0,
    'last_reground_at': None,
    'last_auditor_verdict': None,
    'contract_status': 'unknown',
    'latest_completed_slice': None,
    'latest_verified_slice': None,
}
startup = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'test_fixture',
    'confirmed': True,
    'confirmed_at': '2026-01-01T00:00:00.000Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': [],
    'constraints': [],
    'acceptance': [],
    'risks': [],
    'notes': ['Ancestor fixture for worktree root-boundary regression.'],
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'last_reground_at': None,
    'plan_basis': 'test_fixture',
    'candidate_slices': [],
}
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'status': 'idle',
    'slice_id': None,
    'goal': None,
    'contract_ids': [],
    'acceptance_criteria': [],
    'priority': None,
    'why_now': None,
    'blocked_on': [],
    'locked_notes': [],
    'must_fix_findings': [],
    'implementation_surfaces': [],
    'verification_commands': [],
    'basis_commit': None,
    'remaining_contract_ids_before': [],
    'release_blocker_count_before': None,
    'high_value_gap_count_before': None,
}
evidence = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'none',
    'slice_id': None,
    'goal': None,
    'contract_ids': [],
    'basis_commit': None,
    'head_sha': None,
    'verification_commands': [],
    'outcome': 'not_recorded',
    'recorded_at': None,
    'summary': 'No deterministic verification evidence is recorded for the ancestor fixture.',
}
write_json('state.json', state)
write_json('startup-brief.json', startup)
write_json('plan.json', plan)
write_json('active-slice.json', active)
write_json('verification-evidence.json', evidence)
(current / 'slice-history.jsonl').write_text('', encoding='utf-8')
(current / 'stop-check-history.jsonl').write_text('', encoding='utf-8')
PY
}

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

build_handoff() {
  local mission="$1"
  local verification_command="$2"
  python3 - "$mission" "$verification_command" <<'PY'
import json
import sys

mission = sys.argv[1]
verification_command = sys.argv[2]
capsule = {
    'kind': 'cook_handoff',
    'source': 'primary_agent',
    'captured_at': '2026-01-01T00:00:01.000Z',
    'source_turn_id': 'worktree-root-boundary-test',
    'mission': mission,
    'scope': [
        'Create canonical completion workflow state under the current nested worktree root.',
        'Do not read or mutate completion workflow state from an ancestor checkout.'
    ],
    'constraints': [
        'Bound completion state discovery to the current Git worktree root even when process.cwd() points elsewhere.'
    ],
    'acceptance': [
        'Running /cook inside a nested Git worktree creates .agent/current/state.json in that worktree.',
        'The ancestor checkout .agent/current/state.json remains unchanged.'
    ],
    'risks': [
        'Nested worktrees stored under a parent checkout can accidentally inherit the parent completion state.'
    ],
    'notes': [
        'Regression coverage for nested worktree completion-root discovery.'
    ],
    'handoff_kind': 'implementation_workflow_handoff',
    'first_slice_goal': 'Verify nested worktree completion state isolation.',
    'first_slice_non_goals': [],
    'implementation_surfaces': [
        'extensions/completion/state-store.ts'
    ],
    'verification_commands': [
        verification_command
    ],
    'why_this_slice_first': 'The root boundary must be correct before /cook can safely run in nested worktrees.',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'why_cook_now': 'The nested worktree has explicit startup intent and must not resume the ancestor workflow.'
}
print('```cook_handoff\n' + json.dumps(capsule, ensure_ascii=False, indent=2) + '\n```')
PY
}

PARENT="$TMPDIR/lobster"
CHILD_DIRECT="$PARENT/.worktrees/cdn-onboarding-direct"
CHILD_SESSION="$PARENT/.worktrees/cdn-onboarding-session"
PARENT_MISSION='Ancestor workflow that must not leak into nested worktree.'
CHILD_DIRECT_MISSION='Start isolated workflow inside nested worktree (direct cwd).'
CHILD_SESSION_MISSION='Start isolated workflow inside nested worktree (session cwd).'
mkdir -p "$PARENT" "$CHILD_DIRECT" "$CHILD_SESSION"

git -C "$PARENT" init -q
git -C "$CHILD_DIRECT" init -q
git -C "$CHILD_SESSION" init -q
write_minimal_completion_state "$PARENT" "$PARENT_MISSION"

HANDOFF_DIRECT="$(build_handoff "$CHILD_DIRECT_MISSION" "npm run worktree-root-boundary-test")"
DIRECT_OUT="$TMPDIR/pi-completion-worktree-root-boundary-direct.out"
DIRECT_ERR="$TMPDIR/pi-completion-worktree-root-boundary-direct.err"
(
  cd "$CHILD_DIRECT"
  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$HANDOFF_DIRECT" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi -e "$PKG_ROOT" -p "/cook start an isolated nested worktree workflow"
) >"$DIRECT_OUT" 2>"$DIRECT_ERR"

python3 - "$PARENT" "$CHILD_DIRECT" "$PARENT_MISSION" "$CHILD_DIRECT_MISSION" "$DIRECT_OUT" "$DIRECT_ERR" <<'PY'
import json
import sys
from pathlib import Path

parent = Path(sys.argv[1])
child = Path(sys.argv[2])
parent_mission = sys.argv[3]
child_mission = sys.argv[4]
output = Path(sys.argv[5]).read_text(encoding='utf-8') + Path(sys.argv[6]).read_text(encoding='utf-8')

parent_state_path = parent / '.agent' / 'current' / 'state.json'
child_state_path = child / '.agent' / 'current' / 'state.json'
assert child_state_path.exists(), 'nested worktree /cook should create .agent/current/state.json under the direct child worktree root'
parent_state = json.loads(parent_state_path.read_text(encoding='utf-8'))
child_state = json.loads(child_state_path.read_text(encoding='utf-8'))
assert parent_state['mission_anchor'] == parent_mission, 'direct nested worktree /cook must not refocus or mutate the ancestor workflow state'
assert child_state['mission_anchor'] == child_mission, 'direct nested worktree /cook should use the child startup handoff mission'
assert child_state['workflow_session_id'] != parent_state['workflow_session_id'], 'direct nested worktree /cook should create an independent workflow session'
assert (child / '.agent' / 'current' / 'startup-brief.json').exists(), 'direct nested worktree /cook should persist a local startup brief'
assert 'Started completion workflow for: Start isolated workflow inside nested worktree (direct cwd).' in output, 'direct nested worktree /cook should report a fresh local workflow start'
PY

SESSION_PATH="$TMPDIR/worktree-root-boundary-session.jsonl"
write_session "$SESSION_PATH" "$CHILD_SESSION" "Use the child nested worktree cwd for this session."
HANDOFF_SESSION="$(build_handoff "$CHILD_SESSION_MISSION" "npm run worktree-root-boundary-test")"
SESSION_OUT="$TMPDIR/pi-completion-worktree-root-boundary-session.out"
SESSION_ERR="$TMPDIR/pi-completion-worktree-root-boundary-session.err"
(
  cd "$PARENT"
  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$HANDOFF_SESSION" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi --session "$SESSION_PATH" -e "$PKG_ROOT" -p "/cook start an isolated nested worktree workflow from a parent process cwd"
) >"$SESSION_OUT" 2>"$SESSION_ERR"

python3 - "$PARENT" "$CHILD_SESSION" "$PARENT_MISSION" "$CHILD_SESSION_MISSION" "$SESSION_OUT" "$SESSION_ERR" <<'PY'
import json
import sys
from pathlib import Path

parent = Path(sys.argv[1])
child = Path(sys.argv[2])
parent_mission = sys.argv[3]
child_mission = sys.argv[4]
output = Path(sys.argv[5]).read_text(encoding='utf-8') + Path(sys.argv[6]).read_text(encoding='utf-8')

parent_state_path = parent / '.agent' / 'current' / 'state.json'
child_state_path = child / '.agent' / 'current' / 'state.json'
assert child_state_path.exists(), 'session-bound nested worktree /cook should create .agent/current/state.json under the child worktree root even when process.cwd() is the ancestor repo'
parent_state = json.loads(parent_state_path.read_text(encoding='utf-8'))
child_state = json.loads(child_state_path.read_text(encoding='utf-8'))
assert parent_state['mission_anchor'] == parent_mission, 'session-bound nested worktree /cook must not resume or mutate the ancestor workflow state'
assert child_state['mission_anchor'] == child_mission, 'session-bound nested worktree /cook should use the child startup handoff mission'
assert child_state['workflow_session_id'] != parent_state['workflow_session_id'], 'session-bound nested worktree /cook should create an independent workflow session'
assert (child / '.agent' / 'current' / 'startup-brief.json').exists(), 'session-bound nested worktree /cook should persist a local startup brief'
assert 'Started completion workflow for: Start isolated workflow inside nested worktree (session cwd).' in output, 'session-bound nested worktree /cook should report a fresh local workflow start'
PY

echo "worktree root boundary test passed: $CHILD_DIRECT and $CHILD_SESSION"
