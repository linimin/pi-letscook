#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${CURSOR_LIVE_TEST:-}" != "1" ]]; then
  echo "cursor-sdk-live-test skipped (set CURSOR_LIVE_TEST=1 to run)"
  exit 0
fi

if [[ -z "${CURSOR_API_KEY:-}" && -z "${PI_COMPLETION_CURSOR_API_KEY:-}" ]]; then
  echo "cursor-sdk-live-test skipped (CURSOR_API_KEY is required when CURSOR_LIVE_TEST=1)"
  exit 1
fi

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const pkgRoot = process.env.PKGTST_ROOT;

async function main() {
  const sdkMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/cursor-sdk-role-runner.ts')).href);

  const result = await sdkMod.runCursorSdkRoleAttempt({
    root: pkgRoot,
    role: 'completion-implementer',
    combinedPrompt: 'Reply with exactly the single word: ok',
  });

  assert.equal(result.exitCode, 0, `SDK live run failed: ${result.stderr ?? '(no stderr)'}`);
  assert.match((result.assistantText ?? '').toLowerCase(), /\bok\b/, `expected ok in assistant text, got: ${result.assistantText}`);
  console.log('cursor-sdk-live-test passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
