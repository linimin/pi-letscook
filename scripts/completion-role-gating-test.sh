#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
pi() {
  env -u PI_COMPLETION_ROLE command pi --no-extensions "$@"
}

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required completion-role gating text: ${snippet}`);
  }
};
const assertNotIncludes = (file, snippet) => {
  const text = read(file);
  if (text.includes(snippet)) {
    throw new Error(`${file} still contains stale completion-role gating text: ${snippet}`);
  }
};

assertIncludes('extensions/completion/index.ts', 'function hasWorkflowRecord(');
assertIncludes('extensions/completion/index.ts', 'function workflowHardLockActive(');
assertIncludes('extensions/completion/index.ts', 'function hasStickyWorkflowContinuation(');
assertIncludes('extensions/completion/index.ts', 'function isLikelyWorkflowContinuationTurn(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionWorkflowSessionTurn(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionWorkflowDispatchContext(');
assertIncludes('extensions/completion/index.ts', 'if (!hasWorkflowRecord(snapshot)) return false;');
assertIncludes('extensions/completion/index.ts', 'if (isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx)) return true;');
assertIncludes('extensions/completion/index.ts', 'return isCompletionWorkflowSessionTurn(snapshot, ctx) || hasStickyWorkflowContinuation(snapshot);');
assertIncludes('extensions/completion/index.ts', 'hasStickyWorkflowContinuation(snapshot) && hasRecentlyCompletedCompletionRole(rootKey)');
assertIncludes('extensions/completion/index.ts', 'function shouldInjectStoppedWorkflowBoundary(');
assertIncludes('extensions/completion/index.ts', 'const stoppedWorkflowReminder = buildStoppedWorkflowBoundaryReminder(loaded.snapshot);');
assertIncludes('extensions/completion/index.ts', 'const workflowHardLockActiveNow = workflowHardLockActive(snapshot);');
assertIncludes('extensions/completion/index.ts', 'workflowHardLockActive: workflowHardLockActiveNow,');
assertIncludes('extensions/completion/driver.ts', 'function parseCookWorkflowControlAction(');
assertIncludes('extensions/completion/driver.ts', 'async function parkWorkflow(');
assertIncludes('extensions/completion/driver.ts', 'async function supersedeQueuedDriverPromptMetadata(');
assertIncludes('extensions/completion/driver.ts', 'async function reactivateParkedWorkflow(');
assertIncludes('extensions/completion/driver.ts', 'async function cancelStoppedWorkflow(');
assertIncludes('extensions/completion/driver.ts', 'supersedeQueuedDriverPromptMetadata(snapshot, "cancelled")');
assertIncludes('extensions/completion/driver.ts', 'clearDriverContinuationTracker(rootKey)');
assertNotIncludes('extensions/completion/driver.ts', '"/cook park is only available when the current workflow is already stopped');
assertIncludes('extensions/completion/driver.ts', '"/cook cancel is only available when the current workflow is already stopped');
assertIncludes('extensions/completion/index.ts', 'function isWorkflowClosedForDriverContinuation(');
assertIncludes('extensions/completion/index.ts', 'function isAuthoritativeQueuedCompletionDriverPrompt(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionDriverPromptText(');
assertIncludes('extensions/completion/index.ts', 'pi.on("input"');
assertIncludes('extensions/completion/index.ts', 'return { action: "handled" as const };');
assertIncludes('extensions/completion/index.ts', 'Ignored stale completion workflow driver prompt because canonical state no longer authorizes auto-resume or continuation.');
assertIncludes('extensions/completion/index.ts', '/cook park is available anytime an active workflow exists, including while continuation_policy is continue');
assertIncludes('extensions/completion/index.ts', '/cook park anytime while a workflow is active; resume and cancel when stopped or parked');
assertIncludes('extensions/completion/policy-guards.ts', 'workflowHardLockActive: boolean;');
assertIncludes('extensions/completion/policy-guards.ts', 'while the completion workflow is hard-locked.');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'export function buildStoppedWorkflowBoundaryReminder(');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Supported same-repo controls are: rerun /cook or /cook resume to continue from canonical state; run /cook park');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'If requires_reground == true and next_mandatory_role == completion-regrounder, auto-dispatch regrounder unless canonical state proves a real external blocker.');
assertIncludes('extensions/completion/index.ts', 'If requires_reground == true and next_mandatory_role == completion-regrounder, treat that as a continue-state auto-reground handoff unless canonical state also proves a real external blocker.');
assertIncludes('docs/maintainer/protocol.md', 'routine internal re-grounding is not a stopped state by itself');
assertIncludes('CHANGELOG.md', 'added explicit stopped-workflow `/cook resume`, `/cook park`, and `/cook cancel` controls');

assertNotIncludes('extensions/completion/index.ts', 'return hasCompletionRoutingActivation(snapshot) || hasActiveWorkflowEntry(snapshot);');
assertNotIncludes('extensions/completion/policy-guards.ts', 'completionActive: boolean;');

const indexText = read('extensions/completion/index.ts');
const workflowRecordIndex = indexText.indexOf('function hasWorkflowRecord(');
const stickyContinuationIndex = indexText.indexOf('function hasStickyWorkflowContinuation(');
const continuationIntentIndex = indexText.indexOf('function isLikelyWorkflowContinuationTurn(');
const sessionTurnIndex = indexText.indexOf('function isCompletionWorkflowSessionTurn(');
const stoppedBoundaryIndex = indexText.indexOf('function shouldInjectStoppedWorkflowBoundary(');
const dispatchContextIndex = indexText.indexOf('function isCompletionWorkflowDispatchContext(');
const sessionTurnCookIndex = indexText.indexOf('if (isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx)) return true;');
const stickyReturnIndex = indexText.indexOf('return isCompletionWorkflowSessionTurn(snapshot, ctx) || hasStickyWorkflowContinuation(snapshot);');
const stoppedReminderIndex = indexText.indexOf('const stoppedWorkflowReminder = buildStoppedWorkflowBoundaryReminder(loaded.snapshot);');
const agentEndSelfHealIndex = indexText.indexOf('hasStickyWorkflowContinuation(snapshot) && hasRecentlyCompletedCompletionRole(rootKey)');
const toolGateIndex = indexText.indexOf('const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowDispatchContext(snapshot, ctx);');
const roleExecutionIndex = indexText.indexOf('const result = await runCompletionRole({');
const postRoleCleanupIndex = indexText.indexOf('await cleanupClosedWorkflowRuntimeIfNeeded(runCwd);');
const liveRoleStatusIndex = indexText.indexOf('liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(result.activity, { status: result.ok ? "ok" : "error" }));');
const postRoleStatusRefreshIndex = indexText.indexOf('await refreshCompletionStatus({ ctx: ctx as { cwd: string; hasUI: boolean; ui: any }, ...statusSurfaceArgs });', postRoleCleanupIndex);
if (
  workflowRecordIndex === -1 ||
  stickyContinuationIndex === -1 ||
  continuationIntentIndex === -1 ||
  sessionTurnIndex === -1 ||
  stoppedBoundaryIndex === -1 ||
  dispatchContextIndex === -1 ||
  sessionTurnCookIndex === -1 ||
  stickyReturnIndex === -1 ||
  stoppedReminderIndex === -1 ||
  agentEndSelfHealIndex === -1 ||
  toolGateIndex === -1
) {
  throw new Error('extensions/completion/index.ts must self-heal active continuation sessions and expose stopped-workflow controls before dispatching completion_role.');
}
if (!(workflowRecordIndex < stickyContinuationIndex && stickyContinuationIndex < continuationIntentIndex && continuationIntentIndex < sessionTurnCookIndex && sessionTurnCookIndex < sessionTurnIndex && sessionTurnIndex < dispatchContextIndex && dispatchContextIndex < stickyReturnIndex && stickyReturnIndex < stoppedBoundaryIndex && stoppedBoundaryIndex < agentEndSelfHealIndex && agentEndSelfHealIndex < stoppedReminderIndex && stoppedReminderIndex < toolGateIndex)) {
  throw new Error('extensions/completion/index.ts should define workflow-presence, stopped-boundary, and sticky continuation helpers before reusing them for completion_role dispatch.');
}
if (roleExecutionIndex === -1 || postRoleCleanupIndex === -1 || liveRoleStatusIndex === -1 || postRoleStatusRefreshIndex === -1) {
  throw new Error('extensions/completion/index.ts must keep immediate post-completion_role cleanup assertions in place.');
}
if (!(roleExecutionIndex < postRoleCleanupIndex && postRoleCleanupIndex < liveRoleStatusIndex && liveRoleStatusIndex < postRoleStatusRefreshIndex)) {
  throw new Error('extensions/completion/index.ts should clean closed workflow residue immediately after completion_role returns and before status refresh.');
}
NODE

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

write_stopped_fixture() {
  local repo="$1"
  local continuation_policy="$2"
  local current_phase="$3"
  local workflow_entry_status="${4:-active}"
  local continuation_reason="${5:-Stopped workflow regression fixture.}"
  local requires_reground="${6:-__default__}"
  local next_mandatory_role="${7:-__default__}"
  local next_mandatory_action="${8:-Resume or park the stopped workflow fixture.}"

  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    printf '# stopped workflow fixture\n' > README.md
    git add README.md
    git -c user.name='Completion Test' -c user.email='completion-test@example.com' commit -qm 'fixture'
  )
  local basis_sha
  basis_sha="$(git -C "$repo" rev-parse HEAD)"

  python3 - "$repo" "$basis_sha" "$continuation_policy" "$current_phase" "$workflow_entry_status" "$continuation_reason" "$requires_reground" "$next_mandatory_role" "$next_mandatory_action" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
basis_sha = sys.argv[2]
continuation_policy = sys.argv[3]
current_phase = sys.argv[4]
workflow_entry_status = sys.argv[5]
continuation_reason = sys.argv[6]
requires_reground_raw = sys.argv[7]
next_mandatory_role_raw = sys.argv[8]
next_mandatory_action = sys.argv[9]

if requires_reground_raw == '__default__':
    requires_reground = workflow_entry_status != 'active'
else:
    requires_reground = requires_reground_raw.lower() == 'true'

if next_mandatory_role_raw == '__default__':
    next_mandatory_role = 'completion-regrounder' if workflow_entry_status != 'active' else 'completion-implementer'
else:
    next_mandatory_role = next_mandatory_role_raw
current_dir = repo / '.agent' / 'current'
current_dir.mkdir(parents=True, exist_ok=True)
(current_dir / 'tmp').mkdir(parents=True, exist_ok=True)

mission = 'Exercise stopped-workflow Resume/Park/Cancel controls.'
contract_id = 'STOPPED-WORKFLOW-RESUME-PARK-CANCEL'
implementation_surfaces = [
    'extensions/completion/index.ts',
    'extensions/completion/driver.ts',
    'extensions/completion/policy-guards.ts',
    'extensions/completion/prompt-surfaces.ts',
    'README.md',
]
verification_commands = ['npm run completion-role-gating-test']
acceptance = [
    'Stopped workflows expose explicit same-repo Resume/Park/Cancel controls.',
    'Park clears stale active-slice handoff and forces canonical reground.',
]
selected_status = 'selected' if workflow_entry_status == 'active' else 'planned'
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'status': 'selected' if workflow_entry_status == 'active' else 'idle',
    'slice_id': 'fixture-stopped-workflow-controls' if workflow_entry_status == 'active' else None,
    'goal': 'Exercise explicit stopped-workflow Resume/Park/Cancel controls.' if workflow_entry_status == 'active' else None,
    'contract_ids': [contract_id] if workflow_entry_status == 'active' else [],
    'acceptance_criteria': acceptance if workflow_entry_status == 'active' else [],
    'blocked_on': [],
    'locked_notes': ['Preserve hard locks until Park or Cancel is recorded canonically.'] if workflow_entry_status == 'active' else [],
    'must_fix_findings': [],
    'implementation_surfaces': implementation_surfaces if workflow_entry_status == 'active' else [],
    'verification_commands': verification_commands if workflow_entry_status == 'active' else [],
    'basis_commit': basis_sha if workflow_entry_status == 'active' else None,
    'remaining_contract_ids_before': [contract_id] if workflow_entry_status == 'active' else [],
    'release_blocker_count_before': 1 if workflow_entry_status == 'active' else None,
    'high_value_gap_count_before': 1 if workflow_entry_status == 'active' else None,
    'priority': 100 if workflow_entry_status == 'active' else None,
    'why_now': 'Regression fixture for stopped-workflow control coverage.' if workflow_entry_status == 'active' else None,
}
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': workflow_entry_status,
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-06-11T00:00:00Z',
    'workflow_session_id': 'stopped-workflow-fixture-session',
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': current_phase,
    'continuation_policy': continuation_policy,
    'continuation_reason': continuation_reason,
    'project_done': False,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'requires_reground': requires_reground,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 1,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': [contract_id],
    'release_blocker_ids': [contract_id],
    'next_mandatory_action': next_mandatory_action,
    'next_mandatory_role': next_mandatory_role,
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 0,
    'last_reground_at': '2026-06-11T00:00:00Z',
    'last_auditor_verdict': None,
    'contract_status': 'stopped_fixture',
    'latest_completed_slice': None,
    'latest_verified_slice': None,
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'last_reground_at': '2026-06-11T00:00:00Z',
    'plan_basis': 'stopped_workflow_fixture',
    'candidate_slices': [
        {
            'slice_id': 'fixture-stopped-workflow-controls',
            'goal': 'Exercise explicit stopped-workflow Resume/Park/Cancel controls.',
            'acceptance_criteria': acceptance,
            'contract_ids': [contract_id],
            'priority': 100,
            'status': selected_status,
            'why_now': 'Regression fixture for stopped-workflow control coverage.',
            'blocked_on': [],
            'evidence': [],
            'locked_notes': ['Preserve hard locks until Park or Cancel is recorded canonically.'],
            'must_fix_findings': [],
            'implementation_surfaces': implementation_surfaces,
            'verification_commands': verification_commands,
            'basis_commit': basis_sha,
            'remaining_contract_ids_before': [contract_id],
            'release_blocker_count_before': 1,
            'high_value_gap_count_before': 1,
        }
    ],
}
startup_brief = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'primary_agent_handoff',
    'confirmed': True,
    'confirmed_at': '2026-06-11T00:00:00Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': ['Exercise stopped-workflow command controls from canonical state.'],
    'constraints': ['Preserve continue-state hard locks while allowing explicit Park/Cancel.'],
    'acceptance': acceptance,
    'risks': ['Regression fixture drift can hide stopped-workflow dead-zone failures.'],
    'notes': ['Stopped-workflow control regression fixture.'],
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
    'summary': 'No deterministic verification evidence is recorded yet because this fixture is exercising stopped-workflow control state.',
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

ACTIVE_REGROUND_ROOT="$TMPDIR/active-reground-repo"
write_stopped_fixture "$ACTIVE_REGROUND_ROOT" continue reground active 'Active auto-reground workflow regression fixture.' true completion-regrounder 'Reconcile canonical state from current repo truth before continuing the active auto-reground fixture.'

ACTIVE_REGROUND_REMINDER="$TMPDIR/active-reground-reminder.txt"
ACTIVE_REGROUND_AUTO_RESUME="$TMPDIR/active-reground-auto-resume.txt"
(
  cd "$ACTIVE_REGROUND_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH="$ACTIVE_REGROUND_REMINDER" \
  PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH="$ACTIVE_REGROUND_AUTO_RESUME" \
  pi -e "$ROOT" -p 'Please keep going on the workflow.' \
    >"$TMPDIR/pi-active-reground-ordinary.out" 2>"$TMPDIR/pi-active-reground-ordinary.err"
)

python3 - "$ACTIVE_REGROUND_REMINDER" "$ACTIVE_REGROUND_AUTO_RESUME" "$TMPDIR/pi-active-reground-ordinary.out" "$TMPDIR/pi-active-reground-ordinary.err" <<'PY'
import sys
from pathlib import Path

reminder = Path(sys.argv[1])
auto_resume = Path(sys.argv[2])
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
if reminder.exists():
    text = reminder.read_text()
    assert 'currently stopped but still canonically active' not in text, text
assert auto_resume.exists(), 'active continue-state auto-reground should still auto-resume ordinary follow-up'
prompt = auto_resume.read_text()
assert 'Resume the completion workflow from canonical state.' in prompt, prompt
assert 'If requires_reground == true and next_mandatory_role == completion-regrounder, treat that as a continue-state auto-reground handoff unless canonical state also proves a real external blocker.' in prompt, prompt
assert 'Skipped completion workflow auto-resume prompt (test mode)' in output, output
PY

CONTINUE_ROOT="$TMPDIR/continue-repo"
write_stopped_fixture "$CONTINUE_ROOT" continue implement active 'Active continue-state workflow regression fixture.' false completion-implementer 'Implement the selected fixture slice before continuing.'

(
  cd "$CONTINUE_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi -e "$ROOT" -p '/cook park' \
    >"$TMPDIR/pi-continue-workflow-park.out" 2>"$TMPDIR/pi-continue-workflow-park.err"
)

python3 - "$CONTINUE_ROOT" "$TMPDIR/pi-continue-workflow-park.out" "$TMPDIR/pi-continue-workflow-park.err" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
state = json.loads((root / '.agent/current/state.json').read_text())
plan = json.loads((root / '.agent/current/plan.json').read_text())
active = json.loads((root / '.agent/current/active-slice.json').read_text())
evidence = json.loads((root / '.agent/current/verification-evidence.json').read_text())
assert state['workflow_entry_status'] == 'parked', state
assert state['continuation_policy'] == 'paused', state
assert state['requires_reground'] is True, state
assert state['next_mandatory_role'] == 'completion-regrounder', state
assert 'continuation_policy was continue' in state['continuation_reason'], state
assert active['status'] == 'idle', active
assert active['slice_id'] is None, active
assert plan['candidate_slices'][0]['status'] == 'planned', plan
assert evidence['subject_type'] == 'none', evidence
assert 'Parked active completion workflow.' in output, output
driver_prompt = json.loads((root / '.agent/current/tmp/driver-prompt.json').read_text())
assert driver_prompt['kind'] == 'superseded', driver_prompt
assert driver_prompt.get('superseded_reason') == 'parked', driver_prompt
assert driver_prompt.get('prompt_hash') is None, driver_prompt
PY

CONTINUE_PARKED_AUTO_RESUME="$TMPDIR/continue-parked-auto-resume.txt"
(
  cd "$CONTINUE_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH="$CONTINUE_PARKED_AUTO_RESUME" \
  pi -e "$ROOT" -p 'Please keep going on the workflow.' \
    >"$TMPDIR/pi-continue-parked-ordinary.out" 2>"$TMPDIR/pi-continue-parked-ordinary.err"
)

if [[ -e "$CONTINUE_PARKED_AUTO_RESUME" ]]; then
  echo "expected /cook park from continue state to disable stale auto-resume on ordinary follow-up" >&2
  exit 1
fi

BLOCKED_ROOT="$TMPDIR/blocked-repo"
write_stopped_fixture "$BLOCKED_ROOT" blocked blocked active 'Blocked stopped-workflow regression fixture.'

STOPPED_REMINDER="$TMPDIR/stopped-workflow-reminder.txt"
STOPPED_AUTO_RESUME="$TMPDIR/stopped-workflow-auto-resume.txt"
(
  cd "$BLOCKED_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH="$STOPPED_REMINDER" \
  PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH="$STOPPED_AUTO_RESUME" \
  pi -e "$ROOT" -p 'Please let me edit directly in ordinary chat.' \
    >"$TMPDIR/pi-stopped-workflow-ordinary.out" 2>"$TMPDIR/pi-stopped-workflow-ordinary.err"
)

python3 - "$STOPPED_REMINDER" "$STOPPED_AUTO_RESUME" "$TMPDIR/pi-stopped-workflow-ordinary.out" "$TMPDIR/pi-stopped-workflow-ordinary.err" <<'PY'
import sys
from pathlib import Path

reminder = Path(sys.argv[1])
auto_resume = Path(sys.argv[2])
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
assert reminder.exists(), 'ordinary blocked workflow turn should inject the stopped-workflow control reminder'
text = reminder.read_text()
assert 'currently stopped but still canonically active' in text, text
assert '/cook resume' in text, text
assert '/cook park' in text, text
assert '/cook cancel' in text, text
assert 'Do not tell the user to hand-edit .agent state or open a new chat' in text, text
assert not auto_resume.exists(), 'ordinary blocked workflow turn must not auto-resume'
assert 'Skipped completion workflow auto-resume prompt (test mode)' not in output, output
PY

(
  cd "$BLOCKED_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi -e "$ROOT" -p '/cook park' \
    >"$TMPDIR/pi-stopped-workflow-park.out" 2>"$TMPDIR/pi-stopped-workflow-park.err"
)

python3 - "$BLOCKED_ROOT" "$TMPDIR/pi-stopped-workflow-park.out" "$TMPDIR/pi-stopped-workflow-park.err" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
state = json.loads((root / '.agent/current/state.json').read_text())
plan = json.loads((root / '.agent/current/plan.json').read_text())
active = json.loads((root / '.agent/current/active-slice.json').read_text())
evidence = json.loads((root / '.agent/current/verification-evidence.json').read_text())
assert state['workflow_entry_status'] == 'parked', state
assert state['continuation_policy'] == 'paused', state
assert state['requires_reground'] is True, state
assert state['next_mandatory_role'] == 'completion-regrounder', state
assert state['next_mandatory_action'] == 'Reconcile canonical state from current repo truth before resuming the parked workflow.', state
assert active['status'] == 'idle', active
assert active['slice_id'] is None, active
assert active['acceptance_criteria'] == [], active
assert plan['candidate_slices'][0]['status'] == 'planned', plan
assert evidence['subject_type'] == 'none', evidence
assert evidence['outcome'] == 'not_recorded', evidence
assert 'Parked completion workflow.' in output, output
PY

PARKED_BOUNDARY="$TMPDIR/parked-workflow-boundary.txt"
PARKED_AUTO_RESUME="$TMPDIR/parked-workflow-auto-resume.txt"
(
  cd "$BLOCKED_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH="$PARKED_BOUNDARY" \
  PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH="$PARKED_AUTO_RESUME" \
  pi -e "$ROOT" -p 'Work on the repo in ordinary chat now.' \
    >"$TMPDIR/pi-parked-workflow-ordinary.out" 2>"$TMPDIR/pi-parked-workflow-ordinary.err"
)

python3 - "$PARKED_BOUNDARY" "$PARKED_AUTO_RESUME" <<'PY'
import sys
from pathlib import Path

boundary = Path(sys.argv[1])
auto_resume = Path(sys.argv[2])
assert boundary.exists(), 'parked workflow should fall back to the ordinary /cook boundary reminder'
text = boundary.read_text()
assert 'ordinary main chat unless the user explicitly runs /cook' in text, text
assert '/cook is optional workflow mode' in text, text
assert 'currently stopped but still canonically active' not in text, text
assert not auto_resume.exists(), 'parked workflow must not auto-resume ordinary chat'
PY

PARKED_RESUME_PROMPT="$TMPDIR/parked-workflow-resume-prompt.txt"
(
  cd "$BLOCKED_ROOT"
  PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$PARKED_RESUME_PROMPT" \
  pi -e "$ROOT" -p '/cook' \
    >"$TMPDIR/pi-parked-workflow-resume.out" 2>"$TMPDIR/pi-parked-workflow-resume.err"
)

python3 - "$BLOCKED_ROOT" "$PARKED_RESUME_PROMPT" "$TMPDIR/pi-parked-workflow-resume.out" "$TMPDIR/pi-parked-workflow-resume.err" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
prompt = Path(sys.argv[2]).read_text()
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
state = json.loads((root / '.agent/current/state.json').read_text())
assert state['workflow_entry_status'] == 'active', state
assert state['continuation_policy'] == 'continue', state
assert state['current_phase'] == 'reground', state
assert state['requires_reground'] is True, state
assert state['next_mandatory_role'] == 'completion-regrounder', state
assert 'Resume the completion workflow from canonical state.' in prompt, prompt
assert '/cook park' in prompt, prompt
assert '/cook cancel' in prompt, prompt
assert 'Resumed parked completion workflow from canonical state' in output, output
PY

AWAIT_ROOT="$TMPDIR/await-user-input-repo"
write_stopped_fixture "$AWAIT_ROOT" await_user_input awaiting_user active 'Await-user-input stopped-workflow regression fixture.'
AWAIT_RESUME_PROMPT="$TMPDIR/await-user-input-resume-prompt.txt"
(
  cd "$AWAIT_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$AWAIT_RESUME_PROMPT" \
  pi -e "$ROOT" -p '/cook resume' \
    >"$TMPDIR/pi-await-user-input-resume.out" 2>"$TMPDIR/pi-await-user-input-resume.err"
)

python3 - "$AWAIT_ROOT" "$AWAIT_RESUME_PROMPT" "$TMPDIR/pi-await-user-input-resume.out" "$TMPDIR/pi-await-user-input-resume.err" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
prompt = Path(sys.argv[2]).read_text()
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
state = json.loads((root / '.agent/current/state.json').read_text())
assert state['workflow_entry_status'] == 'active', state
assert state['continuation_policy'] == 'await_user_input', state
assert state['current_phase'] == 'awaiting_user', state
assert 'Resume the completion workflow from canonical state.' in prompt, prompt
assert '/cook park' in prompt, prompt
assert '/cook cancel' in prompt, prompt
assert 'Skipped completion workflow resume prompt (test mode)' in output, output
PY

CANCEL_ROOT="$TMPDIR/cancel-repo"
write_stopped_fixture "$CANCEL_ROOT" blocked blocked active 'Blocked workflow that should be cancellable.'
python3 - "$CANCEL_ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
metadata = {
    'kind': 'auto-resume',
    'queued_at': '2026-06-11T00:00:00Z',
    'workflow_session_id': 'stopped-workflow-fixture-session',
    'prompt_hash': 'pre-cancel-queued-driver-prompt-hash',
}
(root / '.agent/current/tmp/driver-prompt.json').write_text(json.dumps(metadata, indent=2) + '\n')
PY
(
  cd "$CANCEL_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi -e "$ROOT" -p '/cook cancel' \
    >"$TMPDIR/pi-stopped-workflow-cancel.out" 2>"$TMPDIR/pi-stopped-workflow-cancel.err"
)

python3 - "$CANCEL_ROOT" "$TMPDIR/pi-stopped-workflow-cancel.out" "$TMPDIR/pi-stopped-workflow-cancel.err" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
assert 'Cancelled completion workflow.' in output, output
state_path = root / '.agent/current/state.json'
if state_path.exists():
    state = json.loads(state_path.read_text())
    assert state['continuation_policy'] == 'done', state
    assert state['workflow_entry_status'] == 'cancelled', state
driver_prompt_path = root / '.agent/current/tmp/driver-prompt.json'
if driver_prompt_path.exists():
    driver_prompt = json.loads(driver_prompt_path.read_text())
    assert driver_prompt['kind'] == 'superseded', driver_prompt
    assert driver_prompt.get('superseded_reason') == 'cancelled', driver_prompt
    assert driver_prompt.get('prompt_hash') is None, driver_prompt
PY

CANCEL_AUTO_RESUME="$TMPDIR/cancel-auto-resume.txt"
(
  cd "$CANCEL_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_ON_SESSION_START=1 \
  PI_COMPLETION_TEST_AUTO_CONTINUE_PROMPT_PATH="$CANCEL_AUTO_RESUME" \
  pi -e "$ROOT" -p 'Continue in ordinary chat after cancel.' \
    >"$TMPDIR/pi-stopped-workflow-cancel-follow-up.out" 2>"$TMPDIR/pi-stopped-workflow-cancel-follow-up.err"
)

if [[ -e "$CANCEL_AUTO_RESUME" ]]; then
  echo "expected /cook cancel to disable stale auto-resume on ordinary follow-up" >&2
  exit 1
fi

echo "completion-role gating test passed"
