#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash ./scripts/ensure-local-completion-forwarders.sh
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, local .agent runtime parity, package-owned verifier entrypoint parity, role/protocol path parity, slice-surface parity, explicit-/cook parity, startup/refocus/context regressions, canonical evidence artifact, active-slice contract, observability, completion-role gating, dirty-worktree policy, stop-wave epoch, legacy cleanup, evaluator calibration, structured-report repair coverage, and rubric contract coverage"
npm run verify-completion-control-plane

python3 - <<'PY'
from pathlib import Path

checks = {
    'README.md': [
        'The canonical storage contract is package-owned defaults plus ignored `.agent/**` runtime state.',
        'thin `.agent/verify_completion_*.sh` forwarders',
        'npm run verify-completion-control-plane',
        'npm run verify-completion-stop',
    ],
    '.gitignore': [
        '# completion workflow local state',
        '.agent/',
    ],
    'scripts/verify-completion-control-plane.js': [
        'const REQUIRED_TRACKED_CONTRACT_FILES = [',
        'subject_type must be selected_slice when active slice exact handoff requires verification evidence',
    ],
    'scripts/verify-completion-stop.sh': [
        'stop_aggregation_policy must be unanimous-current-head-v1',
        'Current HEAD has a can_stop=no judgment',
        'valid current-HEAD judgments',
        'COMPLETION_REPO_VERIFY_COMMAND',
    ],
}

for path, needles in checks.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'[release-check] missing expected verifier-parity text in {path}: {needle}')
PY

echo "[release-check] verifying public /cook parity and primary-agent-handoff docs/help"
python3 - <<'PY'
from pathlib import Path

checks = {
    "README.md": [
        "You can still implement directly in ordinary chat when you do not need workflow state.",
        "When you explicitly run `/cook`, it first checks for a fresh explicit primary-agent handoff.",
        "If one is missing, it calls a same-entry primary-agent handoff synthesis step from the current task context or inline `/cook` prompt, then asks you to **Start** or **Cancel** before rewriting canonical workflow state.",
        "Explicit `/cook` capsules are still valid startup intake, but they are no longer the only path because `/cook` can synthesize the primary-agent handoff in the same entry when needed.",
        "`/cook <prompt>` lets you provide explicit startup intent inline without bypassing synthesis or confirmation",
    ],
    "CHANGELOG.md": [
        "preserved the confirmed `/cook` startup intent in canonical `.agent/current/startup-brief.json` so workflow entry is durable before regrounding authors canonical slices",
        "moved workflow-session legitimacy away from in-memory routing activation and legacy `/skill:completion-protocol` prompt dependence toward canonical workflow-session state plus explicit `/cook` entry turns",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly runs /cook, the extension should call a primary-agent handoff synthesis step from the current task context, show Start/Cancel confirmation, and persist the confirmed startup brief into .agent/** without making the user rerun /cook."',
        '"Do not expect /cook to infer or guess startup intent from recent discussion alone; /cook should use explicit primary-agent handoff data, whether it already exists or is synthesized in the same /cook entry."',
        '"In ordinary chat, do not load or follow completion-protocol, and do not call completion_role."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because the primary-agent handoff step could not prepare a concrete startup handoff from the current task context. Clarify the mission, first slice, or verification intent in the main chat, then rerun /cook."',
        'description: "/cook workflow: start or replace workflow from a primary-agent startup brief (optionally seeded by an inline prompt), or resume the current workflow from canonical state"',
        '"Do not call completion_role from ordinary chat; it is reserved for active /cook workflow sessions."',
        '`COMPLETION WORKFLOW DRIVER\\nStart or continue the completion workflow for this repo.',
        'function isLikelyWorkflowContinuationTurn(',
        'return isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx) || isLikelyWorkflowContinuationTurn(snapshot, ctx);',
    ],
    "extensions/completion/policy-guards.ts": [
        'return "completion_role may only be used from an active /cook workflow session.";',
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
npm run completion-role-gating-test
npm run dirty-worktree-policy-test
npm run stop-wave-epoch-test
bash ./scripts/legacy-cleanup-test.sh
npm run evaluator-calibration-test
npm run report-repair-test
npm run rubric-contract-test

echo "[release-check] verifying packaged workflow assets in npm pack output"
PACK_JSON="$(npm pack --dry-run --json)"
python3 - "$PACK_JSON" <<'PY'
import json
import sys

required = {
    'scripts/verify-completion-control-plane.js',
    'scripts/verify-completion-stop.sh',
}

forbidden = {
    '.cook/README.md',
    '.cook/workflow.json',
    '.cook/profile.json',
    '.agent/verify_completion_stop.sh',
    '.agent/verify_completion_control_plane.sh',
}

payload = json.loads(sys.argv[1])
if not isinstance(payload, list) or not payload:
    raise SystemExit('[release-check] npm pack --dry-run --json returned no package payload')
files = {item.get('path') for item in payload[0].get('files', []) if isinstance(item, dict)}
missing = sorted(required - files)
if missing:
    raise SystemExit(f"[release-check] npm pack --dry-run is missing required verifier/config package files: {', '.join(missing)}")
extra_forbidden = sorted(forbidden & files)
if extra_forbidden:
    raise SystemExit(f"[release-check] npm pack --dry-run must not publish repo-local verifier forwarders: {', '.join(extra_forbidden)}")
PY

echo "release check passed"
