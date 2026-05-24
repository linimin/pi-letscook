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

cd "$TMPDIR"
git init -q

BOOTSTRAP_SESSION="$TMPDIR/session-bootstrap.jsonl"
BOOTSTRAP_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Smoke-test mission.",
    "scope": [
        "Bootstrap a completion workflow for the refocus regression fixture."
    ],
    "constraints": [
        "Keep active-workflow refocus behavior under the explicit-handoff startup contract."
    ],
    "acceptance": [
        "Bootstrap canonical refocus-fixture state for the active-workflow regression.",
        "Verify the refocus regression with npm run refocus-test."
    ],
    "risks": [],
    "notes": [
        "Use explicit primary-agent handoff startup for the refocus regression fixture."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Bootstrap the refocus regression fixture from a fresh explicit handoff.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "scripts/refocus-test.sh"
    ],
    "verification_commands": [
        "npm run refocus-test"
    ],
    "why_this_slice_first": "The refocus regression fixture needs canonical state before active-workflow routing can be exercised.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The active-workflow refocus regression needs a fresh explicit startup boundary."
}
messages = [
    {"role": "user", "content": "Prepare the refocus regression fixture and tell me when it is ready for /cook."},
    {"role": "assistant", "content": "The refocus regression fixture is ready for /cook.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$BOOTSTRAP_SESSION" "$TMPDIR" "$BOOTSTRAP_MESSAGES"

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
pi --session "$BOOTSTRAP_SESSION" -e "$PKG_ROOT" -p "/cook" >"$TMPDIR/pi-completion-refocus-bootstrap.out" 2>"$TMPDIR/pi-completion-refocus-bootstrap.err" &
PI_PID=$!
for _ in $(seq 1 60); do
  if [[ -f .agent/profile.json && -f .agent/state.json && -f .agent/plan.json && -f .agent/active-slice.json ]]; then
    break
  fi
  sleep 1
done
if [[ ! -f .agent/profile.json || ! -f .agent/state.json || ! -f .agent/plan.json || ! -f .agent/active-slice.json ]]; then
  echo "completion bootstrap did not materialize canonical files in time" >&2
  cat "$TMPDIR/pi-completion-refocus-bootstrap.err" >&2 || true
  kill "$PI_PID" >/dev/null 2>&1 || true
  wait "$PI_PID" >/dev/null 2>&1 || true
  exit 1
fi
kill "$PI_PID" >/dev/null 2>&1 || true
wait "$PI_PID" >/dev/null 2>&1 || true

INITIAL_MISSION="$(python3 - <<'PY'
import json
from pathlib import Path
state = json.loads(Path('.agent/state.json').read_text())
print(state['mission_anchor'])
PY
)"

INLINE_PROMPT_ROUTING="$TMPDIR/inline-prompt-routing.json"
INLINE_PROMPT_PROPOSAL="$TMPDIR/inline-prompt-proposal.json"
INLINE_PROMPT_CHOOSER="$TMPDIR/inline-prompt-chooser.json"
INLINE_PROMPT_BASELINE="$TMPDIR/inline-prompt-before.json"
INLINE_PROMPT_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "inline-refocus",
    "mission": "Replace the active workflow from inline /cook prompt.",
    "scope": [
        "Swap the initial bootstrap workflow for the inline-prompt replacement mission."
    ],
    "constraints": [
        "Keep the approval-only Start/Cancel refocus gate."
    ],
    "acceptance": [
        "Rewrite canonical state only after the inline replacement mission is approved."
    ],
    "risks": [],
    "notes": [
        "Inline /cook prompt should override stale startup context while the workflow is active."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Replace the active workflow using the inline /cook prompt.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "scripts/refocus-test.sh"
    ],
    "verification_commands": [
        "npm run refocus-test"
    ],
    "why_this_slice_first": "Inline prompt replacement should work without bouncing users back to the main chat.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The inline replacement mission is concrete enough to refocus the active workflow."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
python3 - "$INLINE_PROMPT_BASELINE" <<'PY'
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

PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$INLINE_PROMPT_HANDOFF" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$INLINE_PROMPT_ROUTING" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$INLINE_PROMPT_PROPOSAL" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$INLINE_PROMPT_CHOOSER" \
PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi -e "$PKG_ROOT" -p "/cook replace the active workflow from this inline prompt" \
  >"$TMPDIR/pi-completion-refocus-inline-prompt.out" 2>"$TMPDIR/pi-completion-refocus-inline-prompt.err"

python3 - "$TMPDIR/pi-completion-refocus-inline-prompt.out" "$TMPDIR/pi-completion-refocus-inline-prompt.err" "$INLINE_PROMPT_ROUTING" "$INLINE_PROMPT_PROPOSAL" "$INLINE_PROMPT_CHOOSER" "$INITIAL_MISSION" "$INLINE_PROMPT_BASELINE" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).read_text() + Path(sys.argv[2]).read_text()
routing = json.loads(Path(sys.argv[3]).read_text())
proposal = json.loads(Path(sys.argv[4]).read_text())
chooser = json.loads(Path(sys.argv[5]).read_text())
initial_mission = sys.argv[6]
before = json.loads(Path(sys.argv[7]).read_text())
tracked = [
    Path('.agent/mission.md'),
    Path('.agent/profile.json'),
    Path('.agent/state.json'),
    Path('.agent/plan.json'),
    Path('.agent/active-slice.json'),
    Path('.agent/verification-evidence.json'),
]
after = {path.name: path.read_text() for path in tracked}
state = json.loads(after['state.json'])
plan = json.loads(after['plan.json'])
active = json.loads(after['active-slice.json'])
current_state = json.loads(before['state.json'])
assert current_state['mission_anchor'] == initial_mission, 'active /cook inline prompt should start from the current mission anchor'
assert routing['action'] == 'refocus', 'active /cook inline prompt should route through refocus'
assert routing['reason'] == 'fresh_explicit_handoff', 'active /cook inline prompt should synthesize an explicit startup brief for replacement'
assert proposal['mission'] == 'Replace the active workflow from inline /cook prompt.', 'active /cook inline prompt should surface the replacement mission'
assert 'Replace the active workflow from inline /cook prompt.' in chooser['title'], 'active /cook inline prompt should surface the replacement mission in the chooser'
assert state['mission_anchor'] == 'Replace the active workflow from inline /cook prompt.', 'active /cook inline prompt should refocus the canonical mission'
assert plan['mission_anchor'] == state['mission_anchor'], 'refocused plan should match the inline-prompt mission anchor'
assert active['mission_anchor'] == state['mission_anchor'], 'refocused active slice should match the inline-prompt mission anchor'
assert before != after, 'active /cook inline prompt should rewrite canonical files after confirmation'
assert 'Refocused completion mission from explicit primary-agent handoff to: Replace the active workflow from inline /cook prompt.' in output, 'active /cook inline prompt should report the refocused mission'
PY

