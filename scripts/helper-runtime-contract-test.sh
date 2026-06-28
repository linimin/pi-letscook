#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const fsp = require('node:fs/promises');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function withTempDir(run) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'pi-letscook-helper-runtime-'));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function exists(targetPath) {
  try {
    await fsp.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

function validOutputObject(summary = 'Helper finished.') {
  return {
    summary,
    evidence: ['src/example.ts:1-3'],
    paths: ['src/example.ts'],
    open_questions: [],
  };
}

function validOutput(summary = 'Helper finished.') {
  return JSON.stringify(validOutputObject(summary));
}

function helperEmitEventLines(outputObj, helper = 'scout') {
  const toolName = helper === 'critic' ? 'completion_helper_emit_critic_result' : 'completion_helper_emit_scout_result';
  const contractId = helper === 'critic' ? 'completion.helper.critic.v1' : 'completion.helper.scout.v1';
  const toolCallId = 'structured-call';
  return [
    JSON.stringify({ type: 'tool_execution_start', toolName, toolCallId }),
    JSON.stringify({
      type: 'tool_execution_end',
      toolName,
      toolCallId,
      result: {
        content: [{ type: 'text', text: outputObj.summary }],
        details: {
          contractId,
          schemaVersion: 1,
          ...outputObj,
        },
      },
    }),
  ];
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const policyMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-policy.ts')).href);
  const runnerMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-runner.ts')).href);
  const storeMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/state-store.ts')).href);
  const typesMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-types.ts')).href);

  const {
    allowedHelpersForRole,
    clampHelperTimeoutMs,
    helperToolAllowlist,
    isHelperAllowedForRole,
  } = policyMod;
  const {
    HELPER_REQUIRED_FLAGS,
    defaultHelperSubprocessRunner,
    parseHelperDefinitionText,
    parseStructuredHelperOutput,
    resolveHelperModel,
    runCompletionHelper,
  } = runnerMod;
  const { helperRunLockDir } = storeMod;
  const { HELPER_PROXY_TOOL_NAMES } = typesMod;

  assert.equal(isHelperAllowedForRole('completion-implementer', 'scout'), true, 'implementer should be allowed to run scout');
  assert.equal(isHelperAllowedForRole('completion-reviewer', 'scout'), false, 'reviewer must stay disallowed');
  assert.deepEqual(new Set(allowedHelpersForRole('completion-implementer')), new Set(['scout', 'critic']));
  assert.deepEqual(allowedHelpersForRole('completion-reviewer'), [], 'reviewer helper allowlist should stay empty');
  assert.equal(clampHelperTimeoutMs('scout', 999999), 120000, 'scout timeout should clamp to the V1 max');
  assert.deepEqual(helperToolAllowlist('critic'), [...HELPER_PROXY_TOOL_NAMES, 'completion_helper_emit_critic_result'], 'critic must receive the fixed guarded tool allowlist plus structured emit tool');

  const syntheticHelper = parseHelperDefinitionText('scout', '---\nname: scout\nmodel: helper-model\n---\nSynthetic prompt body.\n', '/synthetic/scout.md');
  const resolvedSyntheticModel = await resolveHelperModel({
    helperDefinition: syntheticHelper,
    callerRole: 'completion-implementer',
    roleModel: 'role-model-alpha',
  });
  assert.equal(resolvedSyntheticModel.callerRoleModel, 'role-model-alpha');
  assert.equal(resolvedSyntheticModel.usedModel, 'helper-model', 'helper frontmatter model should override caller role model');

  const parsedOutput = parseStructuredHelperOutput(validOutput('Structured helper output is valid.'));
  assert.equal(parsedOutput.summary, 'Structured helper output is valid.');

  const defaultRunnerEvents = [];
  const directRunnerSignal = new AbortController();
  const directRunnerPayload = validOutput('Default runner captured assistant JSON.');
  const defaultRunnerResult = await defaultHelperSubprocessRunner({
    command: process.execPath,
    args: ['-e', `console.log(${JSON.stringify(JSON.stringify({ type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: directRunnerPayload }] } }))})`],
    cwd: pkgRoot,
    env: process.env,
    signal: directRunnerSignal.signal,
    onJsonEvent: (event) => defaultRunnerEvents.push(event),
  });
  assert.equal(defaultRunnerResult.exitCode, 0, 'default helper subprocess runner should preserve the provided command/args contract');
  assert.equal(defaultRunnerResult.assistantText, directRunnerPayload, 'default helper subprocess runner should capture final assistant text');
  assert.equal(defaultRunnerEvents.length, 1, 'default helper subprocess runner should surface parsed JSON events');
  assert.throws(
    () => parseStructuredHelperOutput(JSON.stringify({ summary: 'x'.repeat(600), evidence: [], paths: [], open_questions: [] })),
    /summary exceeded the V1 byte cap/,
    'oversized summary should fail closed',
  );
  assert.throws(
    () => parseStructuredHelperOutput(JSON.stringify({ summary: 'ok', evidence: ['good', 42], paths: [], open_questions: [] })),
    /must contain only non-empty strings/,
    'non-string helper arrays should fail closed',
  );

  await withTempDir(async (tmpRoot) => {
    const repoRoot = path.join(tmpRoot, 'repo');
    await fsp.mkdir(path.join(repoRoot, '.agent', 'current', 'tmp'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'subdir'), { recursive: true });
    const realRepoRoot = await fsp.realpath(repoRoot);
    const lockDir = helperRunLockDir(realRepoRoot);

    const capturedSpecs = [];
    const success = await runCompletionHelper({
      root: repoRoot,
      helper: 'critic',
      callerRole: 'completion-implementer',
      task: 'Pressure-test the proposed diff.',
      cwd: 'subdir',
      roleModel: 'role-model-beta',
      runId: 'success-contract',
      subprocessRunner: async (spec) => {
        capturedSpecs.push(spec);
        const outputObj = validOutputObject('Critic completed successfully.');
        const events = [
          { type: 'tool_execution_start', toolName: 'completion_helper_read' },
          {
            type: 'tool_execution_update',
            partialResult: { details: { stage: 'read-source' } },
          },
          {
            type: 'message_end',
            message: {
              role: 'assistant',
              content: [{ type: 'text', text: validOutput('Critic completed successfully.') }],
            },
          },
        ];
        for (const event of events) spec.onJsonEvent?.(event, JSON.stringify(event));
        return {
          exitCode: 0,
          assistantText: validOutput('Critic completed successfully.'),
          eventLines: [...helperEmitEventLines(outputObj, 'critic'), ...events.map((event) => JSON.stringify(event))],
        };
      },
    });

    assert.equal(success.ok, true, 'successful helper run should succeed');
    assert.equal(success.usedModel, 'role-model-beta', 'used model should resolve deterministically from the caller role model when helper frontmatter is unpinned');
    assert.equal(capturedSpecs.length, 1, 'successful run should invoke the subprocess once');
    const spec = capturedSpecs[0];
    assert.equal(spec.cwd, path.join(realRepoRoot, 'subdir'));
    assert.equal(spec.env.PI_COMPLETION_HELPER, 'critic');
    assert.equal(spec.env.PI_COMPLETION_CALLER_ROLE, 'completion-implementer');
    assert.equal(spec.env.PI_COMPLETION_HELPER_ROOT, realRepoRoot);
    assert.equal(spec.env.PI_COMPLETION_HELPER_CWD, path.join(realRepoRoot, 'subdir'));
    assert.equal(spec.env.PI_COMPLETION_ROLE_MODEL, 'role-model-beta');
    assert.equal(spec.env.PI_COMPLETION_ROLE, undefined, 'helper env should not inherit authoritative PI_COMPLETION_ROLE');
    for (const flag of HELPER_REQUIRED_FLAGS) {
      assert.ok(spec.args.includes(flag), `helper invocation must include required flag: ${flag}`);
    }
    const toolsIndex = spec.args.indexOf('--tools');
    assert.ok(toolsIndex >= 0, 'helper invocation must include --tools');
    assert.equal(spec.args[toolsIndex + 1], helperToolAllowlist('critic').join(','), 'helper invocation must pin the guarded tool allowlist');
    const extensionIndex = spec.args.indexOf('-e');
    assert.ok(extensionIndex >= 0, 'helper invocation must explicitly load helper-tools');
    assert.equal(spec.args[extensionIndex + 1], path.join(pkgRoot, 'extensions', 'helper-tools'), 'helper invocation must use the package-owned helper-tools extension');

    const invalidOutput = await runCompletionHelper({
      root: repoRoot,
      helper: 'scout',
      callerRole: 'completion-implementer',
      task: 'Emit malformed helper JSON.',
      runId: 'invalid-output',
      subprocessRunner: async () => ({
        exitCode: 0,
        assistantText: 'not-json',
        eventLines: [],
      }),
    });
    assert.equal(invalidOutput.ok, false, 'malformed helper output must fail closed');
    assert.equal(invalidOutput.failureKind, 'invalid_output');
    assert.equal(await exists(lockDir), false, 'lock must be released after invalid output failure');

    const timeoutResult = await runCompletionHelper({
      root: repoRoot,
      helper: 'scout',
      callerRole: 'completion-implementer',
      task: 'Time out deterministically.',
      runId: 'timeout-contract',
      timeoutMs: 25,
      subprocessRunner: (spec) => new Promise((resolve) => {
        spec.signal.addEventListener('abort', () => {
          resolve({ exitCode: 143, stderr: 'timeout', eventLines: [] });
        }, { once: true });
      }),
    });
    assert.equal(timeoutResult.ok, false, 'timeout should fail closed');
    assert.equal(timeoutResult.failureKind, 'timeout');
    assert.equal(await exists(lockDir), false, 'lock must be released after timeout');

    const abortController = new AbortController();
    const abortPromise = runCompletionHelper({
      root: repoRoot,
      helper: 'critic',
      callerRole: 'completion-implementer',
      task: 'Abort deterministically.',
      runId: 'abort-contract',
      signal: abortController.signal,
      subprocessRunner: (spec) => new Promise((resolve) => {
        spec.signal.addEventListener('abort', () => {
          resolve({ exitCode: 130, stderr: 'aborted', eventLines: [] });
        }, { once: true });
      }),
    });
    setTimeout(() => abortController.abort(), 10);
    const aborted = await abortPromise;
    assert.equal(aborted.ok, false, 'abort should fail closed');
    assert.equal(aborted.failureKind, 'aborted');
    assert.equal(await exists(lockDir), false, 'lock must be released after abort');

    let releaseFirstRun;
    const firstRunPromise = runCompletionHelper({
      root: repoRoot,
      helper: 'scout',
      callerRole: 'completion-implementer',
      task: 'Hold the single-helper lock.',
      runId: 'concurrent-one',
      subprocessRunner: () => new Promise((resolve) => {
        releaseFirstRun = () => {
          const outputObj = validOutputObject('First helper finished.');
          resolve({
            exitCode: 0,
            assistantText: validOutput('First helper finished.'),
            eventLines: helperEmitEventLines(outputObj, 'scout'),
          });
        };
      }),
    });

    for (let attempt = 0; attempt < 50 && !(await exists(lockDir)); attempt += 1) {
      await sleep(10);
    }
    assert.equal(await exists(lockDir), true, 'first helper run should hold the lock while in flight');

    const secondRun = await runCompletionHelper({
      root: repoRoot,
      helper: 'critic',
      callerRole: 'completion-implementer',
      task: 'Compete for the lock.',
      runId: 'concurrent-two',
      subprocessRunner: async () => ({
        exitCode: 0,
        assistantText: validOutput('Second helper should never start.'),
        eventLines: [],
      }),
    });
    assert.equal(secondRun.ok, false, 'concurrent second helper must fail closed');
    assert.equal(secondRun.failureKind, 'policy');
    assert.ok(secondRun.message.includes('another helper is already running'), `unexpected concurrent-lock message: ${secondRun.message}`);

    releaseFirstRun();
    const firstRun = await firstRunPromise;
    assert.equal(firstRun.ok, true, 'first helper should complete once released');
    assert.equal(await exists(lockDir), false, 'lock must be released after the first helper completes');
  });

  console.log('helper runtime contract test passed');
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
NODE
