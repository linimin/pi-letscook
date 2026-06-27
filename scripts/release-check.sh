#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
AGENT_PRESENT_BEFORE=0
if [[ -e .agent ]]; then
  AGENT_PRESENT_BEFORE=1
fi
cleanup_release_check_agent_dir() {
  if [[ "$AGENT_PRESENT_BEFORE" -eq 0 && -d .agent && ! -e .agent/current ]]; then
    rm -rf .agent
  fi
}
trap cleanup_release_check_agent_dir EXIT
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1

echo "[release-check] running control-plane validation, helper runtime capability probe, packaged helper smoke, helper authority-boundary, artifact-layout, runtime-contract, role-gating, structured-output, observability regressions, local .agent runtime parity, package-owned verifier entrypoint parity, role/protocol path parity, slice-surface parity, explicit-/cook parity, startup/refocus/context/worktree-root regressions, prompt-budget coverage, agent_end auto-resume delivery coverage, canonical evidence artifact, active-slice contract, observability, completion-role gating, dirty-worktree policy, stop-wave epoch, legacy cleanup, evaluator calibration, structured-report repair coverage, and rubric contract coverage"
npm run verify-completion-control-plane
bash ./scripts/helper-runtime-capability-test.sh
PI_HELPER_PACKAGING_SKIP_RUNTIME=1 bash ./scripts/helper-packaging-smoke-test.sh
bash ./scripts/helper-authority-boundary-test.sh
bash ./scripts/helper-artifact-layout-test.sh
bash ./scripts/helper-runtime-contract-test.sh
bash ./scripts/helper-role-gating-test.sh
bash ./scripts/helper-structured-output-test.sh
bash ./scripts/helper-observability-test.sh

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
        "When you explicitly run `/cook`, it calls a same-entry primary-agent handoff synthesis step from the current task context or inline `/cook` prompt, then asks you to **Start** or **Cancel** before rewriting canonical workflow state.",
        "If no primary-agent-generated handoff is startable, `/cook` fails closed before showing **Start** or **Cancel**.",
        "Preview `/cook` capsules in ordinary chat may still help the conversation, but `/cook` does not consume them directly. It always synthesizes the startup handoff for the current workflow entry and fails closed when synthesis cannot produce a startable brief.",
        "`/cook <prompt>` lets you provide explicit startup intent inline without bypassing synthesis or confirmation",
        "startup and next-round entry stay confirm-first, following same-entry primary-agent handoff synthesis -> fail closed",
        "stopped workflows now have explicit same-session controls: rerun `/cook` or `/cook resume` to continue, `/cook park` to park for ordinary direct edits with `requires_reground = true`, and `/cook cancel` to close the workflow",
        "When a workflow reaches a closed `done` or `cancelled` posture, extension cleanup may remove the entire `.agent/` directory as expected closeout behavior.",
        "`task_type` and `evaluation_profile` only come from explicit structured startup artifacts when those fields are present; otherwise `/cook` keeps the packaged `completion-workflow` / `completion-rubric-v1` defaults instead of inferring them from free-text discussion",
        "`recommended_first_slice_kind`",
        "`verifier_scaffolding` first slice",
    ],
    "CHANGELOG.md": [
        "added explicit stopped-workflow `/cook resume`, `/cook park`, and `/cook cancel` controls so blocked, await-user-input, and paused workflows no longer strand the primary agent in a same-repo dead zone",
        "preserved the confirmed `/cook` startup intent in canonical `.agent/current/startup-brief.json` so workflow entry is durable before regrounding authors canonical slices",
        "moved workflow-session legitimacy away from in-memory routing activation and legacy `/skill:completion-protocol` prompt dependence toward canonical workflow-session state plus explicit `/cook` entry turns",
        "removed the remaining main-path `/cook` free-text `task_type` / `evaluation_profile` inference so startup and refocus now keep the packaged `completion-workflow` / `completion-rubric-v1` defaults unless an explicit structured artifact supplies routing fields",
        "removed fresh explicit `cook_handoff` capsule precedence from `/cook` startup so every workflow entry now synthesizes a fresh primary-agent handoff from current context or inline prompt instead of directly consuming earlier preview capsules",
        "aligned `/cook` startup docs/help plus smoke/release parity checks with the shipped same-entry handoff-synthesis -> fail-closed contract so public contract text matches startup behavior",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly runs /cook, the extension should call a primary-agent handoff synthesis step from the current task context or inline /cook prompt, show Start/Cancel confirmation, and persist the confirmed startup brief into .agent/** without making the user rerun /cook."',
        '"If no primary-agent-generated handoff is startable, /cook must fail closed and leave canonical workflow state unchanged."',
        '"In ordinary chat, do not load or follow completion-protocol, and do not call completion_role."',
        '"Supported same-repo controls are: rerun /cook or /cook resume to continue from canonical state; run /cook park to record a parked paused posture that unlocks ordinary direct edits and forces canonical reground before workflow continuation; run /cook cancel to close the workflow and disable stale hard locks or auto-resume."',
        '"Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook."',
    ],
    "scripts/role-runner-contract-test.sh": [
        "Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise.",
        "Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.",
        "assertNotIncludes('extensions/completion/role-runner.ts', 'Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise, task_type, evaluation_profile.');",
    ],
    "scripts/context-proposal-test.sh": [
        "# No workflow yet: planning-only structured startup text must still fail closed instead of becoming workflow intent.",
        "planning-only structured startup text should fail closed without writing canonical state",
        "low-confidence startup analysis should fail closed without writing canonical state",
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because the primary-agent startup step could not prepare a workflow startup brief from the current task context. Clarify the mission, repo-change intent, or key constraints in the main chat, then rerun /cook."',
        'description: "/cook workflow: start or replace workflow by asking the primary agent to synthesize a startup handoff from the current task context or inline prompt (fail closed when no startable handoff is produced); resume the current workflow from canonical state, or use /cook resume|park|cancel for explicit stopped-workflow controls"',
        '"Do not call completion_role from ordinary chat; it is reserved for active /cook workflow sessions."',
        '`COMPLETION WORKFLOW DRIVER\\nStart or continue the completion workflow for this repo.',
        'function isLikelyWorkflowContinuationTurn(',
        'if (isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx)) return true;',
        'function shouldInjectStoppedWorkflowBoundary(',
        'If local .agent helper forwarders or canonical execution-state scaffolding are missing and truthful onboarding or repair is required',
        'If canonical closeout cleanup removes repo-local .agent/ after the workflow reaches done or cancelled',
        'WORKFLOW DRIVER NOTE: Canonical workflow state closed and the extension removed repo-local .agent/ as expected cleanup.',
    ],
    "extensions/completion/policy-guards.ts": [
        'return "completion_role may only be used from an active /cook workflow session.";',
    ],
    "skills/cook-handoff-boundary/SKILL.md": [
        '- load or follow `completion-protocol` while still in ordinary chat',
        '- call `completion_role` before the user has explicitly entered `/cook`',
        'if no primary-agent-generated handoff is startable, fail closed without rewriting canonical workflow state',
        '`/cook` must fail closed when primary-agent synthesis cannot produce a startable handoff',
    ],
    "skills/completion-protocol/SKILL.md": [
        'Load this skill only after the user explicitly enters `/cook` and you are operating inside the `completion` workflow as the workflow driver or a completion role.',
        'Do not load or follow this skill from ordinary chat.',
        'When canonical state is stopped (`await_user_input`, `blocked`, or `paused`), rerun `/cook` or `/cook resume` to continue from canonical state, use `/cook park` to record a parked paused posture with `requires_reground = true` and a cleared active-slice handoff before ordinary direct edits, or use `/cook cancel` to close the workflow and disable stale hard locks / auto-resume.',
        'After canonical state reaches a closed `done` or `cancelled` posture, the extension may delete repo-local `.agent/` before control returns.',
        'These helper files are generated local convenience entrypoints, not tracked repo-contract files.',
        'Use `completion-bootstrapper` only for first-time setup or missing local helper / canonical-state repair.',
        '`recommended_first_slice_kind`',
        '`verifier_scaffolding` first slice',
    ],
    "skills/completion-protocol/references/completion.md": [
        'When canonical state is stopped (`await_user_input`, `blocked`, or `paused`), rerun `/cook` or `/cook resume` to continue from canonical state, use `/cook park` to record a parked paused posture with `requires_reground = true` and a cleared active-slice handoff before ordinary direct edits, or use `/cook cancel` to close the workflow and disable stale hard locks / auto-resume.',
        'After a workflow reaches a closed `done` or `cancelled` posture, extension cleanup may remove the entire `.agent/` directory before control returns.',
        'These helper files are generated local convenience entrypoints, not tracked repo-contract files.',
        '`completion-bootstrapper` is used only for first-time setup or missing local helper / canonical-state repair.',
        '`recommended_first_slice_kind`',
        '`verifier_scaffolding` first slice',
    ],
    "agents/completion-bootstrapper.md": [
        'description: Bootstrap or repair local completion helper files and canonical execution state, then hand off to completion-regrounder.',
        '- `Local helper files repaired: ...`',
    ],
    "agents/completion-regrounder.md": [
        'prefer a `verifier_scaffolding` first slice',
    ],
    "agents/completion-implementer.md": [
        'refresh local repo-level verifier forwarders such as `.agent/verify_completion_stop.sh`',
        'refresh the local `.agent/verify_completion_stop.sh` forwarder so it remains a truthful repo-level baseline verifier.',
        'verifier_scaffolding',
    ],
}

forbidden = {
    "README.md": [
        "asks the primary agent to prepare one in the main chat and leaves canonical state unchanged until you rerun /cook",
        "Explicit `/cook` capsules are the required startup intake for new-workflow, next-round, and replacement entry.",
        "If the primary-agent handoff step still cannot prepare a concrete workflow startup brief, `/cook` fails closed, leaves canonical `.agent/**` state unchanged, and tells you to refine the mission, repo-change intent, or key constraints in the main chat before rerunning `/cook`.",
        "startup and next-round entry stay confirm-first, using explicit primary-agent handoff data when present and otherwise running the primary-agent handoff synthesis step in the same `/cook` entry",
    ],
    "extensions/completion/prompt-surfaces.ts": [
        '"If the user explicitly asks to enter /cook workflow, generate one fresh ```cook_handoff``` capsule in ordinary chat from the primary-agent view of the task, then tell the user to run /cook."',
    ],
    "extensions/completion/index.ts": [
        '"/cook failed closed because starting workflow now requires a fresh explicit primary-agent handoff. Ask the primary agent in the main chat to emit a fresh ```cook_handoff``` capsule, then rerun /cook."',
        'If tracked completion contract files are missing or onboarding is required',
    ],
    "skills/cook-handoff-boundary/SKILL.md": [],
    "skills/completion-protocol/SKILL.md": [
        'Use `completion-bootstrapper` only for first-time setup or missing tracked contract-file repair.',
        'If tracked protocol contract files are missing or first-time onboarding is required, invoke `completion-bootstrapper`.',
    ],
    "skills/completion-protocol/references/completion.md": [
        '`completion-bootstrapper` is used only for first-time setup or missing tracked contract-file repair.',
        'If tracked protocol contract files are missing or first-time onboarding is required, invoke `completion-bootstrapper`.',
    ],
    "agents/completion-bootstrapper.md": [
        'description: Bootstrap or repair tracked completion control-plane files, then hand off to completion-regrounder.',
        '- `Tracked contract files repaired: ...`',
    ],
    "agents/completion-implementer.md": [
        'refresh tracked repo-contract verifier files such as `.agent/verify_completion_stop.sh`',
    ],
    "extensions/completion/proposal.ts": [
        'function inferContextProposalTaskType(',
        'function inferContextProposalEvaluationProfile(',
        'with tests and docs parity',
        'with docs parity',
    ],
    "extensions/completion/startup-intent.ts": [
        'missionAnchorsLikelyEquivalent',
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
npm run agent-end-auto-resume-test
npm run refocus-test
npm run context-proposal-test
npm run prompt-budget-test
npm run worktree-root-boundary-test
bash ./scripts/role-runner-contract-test.sh
if [[ "${PI_COMPLETION_SKIP_CANONICAL_EVIDENCE_ARTIFACT_TEST:-}" != "1" ]]; then
  bash ./scripts/canonical-evidence-artifact-test.sh
fi
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
    'extensions/helper-tools/index.ts',
    'helpers/scout.md',
    'helpers/critic.md',
    'scripts/helper-runtime-capability-test.sh',
    'scripts/helper-packaging-smoke-test.sh',
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