SESSION_INITIAL_REFOCUS="$TMPDIR/session-initial-bare-refocus.jsonl"
INITIAL_REFOCUS_ROUTING="$TMPDIR/initial-bare-refocus-routing.json"
INITIAL_REFOCUS_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Remove completion status line, keep widget.",
    "scope": [
        "Replace the initial smoke-test workflow with the widget mission."
    ],
    "constraints": [
        "Keep the approval-only Start/Cancel refocus gate."
    ],
    "acceptance": [
        "Rewrite canonical state only after the replacement mission is approved."
    ],
    "risks": [],
    "notes": [
        "Use a fresh explicit primary-agent handoff for the active-workflow replacement."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Replace the initial smoke-test workflow with the widget mission.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "scripts/refocus-test.sh"
    ],
    "verification_commands": [
        "npm run refocus-test"
    ],
    "why_this_slice_first": "The fresh explicit handoff is the only supported replacement entry while a workflow is active.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "A different active workflow is ready and explicitly handed off by the primary agent."
}
messages = [
    {"role": "user", "content": "The smoke-test workflow is active, but a different replacement workflow may now be ready."},
    {"role": "assistant", "content": "Use this fresh explicit handoff if you want /cook to replace the active workflow.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"
write_session_messages "$SESSION_INITIAL_REFOCUS" "$TMPDIR" "$INITIAL_REFOCUS_MESSAGES"

PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$INITIAL_REFOCUS_ROUTING" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_INITIAL_REFOCUS" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-completion-refocus.out" 2>"$TMPDIR/pi-completion-refocus.err"

python3 - "$INITIAL_REFOCUS_ROUTING" <<'PY'
import json
import sys
from pathlib import Path

new_anchor = 'Remove completion status line, keep widget.'
expected_task_type = 'completion-workflow'
expected_eval_profile = 'completion-rubric-v1'
routing = json.loads(Path(sys.argv[1]).read_text())
mission_text = Path('.agent/mission.md').read_text()
profile = json.loads(Path('.agent/profile.json').read_text())
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert new_anchor in mission_text, '.agent/mission.md did not update to the refocused mission anchor'
assert profile['task_type'] == expected_task_type, 'profile.json task_type mismatch after refocus'
assert profile['evaluation_profile'] == expected_eval_profile, 'profile.json evaluation_profile mismatch after refocus'
assert state['mission_anchor'] == new_anchor, 'state.json mission_anchor mismatch after refocus'
assert state['task_type'] == expected_task_type, 'state.json task_type mismatch after refocus'
assert state['evaluation_profile'] == expected_eval_profile, 'state.json evaluation_profile mismatch after refocus'
assert state['advisory_startup_brief']['mission'] == new_anchor, 'refocus should preserve the confirmed startup brief as advisory intake'
assert plan['mission_anchor'] == new_anchor, 'plan.json mission_anchor mismatch after refocus'
assert plan['task_type'] == expected_task_type, 'plan.json task_type mismatch after refocus'
assert plan['evaluation_profile'] == expected_eval_profile, 'plan.json evaluation_profile mismatch after refocus'
assert active['mission_anchor'] == new_anchor, 'active-slice.json mission_anchor mismatch after refocus'
assert active['task_type'] == expected_task_type, 'active-slice.json task_type mismatch after refocus'
assert active['evaluation_profile'] == expected_eval_profile, 'active-slice.json evaluation_profile mismatch after refocus'
assert state['current_phase'] == 'reground', 'state.json current_phase should reset to reground after refocus'
assert state['requires_reground'] is True, 'state.json requires_reground should be true after refocus'
assert state['next_mandatory_role'] == 'completion-regrounder', 'next_mandatory_role should reset to completion-regrounder'
assert state['continuation_reason'].startswith('User refocused workflow via /cook:'), 'continuation_reason should record the refocus'
assert plan['plan_basis'] == 'user_refocus', 'plan.json plan_basis should be user_refocus after refocus'
assert active['status'] == 'idle', 'active-slice.json status should reset to idle after refocus'
assert routing['mode'] == 'bare', 'supported refocus should use bare active-workflow routing mode'
assert 'explicitGoal' not in routing, 'supported bare refocus should not expose removed explicit-goal shim fields'
assert 'explicitGoalProvided' not in routing, 'supported bare refocus should not expose removed explicit-goal shim fields'
assert routing['action'] == 'refocus', 'supported bare /cook should classify as refocus when a fresh explicit handoff proposes a different mission'
assert routing['reason'] == 'fresh_explicit_handoff', 'supported bare /cook should record the explicit-handoff replacement reason'
assert routing['proposedMissionAnchor'] == new_anchor, 'explicit handoff routing snapshot should expose the replacement mission anchor'
assert routing['proposalSource'] == 'handoff_capsule', 'explicit handoff routing snapshot should preserve the handoff source'
PY

UPDATED_MISSION="$(python3 - <<'PY'
import json
from pathlib import Path
state = json.loads(Path('.agent/state.json').read_text())
print(state['mission_anchor'])
PY
)"

if [[ "$INITIAL_MISSION" == "$UPDATED_MISSION" ]]; then
  echo "expected mission anchor to change during supported bare refocus" >&2
  exit 1
fi

# Fresh explicit handoff replacements must still reach the chooser and final Start/Cancel gate while the
# workflow is active.
BARE_REFOCUS_MISSION='Exercise explicit active-workflow replacement coverage.'
BARE_REFOCUS_MESSAGES="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "m0002",
    "mission": "Exercise explicit active-workflow replacement coverage.",
    "scope": [
        "Treat the active bare /cook request as an explicit replacement workflow.",
        "Keep the replacement behind the existing approval-only Start/Cancel gate."
    ],
    "constraints": [
        "Do not rewrite canonical state before the final Start confirmation."
    ],
    "acceptance": [
        "Add deterministic coverage proving the chooser and final approval path for this explicit replacement mission."
    ],
    "risks": [],
    "notes": [
        "This replacement should come only from the fresh explicit handoff, not recent discussion inference."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Exercise the active-workflow explicit-handoff replacement path.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "scripts/refocus-test.sh"
    ],
    "verification_commands": [
        "npm run refocus-test"
    ],
    "why_this_slice_first": "The active workflow should only replace from a fresh explicit handoff.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The primary agent explicitly handed off a replacement workflow while the current one is active."
}
messages = [
    {"role": "user", "content": "The current workflow is active, but there is a fresh explicit replacement handoff ready."},
    {"role": "assistant", "content": "Use this fresh explicit handoff if you want /cook to replace the active workflow.\n\n```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```"},
]
print(json.dumps(messages, ensure_ascii=False))
PY
)"

