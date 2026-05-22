#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pi() {
  command pi --no-extensions "$@"
}
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

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

bootstrap_workflow() {
  local repo_root="$1"
  local session_path="$2"
  local discussion="$3"
  local generated_handoff="$4"
  mkdir -p "$repo_root"
  cd "$repo_root"
  git init -q
  write_session "$session_path" "$repo_root" "$discussion"
  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$generated_handoff" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi --session "$session_path" -e "$PKG_ROOT" -p "/cook" \
    >"$TMPDIR/bootstrap.out" 2>"$TMPDIR/bootstrap.err"
}

mark_done() {
  python3 - <<'PY'
import json
from pathlib import Path

state_path = Path('.agent/state.json')
plan_path = Path('.agent/plan.json')
active_path = Path('.agent/active-slice.json')

state = json.loads(state_path.read_text())
state.update({
    'current_phase': 'done',
    'continuation_policy': 'done',
    'continuation_reason': 'Previous workflow completed.',
    'project_done': True,
    'requires_reground': False,
    'next_mandatory_action': None,
    'next_mandatory_role': None,
    'remaining_stop_judges': 0,
    'last_reground_at': '2026-01-01T00:10:00.000Z',
    'contract_status': 'satisfied',
})
state_path.write_text(json.dumps(state, indent=2) + '\n')

plan = json.loads(plan_path.read_text())
plan.update({
    'plan_basis': 'completed_round_fixture',
    'candidate_slices': [],
})
plan_path.write_text(json.dumps(plan, indent=2) + '\n')

active = json.loads(active_path.read_text())
active.update({
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
    'basis_commit': None,
    'remaining_contract_ids_before': [],
    'release_blocker_count_before': None,
    'high_value_gap_count_before': None,
})
active_path.write_text(json.dumps(active, indent=2) + '\n')
PY
}

