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
assertIncludes('extensions/completion/role-runner.ts', 'import {\n\tbuildStartupAnalysisPromptFromEntries,\n\tparseStartupAnalysisOutput,\n} from "./startup-analysis";');
assertIncludes('extensions/completion/role-runner.ts', 'const agent = await loadAgentDefinition(params.root, params.role);');
assertIncludes('extensions/completion/role-runner.ts', 'const systemPromptTemp = await writeTempFile(params.root, "pi-completion-role-", agent.systemPrompt);');
assertIncludes('extensions/completion/role-runner.ts', 'const reportFields = parseReportFields(output);');
assertIncludes('extensions/completion/role-runner.ts', 'const transcription = exitCode === 0 ? await transcribeRoleOutput(params.role, params.root, output, reportFields) : undefined;');
assertIncludes('extensions/completion/role-runner.ts', 'Structured report repair mode:');
assertIncludes('extensions/completion/role-runner.ts', 'Retrying ${params.role} once to repair structured report consistency.');
assertIncludes('extensions/completion/helper-policy.ts', 'export function effectiveRoleToolAllowlist(');
assertIncludes('extensions/completion/helper-policy.ts', 'export function resolveEffectiveCompletionRoleModel(');
assertIncludes('extensions/completion/helper-policy.ts', 'export function buildCompletionRoleSubprocessEnv(');
assertIncludes('extensions/completion/role-runner.ts', 'const roleModel = resolveEffectiveCompletionRoleModel(agent.model, params.requestedModel);');
assertIncludes('extensions/completion/role-runner.ts', 'const effectiveToolAllowlist = effectiveRoleToolAllowlist(params.role, agent.tools);');
assertIncludes('extensions/completion/role-runner.ts', 'const roleEnv = buildCompletionRoleSubprocessEnv(params.role, roleModel);');
assertIncludes('extensions/completion/role-runner.ts', 'env: roleEnv,');
assertIncludes('extensions/completion/role-runner.ts', 'Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise.');
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
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Return exactly one JSON object with keys: verdict, workflow_relation, confidence, mission, scope, constraints, acceptance, diagnostics, critique, risks, possible_noise.');
assertIncludes('extensions/completion/prompt-surfaces.ts', 'Do not include task_type or evaluation_profile in startup-analysis output from free-text discussion. Only explicit structured startup artifacts may supply those routing fields elsewhere in /cook.');
assertIncludes('extensions/completion/index.ts', 'import { generateCookHandoffWithAgent, runCompletionRole } from "./role-runner";');
assertIncludes('extensions/completion/index.ts', 'const result = await runCompletionRole({');
assertIncludes('extensions/completion/index.ts', 'requestedModel: modelArgFromContextModel((ctx as { model?: unknown }).model),');
assertIncludes('extensions/completion/index.ts', 'generateCookHandoff: async ({ recentEntries, workflowContextLines }) =>');
assertIncludes('extensions/completion/index.ts', 'generateCookHandoffWithAgent({');
assertNotIncludes('extensions/completion/role-runner.ts', 'Return exactly one JSON object with keys: mission, scope, constraints, acceptance, critique, risks, task_type, evaluation_profile, confidence, possible_noise.');
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
