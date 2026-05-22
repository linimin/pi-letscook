#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, tracked .agent contract coverage, slice-surface parity, /cook startup-plan parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, legacy cleanup, evaluator calibration, and rubric contract coverage"
bash .agent/verify_completion_control_plane.sh
git ls-files --error-unmatch .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_stop.sh .agent/verify_completion_control_plane.sh >/dev/null

echo "[release-check] verifying public /cook parity and startup-plan docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "You can still implement directly in ordinary chat when you do not need workflow state.",
        "When you explicitly run `/cook`, it first checks for a fresh explicit primary-agent startup-plan preview.",
        "After **Start**, the approved startup plan is written into `.agent/startup-plan.json` / `.agent/startup-plan.md`, and `completion-regrounder` uses it to derive canonical slices from current repo truth.",
        "Explicit `/cook` capsules are still valid startup intake, but they are no longer the only path because `/cook` can synthesize the primary-agent startup plan in the same entry when needed.",
    ],
    "CHANGELOG.md": [
        "rewrote `/cook` startup around an approved startup plan that is captured under `.agent/startup-plan.json` / `.agent/startup-plan.md` after Start instead of leaving startup intent only as advisory intake in `state.json`",
        "kept `/cook` confirm-first while handing the approved startup plan to `completion-regrounder`, which now derives canonical slices from repo truth instead of treating startup intake like an implementation-ready first-slice contract",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly runs /cook, the extension should call a primary-agent startup-plan synthesis step from the current task context, show Start/Cancel confirmation in the same /cook entry, and only write the approved plan into .agent after Start."',
        '"When /cook starts, the approved startup plan should be written into .agent and then handed to completion-regrounder so canonical slices can be derived from repo truth."',
        '"In ordinary chat, do not load or follow completion-protocol, and do not call completion_role."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because the startup-plan step could not prepare a concrete workflow startup plan from the current task context. Clarify the mission, scope, acceptance, or verification intent in the main chat, then rerun /cook."',
        'description: "/cook workflow: capture the approved startup plan into .agent, let completion-regrounder split canonical slices, or resume the current workflow from canonical state"',
        '"Do not call completion_role from ordinary chat; it is reserved for explicit /cook workflow driver turns."',
    ],
    "extensions/completion/policy-guards.ts": [
        'return "completion_role may only be used from an explicit /cook workflow driver turn.";',
    ],
    "skills/cook-handoff-boundary/SKILL.md": [
        '- load or follow `completion-protocol` while still in ordinary chat',
        '- call `completion_role` before the user has explicitly entered `/cook`',
    ],
    "skills/completion-protocol/SKILL.md": [
        'Load this skill only after the user explicitly enters `/cook` and you are operating inside the `completion` workflow as the workflow driver or a completion role.',
        'Do not load or follow this skill from ordinary chat.',
    ],
}

forbidden = {
    "README.md": [
        "asks the primary agent to prepare one in the main chat and leaves canonical state unchanged until you rerun /cook",
        "Explicit `/cook` capsules are the required startup intake for new-workflow, next-round, and replacement entry.",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly asks to enter /cook workflow, generate one fresh ```cook_handoff``` capsule in ordinary chat from the primary-agent view of the task, then tell the user to run /cook."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because starting workflow now requires a fresh explicit primary-agent handoff. Ask the primary agent in the main chat to emit a fresh ```cook_handoff``` capsule, then rerun /cook."',
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