snapshot_tracked() {
  local baseline_path="$1"
  python3 - "$baseline_path" <<'PY'
import json
import sys
from pathlib import Path

tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/startup-plan.json'),
    Path('.agent/startup-plan.md'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
Path(sys.argv[1]).write_text(json.dumps({path.name: path.read_text() for path in tracked}, indent=2) + '\n')
PY
}

STARTUP_DISCUSSION=$'Remove the completion status line while keeping the completion widget and keep the startup confirm-first.'
STARTUP_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Remove the completion status line while keeping the completion widget.",
    "scope": [
        "Keep the non-running completion widget.",
        "Suppress the widget while a completion role is active."
    ],
    "constraints": [
        "Do not reintroduce another completion status surface."
    ],
    "acceptance": [
        "Update README to match the shipped behavior.",
        "Keep observability regression coverage truthful."
    ],
    "risks": [],
    "notes": ["Generated by same-entry primary-agent startup-plan synthesis."],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Remove the completion status line while preserving widget behavior.",
    "first_slice_non_goals": ["Do not add a replacement status surface."],
    "implementation_surfaces": ["extensions/completion/index.ts", "README.md"],
    "verification_commands": ["npm run smoke-test"],
    "why_this_slice_first": "The startup mission is already concrete and bounded enough to begin workflow planning.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The user explicitly chose workflow mode for this bounded implementation mission."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
MATCHING_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Remove the completion status line while keeping the completion widget.",
    "scope": ["Keep the widget behavior aligned with the current mission."],
    "constraints": ["Do not replace the current mission."],
    "acceptance": [
        "Keep the non-running completion widget visible while no role is active.",
        "Verify with npm run smoke-test that active-role suppression still works."
    ],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Continue the current mission without changing it.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["extensions/completion/index.ts"],
    "verification_commands": ["npm run smoke-test"],
    "why_this_slice_first": "The current mission already matches the latest startup plan.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The current workflow should continue without a mission change."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
NON_STARTABLE_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Maybe think about workflow status later.",
    "scope": ["Consider status changes eventually."],
    "constraints": ["Do not commit to concrete repo work yet."],
    "acceptance": ["Discuss possible approaches."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1"
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
NEXT_ROUND_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Start the next workflow round for widget follow-up docs.",
    "scope": [
        "Document the widget-only status behavior for the next round.",
        "Keep the next round confirm-first."
    ],
    "constraints": ["Do not reopen the previous mission."],
    "acceptance": [
        "Record the next round as a new canonical mission.",
        "Keep startup-plan persistence truthful for the next round."
    ],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Reset canonical state for the next widget-docs mission.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["README.md", ".agent/startup-plan.json"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The next round must be anchored before later slice derivation.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The previous workflow is done and the next round is concrete enough to start."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"

# Case 1: startup succeeds only through same-entry primary-agent synthesis.
ROOT_ONE="$TMPDIR/repo-one"
SESSION_ONE="$TMPDIR/session-one.jsonl"
PROPOSAL_ONE="$TMPDIR/proposal-one.json"
mkdir -p "$ROOT_ONE"
cd "$ROOT_ONE"
git init -q
write_session "$SESSION_ONE" "$ROOT_ONE" "$STARTUP_DISCUSSION"
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$STARTUP_HANDOFF" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_ONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/startup-success.out" 2>"$TMPDIR/startup-success.err"

python3 - "$PROPOSAL_ONE" "$TMPDIR/startup-success.out" "$TMPDIR/startup-success.err" <<'PY'
import json
import sys
from pathlib import Path

proposal = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
state = json.loads(Path('.agent/state.json').read_text())
startup_plan = json.loads(Path('.agent/startup-plan.json').read_text())

assert Path('.agent').exists(), 'same-entry primary-agent synthesis should scaffold canonical workflow state'
assert proposal['source'] == 'deferred_primary_agent_handoff', proposal
assert state['advisory_startup_brief']['source'] == 'deferred_primary_agent_handoff', state
assert startup_plan['source'] == 'deferred_primary_agent_handoff', startup_plan
assert 'Initialized completion control plane' in output, output
PY

# Case 2: assistant preview alone is ignored when same-entry synthesis is unavailable.
ROOT_TWO="$TMPDIR/repo-two"
SESSION_TWO="$TMPDIR/session-two.jsonl"
PROPOSAL_TWO="$TMPDIR/proposal-two.json"
mkdir -p "$ROOT_TWO"
cd "$ROOT_TWO"
git init -q
PREVIEW_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Assistant preview should not start workflow by itself.",
    "scope": ["Do not trust the old preview as approval-ready startup state."],
    "constraints": ["Require same-entry synthesis."],
    "acceptance": ["Fail closed without canonical state."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Prove preview-only startup is ignored.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["scripts/context-proposal-test.sh"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "Preview-only startup should no longer bootstrap workflow by itself."
}
messages = [
    {"role": "user", "content": "Should this preview be enough to start workflow on its own?"},
    {"role": "assistant", "content": "Preview only.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_TWO" "$ROOT_TWO" "$PREVIEW_MESSAGES"
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_TWO" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_TWO" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/preview-ignored.out" 2>"$TMPDIR/preview-ignored.err"

python3 - "$PROPOSAL_TWO" "$TMPDIR/preview-ignored.out" "$TMPDIR/preview-ignored.err" <<'PY'
import sys
from pathlib import Path

proposal = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not Path('.agent').exists(), 'preview-only startup must fail closed without same-entry synthesis'
assert not proposal.exists(), 'preview-only startup must not emit a proposal snapshot'
assert '/cook failed closed because the startup-plan step could not prepare a concrete workflow startup plan from the current task context.' in output, output
PY

# Case 3: structured discussion alone no longer falls back when synthesis is unavailable.
ROOT_THREE="$TMPDIR/repo-three"
SESSION_THREE="$TMPDIR/session-three.jsonl"
PROPOSAL_THREE="$TMPDIR/proposal-three.json"
mkdir -p "$ROOT_THREE"
cd "$ROOT_THREE"
git init -q
DISCUSSION_THREE=$'Mission: Rewrite startup flow from structured discussion only.\nScope:\n- Do not run same-entry synthesis.\nAcceptance:\n- Pretend transcript inference is enough.'
write_session "$SESSION_THREE" "$ROOT_THREE" "$DISCUSSION_THREE"
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_THREE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_THREE" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/discussion-ignored.out" 2>"$TMPDIR/discussion-ignored.err"

python3 - "$PROPOSAL_THREE" "$TMPDIR/discussion-ignored.out" "$TMPDIR/discussion-ignored.err" <<'PY'
import sys
from pathlib import Path

proposal = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not Path('.agent').exists(), 'structured discussion alone must fail closed without same-entry synthesis'
assert not proposal.exists(), 'structured discussion alone must not emit a proposal snapshot'
assert '/cook failed closed because the startup-plan step could not prepare a concrete workflow startup plan from the current task context.' in output, output
PY

# Case 4: non-startable synthesized startup plans fail closed with the dedicated same-entry message.
ROOT_FOUR="$TMPDIR/repo-four"
SESSION_FOUR="$TMPDIR/session-four.jsonl"
PROPOSAL_FOUR="$TMPDIR/proposal-four.json"
mkdir -p "$ROOT_FOUR"
cd "$ROOT_FOUR"
git init -q
write_session "$SESSION_FOUR" "$ROOT_FOUR" "$STARTUP_DISCUSSION"
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$NON_STARTABLE_HANDOFF" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_FOUR" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_FOUR" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/non-startable-startup.out" 2>"$TMPDIR/non-startable-startup.err"

python3 - "$PROPOSAL_FOUR" "$TMPDIR/non-startable-startup.out" "$TMPDIR/non-startable-startup.err" <<'PY'
import sys
from pathlib import Path

proposal = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not Path('.agent').exists(), 'non-startable synthesized startup must fail closed'
assert not proposal.exists(), 'non-startable synthesized startup must not emit a proposal snapshot'
assert 'same-entry primary-agent startup-plan synthesis step returned a startup plan that is still not concrete enough' in output, output
assert 'acceptance is not anchored to concrete repo changes or verification' in output, output
PY

# Case 5: active workflow resumes when same-entry synthesis matches the current mission.
ROOT_FIVE="$TMPDIR/repo-five"
SESSION_FIVE_BOOTSTRAP="$TMPDIR/session-five-bootstrap.jsonl"
SESSION_FIVE_MATCHING="$TMPDIR/session-five-matching.jsonl"
ROUTING_FIVE="$TMPDIR/routing-five.json"
CHOOSER_FIVE="$TMPDIR/chooser-five.json"
BASELINE_FIVE="$TMPDIR/baseline-five.json"
bootstrap_workflow "$ROOT_FIVE" "$SESSION_FIVE_BOOTSTRAP" "$STARTUP_DISCUSSION" "$STARTUP_HANDOFF"
cd "$ROOT_FIVE"
snapshot_tracked "$BASELINE_FIVE"
write_session "$SESSION_FIVE_MATCHING" "$ROOT_FIVE" $'Continue the widget mission and keep the workflow aligned.'
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$MATCHING_HANDOFF" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ROUTING_FIVE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CHOOSER_FIVE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_FIVE_MATCHING" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/matching-active.out" 2>"$TMPDIR/matching-active.err"

python3 - "$ROUTING_FIVE" "$CHOOSER_FIVE" "$BASELINE_FIVE" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
chooser = Path(sys.argv[2])
before = json.loads(Path(sys.argv[3]).read_text())
tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/startup-plan.json'),
    Path('.agent/startup-plan.md'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
after = {path.name: path.read_text() for path in tracked}
state = json.loads(after['state.json'])

assert routing['action'] == 'continue', routing
assert routing['reason'] == 'matching_generated_startup_plan', routing
assert routing['currentMissionAnchor'] == state['mission_anchor'], routing
assert routing['proposedMissionAnchor'] == state['mission_anchor'], routing
assert not chooser.exists(), 'matching synthesized mission should not open the chooser'
assert before == after, 'matching synthesized mission should leave canonical state unchanged before resume'
PY

# Case 6: non-startable synthesized active replacement blocks without rewriting canonical state.
ROOT_SIX="$TMPDIR/repo-six"
SESSION_SIX_BOOTSTRAP="$TMPDIR/session-six-bootstrap.jsonl"
SESSION_SIX_BLOCKED="$TMPDIR/session-six-blocked.jsonl"
ROUTING_SIX="$TMPDIR/routing-six.json"
CHOOSER_SIX="$TMPDIR/chooser-six.json"
PROPOSAL_SIX="$TMPDIR/proposal-six.json"
BASELINE_SIX="$TMPDIR/baseline-six.json"
bootstrap_workflow "$ROOT_SIX" "$SESSION_SIX_BOOTSTRAP" "$STARTUP_DISCUSSION" "$STARTUP_HANDOFF"
cd "$ROOT_SIX"
snapshot_tracked "$BASELINE_SIX"
write_session "$SESSION_SIX_BLOCKED" "$ROOT_SIX" $'Maybe replace the current mission, but the new intent is still vague.'
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$NON_STARTABLE_HANDOFF" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ROUTING_SIX" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CHOOSER_SIX" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_SIX" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_SIX_BLOCKED" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/blocked-active.out" 2>"$TMPDIR/blocked-active.err"

python3 - "$ROUTING_SIX" "$CHOOSER_SIX" "$PROPOSAL_SIX" "$BASELINE_SIX" "$TMPDIR/blocked-active.out" "$TMPDIR/blocked-active.err" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
chooser = Path(sys.argv[2])
proposal = Path(sys.argv[3])
before = json.loads(Path(sys.argv[4]).read_text())
output = Path(sys.argv[5]).read_text() + Path(sys.argv[6]).read_text()
tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/startup-plan.json'),
    Path('.agent/startup-plan.md'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
after = {path.name: path.read_text() for path in tracked}

assert routing['action'] == 'blocked', routing
assert routing['reason'] == 'generated_startup_plan_not_startable', routing
assert 'same-entry primary-agent startup-plan synthesis step returned a startup plan that is still not concrete enough' in routing['blockedFailureMessage'], routing
assert not chooser.exists(), 'blocked replacement should not open the chooser'
assert not proposal.exists(), 'blocked replacement should not open final proposal confirmation'
assert before == after, 'blocked replacement should leave canonical state unchanged'
assert 'same-entry primary-agent startup-plan synthesis step returned a startup plan that is still not concrete enough' in output, output
PY

# Case 7: done workflow starts the next round from same-entry synthesis.
ROOT_SEVEN="$TMPDIR/repo-seven"
SESSION_SEVEN_BOOTSTRAP="$TMPDIR/session-seven-bootstrap.jsonl"
SESSION_SEVEN_NEXT="$TMPDIR/session-seven-next.jsonl"
PROPOSAL_SEVEN="$TMPDIR/proposal-seven.json"
bootstrap_workflow "$ROOT_SEVEN" "$SESSION_SEVEN_BOOTSTRAP" "$STARTUP_DISCUSSION" "$STARTUP_HANDOFF"
cd "$ROOT_SEVEN"
mark_done
write_session "$SESSION_SEVEN_NEXT" "$ROOT_SEVEN" $'Start the next workflow round for widget follow-up docs.'
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$NEXT_ROUND_HANDOFF" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_SEVEN" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_SEVEN_NEXT" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/next-round.out" 2>"$TMPDIR/next-round.err"

python3 - "$PROPOSAL_SEVEN" "$TMPDIR/next-round.out" "$TMPDIR/next-round.err" <<'PY'
import json
import sys
from pathlib import Path

proposal = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
state = json.loads(Path('.agent/state.json').read_text())
startup_plan = json.loads(Path('.agent/startup-plan.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())
mission = 'Start the next workflow round for widget follow-up docs.'

assert proposal['source'] == 'deferred_primary_agent_handoff', proposal
assert state['mission_anchor'] == mission, state
assert state['current_phase'] == 'reground', state
assert state['next_mandatory_role'] == 'completion-regrounder', state
assert startup_plan['mission_anchor'] == mission, startup_plan
assert startup_plan['source'] == 'deferred_primary_agent_handoff', startup_plan
assert plan['mission_anchor'] == mission, plan
assert active['mission_anchor'] == mission, active
assert 'Started a new completion workflow round and recorded the approved startup plan' in output, output
PY

grep -q 'export function assessCookHandoffText' "$PKG_ROOT/extensions/completion/proposal.ts"
grep -q 'export async function deriveCookContextProposalFromRecentDiscussion' "$PKG_ROOT/extensions/completion/proposal.ts"
grep -q 'export async function analyzeContextProposalWithAgent' "$PKG_ROOT/extensions/completion/role-runner.ts"

echo "context proposal test passed: $PKG_ROOT"
