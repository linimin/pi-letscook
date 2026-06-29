#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PKG_ROOT"
pi() {
  env -u PI_COMPLETION_ROLE command pi --no-extensions "$@"
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

write_continue_fixture() {
  local repo="$1"
  local session_id="$2"
  local mission="$3"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    printf '# stale driver prompt suppression fixture\n' > README.md
    git add README.md
    git -c user.name='Completion Test' -c user.email='completion-test@example.com' commit -qm 'fixture'
  )
  local basis_sha
  basis_sha="$(git -C "$repo" rev-parse HEAD)"

  python3 - "$repo" "$basis_sha" "$session_id" "$mission" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
basis_sha = sys.argv[2]
session_id = sys.argv[3]
mission = sys.argv[4]
current_dir = repo / '.agent' / 'current'
current_dir.mkdir(parents=True, exist_ok=True)
(current_dir / 'tmp').mkdir(parents=True, exist_ok=True)

contract_id = 'STALE-DRIVER-PROMPT-SUPPRESSION'
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-06-11T00:00:00Z',
    'workflow_session_id': session_id,
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': 'implement',
    'continuation_policy': 'continue',
    'continuation_reason': 'Stale driver prompt suppression regression fixture.',
    'project_done': False,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 1,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': [contract_id],
    'release_blocker_ids': [contract_id],
    'next_mandatory_action': 'Implement the selected fixture slice before continuing.',
    'next_mandatory_role': 'completion-implementer',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 0,
    'last_reground_at': '2026-06-11T00:00:00Z',
    'last_auditor_verdict': None,
    'contract_status': 'stale_driver_fixture',
    'latest_completed_slice': None,
    'latest_verified_slice': None,
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'last_reground_at': '2026-06-11T00:00:00Z',
    'plan_basis': 'stale_driver_fixture',
    'candidate_slices': [{
        'slice_id': 'fixture-stale-driver-prompt-suppression',
        'goal': mission,
        'acceptance_criteria': ['Stale queued driver prompts are suppressed after park or cancel.'],
        'contract_ids': [contract_id],
        'priority': 100,
        'status': 'selected',
        'why_now': 'Regression fixture for stale driver prompt suppression.',
        'blocked_on': [],
        'evidence': [],
        'locked_notes': [],
        'must_fix_findings': [],
        'implementation_surfaces': ['extensions/completion/index.ts'],
        'verification_commands': ['npm run stale-driver-prompt-suppression-test'],
        'basis_commit': basis_sha,
        'remaining_contract_ids_before': [contract_id],
        'release_blocker_count_before': 1,
        'high_value_gap_count_before': 1,
    }],
}
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'status': 'selected',
    'slice_id': 'fixture-stale-driver-prompt-suppression',
    'goal': mission,
    'contract_ids': [contract_id],
    'acceptance_criteria': ['Stale queued driver prompts are suppressed after park or cancel.'],
    'blocked_on': [],
    'locked_notes': [],
    'must_fix_findings': [],
    'implementation_surfaces': ['extensions/completion/index.ts'],
    'verification_commands': ['npm run stale-driver-prompt-suppression-test'],
    'basis_commit': basis_sha,
    'remaining_contract_ids_before': [contract_id],
    'release_blocker_count_before': 1,
    'high_value_gap_count_before': 1,
    'priority': 100,
    'why_now': 'Regression fixture for stale driver prompt suppression.',
}
startup_brief = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'primary_agent_handoff',
    'confirmed': True,
    'confirmed_at': '2026-06-11T00:00:00Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': [mission],
    'constraints': ['Preserve continue-state hard locks until Park or Cancel is recorded canonically.'],
    'acceptance': ['Stale queued driver prompts are suppressed after park or cancel.'],
    'risks': ['Regression fixture drift can hide stale driver prompt failures.'],
    'notes': ['Stale driver prompt suppression regression fixture.'],
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
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
    'summary': 'No deterministic verification evidence is recorded yet because this fixture is exercising stale driver prompt suppression.',
}

