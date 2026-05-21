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
        "Ordinary chat remains advisory until you explicitly run `/cook`. At that point `/cook` synthesizes a startup brief from recent discussion using primary-agent-style context, then asks you to **Start** or **Cancel** before rewriting canonical workflow state.",
        "- startup and next-round entry stay confirm-first, but they now derive startup from explicit user `/cook` entry plus recent discussion when needed",
        "- active workflows resume from canonical `.agent/**` state unless `/cook` synthesizes or receives a concrete replacement mission",
        "`/cook` first checks for a fresh explicit primary-agent handoff capsule as a compatibility intake path. If none is present, `/cook` synthesizes a startup brief from recent discussion using primary-agent-style context.",
        "when a concrete replacement mission suggests replacing an active workflow, `/cook` shows a chooser before any canonical state rewrite",
    ],
    "CHANGELOG.md": [
        "removed proactive primary-agent `/cook` prompting and default ordinary-chat `cook_handoff` emission so main chat stays advisory until the user explicitly runs `/cook`",
        "changed bare `/cook` startup and done-workflow next-round entry to synthesize a deferred primary-agent startup brief from recent discussion instead of requiring a pre-authored explicit handoff capsule",
        "updated public parity and shipped package contents so the tracked `.agent` contract files are included in package tarballs and packaged smoke/release verification can scaffold canonical state truthfully",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"/cook is the only explicit entrypoint into long-running completion workflow."',
        '"Do not proactively tell the user to run /cook just because a task looks workflow-worthy, and do not emit a ```cook_handoff``` capsule by default in ordinary chat."',
        '"Only provide a preview startup brief or ```cook_handoff``` capsule in ordinary chat when the user explicitly asks for that preview behavior."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because it could not derive a concrete startup brief from recent discussion. Clarify the mission, first slice, or verification intent in the main chat, then rerun /cook."',
        'description: "/cook workflow: synthesize a startup brief when the user explicitly enters /cook, resume the current workflow from canonical state, or confirm a replacement mission from explicit /cook entry"',
    ],
}

forbidden = {
    "README.md": [
        "wait for a fresh primary-agent handoff",
        "require a fresh valid explicit primary-agent handoff",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"When handing off, explain that /cook can start a new workflow or next round only from a fresh valid explicit primary-agent handoff capsule; otherwise it fails closed, while already-active workflows resume from canonical .agent state unless a fresh valid explicit handoff proposes replacement."',
    ],
    "extensions/completion/index.ts": [
        'description: "/cook workflow: start a new workflow or next round only from a fresh explicit primary-agent handoff, resume the current workflow from canonical state, or confirm an explicit replacement from the explicit /cook command"',
        '"/cook failed closed because new-workflow startup now requires a fresh valid explicit primary-agent handoff from the immediately preceding ordinary-chat turn; recent discussion alone no longer starts a workflow. Ask the primary agent to hand off explicitly in the main chat, then rerun /cook."',
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
