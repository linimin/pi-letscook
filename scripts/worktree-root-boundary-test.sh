#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pi() {
  env -u PI_COMPLETION_ROLE pi --no-extensions "$@"
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

PARENT="$TMPDIR/lobster"
CHILD="$PARENT/.worktrees/cdn-onboarding"
PARENT_MISSION='Ancestor workflow that must not leak into nested worktree.'
CHILD_MISSION='Start isolated workflow inside nested worktree.'
mkdir -p "$PARENT" "$CHILD"
git -C "$PARENT" init -q
git -C "$CHILD" init -q
write_minimal_completion_state "$PARENT" "$PARENT_MISSION"

HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    'kind': 'cook_handoff',
    'source': 'primary_agent',
    'captured_at': '2026-01-01T00:00:01.000Z',
    'source_turn_id': 'worktree-root-boundary-test',
    'mission': 'Start isolated workflow inside nested worktree.',
    'scope': [
        'Create canonical completion workflow state under the current nested worktree root.',
        'Do not read or mutate completion workflow state from an ancestor checkout.'
    ],
    'constraints': [
        'Bound completion state discovery to the current Git worktree root.'
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
        'npm run worktree-root-boundary-test'
    ],
    'why_this_slice_first': 'The root boundary must be correct before /cook can safely run in nested worktrees.',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'why_cook_now': 'The nested worktree has explicit startup intent and must not resume the ancestor workflow.'
}
print('```cook_handoff\n' + json.dumps(capsule, ensure_ascii=False, indent=2) + '\n```')
PY
)"

cd "$CHILD"
if ! PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$HANDOFF" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi -e "$PKG_ROOT" -p "/cook start an isolated nested worktree workflow" \
    >"$TMPDIR/pi-completion-worktree-root-boundary.out" \
    2>"$TMPDIR/pi-completion-worktree-root-boundary.err"; then
  echo "pi /cook command failed" >&2
  cat "$TMPDIR/pi-completion-worktree-root-boundary.out" >&2 || true
  cat "$TMPDIR/pi-completion-worktree-root-boundary.err" >&2 || true
  exit 1
fi

python3 - "$PARENT" "$CHILD" "$PARENT_MISSION" "$CHILD_MISSION" "$TMPDIR/pi-completion-worktree-root-boundary.out" "$TMPDIR/pi-completion-worktree-root-boundary.err" <<'PY'
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
assert child_state_path.exists(), 'nested worktree /cook should create .agent/current/state.json under the nested worktree root'
parent_state = json.loads(parent_state_path.read_text(encoding='utf-8'))
child_state = json.loads(child_state_path.read_text(encoding='utf-8'))
assert parent_state['mission_anchor'] == parent_mission, 'nested worktree /cook must not refocus or mutate the ancestor workflow state'
assert child_state['mission_anchor'] == child_mission, 'nested worktree /cook should use the child startup handoff mission'
assert child_state['workflow_session_id'] != parent_state['workflow_session_id'], 'nested worktree /cook should create an independent workflow session'
assert (child / '.agent' / 'current' / 'startup-brief.json').exists(), 'nested worktree /cook should persist a local startup brief'
assert 'Started completion workflow for: Start isolated workflow inside nested worktree.' in output, 'nested worktree /cook should report a fresh local workflow start'
PY

echo "worktree root boundary test passed: $CHILD"
