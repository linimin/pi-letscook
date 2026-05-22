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

bootstrap_active_workflow() {
  local repo_root="$1"
  local session_path="$2"
  local bootstrap_discussion="$3"
  local generated_handoff="$4"

  mkdir -p "$repo_root"
  cd "$repo_root"
  git init -q
  write_session "$session_path" "$repo_root" "$bootstrap_discussion"

  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$generated_handoff" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  pi --session "$session_path" -e "$PKG_ROOT" -p "/cook" \
    >"$TMPDIR/bootstrap.out" 2>"$TMPDIR/bootstrap.err"

  for file in .agent/profile.json .agent/state.json .agent/startup-plan.json .agent/startup-plan.md .agent/plan.json .agent/active-slice.json .agent/verification-evidence.json; do
    [[ -f "$file" ]] || { echo "missing canonical bootstrap file: $file" >&2; exit 1; }
  done
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

BOOTSTRAP_DISCUSSION=$'Prepare the active workflow fixture and keep the initial mission small and truthful.'
BOOTSTRAP_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Maintain the active workflow fixture baseline.",
    "scope": [
        "Scaffold canonical completion files for the refocus regression fixture.",
        "Keep the initial workflow ready for later replacement checks."
    ],
    "constraints": [
        "Use supported bare /cook startup only."
    ],
    "acceptance": [
        "Bootstrap canonical completion state for the refocus regression fixture.",
        "Keep scripts/refocus-test.sh aligned with the shipped startup behavior."
    ],
    "risks": [],
    "notes": [
        "Bootstrap from same-entry primary-agent startup-plan synthesis."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Scaffold canonical files for the refocus regression fixture.",
    "first_slice_non_goals": [],
    "implementation_surfaces": ["scripts/refocus-test.sh"],
    "verification_commands": ["npm run refocus-test"],
    "why_this_slice_first": "Canonical state must exist before refocus can be exercised.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "The fixture startup is concrete enough to begin workflow planning."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"
REPLACEMENT_DISCUSSION=$'Switch the active workflow to the widget mission and keep the change confirm-first.'
REPLACEMENT_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    "kind": "cook_handoff",
    "source": "primary_agent",
    "mission": "Remove the completion status line while keeping the completion widget.",
    "scope": [
        "Replace the active fixture mission with the widget mission.",
        "Keep refocus approval-only before canonical rewrite."
    ],
    "constraints": [
        "Do not bypass the Start/Cancel gate."
    ],
    "acceptance": [
        "Rewrite canonical workflow state only after the replacement mission is approved.",
        "Keep refocus regression coverage aligned with same-entry synthesis behavior."
    ],
    "risks": [
        "Do not leave the old mission partially active after refocus."
    ],
    "notes": [
        "This replacement must come from same-entry primary-agent startup-plan synthesis."
    ],
    "handoff_kind": "implementation_workflow_handoff",
    "first_slice_goal": "Rewrite canonical workflow state for the widget mission.",
    "first_slice_non_goals": ["Do not start implementation before the refocus is approved."],
    "implementation_surfaces": ["scripts/refocus-test.sh", ".agent/startup-plan.json"],
    "verification_commands": ["npm run refocus-test"],
    "why_this_slice_first": "The active workflow must be re-anchored before later role dispatch.",
    "task_type": "completion-workflow",
    "evaluation_profile": "completion-rubric-v1",
    "why_cook_now": "A different workflow mission is now concrete enough to replace the active one."
}
print("```cook_handoff\n" + json.dumps(capsule, ensure_ascii=False, indent=2) + "\n```")
PY
)"

