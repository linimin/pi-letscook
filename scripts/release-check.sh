#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, explicit-/cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook parity and explicit-handoff docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "You can still implement directly in ordinary chat when you do not need workflow state.",
        "When you explicitly run `/cook`, it should consume the explicit primary-agent handoff you already prepared in ordinary chat, then ask you to **Start** or **Cancel** before rewriting canonical workflow state.",
        "Explicit `/cook` capsules are the required startup intake for new-workflow, next-round, and replacement entry.",
        "`/cook` first checks for a fresh explicit primary-agent handoff capsule.",
        "New-workflow entry, done-workflow next-round entry, and active-workflow replacement should use that handoff instead of guessing from recent discussion.",
    ],
    "CHANGELOG.md": [
        "made `/cook` stop inferring startup handoffs from recent discussion so workflow startup and replacement now require fresh explicit primary-agent `cook_handoff` data",
        "clarified that when a user explicitly chooses `/cook`, the primary agent must author the handoff in ordinary chat and `/cook` must consume that handoff instead of guessing",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly asks to enter /cook workflow, generate one fresh ```cook_handoff``` capsule in ordinary chat from the primary-agent view of the task, then tell the user to run /cook."',
        '"Do not expect /cook to infer or guess startup intent from recent discussion alone; /cook should consume the explicit primary-agent handoff instead."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because starting workflow now requires a fresh explicit primary-agent handoff. Ask the primary agent in the main chat to emit a fresh ```cook_handoff``` capsule, then rerun /cook."',
        'description: "/cook workflow: start or replace workflow only from an explicit primary-agent handoff, or resume the current workflow from canonical state"',
    ],
}

forbidden = {
    "README.md": [
        "synthesizes a startup brief from recent discussion using primary-agent-style context",
        "derive startup from explicit user `/cook` entry plus recent discussion when needed",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly runs /cook, /cook will synthesize a startup brief from recent discussion using primary-agent-style context, then show Start/Cancel confirmation before canonical workflow state is rewritten."',
    ],
    "extensions/completion/index.ts": [
        'description: "/cook workflow: optionally enter tracked workflow mode, synthesize a startup brief from explicit /cook entry, resume the current workflow from canonical state, or confirm a replacement mission"',
        '"/cook failed closed because it could not derive a concrete startup brief from recent discussion. Clarify the mission, first slice, or verification intent in the main chat, then rerun /cook."',
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
