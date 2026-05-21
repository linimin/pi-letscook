#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, explicit-/cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook parity and optional-workflow docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "You can still implement directly in ordinary chat when you do not need workflow state.",
        "Only explicit `/cook` enters workflow mode. Ordinary prompts stay in the main chat and go straight to the primary agent.",
        "Ordinary chat can still directly implement repo changes. `/cook` is for the cases where you want workflow control rather than just implementation help.",
        "- `/cook` is an optional workflow boundary and manual entry point",
        "- ordinary main-chat discussion may clarify, propose, or directly implement repo changes without entering workflow mode",
        "None of this prevents ordinary-chat implementation when you choose not to enter workflow mode.",
    ],
    "CHANGELOG.md": [
        "made ordinary chat implementation-first again so the primary agent may directly edit repo files without requiring `/cook` when workflow state is unnecessary",
        "repositioned `/cook` as optional workflow mode for confirm-first startup, resumability, review/audit flow, and canonical `.agent/**` state rather than as a mandatory implementation boundary",
        "updated ordinary-chat boundary docs, reminders, and release-parity checks so they no longer tell the agent to block repo edits pending explicit `/cook`",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"Ordinary chat may clarify requirements, discuss tradeoffs, refine scope, and directly implement requested repo changes, including multi-file work, when that is the most helpful response."',
        '"/cook is optional workflow mode for resumability, review, audit, canonical .agent state, or deliberate multi-session control; it is not required just to edit repo files in ordinary chat."',
        '"If the user wants direct implementation now, stay in ordinary chat and help directly instead of blocking on /cook."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because it could not derive a concrete startup brief from recent discussion. Clarify the mission, first slice, or verification intent in the main chat, then rerun /cook."',
        'description: "/cook workflow: optionally enter tracked workflow mode, synthesize a startup brief from explicit /cook entry, resume the current workflow from canonical state, or confirm a replacement mission"',
    ],
}

forbidden = {
    "README.md": [
        "mature long-running implementation still must not start before explicit `/cook`",
        "Ordinary chat remains advisory until you explicitly run `/cook`.",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"Before that explicit /cook entry, do not begin long-running product implementation in ordinary chat, do not edit tracked product files for that workflow-level task, and do not act as though /cook had already been invoked."',
    ],
    "skills/cook-handoff-boundary/SKILL.md": [
        "Before that explicit `/cook` entry, the primary agent must stop short of long-running implementation for workflow-level tasks.",
        "not edit tracked product files for that workflow-level task in ordinary chat",
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