# Case 1: chooser cancel leaves canonical state untouched while still surfacing synthesized replacement routing.
ROOT_ONE="$TMPDIR/repo-one"
SESSION_ONE_BOOTSTRAP="$TMPDIR/session-one-bootstrap.jsonl"
SESSION_ONE_REFOCUS="$TMPDIR/session-one-refocus.jsonl"
ROUTING_ONE="$TMPDIR/routing-one.json"
CHOOSER_ONE="$TMPDIR/chooser-one.json"
PROPOSAL_ONE="$TMPDIR/proposal-one.json"
BASELINE_ONE="$TMPDIR/baseline-one.json"
bootstrap_active_workflow "$ROOT_ONE" "$SESSION_ONE_BOOTSTRAP" "$BOOTSTRAP_DISCUSSION" "$BOOTSTRAP_HANDOFF"
cd "$ROOT_ONE"
snapshot_tracked "$BASELINE_ONE"
write_session "$SESSION_ONE_REFOCUS" "$ROOT_ONE" "$REPLACEMENT_DISCUSSION"

PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$REPLACEMENT_HANDOFF" \
PI_COMPLETION_EXISTING_WORKFLOW_ACTION=cancel \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ROUTING_ONE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CHOOSER_ONE" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_ONE" \
pi --session "$SESSION_ONE_REFOCUS" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/refocus-one.out" 2>"$TMPDIR/refocus-one.err"

python3 - "$ROUTING_ONE" "$CHOOSER_ONE" "$PROPOSAL_ONE" "$BASELINE_ONE" "$TMPDIR/refocus-one.out" "$TMPDIR/refocus-one.err" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
chooser = json.loads(Path(sys.argv[2]).read_text())
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

assert routing['action'] == 'refocus', routing
assert routing['reason'] == 'generated_replacement_startup_plan', routing
assert routing['proposedMissionAnchor'] == 'Remove the completion status line while keeping the completion widget.', routing
assert chooser['choices'][1].startswith('Start new workflow from same-entry primary-agent startup plan'), chooser
assert not proposal.exists(), 'chooser cancel should not open the final Start/Cancel proposal snapshot'
assert before == after, 'chooser cancel should leave canonical workflow files unchanged'
assert 'Cancelled existing workflow confirmation.' in output, output
PY

# Case 2: final Start/Cancel cancel still leaves canonical state untouched after chooser acceptance.
ROOT_TWO="$TMPDIR/repo-two"
SESSION_TWO_BOOTSTRAP="$TMPDIR/session-two-bootstrap.jsonl"
SESSION_TWO_REFOCUS="$TMPDIR/session-two-refocus.jsonl"
ROUTING_TWO="$TMPDIR/routing-two.json"
CHOOSER_TWO="$TMPDIR/chooser-two.json"
PROPOSAL_TWO="$TMPDIR/proposal-two.json"
BASELINE_TWO="$TMPDIR/baseline-two.json"
bootstrap_active_workflow "$ROOT_TWO" "$SESSION_TWO_BOOTSTRAP" "$BOOTSTRAP_DISCUSSION" "$BOOTSTRAP_HANDOFF"
cd "$ROOT_TWO"
snapshot_tracked "$BASELINE_TWO"
write_session "$SESSION_TWO_REFOCUS" "$ROOT_TWO" "$REPLACEMENT_DISCUSSION"

PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$REPLACEMENT_HANDOFF" \
PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=cancel \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ROUTING_TWO" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CHOOSER_TWO" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_TWO" \
pi --session "$SESSION_TWO_REFOCUS" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/refocus-two.out" 2>"$TMPDIR/refocus-two.err"

python3 - "$ROUTING_TWO" "$CHOOSER_TWO" "$PROPOSAL_TWO" "$BASELINE_TWO" "$TMPDIR/refocus-two.out" "$TMPDIR/refocus-two.err" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
chooser = json.loads(Path(sys.argv[2]).read_text())
proposal = json.loads(Path(sys.argv[3]).read_text())
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