SESSION_BARE_CHOOSER_CANCEL="$TMPDIR/session-bare-chooser-cancel.jsonl"
BARE_CHOOSER_SNAPSHOT="$TMPDIR/bare-existing-workflow-chooser.json"
BARE_ROUTING_CHOOSER_CANCEL="$TMPDIR/bare-routing-chooser-cancel.json"
write_session_messages "$SESSION_BARE_CHOOSER_CANCEL" "$TMPDIR" "$BARE_REFOCUS_MESSAGES"

PI_COMPLETION_EXISTING_WORKFLOW_ACTION=cancel \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$BARE_CHOOSER_SNAPSHOT" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$BARE_ROUTING_CHOOSER_CANCEL" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_BARE_CHOOSER_CANCEL" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-completion-bare-chooser-cancel.out" 2>"$TMPDIR/pi-completion-bare-chooser-cancel.err"

python3 - "$BARE_CHOOSER_SNAPSHOT" "$BARE_ROUTING_CHOOSER_CANCEL" "$TMPDIR/pi-completion-bare-chooser-cancel.out" "$TMPDIR/pi-completion-bare-chooser-cancel.err" "$UPDATED_MISSION" "$BARE_REFOCUS_MISSION" <<'PY'
import json
import sys
from pathlib import Path

