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

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function assertIncludes(file, snippet) {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required helper role-gating text: ${snippet}`);
  }
}

async function withEnv(name, value, fn) {
  const previous = process.env[name];
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
  try {
    return await fn();
  } finally {
    if (previous === undefined) delete process.env[name];
    else process.env[name] = previous;
  }
}

async function withTempDir(run) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'pi-letscook-helper-role-gating-'));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const helperPolicyMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-policy.ts')).href);
  const helperRunnerMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-runner.ts')).href);

  const {
    canRoleUseCompletionAssist,
    COMPLETION_ASSIST_TOOL_NAME,
    effectiveRoleToolAllowlist,
    resolveEffectiveCompletionRoleModel,
    buildCompletionRoleSubprocessEnv,
  } = helperPolicyMod;
  const { runCompletionHelper } = helperRunnerMod;

  assertIncludes('extensions/completion/index.ts', 'if (canRoleUseCompletionAssist(activeCompletionRole)) {');
  assertIncludes('extensions/completion/index.ts', 'name: COMPLETION_ASSIST_TOOL_NAME');
  assertIncludes('extensions/completion/index.ts', 'roleModel: roleModelFromEnv(),');
  assertIncludes('extensions/completion/index.ts', 'requestedModel: modelArgFromContextModel((ctx as { model?: unknown }).model),');
  assertIncludes('extensions/completion/helper-policy.ts', 'export function effectiveRoleToolAllowlist(');
  assertIncludes('extensions/completion/helper-policy.ts', 'export function resolveEffectiveCompletionRoleModel(');
  assertIncludes('extensions/completion/helper-policy.ts', 'export function buildCompletionRoleSubprocessEnv(');
  assertIncludes('extensions/completion/role-runner.ts', 'effectiveRoleToolAllowlist(params.role, agent.tools)');
  assertIncludes('extensions/completion/role-runner.ts', 'resolveEffectiveCompletionRoleModel(agent.model, params.requestedModel)');
  assertIncludes('extensions/completion/role-runner.ts', 'buildCompletionRoleSubprocessEnv(params.role, roleModel)');
  assertIncludes('extensions/completion/helper-runner.ts', 'asString(process.env.PI_COMPLETION_ROLE_MODEL)');
  assertIncludes('extensions/completion/policy-guards.ts', 'completion_assist may only be used while the canonical /cook workflow is active.');
  assertIncludes('agents/completion-implementer.md', 'tools: read,grep,find,ls,bash,write,edit,completion_assist');
  assertIncludes('agents/completion-regrounder.md', 'tools: read,grep,find,ls,bash,write,edit,completion_assist');

  assert.equal(COMPLETION_ASSIST_TOOL_NAME, 'completion_assist');
  assert.equal(canRoleUseCompletionAssist('completion-implementer'), true, 'implementer must stay helper-eligible');
  assert.equal(canRoleUseCompletionAssist('completion-regrounder'), true, 'regrounder must stay helper-eligible');
  assert.equal(canRoleUseCompletionAssist('completion-reviewer'), false, 'reviewer must remain helper-ineligible');
  assert.equal(canRoleUseCompletionAssist(undefined), false, 'ordinary chat must remain helper-ineligible');

  assert.deepEqual(
    effectiveRoleToolAllowlist('completion-implementer', ['read', 'edit']),
    ['read', 'edit', 'completion_assist'],
    'allowed roles must force-union completion_assist into the effective allowlist',
  );
  assert.deepEqual(
    effectiveRoleToolAllowlist('completion-regrounder', ['read', 'completion_assist', 'grep']),
    ['read', 'completion_assist', 'grep'],
    'allowed roles must not duplicate completion_assist when it is already declared',
  );
  assert.deepEqual(
    effectiveRoleToolAllowlist('completion-reviewer', ['read', 'completion_assist', 'grep']),
    ['read', 'grep'],
    'disallowed roles must not gain completion_assist from prompt overrides',
  );
  assert.deepEqual(
    effectiveRoleToolAllowlist('completion-implementer', []),
    ['completion_assist'],
    'allowed roles with an explicit empty tool list must still see completion_assist',
  );

  assert.equal(
    resolveEffectiveCompletionRoleModel('anthropic/claude-3.7', 'openai/gpt-5'),
    'anthropic/claude-3.7',
    'pinned role frontmatter model must take precedence',
  );
  assert.equal(
    resolveEffectiveCompletionRoleModel(undefined, 'openai/gpt-5'),
    'openai/gpt-5',
    'requested role model must propagate when the role prompt is unpinned',
  );
  assert.equal(
    resolveEffectiveCompletionRoleModel(undefined, undefined),
    undefined,
    'model propagation must stay optional when no effective role model is known',
  );

  const capturedEnv = await withEnv('PI_COMPLETION_HELPER', 'scout', async () => await withEnv('PI_COMPLETION_HELPER_ROOT', '/tmp/outside', async () => buildCompletionRoleSubprocessEnv('completion-implementer', 'openai/gpt-5')));
  assert.equal(capturedEnv.PI_COMPLETION_ROLE, 'completion-implementer');
  assert.equal(capturedEnv.PI_COMPLETION_ROLE_MODEL, 'openai/gpt-5');
  assert.equal(capturedEnv.PI_COMPLETION_HELPER, undefined, 'authoritative role env must not leak helper-only env');
  assert.equal(capturedEnv.PI_COMPLETION_HELPER_ROOT, undefined, 'authoritative role env must clear helper boundary env');

  const capturedEnvWithoutModel = buildCompletionRoleSubprocessEnv('completion-regrounder');
  assert.equal(capturedEnvWithoutModel.PI_COMPLETION_ROLE, 'completion-regrounder');
  assert.equal(capturedEnvWithoutModel.PI_COMPLETION_ROLE_MODEL, undefined, 'role model env must stay absent when unknown');

  await withTempDir(async (tmpRoot) => {
    const repoRoot = path.join(tmpRoot, 'repo');
    await fsp.mkdir(path.join(repoRoot, '.agent', 'current', 'tmp'), { recursive: true });

    let disallowedSpawned = false;
    const disallowed = await runCompletionHelper({
      root: repoRoot,
      helper: 'scout',
      callerRole: 'completion-reviewer',
      task: 'This reviewer should never gain helper authority.',
      runId: 'reviewer-blocked',
      subprocessRunner: async () => {
        disallowedSpawned = true;
        return {
          exitCode: 0,
          assistantText: JSON.stringify({ summary: 'unexpected', evidence: [], paths: [], open_questions: [] }),
          eventLines: [],
        };
      },
    });
    assert.equal(disallowed.ok, false, 'disallowed roles must fail closed before helper subprocess launch');
    assert.equal(disallowed.failureKind, 'policy');
    assert.equal(disallowedSpawned, false, 'disallowed roles must not reach the helper subprocess');

    const ordinaryChatVisible = canRoleUseCompletionAssist(undefined);
    const implementerVisible = canRoleUseCompletionAssist('completion-implementer');
    const regrounderVisible = canRoleUseCompletionAssist('completion-regrounder');
    const reviewerVisible = canRoleUseCompletionAssist('completion-reviewer');
    const stopJudgeVisible = canRoleUseCompletionAssist('completion-stop-judge');
    assert.equal(ordinaryChatVisible, false, 'ordinary chat must not gain completion_assist visibility');
    assert.equal(implementerVisible, true, 'implementer must retain completion_assist visibility');
    assert.equal(regrounderVisible, true, 'regrounder must retain completion_assist visibility');
    assert.equal(reviewerVisible, false, 'reviewer must remain helper-blind');
    assert.equal(stopJudgeVisible, false, 'stop judge must remain helper-blind');
  });
})();
NODE

echo "helper role gating test passed"
