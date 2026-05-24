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

assertIncludes('extensions/completion/index.ts', 'function isCompletionWorkflowSessionTurn(');
assertIncludes('extensions/completion/index.ts', 'return hasCompletionRoutingActivation(snapshot) || hasActiveWorkflowEntry(snapshot);');
assertIncludes('extensions/completion/index.ts', 'const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowSessionTurn(snapshot, ctx);');
assertIncludes('extensions/completion/policy-guards.ts', 'return "completion_role may only be used from an active /cook workflow session.";');
assertIncludes('CHANGELOG.md', 'made active `/cook` workflows sticky across subsequent turns so completion-role dispatch and workflow context continue to self-heal from canonical active state instead of depending on prompt-shaped driver turns');
assertIncludes('CHANGELOG.md', 'stopped pushing users to rerun `/cook` for routine active-workflow continuation or exact await-user-input replies when canonical workflow state is already active');

assertNotIncludes('extensions/completion/index.ts', 'function isOrdinaryMainChatTurnDuringActiveWorkflow(');
assertNotIncludes('extensions/completion/index.ts', 'function isCompletionRoleDispatchAllowedTurn(');
assertNotIncludes('extensions/completion/index.ts', 'function isAwaitingUserInputWorkflowReplyTurn(');

const indexText = read('extensions/completion/index.ts');
const sessionTurnIndex = indexText.indexOf('function isCompletionWorkflowSessionTurn(');
const stickyReturnIndex = indexText.indexOf('return hasCompletionRoutingActivation(snapshot) || hasActiveWorkflowEntry(snapshot);');
const toolGateIndex = indexText.indexOf('const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowSessionTurn(snapshot, ctx);');
if (sessionTurnIndex === -1 || stickyReturnIndex === -1 || toolGateIndex === -1) {
  throw new Error('extensions/completion/index.ts must derive workflow legitimacy from canonical active state and reuse that gate for completion_role dispatch.');
}
if (!(sessionTurnIndex < stickyReturnIndex && stickyReturnIndex < toolGateIndex)) {
  throw new Error('extensions/completion/index.ts should define sticky workflow-session detection before reusing it for completion_role dispatch.');
}
NODE

echo "completion-role gating test passed"