chooser = json.loads(Path(sys.argv[1]).read_text())
routing = json.loads(Path(sys.argv[2]).read_text())
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
updated_mission = sys.argv[5]
replacement_mission = sys.argv[6]
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert state['mission_anchor'] == updated_mission, 'chooser cancel should keep the current mission anchor'
assert plan['mission_anchor'] == updated_mission, 'chooser cancel should keep plan.json unchanged'
assert active['mission_anchor'] == updated_mission, 'chooser cancel should keep active-slice.json unchanged'
assert routing['mode'] == 'bare', 'bare /cook should snapshot bare active-workflow routing mode'
assert 'explicitGoal' not in routing, 'bare chooser routing should not expose removed explicit-goal shim fields'
assert 'explicitGoalProvided' not in routing, 'bare chooser routing should not expose removed explicit-goal shim fields'
assert routing['action'] == 'refocus', 'fresh explicit replacement handoff should classify active bare /cook as refocus'
assert routing['reason'] == 'fresh_explicit_handoff', 'fresh explicit replacement handoff should record the explicit-handoff reason'
assert routing['currentMissionAnchor'] == updated_mission, 'explicit-handoff routing should keep the current mission anchor until the user approves replacement'
assert routing['proposedMissionAnchor'] == replacement_mission, 'explicit-handoff routing should expose the proposed replacement mission'
assert routing['proposalSource'] == 'handoff_capsule', 'explicit-handoff routing should preserve the handoff source'
assert chooser['title'].startswith('Existing completion workflow found'), 'bare chooser snapshot should describe the existing-workflow prompt'
assert chooser['choices'][0].startswith('Continue current workflow'), 'bare chooser should keep the continue option'
assert chooser['choices'][1].startswith('Start new workflow from explicit primary-agent handoff'), 'bare chooser should offer the explicit-handoff replacement option'
assert 'Start/Cancel confirmation' in chooser['choices'][1], 'bare chooser should mention the approval-only replacement confirmation'
assert chooser['choices'][2].startswith('Cancel'), 'bare chooser should keep the cancel option'
assert 'Discuss changes in the main chat and rerun /cook.' in output, 'bare chooser cancel should redirect users back to the main chat and rerun /cook'
PY

