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

assertIncludes('extensions/completion/cursor-role-config.ts', 'PI_COMPLETION_CURSOR_ENABLED');
assertIncludes('extensions/completion/cursor-role-config.ts', 'completion-implementer');
assertIncludes('extensions/completion/cursor-role-config.ts', 'completion-reviewer');
assertIncludes('extensions/completion/cursor-role-config.ts', 'resolveRoleBackend');
assertIncludes('extensions/completion/cursor-role-config.ts', 'if (!isCursorBackendEnabled()) return "pi"');
assertIncludes('extensions/completion/role-runner.ts', 'resolveRoleBackend(params.role, agent)');
assertIncludes('extensions/completion/role-runner.ts', 'allowTextFallback: backend !== "pi"');
assertIncludes('extensions/completion/role-runner.ts', 'transcription?.errors.length ?? 0) > 0');
assertIncludes('extensions/completion/types.ts', 'cursorModel?: string');
assertIncludes('extensions/completion/types.ts', 'roleBackend?: string');

console.log('cursor-role-config-test passed');
NODE
