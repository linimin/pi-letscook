#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function withTempDir(run) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'pi-letscook-helper-artifacts-'));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, 'utf8'));
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const runnerMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-runner.ts')).href);
  const storeMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/state-store.ts')).href);
  const {
    helperToolsExtensionPath,
    loadHelperDefinition,
    runCompletionHelper,
  } = runnerMod;
  const { helperArtifactsDir } = storeMod;

  const helperDef = await loadHelperDefinition('scout');
  assert.equal(path.resolve(helperDef.filePath), path.join(pkgRoot, 'helpers', 'scout.md'), 'helper definition must load from the package-owned helper asset');
  assert.equal(path.resolve(helperToolsExtensionPath()), path.join(pkgRoot, 'extensions', 'helper-tools'), 'helper runner must point at the package-owned helper-tools extension');

  await withTempDir(async (tmpRoot) => {
    const repoRoot = path.join(tmpRoot, 'repo');
    await fsp.mkdir(path.join(repoRoot, '.agent', 'current', 'tmp'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'subdir'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, '.pi', 'helpers'), { recursive: true });
    const realRepoRoot = await fsp.realpath(repoRoot);
    await fsp.writeFile(path.join(repoRoot, '.pi', 'helpers', 'scout.md'), 'override should be ignored\n', 'utf8');

    const result = await runCompletionHelper({
      root: repoRoot,
      helper: 'scout',
      callerRole: 'completion-implementer',
      task: 'Collect bounded evidence.',
      cwd: 'subdir',
      roleModel: 'role-model-alpha',
      runId: 'artifact-layout',
      subprocessRunner: async () => ({
        exitCode: 0,
        assistantText: JSON.stringify({
          summary: 'Collected bounded evidence.',
          evidence: ['top.txt:1-1'],
          paths: ['top.txt'],
          open_questions: [],
        }),
        eventLines: [JSON.stringify({ type: 'tool_execution_start', toolName: 'completion_helper_read' })],
      }),
    });

    assert.equal(result.ok, true, 'successful helper run should pass');
    const expectedArtifactDir = path.join(helperArtifactsDir(realRepoRoot), 'artifact-layout');
    assert.equal(path.resolve(result.artifactDir), expectedArtifactDir, 'artifact dir must stay under canonical helper scratch');

    const promptPath = path.join(expectedArtifactDir, 'prompt.md');
    const invocationPath = path.join(expectedArtifactDir, 'invocation.json');
    const eventsPath = path.join(expectedArtifactDir, 'events.jsonl');
    const resultPath = path.join(expectedArtifactDir, 'result.json');
    for (const filePath of [promptPath, invocationPath, eventsPath, resultPath]) {
      const stat = await fsp.stat(filePath).catch(() => undefined);
      assert.ok(stat && stat.isFile(), `expected artifact file to exist: ${filePath}`);
    }

    const promptText = await fsp.readFile(promptPath, 'utf8');
    assert.ok(promptText.includes('internal helper subprocess for `pi-letscook`'), 'staged prompt must contain the package-owned helper body');

    const invocation = await readJson(invocationPath);
    assert.equal(invocation.helper, 'scout');
    assert.equal(invocation.callerRole, 'completion-implementer');
    assert.equal(invocation.resolvedCwd, path.join(realRepoRoot, 'subdir'));
    assert.equal(invocation.usedModel, 'role-model-alpha');
    assert.equal(invocation.callerRoleModel, 'role-model-alpha');
    assert.equal(invocation.env.PI_COMPLETION_HELPER, 'scout');
    assert.equal(invocation.env.PI_COMPLETION_CALLER_ROLE, 'completion-implementer');
    assert.equal(invocation.env.PI_COMPLETION_HELPER_ROOT, realRepoRoot);
    assert.equal(invocation.env.PI_COMPLETION_HELPER_CWD, path.join(realRepoRoot, 'subdir'));
    assert.equal(invocation.env.PI_COMPLETION_ROLE_MODEL, 'role-model-alpha');
    assert.ok(Array.isArray(invocation.toolAllowlist) && invocation.toolAllowlist.length === 4, 'invocation must persist the fixed helper tool allowlist');

    const artifactResult = await readJson(resultPath);
    assert.equal(artifactResult.ok, true, 'successful result.json should preserve the success contract');
    assert.equal(artifactResult.artifactDir, expectedArtifactDir);

    const missingScratchRoot = path.join(tmpRoot, 'missing-scratch-repo');
    await fsp.mkdir(missingScratchRoot, { recursive: true });
    const failed = await runCompletionHelper({
      root: missingScratchRoot,
      helper: 'scout',
      callerRole: 'completion-implementer',
      task: 'Fail without canonical helper scratch.',
      runId: 'missing-scratch',
      subprocessRunner: async () => {
        throw new Error('runner should not be called when canonical scratch is missing');
      },
    });
    assert.equal(failed.ok, false, 'missing helper scratch must fail closed');
    assert.equal(failed.failureKind, 'policy');
    assert.ok(failed.message.includes('canonical helper scratch root'), `unexpected failure message: ${failed.message}`);
    assert.equal(path.resolve(failed.artifactDir), path.join(await fsp.realpath(missingScratchRoot), '.agent', 'current', 'tmp', 'helpers', 'missing-scratch'));
  });

  console.log('helper artifact layout test passed');
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
NODE