SESSION_BARE_FINAL_CANCEL="$TMPDIR/session-bare-final-cancel.jsonl"
BARE_ROUTING_FINAL_CANCEL="$TMPDIR/bare-routing-final-cancel.json"
BARE_PROPOSAL_CANCEL="$TMPDIR/bare-replacement-proposal-cancel.json"
write_session_messages "$SESSION_BARE_FINAL_CANCEL" "$TMPDIR" "$BARE_REFOCUS_MESSAGES"

PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=cancel \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$BARE_PROPOSAL_CANCEL" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$BARE_ROUTING_FINAL_CANCEL" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_BARE_FINAL_CANCEL" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-completion-bare-final-cancel.out" 2>"$TMPDIR/pi-completion-bare-final-cancel.err"

python3 - "$BARE_PROPOSAL_CANCEL" "$BARE_ROUTING_FINAL_CANCEL" "$TMPDIR/pi-completion-bare-final-cancel.out" "$TMPDIR/pi-completion-bare-final-cancel.err" "$UPDATED_MISSION" "$BARE_REFOCUS_MISSION" <<'PY'
import json
import sys
from pathlib import Path

proposal = json.loads(Path(sys.argv[1]).read_text())
routing = json.loads(Path(sys.argv[2]).read_text())
output = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
updated_mission = sys.argv[5]
replacement_mission = sys.argv[6]
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert state['mission_anchor'] == updated_mission, 'final Start/Cancel cancel should keep the current mission anchor'
assert plan['mission_anchor'] == updated_mission, 'final Start/Cancel cancel should keep plan.json unchanged'
assert active['mission_anchor'] == updated_mission, 'final Start/Cancel cancel should keep active-slice.json unchanged'
assert routing['action'] == 'refocus', 'final Start/Cancel cancel should still come from an explicit-handoff refocus classification'
assert routing['reason'] == 'fresh_explicit_handoff', 'final Start/Cancel cancel should preserve the explicit-handoff reason'
assert routing['currentMissionAnchor'] == updated_mission, 'final Start/Cancel cancel should keep the current mission anchor until the user approves replacement'
assert proposal['mission'] == replacement_mission, 'final Start/Cancel cancel should still prepare the replacement proposal before rewriting state'
assert proposal['source'] == 'handoff_capsule', 'final Start/Cancel cancel should preserve the explicit-handoff proposal source'
assert 'Discuss changes in the main chat and rerun /cook.' in output, 'final Start/Cancel cancel should redirect users back to the main chat and rerun /cook'
PY

