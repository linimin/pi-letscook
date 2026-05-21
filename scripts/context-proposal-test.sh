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

ROOT="$TMPDIR/repo"
mkdir -p "$ROOT"
cd "$ROOT"
git init -q

# No workflow yet: bare /cook should be able to generate a primary-agent handoff in the same entry,
# then continue directly to startup confirmation.
SESSION_ZERO="$TMPDIR/session-zero.jsonl"
DISCUSSION_ZERO=$'Mission: Remove the completion status line while keeping the completion widget.
Scope:
- Keep the non-running completion widget.
- Suppress the widget while a completion role is active.
Constraints:
- Do not reintroduce any other completion status surface.
Acceptance:
- Update README to match the shipped behavior.
- Keep observability regression coverage truthful.'
DISCUSSION_SNAPSHOT_ZERO="$TMPDIR/context-proposal-structured-fallback.json"
GENERATED_HANDOFF_ZERO="$(python3 - <<'PY'
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
        "Do not reintroduce any other completion status surface."
    ],
    "acceptance": [
        "Update README to match the shipped behavior.",
        "Keep observability regression coverage truthful."
    ],
    "risks": [],
    "notes": ["Generated by the primary-agent handoff step triggered from /cook."],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Remove the completion status line while preserving the widget behavior.",
    "first_slice_non_goals": ["Do not reintroduce another status surface."],
    "implementation_surfaces": ["extensions/completion/index.ts", "README.md"],
    "verification_commands": ["npm run smoke-test"],
    "why_this_slice_first": "This slice is already concrete and bounded enough to start workflow safely.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The user explicitly chose workflow mode for this bounded implementation slice."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
write_session "$SESSION_ZERO" "$ROOT" "$DISCUSSION_ZERO"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$GENERATED_HANDOFF_ZERO" PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_ZERO" PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 pi --session "$SESSION_ZERO" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-structured-fallback.out" 2>"$TMPDIR/pi-completion-context-proposal-structured-fallback.err"

python3 - "$TMPDIR/pi-completion-context-proposal-structured-fallback.out" "$TMPDIR/pi-completion-context-proposal-structured-fallback.err" "$DISCUSSION_SNAPSHOT_ZERO" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
assert Path('.agent').exists(), 'primary-agent handoff generation should scaffold canonical state in the same /cook entry'
assert snapshot.exists(), 'primary-agent handoff generation should emit a startup proposal snapshot'
proposal = json.loads(snapshot.read_text())
brief = json.loads(Path('.agent/state.json').read_text())['advisory_startup_brief']
assert proposal['source'] == 'handoff_capsule', 'generated primary-agent handoff should be consumed as handoff capsule startup source'
assert brief['source'] == 'primary_agent_handoff', 'generated primary-agent handoff should record primary_agent_handoff advisory intake'
assert 'Initialized completion control plane' in output, 'same-entry primary-agent handoff generation should initialize canonical workflow state'
PY

rm -rf .agent

