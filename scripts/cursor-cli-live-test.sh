#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${CURSOR_LIVE_TEST:-}" != "1" ]]; then
  echo "cursor-cli-live-test skipped (set CURSOR_LIVE_TEST=1 to run)"
  exit 0
fi

if [[ -z "${CURSOR_API_KEY:-}" && -z "${PI_COMPLETION_CURSOR_API_KEY:-}" ]]; then
  echo "cursor-cli-live-test skipped (CURSOR_API_KEY is required when CURSOR_LIVE_TEST=1)"
  exit 1
fi

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const pkgRoot = process.env.PKGTST_ROOT;

async function loadModules() {
  const cliMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/cursor-cli-role-runner.ts')).href);
  const configMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/cursor-role-config.ts')).href);
  return { cliMod, configMod };
}

async function runLiveCliPromptTest(mods) {
  const { cliMod, configMod } = mods;
  const apiKey = configMod.resolveCursorApiKey();
  assert.ok(apiKey, 'CURSOR_API_KEY must be set for live CLI test');

  const cli = configMod.resolveCursorCliBinary();
  cliMod.assertCursorCliAvailable(cli);

  const promptDir = path.join(pkgRoot, '.agent', 'tmp', 'cursor-cli-role');
  fs.mkdirSync(promptDir, { recursive: true });
  const promptPath = path.join(promptDir, `live-test-${process.pid}.md`);
  const promptBody = 'Reply with exactly the single word: ok';
  fs.writeFileSync(promptPath, promptBody, { encoding: 'utf8', mode: 0o600 });

  const relative = path.relative(pkgRoot, promptPath).split(path.sep).join('/');
  const promptReference = `@${relative}`;

  const args = [
    '--mode',
    'ask',
    '-p',
    '--output-format',
    'json',
    '--workspace',
    pkgRoot,
    '--model',
    configMod.resolveCursorModel('completion-reviewer'),
    '--trust',
    promptReference,
  ];

  const { exitCode, stdout, stderr } = await new Promise((resolve, reject) => {
    const proc = spawn(cli, args, {
      cwd: pkgRoot,
      env: { ...process.env, CURSOR_API_KEY: apiKey },
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
    });
    let stdoutText = '';
    let stderrText = '';
    proc.stdout.on('data', (chunk) => {
      stdoutText += chunk.toString();
    });
    proc.stderr.on('data', (chunk) => {
      stderrText += chunk.toString();
    });
    proc.on('error', reject);
    proc.on('close', (code) => resolve({ exitCode: code ?? 0, stdout: stdoutText, stderr: stderrText }));
  });

  try {
    const finalized = cliMod.finalizeCursorCliRoleAttemptResult({
      exitCode,
      stdout,
      stderr: stderr.trim() || undefined,
    });
    assert.equal(finalized.exitCode, 0, `live CLI failed: ${finalized.stderr ?? stderr}`);
    const assistantText = finalized.assistantText ?? '';
    assert.match(assistantText.toLowerCase(), /\bok\b/, `expected assistant text to include ok, got: ${assistantText}`);
    assert.ok(
      !assistantText.includes(promptReference),
      'assistant output should expand @ prompt reference instead of echoing the path',
    );
  } finally {
    fs.rmSync(promptPath, { force: true });
  }
}

async function main() {
  const mods = await loadModules();

  const unparseable = mods.cliMod.finalizeCursorCliRoleAttemptResult({
    exitCode: 0,
    stdout: 'not-json',
    stderr: undefined,
  });
  assert.equal(unparseable.exitCode, 1, 'unparseable stdout should fail closed');

  await runLiveCliPromptTest(mods);
  console.log('cursor-cli-live-test passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