SESSION_BARE_ACCEPT="$TMPDIR/session-bare-accept.jsonl"
BARE_ROUTING_ACCEPT="$TMPDIR/bare-routing-accept.json"
BARE_PROPOSAL_ACCEPT="$TMPDIR/bare-replacement-proposal-accept.json"
write_session_messages "$SESSION_BARE_ACCEPT" "$TMPDIR" "$BARE_REFOCUS_MESSAGES"

PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$BARE_PROPOSAL_ACCEPT" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$BARE_ROUTING_ACCEPT" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SESSION_BARE_ACCEPT" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-completion-bare-accept.out" 2>"$TMPDIR/pi-completion-bare-accept.err"

python3 - "$BARE_PROPOSAL_ACCEPT" "$BARE_ROUTING_ACCEPT" <<'PY'
import json
import sys
from pathlib import Path

new_anchor = 'Exercise explicit active-workflow replacement coverage.'
expected_task_type = 'completion-workflow'
expected_eval_profile = 'completion-rubric-v1'
proposal = json.loads(Path(sys.argv[1]).read_text())
routing = json.loads(Path(sys.argv[2]).read_text())
mission_text = Path('.agent/mission.md').read_text()
profile = json.loads(Path('.agent/profile.json').read_text())
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert proposal['mission'] == new_anchor, 'accepted bare refocus should preserve the replacement proposal mission'
assert routing['mode'] == 'bare', 'accepted bare refocus should keep bare routing mode'
assert 'explicitGoal' not in routing, 'accepted bare refocus should not expose removed explicit-goal shim fields'
assert 'explicitGoalProvided' not in routing, 'accepted bare refocus should not expose removed explicit-goal shim fields'
assert routing['action'] == 'refocus', 'accepted bare refocus should keep the explicit-handoff refocus classification'
assert routing['reason'] == 'fresh_explicit_handoff', 'accepted bare refocus should keep the explicit-handoff reason'
assert routing['currentMissionAnchor'] == 'Remove completion status line, keep widget.', 'accepted bare refocus should expose the original mission until Start is accepted'
assert routing['proposalSource'] == 'handoff_capsule', 'accepted bare refocus should preserve the explicit-handoff source'
assert new_anchor in mission_text, '.agent/mission.md did not update to the bare refocus mission anchor'
assert profile['task_type'] == expected_task_type, 'profile.json task_type mismatch after bare refocus'
assert profile['evaluation_profile'] == expected_eval_profile, 'profile.json evaluation_profile mismatch after bare refocus'
assert state['mission_anchor'] == new_anchor, 'state.json mission_anchor mismatch after bare refocus'
assert state['task_type'] == expected_task_type, 'state.json task_type mismatch after bare refocus'
assert state['evaluation_profile'] == expected_eval_profile, 'state.json evaluation_profile mismatch after bare refocus'
assert state['advisory_startup_brief']['mission'] == new_anchor, 'bare refocus should preserve the confirmed startup brief as advisory intake'
assert plan['mission_anchor'] == new_anchor, 'plan.json mission_anchor mismatch after bare refocus'
assert plan['task_type'] == expected_task_type, 'plan.json task_type mismatch after bare refocus'
assert plan['evaluation_profile'] == expected_eval_profile, 'plan.json evaluation_profile mismatch after bare refocus'
assert active['mission_anchor'] == new_anchor, 'active-slice.json mission_anchor mismatch after bare refocus'
assert active['task_type'] == expected_task_type, 'active-slice.json task_type mismatch after bare refocus'
assert active['evaluation_profile'] == expected_eval_profile, 'active-slice.json evaluation_profile mismatch after bare refocus'
assert state['current_phase'] == 'reground', 'state.json current_phase should reset to reground after bare refocus'
assert state['requires_reground'] is True, 'state.json requires_reground should be true after bare refocus'
assert state['next_mandatory_role'] == 'completion-regrounder', 'next_mandatory_role should reset to completion-regrounder after bare refocus'
assert state['continuation_reason'].startswith('User refocused workflow via /cook:'), 'continuation_reason should record the bare refocus'
assert plan['plan_basis'] == 'user_refocus', 'plan.json plan_basis should be user_refocus after bare refocus'
assert active['status'] == 'idle', 'active-slice.json status should reset to idle after bare refocus'
PY

