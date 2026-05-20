#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, explicit-/cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook parity and explicit-entry docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "`/cook` is the explicit workflow boundary for starting, continuing, refocusing, or beginning the next round of long-running repo work.",
        "Only explicit `/cook` enters the workflow. Ordinary prompts stay in the main chat and go straight to the primary agent.",
        "Before you explicitly run `/cook`, the conversation can still stay in ordinary chat: the primary agent may keep answering follow-up questions and refining requirements rather than switching into a hard handoff-only refusal mode.",
        "That handoff should include an explicit structured `/cook` capsule in the assistant reply once the first slice is implementation-ready, so `/cook` can confirm the already-formed mission instead of re-deriving it from broad ambient context.",
        "The capsule is still advisory startup intake, not canonical workflow state, and new-workflow or next-round entry only proceeds when it already names the first bounded slice, repo-change-oriented acceptance, implementation surfaces, and verification commands.",
        "- startup and next-round entry stay confirm-first and require a fresh valid explicit primary-agent handoff",
        "- active workflows resume from canonical `.agent/**` state unless a fresh valid explicit handoff proposes a replacement",
        "`/cook` first looks for a fresh explicit primary-agent handoff capsule from recent ordinary-chat discussion. New-workflow entry and done-workflow next-round entry start only when that capsule is fresh, valid, and implementation-startable; otherwise `/cook` fails closed instead of deriving startup from recent discussion.",
        "When a workflow is already active and no fresh valid explicit handoff is present, `/cook` resumes from canonical `.agent/**` state instead of deriving replacement startup from recent discussion.",
        "Without one, `/cook` fails closed instead of deriving the next round from recent discussion.",
        "when a fresh explicit handoff suggests replacing an active workflow, `/cook` shows a chooser before any canonical state rewrite",
    ],
    "CHANGELOG.md": [
        "relaxed the pre-`/cook` ordinary-chat boundary so the primary agent can keep discussing and refining requirements before explicit `/cook` instead of switching into a hard handoff-only refusal mode as soon as workflow-worthiness is detected",
        "made fresh explicit `/cook` handoffs reusable from recent ordinary-chat discussion instead of requiring the immediately preceding turn, so Cancel can return users cleanly to ordinary discussion before they rerun `/cook`",
        "kept bare `/cook` startup and done-workflow next-round entry fail-closed on missing or non-startable explicit handoffs, while active workflows still resume from canonical `.agent/**` state unless a fresh explicit handoff proposes replacement",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"/cook is the only explicit entrypoint into long-running completion workflow."',
        '"If the user keeps asking follow-up questions or refining requirements before /cook, continue that ordinary-chat discussion normally instead of switching into a handoff-only refusal mode, but do not act as though /cook had already been invoked."',
        '"When handing off, explain that /cook can start a new workflow or next round only from a fresh valid explicit primary-agent handoff capsule from recent ordinary-chat discussion; otherwise it fails closed, while already-active workflows resume from canonical .agent state unless a fresh valid explicit handoff proposes replacement."',
        '"The capsule is startup intake for /cook only: do not present it as canonical .agent state',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because new-workflow startup now requires a fresh valid explicit primary-agent handoff from recent ordinary-chat discussion; recent discussion alone no longer starts a workflow. Ask the primary agent to hand off explicitly in the main chat, then rerun /cook."',
        'description: "/cook workflow: start a new workflow or next round only from a fresh recent explicit primary-agent handoff, resume the current workflow from canonical state, or confirm an explicit replacement from the explicit /cook command"',
    ],
}

forbidden = {
    "README.md": [
        "Start a new workflow from recent discussion:",
        "`/cook` falls back to deriving a startup brief from recent discussion only when no fresh explicit handoff is blocking startup",
        "Without a fresh explicit handoff blocking startup, `/cook` can fall back to recent discussion.",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"When handing off, explain that /cook will first look for a fresh explicit primary-agent handoff capsule and otherwise fall back to recent discussion."',
    ],
    "extensions/completion/index.ts": [
        'description: "/cook workflow: derive a startup brief from recent discussion, then start, continue, refocus, or start the next round from the explicit /cook command"',
        '"/cook failed closed because recent discussion did not produce a clear execution-ready startup brief with Mission/Scope/Constraints/Acceptance for concrete repo changes. Clarify the concrete repo changes in the main chat and rerun /cook."',
    ],
}

for path, needles in checks.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"[release-check] missing expected /cook parity text in {path}: {needle}")

for path, needles in forbidden.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle in text:
            raise SystemExit(f"[release-check] found stale /cook parity text in {path}: {needle}")
PY

npm run smoke-test
npm run refocus-test
npm run context-proposal-test
bash ./scripts/role-runner-contract-test.sh
bash ./scripts/canonical-evidence-artifact-test.sh
bash ./scripts/active-slice-contract-test.sh
npm run observability-status-test
bash ./scripts/legacy-cleanup-test.sh
npm run evaluator-calibration-test
npm run rubric-contract-test

echo "[release-check] verifying packaged .agent contract files in npm pack output"
PACK_JSON="$(npm pack --dry-run --json)"
python3 - "$PACK_JSON" <<'PY'
import json
import sys

required = {
    '.agent/README.md',
    '.agent/mission.md',
    '.agent/profile.json',
    '.agent/verify_completion_stop.sh',
    '.agent/verify_completion_control_plane.sh',
}

payload = json.loads(sys.argv[1])
if not isinstance(payload, list) or not payload:
    raise SystemExit('[release-check] npm pack --dry-run --json returned no package payload')
files = {item.get('path') for item in payload[0].get('files', []) if isinstance(item, dict)}
missing = sorted(required - files)
if missing:
    raise SystemExit(f"[release-check] npm pack --dry-run is missing tracked .agent contract files: {', '.join(missing)}")
PY

echo "release check passed"
