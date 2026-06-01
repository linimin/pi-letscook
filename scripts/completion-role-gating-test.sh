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
    throw new Error(`${file} is missing required completion-role gating text: ${snippet}`);
  }
};
const assertNotIncludes = (file, snippet) => {
  const text = read(file);
  if (text.includes(snippet)) {
    throw new Error(`${file} still contains stale completion-role gating text: ${snippet}`);
  }
};

assertIncludes('extensions/completion/index.ts', 'function hasStickyWorkflowContinuation(');
assertIncludes('extensions/completion/index.ts', 'function hasRecentlyCompletedCompletionRole(');
assertIncludes('extensions/completion/index.ts', 'function isLikelyWorkflowContinuationTurn(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionWorkflowSessionTurn(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionWorkflowDispatchContext(');
assertIncludes('extensions/completion/index.ts', 'return isCookCommandTurn(ctx) || isCompletionDriverPromptTurn(snapshot, ctx) || isLikelyWorkflowContinuationTurn(snapshot, ctx);');
assertIncludes('extensions/completion/index.ts', 'return isCompletionWorkflowSessionTurn(snapshot, ctx) || hasStickyWorkflowContinuation(snapshot);');
assertIncludes('extensions/completion/index.ts', 'hasStickyWorkflowContinuation(snapshot) && hasRecentlyCompletedCompletionRole(rootKey)');
assertIncludes('extensions/completion/index.ts', 'const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowDispatchContext(snapshot, ctx);');
assertIncludes('extensions/completion/policy-guards.ts', 'return "completion_role may only be used from an active /cook workflow session.";');
assertIncludes('CHANGELOG.md', 'stopped pushing users to rerun `/cook` for routine active-workflow continuation, exact await-user-input replies, or canonical-continue self-heal when canonical workflow state is already active');

assertNotIncludes('extensions/completion/index.ts', 'return hasCompletionRoutingActivation(snapshot) || hasActiveWorkflowEntry(snapshot);');

const indexText = read('extensions/completion/index.ts');
const stickyContinuationIndex = indexText.indexOf('function hasStickyWorkflowContinuation(');
const completedRoleIndex = indexText.indexOf('function hasRecentlyCompletedCompletionRole(');
const continuationIntentIndex = indexText.indexOf('function isLikelyWorkflowContinuationTurn(');
const sessionTurnIndex = indexText.indexOf('function isCompletionWorkflowSessionTurn(');
const dispatchContextIndex = indexText.indexOf('function isCompletionWorkflowDispatchContext(');
const stickyReturnIndex = indexText.indexOf('return isCompletionWorkflowSessionTurn(snapshot, ctx) || hasStickyWorkflowContinuation(snapshot);');
const agentEndSelfHealIndex = indexText.indexOf('hasStickyWorkflowContinuation(snapshot) && hasRecentlyCompletedCompletionRole(rootKey)');
const toolGateIndex = indexText.indexOf('const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowDispatchContext(snapshot, ctx);');
const roleExecutionIndex = indexText.indexOf('const result = await runCompletionRole({');
const postRoleCleanupIndex = indexText.indexOf('await cleanupClosedWorkflowRuntimeIfNeeded(runCwd);');
const liveRoleStatusIndex = indexText.indexOf('liveRoleActivityByRoot.set(rootKey, cloneLiveRoleActivity(result.activity, { status: result.ok ? "ok" : "error" }));');
const postRoleStatusRefreshIndex = indexText.indexOf('await refreshCompletionStatus({ ctx: ctx as { cwd: string; hasUI: boolean; ui: any }, ...statusSurfaceArgs });', postRoleCleanupIndex);
if (stickyContinuationIndex === -1 || completedRoleIndex === -1 || continuationIntentIndex === -1 || sessionTurnIndex === -1 || dispatchContextIndex === -1 || stickyReturnIndex === -1 || agentEndSelfHealIndex === -1 || toolGateIndex === -1) {
  throw new Error('extensions/completion/index.ts must self-heal active continuation sessions before dispatching completion_role.');
}
if (!(stickyContinuationIndex < continuationIntentIndex && continuationIntentIndex < sessionTurnIndex && sessionTurnIndex < dispatchContextIndex && dispatchContextIndex < stickyReturnIndex && stickyReturnIndex < agentEndSelfHealIndex && agentEndSelfHealIndex < toolGateIndex && stickyContinuationIndex < completedRoleIndex && completedRoleIndex < toolGateIndex)) {
  throw new Error('extensions/completion/index.ts should define sticky continuation detection before reusing it for completion_role dispatch.');
}
if (roleExecutionIndex === -1 || postRoleCleanupIndex === -1 || liveRoleStatusIndex === -1 || postRoleStatusRefreshIndex === -1) {
  throw new Error('extensions/completion/index.ts must keep immediate post-completion_role cleanup assertions in place.');
}
if (!(roleExecutionIndex < postRoleCleanupIndex && postRoleCleanupIndex < liveRoleStatusIndex && liveRoleStatusIndex < postRoleStatusRefreshIndex)) {
  throw new Error('extensions/completion/index.ts should clean closed workflow residue immediately after completion_role returns and before status refresh.');
}
NODE

echo "completion-role gating test passed"