# No workflow yet: user-authored faux handoffs must not bootstrap canonical workflow state.
SESSION_ZERO_USER_AUTHORED="$TMPDIR/session-zero-user-authored.jsonl"
USER_AUTHORED_SNAPSHOT_ZERO="$TMPDIR/context-proposal-user-authored-handoff.json"
USER_AUTHORED_MESSAGES_ZERO="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0001",
    "mission": "User-authored faux handoff should not start workflow.",
    "scope": ["Attempt to fake an explicit handoff from the user turn."],
    "constraints": ["Do not trust user-authored capsules as primary-agent handoff."],
    "acceptance": ["Fail closed without writing canonical state."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Prove that user-authored faux handoffs are rejected.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["scripts/context-proposal-test.sh"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "Rejecting user-authored capsules is part of the fail-closed startup boundary."
}
messages = [
    {"role": "user", "content": "Run /cook from this user-authored capsule only.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_ZERO_USER_AUTHORED" "$ROOT" "$USER_AUTHORED_MESSAGES_ZERO"

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$USER_AUTHORED_SNAPSHOT_ZERO" \
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ZERO_USER_AUTHORED" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-user-authored.out" 2>"$TMPDIR/pi-completion-context-proposal-user-authored.err"

python3 - "$TMPDIR/pi-completion-context-proposal-user-authored.out" "$TMPDIR/pi-completion-context-proposal-user-authored.err" "$USER_AUTHORED_SNAPSHOT_ZERO" <<'PY'
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
assert not Path('.agent').exists(), 'user-authored faux handoff without supporting discussion should still fail closed without writing canonical state'
assert not snapshot.exists(), 'user-authored faux handoff should not emit a startup proposal snapshot'
assert 'primary-agent handoff step could not prepare a concrete startup handoff' in output, 'user-authored faux handoff should fail closed when primary-agent handoff generation yields no handoff'
PY

# No workflow yet: malformed or invalid assistant handoff capsules must also fail closed.
SESSION_ZERO_INVALID="$TMPDIR/session-zero-invalid-handoff.jsonl"
INVALID_SNAPSHOT_ZERO="$TMPDIR/context-proposal-invalid-handoff.json"
INVALID_MESSAGES_ZERO='[{"role":"assistant","content":"This is not a valid startup capsule.\n\n```cook_handoff\n{\"kind\":\"cook_handoff\",\"source\":\"primary_agent\",\"mission\":\"Broken JSON handoff\"\n```"}]'
write_session_messages "$SESSION_ZERO_INVALID" "$ROOT" "$INVALID_MESSAGES_ZERO"

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$INVALID_SNAPSHOT_ZERO" \
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ZERO_INVALID" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-invalid-handoff.out" 2>"$TMPDIR/pi-completion-context-proposal-invalid-handoff.err"

python3 - "$TMPDIR/pi-completion-context-proposal-invalid-handoff.out" "$TMPDIR/pi-completion-context-proposal-invalid-handoff.err" "$INVALID_SNAPSHOT_ZERO" <<'PY'
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
assert not Path('.agent').exists(), 'invalid assistant handoff without supporting discussion should fail closed without writing canonical state'
assert not snapshot.exists(), 'invalid assistant handoff should not emit a startup proposal snapshot'
assert 'primary-agent handoff step could not prepare a concrete startup handoff' in output, 'invalid assistant handoff should fail closed when no valid handoff can be prepared'
PY

# No workflow yet: a fresh explicit primary-agent handoff should still bootstrap canonical startup state.
SESSION_ONE="$TMPDIR/session-one.jsonl"
HANDOFF_SNAPSHOT_ONE="$TMPDIR/context-proposal-explicit-startup.json"
HANDOFF_MESSAGES_ONE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Remove the completion status line while keeping the completion widget.",
    "scope": [
        "Keep the non-running completion widget.",
        "Suppress the widget while a completion role is active."
    ],
    "constraints": [
        "Do not reintroduce any other completion status surface."
    ],
    "acceptance": [
        "Update README to match the shipped behavior.",
        "Keep observability regression coverage truthful."
    ],
    "risks": [
        "Stale widget-removal discussion could broaden the startup plan if the handoff is ignored."
    ],
    "notes": [
        "Keep the startup brief aligned with the explicit primary-agent plan."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Land the completion-status removal and keep the completion widget coverage truthful.",
    "first_slice_non_goals": [
        "Do not reintroduce any other completion status surface."
    ],
    "implementation_surfaces": [
        "extensions/completion/index.ts",
        "scripts/context-proposal-test.sh"
    ],
    "verification_commands": [
        "npm run context-proposal-test"
    ],
    "why_this_slice_first": "The startup boundary regression is already bounded enough to implement safely.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The explicit startup brief is concrete and ready for repo changes."
}
messages = [
    {"role": "user", "content": "Please think through the completion widget startup boundary and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "This task is now ready for /cook. Run /cook to confirm the startup brief.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_ONE" "$ROOT" "$HANDOFF_MESSAGES_ONE"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_ONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-explicit-startup.out" 2>"$TMPDIR/pi-completion-context-proposal-explicit-startup.err"

python3 - "$HANDOFF_SNAPSHOT_ONE" <<'PY'
import json
import sys
from pathlib import Path

mission = 'Remove the completion status line while keeping the completion widget.'
expected_task_type = 'completion-workflow'
expected_eval_profile = 'completion-rubric-v1'
mission_text = Path('.agent/mission.md').read_text()
profile = json.loads(Path('.agent/profile.json').read_text())
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())
proposal = json.loads(Path(sys.argv[1]).read_text())

assert mission in mission_text, '.agent/mission.md did not record the explicit-handoff mission anchor'
assert profile['task_type'] == expected_task_type, 'profile.json task_type mismatch after explicit-handoff bootstrap'
assert profile['evaluation_profile'] == expected_eval_profile, 'profile.json evaluation_profile mismatch after explicit-handoff bootstrap'
assert state['mission_anchor'] == mission, 'state.json mission_anchor mismatch after explicit-handoff bootstrap'
assert state['task_type'] == expected_task_type, 'state.json task_type mismatch after explicit-handoff bootstrap'
assert state['evaluation_profile'] == expected_eval_profile, 'state.json evaluation_profile mismatch after explicit-handoff bootstrap'
assert plan['mission_anchor'] == mission, 'plan.json mission_anchor mismatch after explicit-handoff bootstrap'
assert plan['task_type'] == expected_task_type, 'plan.json task_type mismatch after explicit-handoff bootstrap'
assert plan['evaluation_profile'] == expected_eval_profile, 'plan.json evaluation_profile mismatch after explicit-handoff bootstrap'
assert active['mission_anchor'] == mission, 'active-slice.json mission_anchor mismatch after explicit-handoff bootstrap'
assert active['task_type'] == expected_task_type, 'active-slice.json task_type mismatch after explicit-handoff bootstrap'
assert active['evaluation_profile'] == expected_eval_profile, 'active-slice.json evaluation_profile mismatch after explicit-handoff bootstrap'
brief = state['advisory_startup_brief']
assert brief['kind'] == 'startup_brief', 'state.json should preserve the confirmed startup brief as advisory intake'
assert brief['source'] == 'primary_agent_handoff', 'explicit startup should record the handoff source in advisory intake'
assert brief['mission'] == mission, 'advisory startup brief mission should match the accepted mission anchor'
assert brief['scope'] == ['Keep the non-running completion widget.', 'Suppress the widget while a completion role is active.'], 'advisory startup brief should preserve scope items separately from canonical planning state'
assert brief['constraints'] == ['Do not reintroduce any other completion status surface.'], 'advisory startup brief should preserve constraints separately from canonical planning state'
assert brief['acceptance'] == ['Update README to match the shipped behavior.', 'Keep observability regression coverage truthful.'], 'advisory startup brief should preserve acceptance separately from canonical planning state'
assert brief['risks'] == ['Stale widget-removal discussion could broaden the startup plan if the handoff is ignored.'], 'advisory startup brief should preserve handoff risks'
assert 'First slice goal: Land the completion-status removal and keep the completion widget coverage truthful.' in brief['notes'], 'advisory startup brief should preserve first_slice_goal in notes'
assert 'Verification commands: npm run context-proposal-test' in brief['notes'], 'advisory startup brief should preserve verification_commands in notes'
assert plan['candidate_slices'] == [], 'startup brief should remain advisory intake only until regrounder owns plan selection'
assert active['status'] == 'idle', 'startup brief should not become the active-slice source before regrounder runs'
assert proposal['mission'] == mission, 'explicit startup proposal snapshot should keep the handoff mission anchor'
assert proposal['source'] == 'handoff_capsule', 'explicit startup proposal snapshot should expose the handoff capsule source'
assert proposal['analysis']['taskType'] == expected_task_type, 'explicit startup proposal snapshot should expose task_type hints separately'
assert proposal['analysis']['evaluationProfile'] == expected_eval_profile, 'explicit startup proposal snapshot should expose evaluation_profile hints separately'
assert state['current_phase'] == 'reground', 'state.json current_phase should start at reground after explicit-handoff bootstrap'
assert state['next_mandatory_role'] == 'completion-regrounder', 'next_mandatory_role should start at completion-regrounder after explicit-handoff bootstrap'
assert state['continuation_reason'].startswith('User started workflow via /cook:'), 'initial startup should record the accepted startup routing in continuation_reason'
assert 'task_type=completion-workflow' in state['continuation_reason'], 'initial startup should persist the selected task_type in continuation_reason'
assert 'evaluation_profile=completion-rubric-v1' in state['continuation_reason'], 'initial startup should persist the selected evaluation_profile in continuation_reason'
PY

# Active workflow: bare /cook should resume from canonical state when no fresh explicit handoff exists,
# even if recent discussion restates the current mission in a structured way.
SESSION_ONE_CONTINUE="$TMPDIR/session-one-continue.jsonl"
DISCUSSION_ONE_CONTINUE=$'Mission: Remove the completion status line while keeping the completion widget.\nScope:\n- Keep the current mission focused on the non-running completion widget.\nConstraints:\n- Do not start a different workflow from this discussion.\nAcceptance:\n- Resume the current workflow from canonical state without rewriting it.'
CONTINUE_ROUTING_ONE="$TMPDIR/active-continue-routing.json"
CONTINUE_RESUME_PROMPT_ONE="$TMPDIR/active-continue-resume.txt"
CONTINUE_CHOOSER_ONE="$TMPDIR/unexpected-active-continue-chooser.json"
CONTINUE_PROPOSAL_ONE="$TMPDIR/unexpected-active-continue-proposal.json"
write_session "$SESSION_ONE_CONTINUE" "$ROOT" "$DISCUSSION_ONE_CONTINUE"

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$CONTINUE_ROUTING_ONE" \
PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$CONTINUE_RESUME_PROMPT_ONE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CONTINUE_CHOOSER_ONE" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$CONTINUE_PROPOSAL_ONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE_CONTINUE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-active-continue.out" 2>"$TMPDIR/pi-completion-context-proposal-active-continue.err"

python3 - "$CONTINUE_ROUTING_ONE" "$CONTINUE_RESUME_PROMPT_ONE" "$CONTINUE_CHOOSER_ONE" "$CONTINUE_PROPOSAL_ONE" <<'PY'
import json
import sys
from pathlib import Path

mission = 'Remove the completion status line while keeping the completion widget.'
routing = json.loads(Path(sys.argv[1]).read_text())
resume = Path(sys.argv[2]).read_text()
chooser_path = Path(sys.argv[3])
proposal_path = Path(sys.argv[4])
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert routing['mode'] == 'bare', 'active bare /cook resume regression should snapshot bare routing mode'
assert 'explicitGoal' not in routing, 'active bare /cook resume routing should not expose removed explicit-goal shim fields'
assert 'explicitGoalProvided' not in routing, 'active bare /cook resume routing should not expose removed explicit-goal shim fields'
assert routing['action'] == 'continue', 'active bare /cook should resume when no fresh explicit handoff exists'
assert routing['reason'] == 'missing_explicit_handoff', 'active bare /cook should explain that resume happened because no fresh explicit handoff existed'
assert routing['currentMissionAnchor'] == mission, 'resume routing should preserve the current mission anchor'
assert routing['proposedMissionAnchor'] is None, 'resume routing should not derive a replacement mission from recent discussion'
assert 'Resume the completion workflow from canonical state.' in resume, 'active bare /cook resume should still use the canonical resume prompt'
assert not chooser_path.exists(), 'active bare /cook resume should not open the replacement chooser without a fresh explicit handoff'
assert not proposal_path.exists(), 'active bare /cook resume should not open replacement proposal confirmation without a fresh explicit handoff'
assert state['mission_anchor'] == mission, 'active bare /cook resume should keep state.json unchanged'
assert plan['mission_anchor'] == mission, 'active bare /cook resume should keep plan.json unchanged'
assert active['mission_anchor'] == mission, 'active bare /cook resume should keep active-slice.json unchanged'
PY

# Active workflow: even strongly different recent discussion should no longer open chooser/refocus startup
# when no fresh valid explicit handoff is present.
SESSION_ONE_DISCUSSION_REFOCUS="$TMPDIR/session-one-discussion-refocus.jsonl"
DISCUSSION_ONE_DISCUSSION_REFOCUS=$'Mission: Normalize bare /cook planning phrasing into implementation-result missions.\nScope:\n- Replace the current workflow from recent discussion only.\n- Keep the approval-only Start/Cancel gate before rewriting canonical state.\nConstraints:\n- Do not require a fresh explicit handoff.\nAcceptance:\n- Rewrite canonical state from recent discussion.'
DISCUSSION_REFOCUS_ROUTING_ONE="$TMPDIR/active-discussion-refocus-routing.json"
DISCUSSION_REFOCUS_RESUME_ONE="$TMPDIR/active-discussion-refocus-resume.txt"
DISCUSSION_REFOCUS_CHOOSER_ONE="$TMPDIR/unexpected-active-discussion-refocus-chooser.json"
DISCUSSION_REFOCUS_PROPOSAL_ONE="$TMPDIR/unexpected-active-discussion-refocus-proposal.json"
write_session "$SESSION_ONE_DISCUSSION_REFOCUS" "$ROOT" "$DISCUSSION_ONE_DISCUSSION_REFOCUS"

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$DISCUSSION_REFOCUS_ROUTING_ONE" \
PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$DISCUSSION_REFOCUS_RESUME_ONE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$DISCUSSION_REFOCUS_CHOOSER_ONE" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_REFOCUS_PROPOSAL_ONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE_DISCUSSION_REFOCUS" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-active-discussion-refocus.out" 2>"$TMPDIR/pi-completion-context-proposal-active-discussion-refocus.err"

python3 - "$DISCUSSION_REFOCUS_ROUTING_ONE" "$DISCUSSION_REFOCUS_RESUME_ONE" "$DISCUSSION_REFOCUS_CHOOSER_ONE" "$DISCUSSION_REFOCUS_PROPOSAL_ONE" <<'PY'
import json
import sys
from pathlib import Path

mission = 'Remove the completion status line while keeping the completion widget.'
routing = json.loads(Path(sys.argv[1]).read_text())
resume = Path(sys.argv[2]).read_text()
chooser_path = Path(sys.argv[3])
proposal_path = Path(sys.argv[4])
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert routing['mode'] == 'bare', 'discussion-driven refocus removal should snapshot bare routing mode'
assert routing['action'] == 'continue', 'bare /cook should resume instead of deriving a replacement workflow from recent discussion'
assert routing['reason'] == 'missing_explicit_handoff', 'discussion-driven refocus removal should explain that no fresh explicit handoff existed'
assert routing['currentMissionAnchor'] == mission, 'discussion-driven refocus removal should preserve the current mission anchor'
assert routing['proposedMissionAnchor'] is None, 'discussion-driven refocus removal should not preserve a replacement mission from recent discussion'
assert 'Resume the completion workflow from canonical state.' in resume, 'discussion-driven refocus removal should still queue the canonical resume prompt'
assert not chooser_path.exists(), 'discussion-driven refocus removal should not open the chooser'
assert not proposal_path.exists(), 'discussion-driven refocus removal should not open final proposal confirmation'
assert state['mission_anchor'] == mission, 'discussion-driven refocus removal should keep state.json unchanged'
assert plan['mission_anchor'] == mission, 'discussion-driven refocus removal should keep plan.json unchanged'
assert active['mission_anchor'] == mission, 'discussion-driven refocus removal should keep active-slice.json unchanged'
PY

# Active workflow: summary-only replacement artifacts should also resume the current workflow when no fresh
# explicit handoff exists.
SESSION_ONE_SUMMARY_ONLY="$TMPDIR/session-one-summary-only.jsonl"
SUMMARY_ROUTING_ONE="$TMPDIR/active-summary-only-routing.json"
SUMMARY_RESUME_PROMPT_ONE="$TMPDIR/active-summary-only-resume.txt"
SUMMARY_CHOOSER_ONE="$TMPDIR/unexpected-active-summary-only-chooser.json"
SUMMARY_PROPOSAL_ONE="$TMPDIR/unexpected-active-summary-only-proposal.json"
python3 - "$SESSION_ONE_SUMMARY_ONLY" "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

session_path = Path(sys.argv[1])
cwd = sys.argv[2]
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
        "id": "c3d4e5f6",
        "parentId": None,
        "timestamp": "2026-01-01T00:00:03.000Z",
        "message": {
            "role": "branchSummary",
            "summary": "Mission: Replace the current workflow from the completed plan summary.\nScope:\n- Refocus to a different mission from this summary artifact alone.\nConstraints:\n- Keep the approval-only Start/Cancel gate unchanged.\nAcceptance:\n- Rewrite canonical state from the summary without new user discussion.",
        },
    },
]
with session_path.open('w', encoding='utf-8') as fh:
    for entry in entries:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$SUMMARY_ROUTING_ONE" \
PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$SUMMARY_RESUME_PROMPT_ONE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$SUMMARY_CHOOSER_ONE" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$SUMMARY_PROPOSAL_ONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE_SUMMARY_ONLY" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-active-summary-only.out" 2>"$TMPDIR/pi-completion-context-proposal-active-summary-only.err"

python3 - "$SUMMARY_ROUTING_ONE" "$SUMMARY_RESUME_PROMPT_ONE" "$SUMMARY_CHOOSER_ONE" "$SUMMARY_PROPOSAL_ONE" <<'PY'
import json
import sys
from pathlib import Path

mission = 'Remove the completion status line while keeping the completion widget.'
routing = json.loads(Path(sys.argv[1]).read_text())
resume = Path(sys.argv[2]).read_text()
chooser_path = Path(sys.argv[3])
proposal_path = Path(sys.argv[4])
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert routing['mode'] == 'bare', 'summary-only active bare /cook regression should snapshot bare routing mode'
assert routing['action'] == 'continue', 'summary-only active bare /cook should resume rather than derive replacement startup'
assert routing['reason'] == 'missing_explicit_handoff', 'summary-only active bare /cook should explain that no fresh explicit handoff existed'
assert routing['currentMissionAnchor'] == mission, 'summary-only active bare /cook should preserve the current mission anchor'
assert routing['proposedMissionAnchor'] is None, 'summary-only active bare /cook should not derive a replacement mission from summary artifacts alone'
assert 'Resume the completion workflow from canonical state.' in resume, 'summary-only active bare /cook should still resume the canonical workflow'
assert not chooser_path.exists(), 'summary-only active bare /cook should not open the refocus chooser'
assert not proposal_path.exists(), 'summary-only active bare /cook should not open replacement proposal confirmation'
assert state['mission_anchor'] == mission, 'summary-only active bare /cook should keep state.json unchanged'
assert plan['mission_anchor'] == mission, 'summary-only active bare /cook should keep plan.json unchanged'
assert active['mission_anchor'] == mission, 'summary-only active bare /cook should keep active-slice.json unchanged'
PY

# Active workflow: a fresh explicit handoff that is not implementation-startable should still fail closed
# without rewriting canonical state.
SESSION_ONE_NON_STARTABLE_ACTIVE="$TMPDIR/session-one-non-startable-active.jsonl"
NON_STARTABLE_ACTIVE_ROUTING="$TMPDIR/active-non-startable-routing.json"
NON_STARTABLE_ACTIVE_RESUME="$TMPDIR/unexpected-active-non-startable-resume.txt"
NON_STARTABLE_ACTIVE_CHOOSER="$TMPDIR/unexpected-active-non-startable-chooser.json"
NON_STARTABLE_ACTIVE_PROPOSAL="$TMPDIR/unexpected-active-non-startable-proposal.json"
NON_STARTABLE_ACTIVE_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Replace the current widget mission from a vague explicit handoff.",
    "scope": [
        "Replace the active workflow from a fresh explicit handoff."
    ],
    "constraints": [
        "Do not rely on recent discussion to fill in missing implementation details."
    ],
    "acceptance": [
        "Current behavior stays understandable."
    ],
    "risks": [],
    "notes": [
        "This capsule is intentionally non-startable for active-workflow fail-closed coverage."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Attempt to replace the active workflow from a vague capsule.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "extensions/completion/driver.ts"
    ],
    "verification_commands": [
        "npm run context-proposal-test"
    ],
    "why_this_slice_first": "Active-workflow replacement should fail closed when the capsule is fresh but not startable.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1"
}
messages = [
    {"role": "user", "content": "We may need a different active workflow, but only if there is a fresh explicit handoff."},
    {"role": "assistant", "content": "Only use this capsule if it is concrete enough.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_ONE_NON_STARTABLE_ACTIVE" "$ROOT" "$NON_STARTABLE_ACTIVE_MESSAGES"

python3 - "$TMPDIR/active-non-startable-before.json" <<'PY'
import json
import sys
from pathlib import Path
tracked = {
    'mission.md': Path('.agent/mission.md').read_text(),
    'profile.json': Path('.agent/profile.json').read_text(),
    'state.json': Path('.agent/state.json').read_text(),
    'plan.json': Path('.agent/plan.json').read_text(),
    'active-slice.json': Path('.agent/active-slice.json').read_text(),
    'verification-evidence.json': Path('.agent/verification-evidence.json').read_text(),
}
Path(sys.argv[1]).write_text(json.dumps(tracked, indent=2) + '\n')
PY

PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$NON_STARTABLE_ACTIVE_ROUTING" \
PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$NON_STARTABLE_ACTIVE_RESUME" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$NON_STARTABLE_ACTIVE_CHOOSER" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$NON_STARTABLE_ACTIVE_PROPOSAL" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_ONE_NON_STARTABLE_ACTIVE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-active-non-startable.out" 2>"$TMPDIR/pi-completion-context-proposal-active-non-startable.err"

python3 - "$NON_STARTABLE_ACTIVE_ROUTING" "$NON_STARTABLE_ACTIVE_RESUME" "$NON_STARTABLE_ACTIVE_CHOOSER" "$NON_STARTABLE_ACTIVE_PROPOSAL" "$TMPDIR/pi-completion-context-proposal-active-non-startable.out" "$TMPDIR/pi-completion-context-proposal-active-non-startable.err" "$TMPDIR/active-non-startable-before.json" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
resume_path = Path(sys.argv[2])
chooser_path = Path(sys.argv[3])
proposal_path = Path(sys.argv[4])
output = Path(sys.argv[5]).read_text() + Path(sys.argv[6]).read_text()
before = json.loads(Path(sys.argv[7]).read_text())
after = {
    'mission.md': Path('.agent/mission.md').read_text(),
    'profile.json': Path('.agent/profile.json').read_text(),
    'state.json': Path('.agent/state.json').read_text(),
    'plan.json': Path('.agent/plan.json').read_text(),
    'active-slice.json': Path('.agent/active-slice.json').read_text(),
    'verification-evidence.json': Path('.agent/verification-evidence.json').read_text(),
}

assert routing['mode'] == 'bare', 'fresh non-startable explicit handoff should snapshot bare routing mode'
assert routing['action'] == 'blocked', 'fresh non-startable explicit handoff should fail closed for active bare /cook'
assert routing['reason'] == 'fresh_explicit_handoff_not_startable', 'fresh non-startable explicit handoff should keep the dedicated explicit-handoff fail-closed reason'
assert 'fresh explicit primary-agent handoff exists' in routing['blockedFailureMessage'], 'fresh non-startable explicit handoff should surface the dedicated fail-closed message'
assert 'acceptance is not anchored to concrete repo changes or verification' in routing['blockedFailureMessage'], 'fresh non-startable explicit handoff should explain why the capsule is not startable'
assert not resume_path.exists(), 'fresh non-startable explicit handoff should not queue a resume prompt'
assert not chooser_path.exists(), 'fresh non-startable explicit handoff should not open the replacement chooser'
assert not proposal_path.exists(), 'fresh non-startable explicit handoff should not open final proposal confirmation'
assert 'fresh explicit primary-agent handoff exists' in output, 'fresh non-startable explicit handoff should explain that the explicit capsule blocked active-workflow replacement'
assert before == after, 'fresh non-startable explicit handoff should leave canonical state unchanged'
PY

# Completed workflow: bare /cook should suppress proposals that simply restate the completed mission
# without a clear reopen or next-round signal.
mark_done

SESSION_TWO_COMPLETED_SUPPRESS="$TMPDIR/session-two-completed-suppress.jsonl"
CURRENT_DONE_MISSION="$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('.agent/state.json').read_text())['mission_anchor'])
PY
)"
DISCUSSION_TWO_COMPLETED_SUPPRESS="Mission: ${CURRENT_DONE_MISSION}
Scope:
- Keep the current completed mission exactly as-is.
Constraints:
- Do not start a different workflow from this discussion.
Acceptance:
- Keep the finished mission closed and unchanged."
DISCUSSION_SNAPSHOT_TWO_COMPLETED_SUPPRESS="$TMPDIR/context-proposal-next-round-completed-suppress.json"
write_session "$SESSION_TWO_COMPLETED_SUPPRESS" "$ROOT" "$DISCUSSION_TWO_COMPLETED_SUPPRESS"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_TWO_COMPLETED_SUPPRESS" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_TWO_COMPLETED_SUPPRESS" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-next-round-completed-suppress.out" 2>"$TMPDIR/pi-completion-context-proposal-next-round-completed-suppress.err"

python3 - "$TMPDIR/pi-completion-context-proposal-next-round-completed-suppress.out" "$TMPDIR/pi-completion-context-proposal-next-round-completed-suppress.err" "$DISCUSSION_SNAPSHOT_TWO_COMPLETED_SUPPRESS" "$CURRENT_DONE_MISSION" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
expected = sys.argv[4]
state = json.loads(Path('.agent/state.json').read_text())

assert state['mission_anchor'] == expected, 'completed-topic suppression should keep the done workflow mission anchor unchanged'
assert state['continuation_policy'] == 'done', 'completed-topic suppression should keep the workflow closed'
assert not snapshot.exists(), 'completed-topic suppression should not emit a proposal snapshot when the latest discussion only repeats finished work'
assert 'primary-agent handoff step could not prepare a concrete startup handoff' in output, 'completed-topic suppression should fail closed when no concrete primary-agent handoff can be prepared'
PY

# Completed workflow: bare /cook should also suppress proposals that merely restate canonical
# verification evidence for already verified work.
python3 - <<'PY'
import json
from pathlib import Path

state = json.loads(Path('.agent/state.json').read_text())
state['latest_verified_slice'] = 'verified-logout-redirect'
Path('.agent/state.json').write_text(json.dumps(state, indent=2) + '\n')

evidence = json.loads(Path('.agent/verification-evidence.json').read_text())
evidence.update({
    'subject_type': 'selected_slice',
    'slice_id': 'verified-logout-redirect',
    'goal': 'Add logout redirect regression coverage.',
    'summary': 'Verified logout redirect regression coverage already matches the selected slice and current HEAD.',
    'outcome': 'pass',
})
Path('.agent/verification-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
PY

SESSION_TWO_VERIFIED_SUPPRESS="$TMPDIR/session-two-verified-suppress.jsonl"
DISCUSSION_TWO_VERIFIED_SUPPRESS=$'Mission: Add logout redirect regression coverage.\nScope:\n- Add coverage for logout redirect behavior.\nConstraints:\n- Do not change the verified logout redirect work.\nAcceptance:\n- Keep the verified logout redirect regression coverage unchanged.'
DISCUSSION_SNAPSHOT_TWO_VERIFIED_SUPPRESS="$TMPDIR/context-proposal-next-round-verified-suppress.json"
write_session "$SESSION_TWO_VERIFIED_SUPPRESS" "$ROOT" "$DISCUSSION_TWO_VERIFIED_SUPPRESS"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_TWO_VERIFIED_SUPPRESS" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_TWO_VERIFIED_SUPPRESS" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-next-round-verified-suppress.out" 2>"$TMPDIR/pi-completion-context-proposal-next-round-verified-suppress.err"

python3 - "$TMPDIR/pi-completion-context-proposal-next-round-verified-suppress.out" "$TMPDIR/pi-completion-context-proposal-next-round-verified-suppress.err" "$DISCUSSION_SNAPSHOT_TWO_VERIFIED_SUPPRESS" <<'PY'
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
assert not snapshot.exists(), 'verification-evidence overlap suppression should not emit a proposal snapshot for already verified work'
assert 'primary-agent handoff step could not prepare a concrete startup handoff' in output, 'verification-evidence overlap suppression should fail closed when no concrete primary-agent handoff can be prepared'
PY

# Completed workflow: bare /cook should fail closed for next-round discussion-only startup too,
# even when the discussion is well structured.
SESSION_TWO_NORMALIZED="$TMPDIR/session-two-normalized.jsonl"
DISCUSSION_TWO_NORMALIZED=$'Mission: 開始實作這個方案\nScope:\n- Normalize bare /cook planning phrasing for the next workflow round.\n- Reset canonical state for the new implementation mission.\nConstraints:\n- Do not resume the completed workflow when the new round is clearly different.\nAcceptance:\n- Start a new round with the normalized mission anchor.'
DISCUSSION_SNAPSHOT_TWO_NORMALIZED="$TMPDIR/context-proposal-next-round-normalized.json"
write_session "$SESSION_TWO_NORMALIZED" "$ROOT" "$DISCUSSION_TWO_NORMALIZED"

GENERATED_HANDOFF_TWO_NORMALIZED="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Start the next workflow round with a normalized implementation mission.",
    "scope": [
        "Reset canonical state for the new implementation mission.",
        "Keep the next round distinct from the completed workflow."
    ],
    "constraints": [
        "Do not resume the completed workflow when the new round is clearly different."
    ],
    "acceptance": [
        "Reset canonical state back to reground for the new mission.",
        "Preserve the tracked completion control-plane files."
    ],
    "risks": [],
    "notes": ["Generated by the primary-agent handoff step triggered from /cook."],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Bootstrap the next workflow round from the normalized implementation mission.",
    "first_slice_non_goals": ["Do not reopen finished slices from the previous workflow."],
    "implementation_surfaces": ["extensions/completion/driver.ts", "scripts/context-proposal-test.sh"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The user explicitly chose workflow mode for a bounded next-round restart.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1"
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$GENERATED_HANDOFF_TWO_NORMALIZED" PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_TWO_NORMALIZED" PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 pi --session "$SESSION_TWO_NORMALIZED" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-next-round-normalized.out" 2>"$TMPDIR/pi-completion-context-proposal-next-round-normalized.err"

python3 - "$TMPDIR/pi-completion-context-proposal-next-round-normalized.out" "$TMPDIR/pi-completion-context-proposal-next-round-normalized.err" "$DISCUSSION_SNAPSHOT_TWO_NORMALIZED" "$CURRENT_DONE_MISSION" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
previous = sys.argv[4]
state = json.loads(Path('.agent/state.json').read_text())
if snapshot.exists():
    proposal = json.loads(snapshot.read_text())
    assert proposal['source'] == 'handoff_capsule', 'done-workflow generated startup should snapshot the primary-agent handoff source'
assert state['mission_anchor'] != previous, 'done-workflow discussion-only startup should advance to the new mission anchor'
assert state['continuation_policy'] == 'continue', 'done-workflow discussion-only startup should reopen workflow state'
assert 'Started a new completion workflow round from explicit primary-agent handoff' in output, 'done-workflow generated startup should report explicit primary-agent handoff startup'
PY

# Completed workflow: a fresh explicit primary-agent handoff should still start the next round.
mark_done

SESSION_TWO="$TMPDIR/session-two.jsonl"
DISCUSSION_SNAPSHOT_TWO="$TMPDIR/context-proposal-next-round-explicit-handoff.json"
HANDOFF_MESSAGES_TWO="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Ship the next workflow round from a fresh explicit handoff.",
    "scope": [
        "Reset canonical state back to reground for the fresh mission.",
        "Preserve the tracked completion control-plane files."
    ],
    "constraints": [
        "Do not resume the completed workflow when the new round is clearly different."
    ],
    "acceptance": [
        "Reset canonical state back to reground for the new mission.",
        "Preserve the tracked completion control-plane files."
    ],
    "risks": [
        "Done-state history could override the fresh mission if the explicit handoff is ignored."
    ],
    "notes": [
        "This next round must come from the fresh explicit handoff rather than recent discussion."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Start the next round from the fresh explicit handoff and preserve canonical control-plane files.",
    "first_slice_non_goals": [
        "Do not resume the completed workflow when the new round is clearly different."
    ],
    "implementation_surfaces": [
        "extensions/completion/driver.ts",
        "scripts/context-proposal-test.sh"
    ],
    "verification_commands": [
        "npm run context-proposal-test"
    ],
    "why_this_slice_first": "The fresh explicit handoff is the smallest truthful next-round startup after the previous workflow closed.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "A new implementation-ready mission was identified after the previous round closed."
}
messages = [
    {"role": "user", "content": "The previous round is done, but there is a fresh next round ready for /cook."},
    {"role": "assistant", "content": "The next round is ready for /cook. Run /cook to confirm this fresh implementation mission.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_TWO" "$ROOT" "$HANDOFF_MESSAGES_TWO"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_TWO" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_TWO" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-next-round.out" 2>"$TMPDIR/pi-completion-context-proposal-next-round.err"

python3 - "$DISCUSSION_SNAPSHOT_TWO" <<'PY'
import json
import sys
from pathlib import Path

mission = 'Ship the next workflow round from a fresh explicit handoff.'
expected_task_type = 'completion-workflow'
expected_eval_profile = 'completion-rubric-v1'
mission_text = Path('.agent/mission.md').read_text()
profile = json.loads(Path('.agent/profile.json').read_text())
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())
proposal = json.loads(Path(sys.argv[1]).read_text())

assert mission in mission_text, '.agent/mission.md did not update to the next-round explicit-handoff mission anchor'
assert profile['task_type'] == expected_task_type, 'profile.json task_type mismatch after next-round explicit handoff startup'
assert profile['evaluation_profile'] == expected_eval_profile, 'profile.json evaluation_profile mismatch after next-round explicit handoff startup'
assert state['mission_anchor'] == mission, 'state.json mission_anchor mismatch after starting the next workflow round from explicit handoff'
assert state['task_type'] == expected_task_type, 'state.json task_type mismatch after starting the next workflow round from explicit handoff'
assert state['evaluation_profile'] == expected_eval_profile, 'state.json evaluation_profile mismatch after starting the next workflow round from explicit handoff'
assert state['advisory_startup_brief']['mission'] == mission, 'next-round explicit handoff should preserve the confirmed startup brief as advisory intake'
assert state['advisory_startup_brief']['source'] == 'primary_agent_handoff', 'next-round explicit handoff should preserve the handoff advisory source'
assert plan['mission_anchor'] == mission, 'plan.json mission_anchor mismatch after starting the next workflow round from explicit handoff'
assert plan['task_type'] == expected_task_type, 'plan.json task_type mismatch after starting the next workflow round from explicit handoff'
assert plan['evaluation_profile'] == expected_eval_profile, 'plan.json evaluation_profile mismatch after starting the next workflow round from explicit handoff'
assert active['mission_anchor'] == mission, 'active-slice.json mission_anchor mismatch after starting the next workflow round from explicit handoff'
assert active['task_type'] == expected_task_type, 'active-slice.json task_type mismatch after starting the next workflow round from explicit handoff'
assert active['evaluation_profile'] == expected_eval_profile, 'active-slice.json evaluation_profile mismatch after starting the next workflow round from explicit handoff'
assert proposal['mission'] == mission, 'next-round explicit handoff proposal snapshot should preserve the handoff mission anchor'
assert proposal['source'] == 'handoff_capsule', 'next-round explicit handoff proposal snapshot should record the handoff capsule source'
assert state['current_phase'] == 'reground', 'state.json current_phase should reset to reground for the next workflow round'
assert state['continuation_policy'] == 'continue', 'continuation_policy should reset to continue for the next workflow round'
assert state['requires_reground'] is True, 'requires_reground should reset to true for the next workflow round'
assert state['project_done'] is False, 'project_done should reset to false for the next workflow round'
assert state['next_mandatory_role'] == 'completion-regrounder', 'next_mandatory_role should reset to completion-regrounder for the next workflow round'
assert state['continuation_reason'].startswith('User refocused workflow via /cook:'), 'continuation_reason should record the next-round refocus'
assert 'task_type=completion-workflow' in state['continuation_reason'], 'next-round refocus should persist the selected task_type'
assert 'evaluation_profile=completion-rubric-v1' in state['continuation_reason'], 'next-round refocus should persist the selected evaluation_profile'
assert plan['plan_basis'] == 'user_refocus', 'plan_basis should reset to user_refocus for the next workflow round'
assert active['status'] == 'idle', 'active-slice should reset to idle for the next workflow round'
PY

# Active workflow: inline `/cook` arguments should fail closed immediately and leave canonical state unchanged.
ACTIVE_INLINE_REJECTION_ROUTING="$TMPDIR/context-proposal-active-inline-arg-routing.json"
ACTIVE_INLINE_REJECTION_PROPOSAL="$TMPDIR/context-proposal-active-inline-arg-proposal.json"
ACTIVE_INLINE_REJECTION_CHOOSER="$TMPDIR/context-proposal-active-inline-arg-chooser.json"
ACTIVE_INLINE_REJECTION_BASELINE="$TMPDIR/context-proposal-active-inline-before.json"
python3 - "$ACTIVE_INLINE_REJECTION_BASELINE" <<'PY'
import json
import sys
from pathlib import Path

tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
Path(sys.argv[1]).write_text(json.dumps({path.name: path.read_text() for path in tracked}, indent=2) + '\n')
PY

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$ACTIVE_INLINE_REJECTION_PROPOSAL" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ACTIVE_INLINE_REJECTION_ROUTING" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$ACTIVE_INLINE_REJECTION_CHOOSER" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi -e "$PKG_ROOT" -p "/cook Replacement mission for the active workflow" >"$TMPDIR/pi-completion-context-proposal-active-inline-arg.out" 2>"$TMPDIR/pi-completion-context-proposal-active-inline-arg.err"

python3 - "$TMPDIR/pi-completion-context-proposal-active-inline-arg.out" "$TMPDIR/pi-completion-context-proposal-active-inline-arg.err" "$ACTIVE_INLINE_REJECTION_ROUTING" "$ACTIVE_INLINE_REJECTION_PROPOSAL" "$ACTIVE_INLINE_REJECTION_CHOOSER" "$ACTIVE_INLINE_REJECTION_BASELINE" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
routing = Path(sys.argv[3])
proposal = Path(sys.argv[4])
chooser = Path(sys.argv[5])
before = json.loads(Path(sys.argv[6]).read_text())
tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]

assert not routing.exists(), 'active /cook inline-args rejection should not run active-workflow routing'
assert not proposal.exists(), 'active /cook inline-args rejection should not emit a replacement startup-brief proposal'
assert not chooser.exists(), 'active /cook inline-args rejection should not open the existing-workflow chooser'
assert '/cook no longer accepts inline arguments.' in output, 'active /cook inline-args rejection should explain the bare-only entry contract'
after = {path.name: path.read_text() for path in tracked}
assert before == after, 'active /cook inline-args rejection should leave canonical files unchanged'
PY

# Completed workflow: inline `/cook` arguments should also fail closed before any next-round proposal derivation.
mark_done

DONE_INLINE_REJECTION_ROUTING="$TMPDIR/context-proposal-done-inline-arg-routing.json"
DONE_INLINE_REJECTION_PROPOSAL="$TMPDIR/context-proposal-done-inline-arg-proposal.json"
DONE_INLINE_REJECTION_CHOOSER="$TMPDIR/context-proposal-done-inline-arg-chooser.json"
DONE_INLINE_REJECTION_BASELINE="$TMPDIR/context-proposal-done-inline-before.json"
python3 - "$DONE_INLINE_REJECTION_BASELINE" <<'PY'
import json
import sys
from pathlib import Path

tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
Path(sys.argv[1]).write_text(json.dumps({path.name: path.read_text() for path in tracked}, indent=2) + '\n')
PY

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DONE_INLINE_REJECTION_PROPOSAL" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$DONE_INLINE_REJECTION_ROUTING" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$DONE_INLINE_REJECTION_CHOOSER" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi -e "$PKG_ROOT" -p "/cook done-workflow replacement mission" >"$TMPDIR/pi-completion-context-proposal-done-inline-arg.out" 2>"$TMPDIR/pi-completion-context-proposal-done-inline-arg.err"

python3 - "$TMPDIR/pi-completion-context-proposal-done-inline-arg.out" "$TMPDIR/pi-completion-context-proposal-done-inline-arg.err" "$DONE_INLINE_REJECTION_ROUTING" "$DONE_INLINE_REJECTION_PROPOSAL" "$DONE_INLINE_REJECTION_CHOOSER" "$DONE_INLINE_REJECTION_BASELINE" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
routing = Path(sys.argv[3])
proposal = Path(sys.argv[4])
chooser = Path(sys.argv[5])
before = json.loads(Path(sys.argv[6]).read_text())
tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
state_before = json.loads(before['state.json'])
assert state_before['current_phase'] == 'done', 'done /cook inline-args rejection should start from a completed workflow'
assert state_before['project_done'] is True, 'done /cook inline-args rejection should start from project_done=true'
assert not routing.exists(), 'done /cook inline-args rejection should not run active-workflow routing while starting the next round'
assert not proposal.exists(), 'done /cook inline-args rejection should not emit a next-round startup-brief proposal'
assert not chooser.exists(), 'done /cook inline-args rejection should not open the existing-workflow chooser when starting the next round'
assert '/cook no longer accepts inline arguments.' in output, 'done /cook inline-args rejection should explain the bare-only entry contract'
after = {path.name: path.read_text() for path in tracked}
assert before == after, 'done /cook inline-args rejection should leave canonical files unchanged'
PY

# Completed workflow again: model-assisted discussion analysis alone should still fail closed
# without a fresh explicit primary-agent handoff.
mark_done

SESSION_FIVE="$TMPDIR/session-five.jsonl"
DISCUSSION_FIVE=$'I do not want to rewrite the parser. The safer path is to let /cook analyze the discussion first, keep the discussion-derived mission anchored once it is clear, and ignore stale scope that drifted in from earlier turns. We should still prove it with a regression test before writing canonical state.'
ANALYST_OUTPUT_FIVE='{"mission":"Use a proposal analyst to summarize natural discussion before /cook writes canonical state.","scope":["Keep the discussion-derived mission anchored once it is clear.","Drop stale scope from earlier turns."],"constraints":["Do not rewrite the parser."],"acceptance":["Add a regression test."],"confidence":0.91,"possible_noise":["old unrelated scope"]}'
DISCUSSION_SNAPSHOT_FIVE="$TMPDIR/context-proposal-analyst-restart-rejected.json"
write_session "$SESSION_FIVE" "$ROOT" "$DISCUSSION_FIVE"

GENERATED_HANDOFF_FIVE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Use the analyst-backed parser follow-up as the next workflow round.",
    "scope": [
        "Keep the discussion-derived mission anchored once it is clear.",
        "Drop stale scope from earlier turns."
    ],
    "constraints": [
        "Do not rewrite the parser."
    ],
    "acceptance": [
        "Add a regression test."
    ],
    "risks": [],
    "notes": ["Generated by the primary-agent handoff step triggered from /cook."],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Land the regression-test-backed parser follow-up without rewriting the parser.",
    "first_slice_non_goals": ["Do not broaden the mission with stale scope."],
    "implementation_surfaces": ["scripts/context-proposal-test.sh"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The user explicitly chose workflow mode and the primary agent can already bound the first slice.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1"
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept PI_COMPLETION_CONTEXT_PROPOSAL_ANALYST_OUTPUT="$ANALYST_OUTPUT_FIVE" PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$GENERATED_HANDOFF_FIVE" PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$DISCUSSION_SNAPSHOT_FIVE" PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 pi --session "$SESSION_FIVE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-analyst.out" 2>"$TMPDIR/pi-completion-context-proposal-analyst.err"

python3 - "$TMPDIR/pi-completion-context-proposal-analyst.out" "$TMPDIR/pi-completion-context-proposal-analyst.err" "$DISCUSSION_SNAPSHOT_FIVE" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
snapshot = Path(sys.argv[3])
state = json.loads(Path('.agent/state.json').read_text())

if snapshot.exists():
    pass
assert state['continuation_policy'] == 'continue', 'done-workflow analyst-backed primary-agent handoff should reopen the workflow'
assert 'Started a new completion workflow round from explicit primary-agent handoff' in output, 'done-workflow analyst-backed startup should report explicit primary-agent handoff startup'
PY

# Custom confirmation UI: start should render proposal content separately from approval-only Start/Cancel actions.
UI_ROOT_START="$TMPDIR/ui-root-start"
mkdir -p "$UI_ROOT_START"
cd "$UI_ROOT_START"
git init -q

UI_SESSION_START="$TMPDIR/ui-session-start.jsonl"
UI_SNAPSHOT_START="$TMPDIR/context-proposal-ui-start.json"
UI_MESSAGES_START="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Replace the crowded selector with a clearer action layout.",
    "scope": ["Separate proposal text from actions."],
    "constraints": ["Preserve approval-only Start/Cancel behavior."],
    "acceptance": ["Add regression coverage."],
    "risks": ["Bundling critique into the action list would make the confirmation harder to scan."],
    "notes": ["Keep critique details separate from the approval-only proposal summary.", "Possible noise: old selector wording"],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Separate the proposal text from the approval-only Start/Cancel actions.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["extensions/completion/prompt-surfaces.ts"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The confirmation layout regression is small and directly testable.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The explicit handoff is concrete enough to exercise the startup confirmation UI."
}
messages = [
    {"role": "user", "content": "Prepare the confirmation-layout work and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "The confirmation-layout work is ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$UI_SESSION_START" "$UI_ROOT_START" "$UI_MESSAGES_START"

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_ACTION=start \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_PATH="$UI_SNAPSHOT_START" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$UI_SESSION_START" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-ui-start.out" 2>"$TMPDIR/pi-completion-context-proposal-ui-start.err"

python3 - "$UI_SNAPSHOT_START" <<'PY'
import json
import sys
from pathlib import Path

snapshot = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path('.agent/state.json').read_text())

assert snapshot['proposalHeading'] == 'Startup brief', 'custom confirmation snapshot should expose a dedicated startup-brief section'
assert snapshot['critiqueHeading'] == 'Notes and risks', 'custom confirmation snapshot should expose notes separately from the startup-brief body'
assert snapshot['routingHeading'] == 'Routing recommendations', 'custom confirmation snapshot should expose routing recommendations separately from the proposal body'
assert 'approval-only' in snapshot['intro'], 'custom confirmation intro should explain the approval-only gate'
assert state['task_type'] == 'completion-workflow', 'start action should preserve canonical task_type'
assert state['evaluation_profile'] == 'completion-rubric-v1', 'start action should preserve canonical evaluation_profile'
assert 'Mission\nReplace the crowded selector with a clearer action layout.' in snapshot['proposalBody'], 'proposal body should be captured separately from the action list'
assert 'Keep critique details separate from the approval-only proposal summary.' not in snapshot['proposalBody'], 'critique notes should not be embedded in the startup-brief body'
assert 'Critique\n- Keep critique details separate from the approval-only proposal summary.' in snapshot['critiqueBody'], 'notes section should render accepted critique notes separately'
assert 'Risks\n- Bundling critique into the action list would make the confirmation harder to scan.' in snapshot['critiqueBody'], 'critique section should render risk notes separately'
assert '- Possible noise: old selector wording' in snapshot['critiqueBody'], 'critique section should preserve additional operator notes separately from the startup-brief body'
assert '- task_type: completion-workflow' in snapshot['routingBody'], 'routing section should render the recommended task_type'
assert '- evaluation_profile: completion-rubric-v1' in snapshot['routingBody'], 'routing section should render the recommended evaluation_profile'
assert [action['id'] for action in snapshot['actions']] == ['start', 'cancel'], 'custom confirmation actions should stay Start/Cancel only'
assert [action['label'] for action in snapshot['actions']] == ['Start', 'Cancel'], 'custom confirmation action labels should be concise'
assert 'Discuss changes in the main chat and rerun /cook.' in snapshot['actions'][1]['description'], 'cancel action should redirect users back to the main chat and rerun /cook'
for action in snapshot['actions']:
    assert 'Replace the crowded selector with a clearer action layout.' not in action['label'], 'proposal mission should not be embedded in action labels'
    assert 'Separate proposal text from actions.' not in action['description'], 'proposal scope should not be embedded in action descriptions'
assert state['mission_anchor'] == 'Replace the crowded selector with a clearer action layout.', 'start action should still accept the proposed mission'
assert state['advisory_startup_brief']['mission'] == 'Replace the crowded selector with a clearer action layout.', 'start action should preserve the confirmed startup brief canonically'
assert state['continuation_reason'].startswith('User started workflow via /cook:'), 'start action should persist the startup routing outcome in continuation_reason'
assert 'Keep critique details separate from the approval-only proposal summary.' in state['continuation_reason'], 'start action should persist the accepted critique outcome canonically'
PY

# Custom confirmation UI: cancel should exit without writing canonical state and should tell the user
# to discuss changes in the main chat before rerunning /cook.
UI_ROOT_CANCEL="$TMPDIR/ui-root-cancel"
mkdir -p "$UI_ROOT_CANCEL"
cd "$UI_ROOT_CANCEL"
git init -q

UI_SESSION_CANCEL="$TMPDIR/ui-session-cancel.jsonl"
UI_SNAPSHOT_CANCEL="$TMPDIR/context-proposal-ui-cancel.json"
UI_MESSAGES_CANCEL="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Cancel from the custom confirmation UI without writing state.",
    "scope": ["Show the proposal separately from the approval-only actions."],
    "constraints": ["Keep cancellation side-effect free."],
    "acceptance": ["Add regression coverage proving cancel leaves .agent absent."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Exercise the cancel path without writing canonical state.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["extensions/completion/prompt-surfaces.ts"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The cancel path is a direct regression around the startup confirmation UI.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The explicit handoff is concrete enough to exercise the cancel confirmation UI."
}
messages = [
    {"role": "user", "content": "Prepare the cancel-path confirmation work and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "The cancel-path confirmation work is ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$UI_SESSION_CANCEL" "$UI_ROOT_CANCEL" "$UI_MESSAGES_CANCEL"

PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_ACTION=cancel \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_UI_PATH="$UI_SNAPSHOT_CANCEL" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$UI_SESSION_CANCEL" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-context-proposal-ui-cancel.out" 2>"$TMPDIR/pi-completion-context-proposal-ui-cancel.err"

python3 - "$UI_SNAPSHOT_CANCEL" "$TMPDIR/pi-completion-context-proposal-ui-cancel.out" "$TMPDIR/pi-completion-context-proposal-ui-cancel.err" <<'PY'
import json
import sys
from pathlib import Path

snapshot = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()
assert 'approval-only' in snapshot['intro'], 'cancel snapshot should keep the approval-only intro'
assert [action['id'] for action in snapshot['actions']] == ['start', 'cancel'], 'cancel snapshot should expose Start/Cancel actions only'
assert [action['label'] for action in snapshot['actions']] == ['Start', 'Cancel'], 'cancel snapshot should keep concise Start/Cancel labels'
assert 'Discuss changes in the main chat and rerun /cook.' in snapshot['actions'][1]['description'], 'cancel action copy should redirect users back to the main chat and rerun /cook'
assert 'Discuss changes in the main chat and rerun /cook.' in output, 'cancel command output should redirect users back to the main chat and rerun /cook'
assert not Path('.agent').exists(), 'cancel action should not write canonical workflow state'
PY

# Explicit primary-agent handoff: /cook should prefer the structured handoff capsule over broad context re-inference.
HANDOFF_ROOT_START="$TMPDIR/handoff-root-start"
mkdir -p "$HANDOFF_ROOT_START"
cd "$HANDOFF_ROOT_START"
git init -q

HANDOFF_SESSION_START="$TMPDIR/handoff-session-start.jsonl"
HANDOFF_SNAPSHOT_START="$TMPDIR/handoff-proposal-start.json"
HANDOFF_MESSAGES_START="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Fix login redirect callback behavior.",
    "scope": [
        "Update the callback redirect decision logic.",
        "Preserve the broader auth flow."
    ],
    "constraints": [
        "Do not refactor the broader auth flow."
    ],
    "acceptance": [
        "Add a regression test for returning to the requested page."
    ],
    "risks": [
        "Stale auth discussion could broaden the startup brief if the handoff is ignored."
    ],
    "notes": [
        "Keep the startup brief aligned with the explicit primary-agent plan."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Land the redirect callback fix and its regression coverage.",
    "first_slice_non_goals": [
        "Do not refactor the broader auth flow."
    ],
    "implementation_surfaces": [
        "src/auth/redirect.ts",
        "tests/auth/redirect.spec.ts"
    ],
    "verification_commands": [
        "npm test -- redirect.spec.ts"
    ],
    "why_this_slice_first": "The redirect callback bug is already bounded enough to start implementation safely.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The implementation plan is concrete and ready for repo changes."
}
messages = [
    {"role": "user", "content": "Please think through the login redirect fix and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "This task is now ready for /cook. Run /cook to confirm the startup brief.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_START" "$HANDOFF_ROOT_START" "$HANDOFF_MESSAGES_START"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_START" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_START" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-start.out" 2>"$TMPDIR/pi-completion-handoff-start.err"

python3 - "$HANDOFF_SNAPSHOT_START" <<'PY'
import json
import sys
from pathlib import Path

snapshot = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path('.agent/state.json').read_text())

assert snapshot['source'] == 'handoff_capsule', 'explicit handoff startup should snapshot the handoff capsule as the proposal source'
assert snapshot['mission'] == 'Fix login redirect callback behavior.', 'explicit handoff startup should preserve the primary-agent mission'
assert state['mission_anchor'] == 'Fix login redirect callback behavior.', 'explicit handoff startup should use the handoff mission as canonical mission_anchor'
assert state['advisory_startup_brief']['source'] == 'primary_agent_handoff', 'explicit handoff startup should preserve the advisory intake source'
assert state['advisory_startup_brief']['risks'] == ['Stale auth discussion could broaden the startup brief if the handoff is ignored.'], 'explicit handoff startup should preserve handoff risks'
assert 'First slice goal: Land the redirect callback fix and its regression coverage.' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve first_slice_goal in advisory notes'
assert 'First slice non-goals: Do not refactor the broader auth flow.' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve first_slice_non_goals in advisory notes'
assert 'Implementation surfaces: src/auth/redirect.ts | tests/auth/redirect.spec.ts' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve implementation_surfaces in advisory notes'
assert 'Verification commands: npm test -- redirect.spec.ts' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve verification_commands in advisory notes'
assert 'Why this slice first: The redirect callback bug is already bounded enough to start implementation safely.' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve why_this_slice_first in advisory notes'
assert 'Primary-agent /cook handoff rationale: The implementation plan is concrete and ready for repo changes.' in state['advisory_startup_brief']['notes'], 'explicit handoff startup should preserve why_cook_now as notes'
PY

# Fresh but non-startable explicit handoff: /cook should fail closed instead of falling back
# to a broad recent-discussion startup brief when the explicit capsule is still too vague.
HANDOFF_ROOT_VAGUE="$TMPDIR/handoff-root-vague"
mkdir -p "$HANDOFF_ROOT_VAGUE"
cd "$HANDOFF_ROOT_VAGUE"
git init -q

HANDOFF_SESSION_VAGUE="$TMPDIR/handoff-session-vague.jsonl"
HANDOFF_SNAPSHOT_VAGUE="$TMPDIR/handoff-proposal-vague.json"
HANDOFF_MESSAGES_VAGUE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Fix login redirect callback behavior.",
    "scope": [
        "Update the callback redirect decision logic."
    ],
    "constraints": [
        "Do not refactor the broader auth flow."
    ],
    "acceptance": [
        "Confirm the final implementation breakdown before coding."
    ],
    "risks": [
        "Broad recent context could be reused if the vague explicit handoff is ignored."
    ],
    "notes": [
        "This handoff is still too vague to start implementation directly."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Patch the callback redirect decision logic.",
    "first_slice_non_goals": [
        "Do not refactor the broader auth flow."
    ],
    "implementation_surfaces": [],
    "verification_commands": [],
    "why_this_slice_first": "The callback redirect path is the likely first slice, but the handoff still lacks execution detail.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The task is workflow-worthy, but the implementation slice is not concrete enough yet."
}
recent_discussion = "Mission: Fix login redirect callback behavior.\nScope:\n- Update the callback redirect decision logic.\nConstraints:\n- Do not refactor the broader auth flow.\nAcceptance:\n- Add a regression test for returning to the requested page."
messages = [
    {"role": "user", "content": recent_discussion},
    {"role": "assistant", "content": "This follow-up might soon be ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_VAGUE" "$HANDOFF_ROOT_VAGUE" "$HANDOFF_MESSAGES_VAGUE"

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_VAGUE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_VAGUE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-vague.out" 2>"$TMPDIR/pi-completion-handoff-vague.err"

python3 - "$HANDOFF_SNAPSHOT_VAGUE" "$TMPDIR/pi-completion-handoff-vague.out" "$TMPDIR/pi-completion-handoff-vague.err" <<'PY'
import sys
from pathlib import Path

snapshot = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not snapshot.exists(), 'fresh non-startable handoff should not emit a startup proposal snapshot'
assert not Path('.agent').exists(), 'fresh non-startable handoff should fail closed without writing canonical state'
assert 'fresh explicit primary-agent handoff exists' in output, 'fresh non-startable handoff should explain that the explicit capsule blocked startup'
assert 'acceptance is not anchored to concrete repo changes or verification' in output, 'fresh non-startable handoff should explain the workflow-only acceptance failure'
assert 'implementation_surfaces is empty' in output, 'fresh non-startable handoff should explain the missing implementation_surfaces requirement'
assert 'verification_commands is empty' in output, 'fresh non-startable handoff should explain the missing verification_commands requirement'
PY

# Fresh explicit handoff with complete first-slice fields but vague acceptance: /cook should still fail closed
# with the dedicated explicit-handoff message instead of bootstrapping canonical state.
HANDOFF_ROOT_VAGUE_ACCEPTANCE="$TMPDIR/handoff-root-vague-acceptance"
mkdir -p "$HANDOFF_ROOT_VAGUE_ACCEPTANCE"
cd "$HANDOFF_ROOT_VAGUE_ACCEPTANCE"
git init -q

HANDOFF_SESSION_VAGUE_ACCEPTANCE="$TMPDIR/handoff-session-vague-acceptance.jsonl"
HANDOFF_SNAPSHOT_VAGUE_ACCEPTANCE="$TMPDIR/handoff-proposal-vague-acceptance.json"
HANDOFF_MESSAGES_VAGUE_ACCEPTANCE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Fix login redirect callback behavior.",
    "scope": [
        "Update the callback redirect decision logic.",
        "Preserve the broader auth flow."
    ],
    "constraints": [
        "Do not refactor the broader auth flow."
    ],
    "acceptance": [
        "Current behavior stays understandable."
    ],
    "risks": [
        "Broad recent context could be reused if the vague explicit handoff is ignored."
    ],
    "notes": [
        "This handoff includes first-slice fields but still lacks concrete acceptance."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Land the redirect callback fix and its regression coverage.",
    "first_slice_non_goals": [
        "Do not refactor the broader auth flow."
    ],
    "implementation_surfaces": [
        "src/auth/redirect.ts",
        "tests/auth/redirect.spec.ts"
    ],
    "verification_commands": [
        "npm test -- redirect.spec.ts"
    ],
    "why_this_slice_first": "The redirect callback bug is already bounded enough to start implementation safely once acceptance is concrete.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The task is workflow-worthy, but the acceptance still needs concrete repo-change detail."
}
recent_discussion = "Mission: Fix login redirect callback behavior.\nScope:\n- Update the callback redirect decision logic.\nConstraints:\n- Do not refactor the broader auth flow.\nAcceptance:\n- Add a regression test for returning to the requested page."
messages = [
    {"role": "user", "content": recent_discussion},
    {"role": "assistant", "content": "This follow-up might soon be ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_VAGUE_ACCEPTANCE" "$HANDOFF_ROOT_VAGUE_ACCEPTANCE" "$HANDOFF_MESSAGES_VAGUE_ACCEPTANCE"

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_VAGUE_ACCEPTANCE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_VAGUE_ACCEPTANCE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-vague-acceptance.out" 2>"$TMPDIR/pi-completion-handoff-vague-acceptance.err"

python3 - "$HANDOFF_SNAPSHOT_VAGUE_ACCEPTANCE" "$TMPDIR/pi-completion-handoff-vague-acceptance.out" "$TMPDIR/pi-completion-handoff-vague-acceptance.err" <<'PY'
import sys
from pathlib import Path

snapshot = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not snapshot.exists(), 'fresh explicit handoff with vague acceptance should not emit a startup proposal snapshot'
assert not Path('.agent').exists(), 'fresh explicit handoff with vague acceptance should fail closed without writing canonical state'
assert 'fresh explicit primary-agent handoff exists' in output, 'fresh explicit handoff with vague acceptance should use the dedicated explicit-handoff fail-closed message'
assert 'acceptance is not anchored to concrete repo changes or verification' in output, 'fresh explicit handoff with vague acceptance should explain the vague acceptance failure'
PY

# Done workflow + fresh handoff: the fresh explicit handoff should override done-state suppression and start the new round.
HANDOFF_ROOT_DONE="$TMPDIR/handoff-root-done"
mkdir -p "$HANDOFF_ROOT_DONE"
cd "$HANDOFF_ROOT_DONE"
git init -q

DONE_SEED_SESSION="$TMPDIR/handoff-done-seed-session.jsonl"
DONE_SEED_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Seed a finished workflow before testing fresh handoff priority.",
    "scope": ["Create canonical workflow state."],
    "constraints": ["Keep the seed minimal."],
    "acceptance": ["Add regression coverage for marking the seeded workflow done before the next step."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Bootstrap the done-workflow seed fixture from an explicit handoff.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["scripts/context-proposal-test.sh"],
    "verification_commands": ["npm run context-proposal-test"],
    "why_this_slice_first": "The done-workflow handoff test needs canonical state before it can be marked done."
}
messages = [
    {"role": "user", "content": "Prepare the done-workflow seed fixture and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "The done-workflow seed fixture is ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$DONE_SEED_SESSION" "$HANDOFF_ROOT_DONE" "$DONE_SEED_MESSAGES"
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$DONE_SEED_SESSION" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-done-seed.out" 2>"$TMPDIR/pi-completion-handoff-done-seed.err"
mark_done

HANDOFF_SESSION_DONE="$TMPDIR/handoff-session-done.jsonl"
HANDOFF_SNAPSHOT_DONE="$TMPDIR/handoff-proposal-done.json"
HANDOFF_MESSAGES_DONE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Reopen the login redirect work for the callback edge case.",
    "scope": [
        "Handle the callback edge case in the redirect logic.",
        "Keep the finished workflow as historical context only."
    ],
    "constraints": [
        "Do not turn done-state suppression into the startup mission."
    ],
    "acceptance": [
        "Add a regression test for the callback edge case."
    ],
    "risks": [
        "Done-state context could override the new mission if the handoff is ignored."
    ],
    "notes": [
        "This is a fresh implementation round, not a summary of the finished workflow."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Patch the callback edge case and cover it with a focused regression test.",
    "first_slice_non_goals": [
        "Do not turn done-state suppression into the startup mission."
    ],
    "implementation_surfaces": [
        "src/auth/redirect.ts",
        "tests/auth/redirect-edge.spec.ts"
    ],
    "verification_commands": [
        "npm test -- redirect-edge.spec.ts"
    ],
    "why_this_slice_first": "The new callback edge case is the smallest fresh implementation slice after the prior round closed.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "A new implementation-ready edge case was identified after the previous round closed."
}
messages = [
    {"role": "user", "content": "The previous round is done, but there is a fresh callback edge case to implement."},
    {"role": "assistant", "content": "The next round is ready for /cook. Run /cook to confirm this fresh implementation mission.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_DONE" "$HANDOFF_ROOT_DONE" "$HANDOFF_MESSAGES_DONE"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_DONE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_DONE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-done.out" 2>"$TMPDIR/pi-completion-handoff-done.err"

python3 - "$HANDOFF_SNAPSHOT_DONE" <<'PY'
import json
import sys
from pathlib import Path

snapshot = json.loads(Path(sys.argv[1]).read_text())
state = json.loads(Path('.agent/state.json').read_text())

assert snapshot['source'] == 'handoff_capsule', 'done-workflow handoff should still use the explicit handoff capsule'
assert snapshot['mission'] == 'Reopen the login redirect work for the callback edge case.', 'done-workflow handoff should preserve the fresh mission'
assert state['mission_anchor'] == 'Reopen the login redirect work for the callback edge case.', 'done-workflow handoff should override done-state suppression with the fresh mission'
assert state['continuation_policy'] == 'continue', 'done-workflow handoff should reopen canonical workflow state for the new round'
assert state['advisory_startup_brief']['source'] == 'primary_agent_handoff', 'done-workflow handoff should preserve the handoff advisory source'
assert 'First slice goal: Patch the callback edge case and cover it with a focused regression test.' in state['advisory_startup_brief']['notes'], 'done-workflow handoff should preserve first_slice_goal in advisory notes'
assert 'Verification commands: npm test -- redirect-edge.spec.ts' in state['advisory_startup_brief']['notes'], 'done-workflow handoff should preserve verification_commands in advisory notes'
PY

# Stale handoff: later discussion should invalidate the older handoff capsule and fail closed instead of falling back to newer discussion.
HANDOFF_ROOT_STALE="$TMPDIR/handoff-root-stale"
mkdir -p "$HANDOFF_ROOT_STALE"
cd "$HANDOFF_ROOT_STALE"
git init -q

HANDOFF_SESSION_STALE="$TMPDIR/handoff-session-stale.jsonl"
HANDOFF_SNAPSHOT_STALE="$TMPDIR/handoff-proposal-stale.json"
HANDOFF_MESSAGES_STALE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Fix the original login redirect callback behavior.",
    "scope": ["Update the original callback redirect logic."],
    "constraints": ["Do not refactor the auth stack."],
    "acceptance": ["Add the original callback regression test."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Ship the original login callback follow-up.",
    "first_slice_non_goals": ["Do not refactor the auth stack."],
    "implementation_surfaces": ["src/auth/login-redirect.ts"],
    "verification_commands": ["npm test -- login-redirect.spec.ts"],
    "why_this_slice_first": "The original callback follow-up was the first bounded implementation slice before later discussion replaced it."
}
newer_discussion = "Mission: Ship logout redirect consistency instead.\nScope:\n- Update the logout redirect path.\nConstraints:\n- Leave the login callback flow unchanged.\nAcceptance:\n- Add a logout redirect regression test."
messages = [
    {"role": "user", "content": "Please plan the login redirect follow-up."},
    {"role": "assistant", "content": "Run /cook if you want to start the original follow-up.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
    {"role": "user", "content": newer_discussion},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_STALE" "$HANDOFF_ROOT_STALE" "$HANDOFF_MESSAGES_STALE"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_STALE" \
PI_COMPLETION_DISABLE_PRIMARY_HANDOFF_SYNTHESIS=1 \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_STALE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-stale.out" 2>"$TMPDIR/pi-completion-handoff-stale.err"

python3 - "$HANDOFF_SNAPSHOT_STALE" "$TMPDIR/pi-completion-handoff-stale.out" "$TMPDIR/pi-completion-handoff-stale.err" <<'PY'
import sys
from pathlib import Path

snapshot = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not snapshot.exists(), 'stale handoff should not emit a startup proposal snapshot'
assert not Path('.agent').exists(), 'stale handoff should fail closed without writing canonical state'
assert 'primary-agent handoff step could not prepare a concrete startup handoff' in output, 'stale handoff should fail closed when the synthesized handoff step produces nothing'
PY

# Negative handoff rationale: a non-startable capsule must not become the startup mission.
HANDOFF_ROOT_NEGATIVE="$TMPDIR/handoff-root-negative"
mkdir -p "$HANDOFF_ROOT_NEGATIVE"
cd "$HANDOFF_ROOT_NEGATIVE"
git init -q

HANDOFF_SESSION_NEGATIVE="$TMPDIR/handoff-session-negative.jsonl"
HANDOFF_SNAPSHOT_NEGATIVE="$TMPDIR/handoff-proposal-negative.json"
HANDOFF_MESSAGES_NEGATIVE="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Do not reopen implementation for the finished workflow.",
    "scope": ["Keep the old workflow closed."],
    "constraints": ["Do not start repo changes."],
    "acceptance": ["Explain that the finished workflow should stay closed."],
    "risks": [],
    "notes": [],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Keep the finished workflow closed.",
    "first_slice_non_goals": ["Do not start repo changes."],
    "implementation_surfaces": ["docs/workflow-status.md"],
    "verification_commands": ["npm test -- workflow-status"],
    "why_this_slice_first": "This is the only bounded next step being proposed, even though the mission itself is invalid."
}
messages = [
    {"role": "user", "content": "Should we reopen the finished workflow?"},
    {"role": "assistant", "content": "Do not reopen it directly.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$HANDOFF_SESSION_NEGATIVE" "$HANDOFF_ROOT_NEGATIVE" "$HANDOFF_MESSAGES_NEGATIVE"

PI_COMPLETION_DISABLE_CONTEXT_PROPOSAL_ANALYST=1 \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$HANDOFF_SNAPSHOT_NEGATIVE" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$HANDOFF_SESSION_NEGATIVE" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-handoff-negative.out" 2>"$TMPDIR/pi-completion-handoff-negative.err"

python3 - "$HANDOFF_SNAPSHOT_NEGATIVE" "$TMPDIR/pi-completion-handoff-negative.out" "$TMPDIR/pi-completion-handoff-negative.err" <<'PY'
import sys
from pathlib import Path

snapshot = Path(sys.argv[1])
output = Path(sys.argv[2]).read_text() + Path(sys.argv[3]).read_text()

assert not snapshot.exists(), 'negative handoff rationale should not emit a startup proposal snapshot'
assert not Path('.agent').exists(), 'negative handoff rationale should fail closed without writing canonical state'
assert '/cook failed closed' in output, 'negative handoff rationale should fail closed instead of becoming the startup mission'
PY

grep -q 'export async function deriveCookContextProposalFromRecentDiscussion' "$PKG_ROOT/extensions/completion/proposal.ts"
grep -q 'export function extractLatestCookHandoffProposal' "$PKG_ROOT/extensions/completion/proposal.ts"
grep -q 'export function parseContextProposalAnalystOutput' "$PKG_ROOT/extensions/completion/proposal.ts"
grep -q 'export function buildContextProposalConfirmationLayout' "$PKG_ROOT/extensions/completion/prompt-surfaces.ts"
grep -q 'export function buildEvaluationRoleContextLines' "$PKG_ROOT/extensions/completion/prompt-surfaces.ts"

echo "context proposal test passed: $ROOT"
