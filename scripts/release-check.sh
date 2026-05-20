#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, explicit-/cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook parity and explicit-entry docs/help"
python3 - <<'PY'
import re
from pathlib import Path

checks = {
    "README.md": [
        "`/cook` is the explicit workflow boundary for starting, continuing, refocusing, or beginning the next round of long-running repo work.",
        "Only explicit `/cook` enters the workflow. Ordinary prompts stay in the main chat and go straight to the primary agent.",
        "If a task has clearly matured into completion-workflow scope, the primary agent should hand you off to `/cook` instead of starting long-running implementation directly in ordinary chat.",
        "That handoff should include an explicit structured `/cook` capsule in the assistant reply so `/cook` can confirm the already-formed mission instead of re-deriving it from broad ambient context.",
        "`/cook` first looks for a fresh explicit primary-agent handoff capsule.",
        "The pre-`/cook` handoff capsule itself is not canonical workflow state. It is only startup intake for `/cook`.",
    ],
    "CHANGELOG.md": [
        "made explicit primary-agent `/cook` handoff the preferred startup-intake path by teaching ordinary-chat handoff turns to emit a structured `cook_handoff` capsule and letting `/cook` prefer that capsule over broad context re-inference when it is fresh and valid",
        "kept context-derived startup as a fallback only, so stale, drifted, or non-startable handoff capsules still fail closed or fall back to recent discussion instead of silently rewriting canonical state",
        "made finished-workflow suppression stay a safety layer instead of a replacement mission when a fresh explicit `/cook` handoff exists, and blocked negative rejection/suppression text from becoming a Startable startup mission",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"/cook is the only explicit entrypoint into long-running completion workflow."',
        '"When you judge that the task has matured into completion-workflow scope',
        '"Also append one exact fenced block in the same assistant reply using ```cook_handoff ... ``` JSON',
        '"The capsule is startup intake for /cook only: do not present it as canonical .agent state',
    ],
}

forbidden = {
    "README.md": [
        "`/cook <hint>`",
        "Natural-language routing is optional and shipped in two modes",
        "PI_COMPLETION_TRIGGER_MODE",
        "workflow-aware router",
        "Send as normal chat",
        "bash ./scripts/cook-trigger-routing-test.sh",
    ],
    "CHANGELOG.md": ["compatibility" + " shim"],
    "extensions/completion/index.ts": [
        'description: "/cook workflow: start, continue, refocus, or start the next round from an explicit /cook command"',
        '"/cook failed closed because recent discussion did not produce a clear execution-ready Mission/Scope/Constraints/Acceptance proposal for concrete repo changes. Clarify the concrete repo changes in the main chat and rerun /cook."',
        'handleCookNaturalLanguageTrigger',
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
            raise SystemExit(f"[release-check] found stale compatibility wording in {path}: {needle}")
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
npm pack --dry-run >/dev/null

echo "release check passed"
