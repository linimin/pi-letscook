#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function withEnv(vars, fn) {
  const previous = new Map();
  for (const [name, value] of Object.entries(vars)) {
    previous.set(name, process.env[name]);
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  try {
    return await fn();
  } finally {
    for (const [name, value] of previous.entries()) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

async function withTempDir(run) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'pi-letscook-helper-structured-output-'));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, 'utf8'));
}

function helperEmitEvents(output, helper = 'scout') {
  const toolName = helper === 'critic' ? 'completion_helper_emit_critic_result' : 'completion_helper_emit_scout_result';
  const contractId = helper === 'critic' ? 'completion.helper.critic.v1' : 'completion.helper.scout.v1';
  const toolCallId = 'structured-call';
  return [
    { type: 'tool_execution_start', toolName, toolCallId },
    {
      type: 'tool_execution_end',
      toolName,
      toolCallId,
      result: {
        content: [{ type: 'text', text: output.summary }],
        details: {
          contractId,
          schemaVersion: 1,
          ...output,
        },
      },
    },
  ];
}

function helperEmitEventLines(output, helper = 'scout') {
  return helperEmitEvents(output, helper).map((event) => JSON.stringify(event));
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const helperRunnerMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-runner.ts')).href);
  const { runCompletionAssistTool } = helperRunnerMod;

  const successOutput = {
    summary: 'Collected bounded evidence.',
    evidence: ['extensions/completion/index.ts:1-20'],
    paths: ['extensions/completion/index.ts'],
    open_questions: [],
  };

  await withTempDir(async (tmpRoot) => {
    const repoRoot = path.join(tmpRoot, 'repo');
    await fsp.mkdir(path.join(repoRoot, '.agent', 'current', 'tmp'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'subdir'), { recursive: true });
    await fsp.writeFile(path.join(repoRoot, 'README.md'), '# helper structured output fixture\n', 'utf8');

    const successUpdates = [];
    const successResult = await withEnv(
      {
        PI_COMPLETION_ROLE: 'completion-implementer',
        PI_COMPLETION_ROLE_MODEL: 'openai/gpt-5-mini',
        PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON: JSON.stringify({
          events: [
            ...helperEmitEvents(successOutput, 'scout'),
            { type: 'tool_execution_start', toolName: 'completion_helper_read' },
            { type: 'tool_execution_update', partialResult: { details: { stage: 'read-source' } } },
            {
              type: 'message_end',
              message: {
                role: 'assistant',
                content: [{ type: 'text', text: JSON.stringify(successOutput) }],
              },
            },
          ],
          eventLines: helperEmitEventLines(successOutput, 'scout'),
          exitCode: 0,
          assistantText: JSON.stringify(successOutput),
        }),
      },
      async () =>
        await runCompletionAssistTool({
          root: repoRoot,
          helper: 'scout',
          callerRole: 'completion-implementer',
          task: 'Inspect the selected slice.',
          cwd: 'subdir',
          signal: new AbortController().signal,
          roleModel: 'openai/gpt-5-mini',
          onUpdate: (update) => successUpdates.push(update),
        }),
    );

    assert.equal(successResult.isError, false, 'successful helper result must not be marked as an error');
    assert.equal(successResult.content[0].text, JSON.stringify(successOutput), 'success content must be exact helper output JSON');
    assert.deepEqual(JSON.parse(successResult.content[0].text), successOutput, 'success content must parse back to the structured helper payload');
    assert.equal(successResult.details.ok, true, 'success details must preserve the helper success contract');
    assert.equal(successResult.details.helper, 'scout');
    assert.equal(successResult.details.usedModel, 'openai/gpt-5-mini', 'helper model should inherit the authoritative role model env when the helper prompt is unpinned');
    assert.ok(successUpdates.length >= 2, 'helper progress should emit partial updates before the final result');
    assert.ok(successUpdates.every((update) => typeof update.content?.[0]?.text === 'string' && update.content[0].text.startsWith('helper scout:')), 'helper progress updates must stay human-readable');

    const invocation = await readJson(path.join(successResult.details.artifactDir, 'invocation.json'));
    assert.equal(invocation.env.PI_COMPLETION_ROLE_MODEL, 'openai/gpt-5-mini', 'invocation metadata must record PI_COMPLETION_ROLE_MODEL propagation');
    assert.equal(invocation.usedModel, 'openai/gpt-5-mini', 'invocation metadata must preserve the effective helper model');

    const invalidOutputResult = await withEnv(
      {
        PI_COMPLETION_ROLE: 'completion-implementer',
        PI_COMPLETION_ROLE_MODEL: 'openai/gpt-5-mini',
        PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON: JSON.stringify({
          exitCode: 0,
          assistantText: 'not-json',
        }),
      },
      async () =>
        await runCompletionAssistTool({
          root: repoRoot,
          helper: 'critic',
          callerRole: 'completion-implementer',
          task: 'Emit malformed helper JSON.',
          signal: new AbortController().signal,
          roleModel: 'openai/gpt-5-mini',
        }),
    );

    assert.equal(invalidOutputResult.isError, true, 'malformed helper output must fail closed');
    assert.equal(invalidOutputResult.details.ok, false, 'failure details must preserve the helper failure contract');
    assert.equal(invalidOutputResult.details.failureKind, 'invalid_output');
    assert.match(invalidOutputResult.details.message, /missing terminating tool result|structured helper details/);
    const invalidOutputPayload = JSON.parse(invalidOutputResult.content[0].text);
    assert.deepEqual(
      invalidOutputPayload,
      {
        ok: false,
        helper: 'critic',
        failureKind: 'invalid_output',
        message: invalidOutputResult.details.message,
        resolvedCwd: invalidOutputResult.details.resolvedCwd,
        artifactDir: invalidOutputResult.details.artifactDir,
      },
      'failure content must stay the exact fixed JSON failure object without debug-only fields',
    );
    assert.equal(Object.prototype.hasOwnProperty.call(invalidOutputPayload, 'rawText'), false, 'failure content must not leak rawText');
    assert.equal(Object.prototype.hasOwnProperty.call(invalidOutputPayload, 'stderr'), false, 'failure content must not leak stderr');

    const cwdEscapeResult = await withEnv(
      {
        PI_COMPLETION_ROLE: 'completion-implementer',
        PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON: JSON.stringify({
          exitCode: 0,
          assistantText: JSON.stringify(successOutput),
        }),
      },
      async () =>
        await runCompletionAssistTool({
          root: repoRoot,
          helper: 'scout',
          callerRole: 'completion-implementer',
          task: 'Reject cwd escape attempts.',
          cwd: '../outside',
          signal: new AbortController().signal,
        }),
    );

    assert.equal(cwdEscapeResult.isError, true, 'cwd escape attempts must fail closed');
    assert.equal(cwdEscapeResult.details.ok, false);
    assert.equal(cwdEscapeResult.details.failureKind, 'policy');
    assert.ok(cwdEscapeResult.details.message.includes('cwd'), `unexpected cwd policy failure message: ${cwdEscapeResult.details.message}`);
    assert.deepEqual(
      JSON.parse(cwdEscapeResult.content[0].text),
      {
        ok: false,
        helper: 'scout',
        failureKind: 'policy',
        message: cwdEscapeResult.details.message,
        resolvedCwd: cwdEscapeResult.details.resolvedCwd,
        artifactDir: cwdEscapeResult.details.artifactDir,
      },
      'policy failures must also use the exact fixed JSON failure contract',
    );

    const assistantOnlyResult = await withEnv(
      {
        PI_COMPLETION_ROLE: 'completion-implementer',
        PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON: JSON.stringify({
          exitCode: 0,
          assistantText: JSON.stringify({ summary: 'legacy ignored', evidence: [], paths: [], open_questions: [] }),
          eventLines: [],
        }),
      },
      async () =>
        await runCompletionAssistTool({
          root: repoRoot,
          helper: 'scout',
          callerRole: 'completion-implementer',
          task: 'Assistant-only helper output must fail closed.',
          signal: new AbortController().signal,
        }),
    );

    assert.equal(assistantOnlyResult.isError, true, 'assistant-only helper output must fail closed without structured tool result');
    assert.equal(assistantOnlyResult.details.failureKind, 'invalid_output');

    const structuredToolResult = await withEnv(
      {
        PI_COMPLETION_ROLE: 'completion-implementer',
        PI_COMPLETION_TEST_HELPER_SPAWN_RESULT_JSON: JSON.stringify({
          exitCode: 0,
          assistantText: JSON.stringify({ summary: 'legacy ignored', evidence: [], paths: [], open_questions: [] }),
          eventLines: helperEmitEventLines(successOutput, 'scout'),
        }),
      },
      async () =>
        await runCompletionAssistTool({
          root: repoRoot,
          helper: 'scout',
          callerRole: 'completion-implementer',
          task: 'Require structured tool output.',
          signal: new AbortController().signal,
        }),
    );

    assert.equal(structuredToolResult.isError, false, 'structured tool-result payload must succeed');
    assert.deepEqual(JSON.parse(structuredToolResult.content[0].text), successOutput);
  });
})();
NODE

echo "helper structured output test passed"