assert routing['action'] == 'refocus', routing
assert routing['reason'] == 'generated_replacement_startup_plan', routing
assert chooser['choices'][1].startswith('Start new workflow from same-entry primary-agent startup plan'), chooser
assert proposal['source'] == 'deferred_primary_agent_handoff', proposal
assert proposal['mission'] == 'Remove the completion status line while keeping the completion widget.', proposal
assert before == after, 'final Start/Cancel cancel should leave canonical workflow files unchanged'
assert 'Cancelled replacement workflow proposal.' in output, output
PY

# Case 3: accepting the synthesized replacement rewrites canonical mission and startup plan.
ROOT_THREE="$TMPDIR/repo-three"
SESSION_THREE_BOOTSTRAP="$TMPDIR/session-three-bootstrap.jsonl"
SESSION_THREE_REFOCUS="$TMPDIR/session-three-refocus.jsonl"
ROUTING_THREE="$TMPDIR/routing-three.json"
CHOOSER_THREE="$TMPDIR/chooser-three.json"
PROPOSAL_THREE="$TMPDIR/proposal-three.json"
bootstrap_active_workflow "$ROOT_THREE" "$SESSION_THREE_BOOTSTRAP" "$BOOTSTRAP_DISCUSSION" "$BOOTSTRAP_HANDOFF"
cd "$ROOT_THREE"
write_session "$SESSION_THREE_REFOCUS" "$ROOT_THREE" "$REPLACEMENT_DISCUSSION"

PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$REPLACEMENT_HANDOFF" \
PI_COMPLETION_EXISTING_WORKFLOW_ACTION=refocus \
PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
PI_COMPLETION_TEST_ACTIVE_WORKFLOW_ROUTING_PATH="$ROUTING_THREE" \
PI_COMPLETION_TEST_EXISTING_WORKFLOW_CHOOSER_PATH="$CHOOSER_THREE" \
PI_COMPLETION_TEST_CONTEXT_PROPOSAL_PATH="$PROPOSAL_THREE" \
pi --session "$SESSION_THREE_REFOCUS" -e "$PKG_ROOT" -p "/cook" \
  >"$TMPDIR/refocus-three.out" 2>"$TMPDIR/refocus-three.err"

python3 - "$ROUTING_THREE" "$CHOOSER_THREE" "$PROPOSAL_THREE" "$TMPDIR/refocus-three.out" "$TMPDIR/refocus-three.err" <<'PY'
import json
import sys
from pathlib import Path

routing = json.loads(Path(sys.argv[1]).read_text())
chooser = json.loads(Path(sys.argv[2]).read_text())
proposal = json.loads(Path(sys.argv[3]).read_text())
output = Path(sys.argv[4]).read_text() + Path(sys.argv[5]).read_text()
state = json.loads(Path('.agent/state.json').read_text())
startup_plan = json.loads(Path('.agent/startup-plan.json').read_text())
startup_plan_md = Path('.agent/startup-plan.md').read_text()
plan = json.loads(Path('.agent/plan.json').read_text())
active = json.loads(Path('.agent/active-slice.json').read_text())

mission = 'Remove the completion status line while keeping the completion widget.'
assert routing['action'] == 'refocus', routing
assert routing['reason'] == 'generated_replacement_startup_plan', routing
assert chooser['choices'][1].startswith('Start new workflow from same-entry primary-agent startup plan'), chooser
assert proposal['source'] == 'deferred_primary_agent_handoff', proposal
assert state['mission_anchor'] == mission, state
assert state['current_phase'] == 'reground', state
assert state['next_mandatory_role'] == 'completion-regrounder', state
assert startup_plan['mission_anchor'] == mission, startup_plan
assert startup_plan['source'] == 'deferred_primary_agent_handoff', startup_plan
assert '## Goal' in startup_plan_md and mission in startup_plan_md, startup_plan_md
assert plan['mission_anchor'] == mission, plan
assert active['mission_anchor'] == mission, active
assert 'Refocused completion mission from same-entry primary-agent startup plan' in output, output
PY

echo "refocus test passed: $PKG_ROOT"
