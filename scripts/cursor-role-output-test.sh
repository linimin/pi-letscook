#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const pkgRoot = process.env.PKGTST_ROOT;

async function main() {
  const cliMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/cursor-cli-role-runner.ts')).href);
  const wiringMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/structured-subprocess-wiring.ts')).href);
  const { StructuredSubprocessOutputError } = await import(
    pathToFileURL(path.join(pkgRoot, 'extensions/completion/subprocess-final-output.ts')).href,
  );

  const text = cliMod.parseCursorCliJsonOutput(JSON.stringify({ result: 'MISSION ANCHOR: test\nAcceptable as-is: yes' }));
  assert.ok(text && text.includes('MISSION ANCHOR'), 'parseCursorCliJsonOutput should extract result text');

  const ndjson = cliMod.parseCursorCliJsonOutput(
    ['{"type":"progress"}', JSON.stringify({ result: 'MISSION ANCHOR: ndjson\nAcceptable as-is: yes' })].join('\n'),
  );
  assert.ok(ndjson && ndjson.includes('ndjson'), 'parseCursorCliJsonOutput should parse trailing NDJSON line');

  const streamJson = cliMod.parseCursorCliJsonOutput(
    [
      JSON.stringify({ type: 'progress' }),
      JSON.stringify({ type: 'assistant', message: { content: [{ type: 'text', text: 'MISSION ANCHOR: stream\nAcceptable as-is: yes' }] } }),
    ].join('\n'),
  );
  assert.ok(streamJson && streamJson.includes('stream'), 'parseCursorCliJsonOutput should parse stream-json assistant events');

  const resolved = wiringMod.resolveRoleSubprocessOutput({
    role: 'completion-reviewer',
    assistantText:
      'MISSION ANCHOR: test\nRemaining contract IDs: none\nRubric:\n- Contract coverage: pass - ok\n- Correctness risk: pass - ok\n- Verification evidence: pass - ok\n- Docs/state parity: pass - ok\nFindings: none\nAcceptable as-is: yes\nSmallest follow-up slice: none; proceed to completion-auditor.',
    eventLines: [],
    fallbackOutput: '',
    allowTextFallback: true,
  });
  assert.equal(resolved.reportFields['Acceptable as-is'], 'yes');

  assert.equal(cliMod.parseCursorCliJsonOutput('not-json-at-all'), undefined);

  const unparseable = cliMod.finalizeCursorCliRoleAttemptResult({
    exitCode: 0,
    stdout: 'not-json-at-all',
    stderr: undefined,
  });
  assert.equal(unparseable.exitCode, 1, 'unparseable stdout with exit 0 should fail closed');
  assert.ok(unparseable.stderr?.includes('parseable JSON'));

  const empty = cliMod.finalizeCursorCliRoleAttemptResult({
    exitCode: 0,
    stdout: '',
    stderr: undefined,
  });
  assert.equal(empty.exitCode, 1, 'empty stdout with exit 0 should fail closed');

  assert.throws(
    () =>
      wiringMod.resolveRoleSubprocessOutput({
        role: 'completion-reviewer',
        assistantText: 'MISSION ANCHOR: test\nAcceptable as-is: yes',
        eventLines: [],
        fallbackOutput: '',
        allowTextFallback: false,
      }),
    StructuredSubprocessOutputError,
    'Pi path should fail closed without structured emit output',
  );

  const sdkMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/cursor-sdk-role-runner.ts')).href);
  const finished = await sdkMod.waitForCursorSdkRun({
    wait: async () => ({ status: 'finished', result: 'done' }),
  });
  assert.equal(finished.status, 'finished');

  let cancelCalled = false;
  const slowRun = {
    wait: () => new Promise((resolve) => setTimeout(() => resolve({ status: 'finished', result: 'late' }), 200)),
    supports: (operation) => operation === 'cancel',
    cancel: async () => {
      cancelCalled = true;
    },
  };
  const controller = new AbortController();
  const abortedWait = sdkMod.waitForCursorSdkRun(slowRun, controller.signal);
  controller.abort();
  await assert.rejects(abortedWait, (error) => error instanceof sdkMod.CursorSdkAbortedError);
  assert.equal(cancelCalled, true, 'abort should cancel the SDK run when supported');

  console.log('cursor-role-output-test passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