SYNTH_REPLACEMENT_SESSION="$TMPDIR/session-synthesized-active-replacement.jsonl"
SYNTH_REPLACEMENT_ROUTING="$TMPDIR/synthesized-active-replacement-routing.json"
SYNTH_REPLACEMENT_PROPOSAL="$TMPDIR/synthesized-active-replacement-proposal.json"
write_session "$SYNTH_REPLACEMENT_SESSION" "$TMPDIR" "Please replace the current workflow with the synthesized replacement mission when I run /cook."

SYNTH_REPLACEMENT_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "captured_at": "2026-01-01T00:00:02.000Z",
    "source_turn_id": "generated-primary-agent-handoff",
    "mission": "Exercise same-entry active-workflow replacement synthesis.",
    "scope": [
        "Generate the replacement handoff inside the same /cook entry.",
        "Keep the chooser and final Start/Cancel confirmation truthful."
    ],
    "constraints": [
        "Do not rewrite canonical state before the final Start confirmation."
    ],
    "acceptance": [
        "Replace the active workflow using the synthesized primary-agent handoff.",
        "Keep deterministic coverage for same-entry active replacement."
    ],
    "risks": [],
    "notes": [
        "This replacement is synthesized during /cook rather than pre-authored in the transcript."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Exercise same-entry active-workflow replacement synthesis.",
    "first_slice_non_goals": [],
    "implementation_surfaces": [
        "scripts/refocus-test.sh"
    ],
    "verification_commands": [
        "npm run refocus-test"
    ],
    "why_this_slice_first": "Active replacement should work when the primary-agent handoff is synthesized in the same /cook entry.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The user explicitly chose workflow mode and the replacement handoff can be synthesized immediately."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"

PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$SYNTH_REPLACEMENT_HANDOFF" \
PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$SYNTH_REPLACEMENT_PROPOSAL" \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$SYNTH_REPLACEMENT_ROUTING" \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
pi --session "$SYNTH_REPLACEMENT_SESSION" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/pi-completion-synthesized-active-replacement.out" 2>"$TMPDIR/pi-completion-synthesized-active-replacement.err"

python3 - "$SYNTH_REPLACEMENT_PROPOSAL" "$SYNTH_REPLACEMENT_ROUTING" <<'PY'
import json
import sys
from pathlib import Path

new_anchor = 'Exercise same-entry active-workflow replacement synthesis.'
proposal = json.loads(Path(sys.argv[1]).read_text())
routing = json.loads(Path(sys.argv[2]).read_text())
state = json.loads(Path('.agent/state.json').read_text())
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

assert proposal['mission'] == new_anchor, 'same-entry synthesized replacement should preserve the replacement proposal mission'
assert routing['action'] == 'refocus', 'same-entry synthesized replacement should classify active bare /cook as refocus'
assert routing['reason'] == 'fresh_explicit_handoff', 'same-entry synthesized replacement should reuse the explicit-handoff routing reason because /cook synthesized an explicit handoff'
assert routing['proposalSource'] == 'handoff_capsule', 'same-entry synthesized replacement should surface the synthesized handoff as a handoff capsule source'
assert state['mission_anchor'] == new_anchor, 'state.json mission_anchor mismatch after same-entry synthesized refocus'
assert plan['mission_anchor'] == new_anchor, 'plan.json mission_anchor mismatch after same-entry synthesized refocus'
assert active['mission_anchor'] == new_anchor, 'active-slice.json mission_anchor mismatch after same-entry synthesized refocus'
assert state['continuation_reason'].startswith('User refocused workflow via /cook:'), 'same-entry synthesized replacement should record the /cook refocus continuation reason'
PY

echo "refocus test passed: $TMPDIR"
