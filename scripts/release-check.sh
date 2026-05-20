#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, mixed-model /cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook mixed-model parity across docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "`/cook` is the explicit workflow boundary for starting, continuing, refocusing, or beginning the next round of long-running repo work.",
        "Before you explicitly run `/cook`, the conversation can still stay in ordinary chat: the primary agent may keep answering follow-up questions and refining requirements rather than switching into a hard handoff-only refusal mode.",
        "If you explicitly ask for a pre-`/cook` preview or capsule, the primary agent may provide one, but that preview is opt-in only and stays non-canonical until you later run `/cook` and choose **Start**.",
        "Bare `/cook` is still the canonical workflow boundary: it synthesizes the startup brief from recent ordinary-chat discussion at `/cook` time, then waits for **Start** or **Cancel** before any canonical `.agent/**` write.",
        "- startup and next-round entry stay confirm-first: bare `/cook` synthesizes the startup brief from recent discussion, then waits for **Start** or **Cancel**",
        "- any pre-`/cook` preview or capsule is explicit-request-only and non-canonical",
        "When no workflow is active, bare `/cook` synthesizes a startup brief from recent ordinary-chat discussion and then waits for **Start** or **Cancel**.",
        "| No workflow yet | `/cook` synthesizes a startup brief from recent discussion and shows **Start** / **Cancel**.",
        "| Previous workflow is `done` | `/cook` synthesizes the next implementation round from recent discussion behind **Start** / **Cancel**.",
        "any pre-`/cook` preview or capsule is advisory only and never writes canonical workflow state by itself",
    ],
    "CHANGELOG.md": [
        "moving default startup and done-workflow next-round synthesis to bare `/cook` from recent ordinary-chat discussion behind the existing **Start** / **Cancel** approval gate",
        "kept pre-`/cook` previews or `cook_handoff` capsules opt-in only, non-canonical, and advisory until the user explicitly runs `/cook`; bare `/cook` no longer depends on a default prebuilt capsule for new-workflow startup",
        "updated public parity and packaged release verification so README/help/changelog/release-check all describe and gate the shipped mixed model truthfully",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"Distinguish a workflow-worthy handoff from an opt-in preview request: by default, do not emit a structured preview or cook_handoff capsule in ordinary chat once the task is concrete enough; recommend bare /cook instead."',
        '"When handing off, explain that bare /cook will synthesize a startup brief from recent ordinary-chat discussion for a new workflow or next round, while already-active workflows resume from canonical .agent state unless the user explicitly chooses a replacement path backed by a fresh valid explicit handoff."',
        '"If the user explicitly asks for a /cook preview or capsule before running /cook, you may append one exact fenced block in the same assistant reply using ```cook_handoff ... ``` JSON',
        '"Any preview capsule is startup intake for /cook only: do not present it as canonical .agent state, an active slice, or a persistent repo contract."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because recent discussion did not produce a clear execution-ready startup brief for bare /cook with Mission/Scope/Constraints/Acceptance for concrete repo changes. Clarify the concrete repo changes in the main chat and rerun /cook; canonical workflow state is still only written after Start."',
        'description: "/cook workflow: synthesize an approval-gated startup brief from recent discussion for new-workflow or next-round entry, resume the current workflow from canonical state, or confirm an explicit active-workflow replacement"',
    ],
}

forbidden = {
    "README.md": [
        "wait for a fresh primary-agent handoff, then run `/cook`",
        "That handoff should include an explicit structured `/cook` capsule in the assistant reply once the first slice is implementation-ready, so `/cook` can confirm the already-formed mission instead of re-deriving it from broad ambient context.",
        "- startup and next-round entry stay confirm-first and require a fresh valid explicit primary-agent handoff",
        "`/cook` first looks for a fresh explicit primary-agent handoff capsule from recent ordinary-chat discussion.",
        "Without one, `/cook` fails closed instead of deriving the next round from recent discussion.",
    ],
    "CHANGELOG.md": [
        "kept bare `/cook` startup and done-workflow next-round entry fail-closed on missing or non-startable explicit handoffs, while active workflows still resume from canonical `.agent/**` state unless a fresh explicit handoff proposes replacement",
    ],
    "extensions/completion/index.ts": [
        'description: "/cook workflow: derive a startup brief from recent discussion for new-workflow or next-round entry, resume the current workflow from canonical state, or confirm an explicit active-workflow replacement"',
        '"/cook failed closed because recent discussion did not produce a clear execution-ready startup brief with Mission/Scope/Constraints/Acceptance for concrete repo changes. Clarify the concrete repo changes in the main chat and rerun /cook."',
    ],
}

for path, needles in checks.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"[release-check] missing expected /cook mixed-model parity text in {path}: {needle}")

for path, needles in forbidden.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle in text:
            raise SystemExit(f"[release-check] found stale /cook explicit-handoff-only text in {path}: {needle}")
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
