#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  if (!read(file).includes(snippet)) throw new Error(`${file} missing: ${snippet}`);
};

assertIncludes('extensions/completion/index.ts', 'readPendingCookHandoff');
assertIncludes('extensions/completion/index.ts', 'resolvePlainCookPendingImport');
assertIncludes('extensions/completion/index.ts', 'consumeCursorConfirmedKickoffEnv');
assertIncludes('extensions/completion/index.ts', 'CURSOR_HANDOFF_CONFIRMED_ENV');
assertIncludes('extensions/completion/index.ts', 'CURSOR_HANDOFF_CONFIRMED_ENV');
assertIncludes('extensions/completion/cursor-handoff-service.ts', 'PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED');
assertIncludes('extensions/completion/cursor-handoff-service.ts', 'readPendingCookHandoff');
assertIncludes('extensions/completion/cursor-handoff-service.ts', 'COOK_HANDOFF_PENDING_SIDECAR_PATH');
assertIncludes('extensions/completion/driver.ts', 'Pending Cursor handoff could not start workflow');
assertIncludes('extensions/completion/driver.ts', 'Start a completion workflow from this Cursor handoff?');

console.log('cursor-handoff-auto-detect-test passed');
NODE
