#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required role-runner extraction text: ${snippet}`);
  }
};
const assertNotIncludes = (file, snippet) => {
  const text = read(file);
  if (text.includes(snippet)) {
    throw new Error(`${file} still contains stale inline role-runner text: ${snippet}`);
  }
};

assertIncludes('extensions/completion/role-runner.ts', 'import { completionRootKey, findCompletionRoot, findRepoRoot } from "./state-store";');
assertIncludes('extensions/completion/role-runner.ts', 'import { buildRoleReportRepairPrompt, parseReportFields, transcribeRoleOutput, type TranscriptionResult } from "./transcription";');
assertIncludes('extensions/completion/role-runner.ts', 'import {\n\tbuildStartupAnalysisPromptFromEntries,\n\tparseStartupAnalysisFromSubprocess,\n\tparseStartupAnalysisOutput,\n} from "./startup-analysis";');
assertIncludes('extensions/completion/role-runner.ts', 'const agent = await loadAgentDefinition(params.root, params.role);');
assertIncludes('extensions/completion/role-runner.ts', 'const systemPromptTemp = await writeTempFile(params.root, "pi-completion-role-", agent.systemPrompt);');
assertIncludes('extensions/completion/role-runner.ts', 'resolveRoleSubprocessOutput({');
assertIncludes('extensions/completion/role-runner.ts', 'parseReportFields(output)');
assertIncludes('extensions/completion/role-runner.ts', 'structuredEvaluatorReport: resolved.structuredEvaluatorReport');
assertIncludes('extensions/completion/role-runner.ts', 'await transcribeRoleOutput(params.role, params.root, output, reportFields, {');
assertIncludes('extensions/completion/role-runner.ts', 'Structured report repair mode:');
assertIncludes('extensions/completion/role-runner.ts', 'Retrying ${params.role} once to repair structured report consistency.');
assertIncludes('extensions/completion/helper-policy.ts', 'export function effectiveRoleToolAllowlist(');
assertIncludes('extensions/completion/helper-policy.ts', 'export function resolveEffectiveCompletionRoleModel(');
assertIncludes('extensions/completion/helper-policy.ts', 'export function buildCompletionRoleSubprocessEnv(');
assertIncludes('extensions/completion/role-runner.ts', 'const roleModel = resolveEffectiveCompletionRoleModel(agent.model, params.requestedModel);');
assertIncludes('extensions/completion/role-runner.ts', 'const effectiveToolAllowlist = effectiveRoleToolAllowlistWithStructured(params.role, agent.tools);');
assertIncludes('extensions/completion/role-runner.ts', 'const roleEnv = buildCompletionRoleSubprocessEnv(params.role, roleModel);');
assertIncludes('extensions/completion/role-runner.ts', 'function maybeWriteTestPromptBundle(');
assertIncludes('extensions/completion/role-runner.ts', 'function maybeWriteTestRolePromptBundle(');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_ROLE_PROMPT_BUNDLE_PATH');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_PRIMARY_HANDOFF_PROMPT_BUNDLE_PATH');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_CONTEXT_PROPOSAL_ANALYST_PROMPT_BUNDLE_PATH');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_FORCE_REPAIR_PROMPT');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_FORCE_PREVIOUS_OUTPUT');
assertIncludes('extensions/completion/role-runner.ts', 'PI_COMPLETION_TEST_CAPTURE_ROLE_PROMPT_ONLY');
assertIncludes('extensions/completion/role-runner.ts', 'function getInheritedHeadroomWrapPiExtensionArgs(): string[] {');
assertIncludes('extensions/completion/role-runner.ts', 'const explicitExtensionPath = process.env.HEADROOM_PI_EXTENSION_PATH?.trim();');
assertIncludes('extensions/completion/role-runner.ts', 'const sessionConfigPath = process.env.HEADROOM_PI_SESSION_CONFIG?.trim();');
assertIncludes('extensions/completion/role-runner.ts', 'const extensionPath = path.join(path.dirname(sessionConfigPath), "extension.ts");');
assertIncludes('extensions/completion/role-runner.ts', 'const inheritedHeadroomExtensionArgs = getInheritedHeadroomWrapPiExtensionArgs();');
assertIncludes('extensions/completion/role-runner.ts', 'if (inheritedHeadroomExtensionArgs.length > 0) args.push(...inheritedHeadroomExtensionArgs);');
assertIncludes('extensions/completion/role-runner.ts', '"--no-builtin-tools",');
assertIncludes('extensions/completion/role-runner.ts', '"--no-skills",');
assertIncludes('extensions/completion/role-runner.ts', '"--no-prompt-templates",');
assertIncludes('extensions/completion/role-runner.ts', '"--no-context-files",');
assertIncludes('extensions/completion/role-runner.ts', 'const args: string[] = [\n\t\t\t"--mode",\n\t\t\t"json",\n\t\t\t"-p",\n\t\t\t"--no-session",\n\t\t\t"--no-extensions",\n\t\t\t"--no-skills",\n\t\t\t"--no-prompt-templates",\n\t\t\t"--no-context-files",\n\t\t\t"--append-system-prompt",\n\t\t\tsystemPromptTemp.filePath,\n\t\t];');
assertIncludes('extensions/completion/role-runner.ts', 'const combinedPrompt = `${args.systemPrompt}\\n\\n${args.taskPrompt}`;');
assertIncludes('extensions/completion/role-runner.ts', 'kind: "primary-handoff",');
assertIncludes('extensions/completion/role-runner.ts', 'kind: "context-proposal-analyst",');
assertIncludes('extensions/completion/role-runner.ts', 'const forcedRepairPrompt = asString(process.env.PI_COMPLETION_TEST_FORCE_REPAIR_PROMPT);');
assertIncludes('extensions/completion/role-runner.ts', 'const forcedPreviousOutput = asString(process.env.PI_COMPLETION_TEST_FORCE_PREVIOUS_OUTPUT);');
assertIncludes('extensions/completion/role-runner.ts', 'analystArgs.push("--model", modelArg, prompt);');
assertIncludes('extensions/completion/role-runner.ts', 'parseStartupAnalysisFromSubprocess');
assertIncludes('extensions/completion/role-runner.ts', 'resolveRoleSubprocessOutput');
assertIncludes('extensions/completion/role-runner.ts', 'const eventLines: string[] = []');
assertIncludes('extensions/completion/role-runner.ts', 'effectiveRoleToolAllowlistWithStructured');
assertIncludes('extensions/completion/subprocess-final-output.ts', 'extractSubprocessFinalOutput');
assertIncludes('extensions/completion/subprocess-final-output.ts', 'requireSubprocessFinalOutput');
assertIncludes('extensions/completion/startup-analysis.ts', 'parseStartupAnalysisFromSubprocess');
assertIncludes('extensions/completion/role-runner.ts', 'env: roleEnv,');
assertIncludes('extensions/completion/role-runner.ts', 'Call completion_emit_startup_analysis exactly once as the final action.');
assertIncludes('extensions/completion/role-runner.ts', 'hasSubprocessFinalOutput');
assertIncludes('extensions/completion/role-runner.ts', '"--no-extensions",');
assertIncludes('extensions/completion/structured-subprocess-wiring.ts', 'resolveCookHandoffSubprocessResult');
assertIncludes('extensions/completion/structured-subprocess-wiring.ts', 'CookHandoffGenerationResult');
assertIncludes('extensions/completion/structured-subprocess-wiring.ts', 'formatCookHandoffNoHandoffSummary');
assertIncludes('extensions/completion/role-runner.ts', 'resolveCookHandoffSubprocessResult');
assertIncludes('extensions/completion/startup-intent.ts', 'handoffSynthesis?: CookHandoffGenerationResult');
assertIncludes('extensions/completion/driver.ts', 'derived.handoffSynthesis');
assertIncludes('extensions/completion/subprocess-final-output.ts', 'hasSubprocessFinalOutput');
assertIncludes('extensions/completion-structured-tools/index.ts', 'terminate: true');
assertIncludes('extensions/helper-tools/index.ts', 'terminate: true');
assertNotIncludes('extensions/completion/structured-subprocess-wiring.ts', 'noExtIndex');
assertIncludes('extensions/completion/role-runner.ts', 'Use workflow_relation values: new_workflow, continue_current_workflow, replace_current_workflow, or unclear.');
assertIncludes('extensions/completion/role-runner.ts', 'Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.');
assertIncludes('extensions/completion/role-runner.ts', 'Treat /cook itself as the workflow-entry signal; do not require English implementation-intent keywords before analyzing recent discussion.');
assertIncludes('extensions/completion/role-runner.ts', 'async function runContextProposalAnalystSubprocess(');
assertIncludes('extensions/completion/role-runner.ts', 'export async function analyzeContextProposalWithAgent(');
assertIncludes('extensions/completion/role-runner.ts', 'class CookStartupOverlay extends Container');
assertIncludes('extensions/completion/role-runner.ts', 'overlay = new CookStartupOverlay(theme, {');
assertIncludes('extensions/completion/startup-analysis.ts', 'export function buildStartupAnalysisPromptFromEntries(');
assertIncludes('extensions/completion/startup-analysis.ts', 'Do not include task_type or evaluation_profile in discussion-derived startup-analysis output. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.');
assertIncludes('extensions/completion/startup-analysis.ts', 'export function parseStartupAnalysisOutput(');
assertIncludes('extensions/completion/startup-validation.ts', 'export function validateStartupAnalysisRecord(');
for (const file of [
  'agents/completion-bootstrapper.md',
  'agents/completion-regrounder.md',
  'agents/completion-implementer.md',
  'agents/completion-reviewer.md',
  'agents/completion-auditor.md',
  'agents/completion-stop-judge.md',
]) {
  assertIncludes(file, 'role-specific completion runtime quick reference');
}
for (const file of [
  'skills/completion-protocol/references/runtime-quick-driver.md',
  'skills/completion-protocol/references/runtime-quick-bootstrapper.md',
  'skills/completion-protocol/references/runtime-quick-regrounder.md',
  'skills/completion-protocol/references/runtime-quick-implementer.md',
  'skills/completion-protocol/references/runtime-quick-reviewer.md',
  'skills/completion-protocol/references/runtime-quick-auditor.md',
  'skills/completion-protocol/references/runtime-quick-stop-judge.md',
]) {
  assertIncludes(file, '# completion runtime quick reference');
}
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise.');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.');
assertIncludes('extensions/completion/index.ts', 'import { generateCookHandoffWithAgent, runCompletionRole } from "./role-runner";');
assertIncludes('extensions/completion/index.ts', 'const PACKAGE_RUNTIME_QUICK_REFERENCES_DIR = PACKAGE_ROOT');
assertIncludes('extensions/completion/index.ts', 'const RUNTIME_QUICK_REFERENCE_DIR = path.join(AGENT_HOME, "skills", "completion-protocol", "references");');
assertIncludes('extensions/completion/index.ts', 'const ROLE_RUNTIME_QUICK_REFERENCE_FILENAMES: Record<CompletionRole | "driver", string> = {');
assertIncludes('extensions/completion/index.ts', 'driver: "runtime-quick-driver.md"');
assertIncludes('extensions/completion/index.ts', '"completion-bootstrapper": "runtime-quick-bootstrapper.md"');
assertIncludes('extensions/completion/index.ts', '"completion-regrounder": "runtime-quick-regrounder.md"');
assertIncludes('extensions/completion/index.ts', '"completion-implementer": "runtime-quick-implementer.md"');
assertIncludes('extensions/completion/index.ts', '"completion-reviewer": "runtime-quick-reviewer.md"');
assertIncludes('extensions/completion/index.ts', '"completion-auditor": "runtime-quick-auditor.md"');
assertIncludes('extensions/completion/index.ts', '"completion-stop-judge": "runtime-quick-stop-judge.md"');
assertIncludes('extensions/completion/index.ts', 'function runtimeQuickReferencePathForRole(role: CompletionRole | "driver"): string {');
assertIncludes('extensions/completion/index.ts', 'function completionProtocolReadBlock(role: CompletionRole | "driver"): string {');
assertIncludes('extensions/completion/index.ts', 'const quickReferencePath = runtimeQuickReferencePathForRole(role);');
assertIncludes('extensions/completion/index.ts', 'Escalate only if runtime protocol details remain ambiguous after the quick reference and canonical .agent/** state:');
assertIncludes('extensions/completion/index.ts', 'const result = await runCompletionRole({');
assertIncludes('extensions/completion/index.ts', 'requestedModel: modelArgFromContextModel((ctx as { model?: unknown }).model),');
assertIncludes('extensions/completion/index.ts', 'generateCookHandoff: async ({ recentEntries, workflowContextLines }) =>');
assertIncludes('extensions/completion/index.ts', 'generateCookHandoffWithAgent({');
assertNotIncludes('extensions/completion/role-runner.ts', 'Return exactly one JSON object with keys: mission, scope, constraints, acceptance, critique, risks, task_type, evaluation_profile, confidence, possible_noise.');
assertNotIncludes('extensions/completion/role-runner.ts', 'const args: string[] = ["--mode", "json", "-p", "--no-session", "--no-extensions", "--append-system-prompt", systemPromptTemp.filePath];');
assertNotIncludes('extensions/completion/role-runner.ts', 'const args: string[] = ["--mode", "json", "-p", "--no-session", "--append-system-prompt", systemPromptTemp.filePath];');
assertNotIncludes('extensions/completion/index.ts', 'Before acting, read the completion protocol skill and reference:');
assertNotIncludes('extensions/completion/index.ts', '`- ${RUNTIME_QUICK_REFERENCE_PATH}`');
for (const file of [
  'agents/completion-bootstrapper.md',
  'agents/completion-regrounder.md',
  'agents/completion-implementer.md',
  'agents/completion-reviewer.md',
  'agents/completion-auditor.md',
  'agents/completion-stop-judge.md',
]) {
  assertNotIncludes(file, 'Load `completion-protocol` before acting.');
}
assertNotIncludes('extensions/completion/role-runner.ts', 'Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise, task_type, evaluation_profile.');
assertNotIncludes('extensions/completion/role-runner.ts', 'task_type and evaluation_profile should be candidate routing hints only; reuse completion-workflow and completion-rubric-v1 unless the structured startup intent clearly requires another explicit value.');
assertNotIncludes('extensions/completion/prompt-surfaces.ts', 'Do not invent task_type or evaluation_profile from free text. Omit those fields unless an explicit structured artifact already supplied them.');
assertNotIncludes('extensions/completion/index.ts', 'const systemPromptTemp = await writeTempFile(runCwd, "pi-cook-proposal-analyst-", CONTEXT_PROPOSAL_ANALYST_SYSTEM_PROMPT);');
assertNotIncludes('extensions/completion/index.ts', 'const invocation = getPiInvocation(args);');
assertNotIncludes('extensions/completion/index.ts', 'async function loadAgentDefinition(');
assertNotIncludes('extensions/completion/index.ts', 'async function writeTempFile(');
assertNotIncludes('extensions/completion/index.ts', 'function getPiInvocation(');
NODE

echo "role-runner contract test passed"
