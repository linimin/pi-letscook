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

assertIncludes('extensions/completion/index.ts', 'function isOrdinaryMainChatTurnDuringActiveWorkflow(');
assertIncludes('extensions/completion/index.ts', 'function isCompletionRoleDispatchAllowedTurn(');
assertIncludes('extensions/completion/index.ts', 'if (isOrdinaryMainChatTurnDuringActiveWorkflow(snapshot, ctx)) return false;');
assertIncludes('extensions/completion/index.ts', 'return asString(snapshot?.state?.continuation_policy) === "continue";');
assertIncludes('extensions/completion/index.ts', 'const completionRoleDispatchAllowed = Boolean(role) || isCompletionRoleDispatchAllowedTurn(snapshot, ctx);');
assertIncludes('extensions/completion/index.ts', 'if (isCookCommandTurn(ctx)) return false;');
assertIncludes('extensions/completion/index.ts', 'if (isCompletionDriverPromptTurn(snapshot, ctx)) return false;');
assertIncludes('extensions/completion/policy-guards.ts', 'return "completion_role may only be used from an active /cook workflow session.";');
assertIncludes('CHANGELOG.md', 'fixed completion-role continuation gating so an already-active `/cook` workflow with `continuation_policy: continue` can keep dispatching mandatory follow-up roles');

assertNotIncludes(
  'extensions/completion/index.ts',
  'const completionRoleDispatchAllowed = Boolean(role) || isCompletionWorkflowSessionTurn(snapshot, ctx);',
);

const indexText = read('extensions/completion/index.ts');
const ordinaryGuardIndex = indexText.indexOf('if (isOrdinaryMainChatTurnDuringActiveWorkflow(snapshot, ctx)) return false;');
const continueFallbackIndex = indexText.indexOf('return asString(snapshot?.state?.continuation_policy) === "continue";');
if (ordinaryGuardIndex === -1 || continueFallbackIndex === -1 || ordinaryGuardIndex > continueFallbackIndex) {
  throw new Error('extensions/completion/index.ts must reject ordinary main-chat turns before allowing the continuation_policy=continue fallback.');
}
NODE

echo "completion-role gating test passed"