(current_dir / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
(current_dir / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
(current_dir / 'active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
(current_dir / 'startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
(current_dir / 'verification-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
(current_dir / 'slice-history.jsonl').write_text('')
(current_dir / 'stop-check-history.jsonl').write_text('')
PY
}

write_blocked_fixture() {
  local repo="$1"
  local session_id="$2"
  local mission="$3"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    printf '# stale driver prompt suppression fixture\n' > README.md
    git add README.md
    git -c user.name='Completion Test' -c user.email='completion-test@example.com' commit -qm 'fixture'
  )
  local basis_sha
  basis_sha="$(git -C "$repo" rev-parse HEAD)"

  python3 - "$repo" "$basis_sha" "$session_id" "$mission" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
basis_sha = sys.argv[2]
session_id = sys.argv[3]
mission = sys.argv[4]
current_dir = repo / '.agent' / 'current'
current_dir.mkdir(parents=True, exist_ok=True)
(current_dir / 'tmp').mkdir(parents=True, exist_ok=True)

contract_id = 'STALE-DRIVER-PROMPT-SUPPRESSION'
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-06-11T00:00:00Z',
    'workflow_session_id': session_id,
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': 'blocked',
    'continuation_policy': 'blocked',
    'continuation_reason': 'Blocked workflow before stale driver prompt cancel suppression.',
    'project_done': False,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 1,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': [contract_id],
    'release_blocker_ids': [contract_id],
    'next_mandatory_action': 'Resolve the blocked workflow fixture before continuing.',
    'next_mandatory_role': 'completion-regrounder',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 0,
    'last_reground_at': '2026-06-11T00:00:00Z',
    'last_auditor_verdict': None,
    'contract_status': 'stale_driver_cancel_fixture',
    'latest_completed_slice': None,
    'latest_verified_slice': None,
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'last_reground_at': '2026-06-11T00:00:00Z',
    'plan_basis': 'stale_driver_cancel_fixture',
    'candidate_slices': [{
        'slice_id': 'fixture-stale-driver-prompt-suppression',
        'goal': mission,
        'acceptance_criteria': ['Stale queued driver prompts are suppressed after cancel.'],
        'contract_ids': [contract_id],
        'priority': 100,
        'status': 'planned',
        'why_now': 'Regression fixture for stale driver prompt suppression.',
        'blocked_on': [],
        'evidence': [],
        'locked_notes': [],
        'must_fix_findings': [],
        'implementation_surfaces': ['extensions/completion/index.ts'],
        'verification_commands': ['npm run stale-driver-prompt-suppression-test'],
        'basis_commit': basis_sha,
        'remaining_contract_ids_before': [contract_id],
        'release_blocker_count_before': 1,
        'high_value_gap_count_before': 1,
    }],
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
    'blocked_on': [],
    'locked_notes': [],
    'must_fix_findings': [],
    'implementation_surfaces': [],
    'verification_commands': [],
    'basis_commit': None,
    'remaining_contract_ids_before': [],
    'release_blocker_count_before': None,
    'high_value_gap_count_before': None,
    'priority': None,
    'why_now': None,
}
startup_brief = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'primary_agent_handoff',
    'confirmed': True,
    'confirmed_at': '2026-06-11T00:00:00Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': [mission],
    'constraints': ['Preserve stopped-workflow controls until Cancel is recorded canonically.'],
    'acceptance': ['Stale queued driver prompts are suppressed after cancel.'],
    'risks': ['Regression fixture drift can hide stale driver prompt failures.'],
    'notes': ['Stale driver prompt suppression regression fixture.'],
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
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
    'summary': 'No deterministic verification evidence is recorded yet because this fixture is exercising stale driver prompt suppression.',
}

(current_dir / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
(current_dir / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
(current_dir / 'active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
(current_dir / 'startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
(current_dir / 'verification-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
(current_dir / 'slice-history.jsonl').write_text('')
(current_dir / 'stop-check-history.jsonl').write_text('')
PY
}

write_stale_driver_prompt_metadata() {
  local repo="$1"
  local prompt_path="$2"
  local session_id="$3"
  python3 - "$repo" "$prompt_path" "$session_id" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
prompt_path = Path(sys.argv[2])
session_id = sys.argv[3]
prompt = (
    'COMPLETION WORKFLOW DRIVER\n'
    'Resume the completion workflow from canonical state.\n\n'
    'Workflow session:\n'
    f'- workflow_session_id: {session_id}\n\n'
    'Resume instructions:\n'
    '- Continue from next_mandatory_role and next_mandatory_action.\n'
)
prompt_path.write_text(prompt)
metadata = {
    'kind': 'auto-resume',
    'queued_at': '2026-06-11T00:00:00Z',
    'workflow_session_id': session_id,
    'prompt_hash': hashlib.sha256(prompt.encode()).hexdigest(),
}
(root / '.agent/current/tmp/driver-prompt.json').write_text(json.dumps(metadata, indent=2) + '\n')
PY
}

run_stale_followup_suppression_case() {
  local label="$1"
  local repo="$2"
  local close_command="$3"
  local expected_superseded_reason="$4"
  local session_id="$5"
  local mission="$6"
  local fixture_writer="$7"
  local stale_prompt_path="$TMPDIR/${label}-stale-driver-prompt.txt"
  local capture="$TMPDIR/${label}-stale-driver-suppression.json"
  local agent_prompt_capture="$TMPDIR/${label}-stale-driver-agent-prompt.txt"
  local input_leak_capture="$TMPDIR/${label}-stale-driver-input-leak.txt"
  local system_reminder="$TMPDIR/${label}-stale-driver-system-reminder.txt"
  local out="$TMPDIR/pi-${label}-stale-driver-suppression.out"
  local err="$TMPDIR/pi-${label}-stale-driver-suppression.err"

  "$fixture_writer" "$repo" "$session_id" "$mission"
  write_stale_driver_prompt_metadata "$repo" "$stale_prompt_path" "$session_id"
  local stale_prompt_text
  stale_prompt_text="$(cat "$stale_prompt_path")"

  (
    cd "$repo"
    PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
    pi -e "$PKG_ROOT" -p "$close_command" \
      >"$TMPDIR/pi-${label}-close.out" 2>"$TMPDIR/pi-${label}-close.err"
  )

  python3 - "$repo" "$stale_prompt_text" "$expected_superseded_reason" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
stale_prompt = sys.argv[2]
expected_reason = sys.argv[3]
state = json.loads((root / '.agent/current/state.json').read_text())
driver_prompt = json.loads((root / '.agent/current/tmp/driver-prompt.json').read_text())
assert driver_prompt['kind'] == 'superseded', driver_prompt
assert driver_prompt.get('superseded_reason') == expected_reason, driver_prompt
assert driver_prompt.get('prompt_hash') is None, driver_prompt
assert hashlib.sha256(stale_prompt.encode()).hexdigest() != driver_prompt.get('prompt_hash'), driver_prompt
if expected_reason == 'parked':
    assert state['workflow_entry_status'] == 'parked', state
else:
    assert state['workflow_entry_status'] == 'cancelled', state
    assert state['continuation_policy'] == 'done', state
PY

  (
    cd "$repo"
    PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
    PI_COMPLETION_TEST_STALE_DRIVER_SUPPRESSION_CAPTURE_PATH="$capture" \
    PI_COMPLETION_TEST_STALE_DRIVER_AGENT_PROMPT_CAPTURE_PATH="$agent_prompt_capture" \
    PI_COMPLETION_TEST_STALE_DRIVER_INPUT_LEAK_CAPTURE_PATH="$input_leak_capture" \
    PI_COMPLETION_TEST_SYSTEM_REMINDER_PATH="$system_reminder" \
    PI_COMPLETION_TEST_STALE_DRIVER_PROMPT="$stale_prompt_text" \
    pi -e "$PKG_ROOT" -e "$PKG_ROOT/scripts/test-fixtures/stale-driver-prompt-suppression-extension.ts" -p "Warm up stale driver prompt suppression for ${label}." \
      >"$out" 2>"$err"
  )

  python3 - "$capture" "$agent_prompt_capture" "$input_leak_capture" "$system_reminder" "$out" "$err" <<'PY'
import json
import sys
from pathlib import Path

capture = Path(sys.argv[1])
agent_prompt_capture = Path(sys.argv[2])
input_leak_capture = Path(sys.argv[3])
system_reminder = Path(sys.argv[4])
output = Path(sys.argv[5]).read_text() + Path(sys.argv[6]).read_text()
assert capture.exists(), 'stale driver prompt hook should record suppression intent'
payload = json.loads(capture.read_text())
assert payload.get('suppressed') is True, payload
assert 'Ignored stale completion workflow driver prompt because canonical state no longer authorizes auto-resume or continuation.' in output, output
assert not agent_prompt_capture.exists(), f'stale driver prompt should not reach before_agent_start, got: {agent_prompt_capture.read_text() if agent_prompt_capture.exists() else ""}'
assert not input_leak_capture.exists(), f'stale driver prompt should not leak through the input pipeline, got: {input_leak_capture.read_text() if input_leak_capture.exists() else ""}'
if system_reminder.exists():
    text = system_reminder.read_text()
    assert '<completion-state>' not in text, text
    assert 'COMPLETION WORKFLOW DRIVER' not in text, text
PY
}

run_stale_followup_suppression_case \
  park \
  "$TMPDIR/park-repo" \
  '/cook park' \
  parked \
  'stale-driver-prompt-suppression-park-session' \
  'Exercise stale driver prompt suppression after /cook park.' \
  write_continue_fixture

run_stale_followup_suppression_case \
  cancel \
  "$TMPDIR/cancel-repo" \
  '/cook cancel' \
  cancelled \
  'stale-driver-prompt-suppression-cancel-session' \
  'Exercise stale driver prompt suppression after /cook cancel.' \
  write_blocked_fixture

echo "stale driver prompt suppression test passed"
