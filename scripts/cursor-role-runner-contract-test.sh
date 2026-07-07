#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  if (!read(file).includes(snippet)) {
    throw new Error(`${file} is missing: ${snippet}`);
  }
};

assertIncludes('extensions/completion/role-runner-backend.ts', 'defaultPiRoleRunner');
assertIncludes('extensions/completion/role-runner-backend.ts', 'PI_COMPLETION_TEST_ROLE_SPAWN_RESULT_JSON');
assertIncludes('extensions/completion/role-runner-backend.ts', 'getPiInvocation');
assertIncludes('extensions/completion/role-runner-backend.ts', 'shouldRetainSubprocessFinalOutputEvent(event)');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'runCursorSdkRoleAttempt');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'import("@cursor/sdk")');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', 'runCursorCliAskRoleAttempt');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', 'assertCursorCliAvailable');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'Agent.create');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', 'finalizeCursorCliRoleAttemptResult');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'waitForCursorSdkRun');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'CursorSdkAbortedError');
assertIncludes('extensions/completion/cursor-sdk-role-runner.ts', 'waitPromise.catch');
assertIncludes('extensions/completion/cursor-handoff.ts', 'quarantineCursorHandoffFile');
assertIncludes('extensions/completion/driver.ts', 'quarantined to');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', '.agent", "tmp", "cursor-cli-role"');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', 'workspaceRelativeAtReference');
assertIncludes('extensions/completion/cursor-cli-role-runner.ts', 'probe.status !== 0');
assertIncludes('extensions/completion/role-runner.ts', 'cursor-sdk');
assertIncludes('extensions/completion/role-runner.ts', 'cursor-cli-ask');

console.log('cursor-role-runner-contract-test passed');
NODE
