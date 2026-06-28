#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');

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

function eventLinesForHelper(details, toolName = 'completion_helper_emit_scout_result', contractId = 'completion.helper.scout.v1') {
  const toolCallId = 'call-structured-1';
  return [
    JSON.stringify({ type: 'tool_execution_start', toolName, toolCallId }),
    JSON.stringify({
      type: 'tool_execution_end',
      toolName,
      toolCallId,
      result: {
        content: [{ type: 'text', text: details.summary }],
        details: {
          contractId,
          schemaVersion: 1,
          ...details,
        },
      },
    }),
  ];
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const { pathToFileURL } = require('node:url');
  const path = require('node:path');
  const wiringMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/structured-subprocess-wiring.ts')).href);
  const { appendStructuredToolsToPiArgs, completionStructuredToolsExtensionPath, resolveCookHandoffSubprocessResult } = wiringMod;

  const structuredExtension = completionStructuredToolsExtensionPath();
  const headroomArgs = appendStructuredToolsToPiArgs(
    ['--mode', 'json', '-p', '--no-session', '--no-extensions', '--extension', '/tmp/headroom-extension.ts', '--tools', 'read'],
    ['completion_emit_startup_analysis'],
  );
  assert.ok(headroomArgs.includes('--no-extensions'), 'appendStructuredToolsToPiArgs must keep --no-extensions');
  assert.equal(headroomArgs.filter((arg) => arg === '--extension' || arg === '-e').length, 2, 'headroom plus structured extension should both load');
  assert.ok(headroomArgs.includes(structuredExtension), 'structured-tools extension must be appended alongside existing extensions');
  assert.match(headroomArgs[headroomArgs.indexOf('--tools') + 1], /completion_emit_startup_analysis/, 'emit tools must merge into --tools');

  const dedupedArgs = appendStructuredToolsToPiArgs(
    ['--no-extensions', '-e', structuredExtension],
    ['completion_emit_startup_analysis'],
  );
  assert.equal(dedupedArgs.filter((arg) => arg === structuredExtension).length, 1, 'structured extension must not be duplicated');

  const finalOutputMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/subprocess-final-output.ts')).href);
  const contractsMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/structured-contracts.ts')).href);
  const helperRunnerMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-runner.ts')).href);
  const renderersMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/structured-renderers.ts')).href);

  const {
    extractSubprocessFinalOutput,
    requireSubprocessFinalOutput,
    StructuredSubprocessOutputError,
  } = finalOutputMod;
  const { COMPLETION_HELPER_SCOUT_CONTRACT_ID, HELPER_EMIT_SCOUT_TOOL } = contractsMod;
  const { resolveStructuredHelperOutput } = helperRunnerMod;
  const { renderReviewerReport } = renderersMod;

  const structuredDetails = {
    summary: 'structured scout summary',
    evidence: ['found evidence'],
    paths: ['README.md'],
    open_questions: ['none'],
  };
  const lines = eventLinesForHelper(structuredDetails);

  const structuredResult = extractSubprocessFinalOutput({
    eventLines: lines,
    contractId: COMPLETION_HELPER_SCOUT_CONTRACT_ID,
    assistantText: JSON.stringify({ summary: 'ignored', evidence: [], paths: [], open_questions: [] }),
  });
  assert.equal(structuredResult.source, 'structured_tool');
  assert.equal(structuredResult.payload.summary, structuredDetails.summary);

  assert.throws(
    () =>
      requireSubprocessFinalOutput({
        eventLines: [],
        contractId: COMPLETION_HELPER_SCOUT_CONTRACT_ID,
        assistantText: JSON.stringify(structuredDetails),
      }),
    StructuredSubprocessOutputError,
  );

  const invalidResult = extractSubprocessFinalOutput({
    eventLines: [
      JSON.stringify({
        type: 'tool_execution_end',
        toolName: HELPER_EMIT_SCOUT_TOOL,
        toolCallId: 'bad',
        result: { details: { summary: 'missing arrays' } },
      }),
    ],
    contractId: COMPLETION_HELPER_SCOUT_CONTRACT_ID,
    assistantText: JSON.stringify(structuredDetails),
  });
  assert.equal(invalidResult.payload, undefined);
  assert.ok(invalidResult.diagnostics.length > 0);

  assert.throws(
    () =>
      resolveStructuredHelperOutput({
        helper: 'scout',
        eventLines: [],
        assistantText: JSON.stringify(structuredDetails),
      }),
    /missing terminating tool result/,
  );

  const resolved = resolveStructuredHelperOutput({
    helper: 'scout',
    eventLines: lines,
    assistantText: JSON.stringify({ summary: 'ignored', evidence: [], paths: [], open_questions: [] }),
  });
  assert.equal(resolved.summary, structuredDetails.summary);

  const reviewerText = renderReviewerReport({
    contractId: 'completion.evaluator.reviewer.v1',
    schemaVersion: 1,
    missionAnchor: 'ship structured output',
    remainingContractIds: 'C-1',
    rubric: [
      { dimension: 'Contract coverage', verdict: 'pass', explanation: 'complete' },
      { dimension: 'Correctness risk', verdict: 'pass', explanation: 'low' },
      { dimension: 'Verification evidence', verdict: 'pass', explanation: 'covered' },
      { dimension: 'Docs/state parity', verdict: 'pass', explanation: 'aligned' },
    ],
    fields: {
      Findings: 'none',
      'Acceptable as-is': 'yes',
      'Smallest follow-up slice': 'none',
    },
  });
  assert.match(reviewerText, /^MISSION ANCHOR: ship structured output/m);
  assert.match(reviewerText, /^Rubric:\s*$/m);
  assert.match(reviewerText, /Acceptable as-is: yes/);

  const {
    COMPLETION_ROLE_REGROUNDER_CONTRACT_ID,
    COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
    EMIT_REGROUNDER_RECONCILIATION_TOOL,
    EMIT_IMPLEMENTER_HANDOFF_TOOL,
  } = contractsMod;

  function eventLinesForRoleHandoff(details, toolName, contractId) {
    const toolCallId = 'call-role-handoff';
    return [
      JSON.stringify({ type: 'tool_execution_start', toolName, toolCallId }),
      JSON.stringify({
        type: 'tool_execution_end',
        toolName,
        toolCallId,
        result: {
          content: [{ type: 'text', text: 'role handoff emitted' }],
          details: {
            contractId,
            schemaVersion: 1,
            fields: details,
          },
        },
      }),
    ];
  }

  const regrounderFields = {
    'Remaining contract IDs': 'C-1',
    'Canonical re-ground applied': 'yes - reconciled plan',
    'Acceptance criteria revalidated': 'yes - all slices checked',
    'Tracked and unignored worktree is clean': 'yes',
    'Reopened slices': 'none',
    'Reconciliation decision': 'none',
    'Reconciled slice ID': 'none',
    'Current selected slice': 'slice-1',
    'Next role to invoke': 'completion-implementer',
    'Exact handoff payload': 'implement slice-1',
    'Canonical blockers or deviations': 'none',
  };

  const regrounderMissingHeader = extractSubprocessFinalOutput({
    eventLines: eventLinesForRoleHandoff(
      regrounderFields,
      EMIT_REGROUNDER_RECONCILIATION_TOOL,
      COMPLETION_ROLE_REGROUNDER_CONTRACT_ID,
    ),
    contractId: COMPLETION_ROLE_REGROUNDER_CONTRACT_ID,
  });
  assert.equal(regrounderMissingHeader.payload, undefined);
  assert.ok(
    regrounderMissingHeader.diagnostics.some((message) => message.includes('missing required field: MISSION ANCHOR')),
    `expected MISSION ANCHOR validation failure, got: ${regrounderMissingHeader.diagnostics.join('; ')}`,
  );

  const implementerFields = {
    'MISSION ANCHOR': 'ship structured output',
    'Slice ID': 'slice-1',
    'Contract IDs closed or advanced': 'C-1',
    'Files changed': 'src/example.ts',
    'Tests added or strengthened': 'scripts/subprocess-structured-output-test.sh',
    'Verification commands run': 'npm run subprocess-structured-output-test',
    'Verification results': 'pass',
    'Commit SHA': 'abc1234',
    'What release gap this closed': 'structured validation',
    'Plan adjustment required': 'no - on track',
    'Residual risks discovered': 'none',
    'Remaining contract IDs after slice': 'none',
  };

  const implementerMissingBeforeSlice = extractSubprocessFinalOutput({
    eventLines: eventLinesForRoleHandoff(
      implementerFields,
      EMIT_IMPLEMENTER_HANDOFF_TOOL,
      COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
    ),
    contractId: COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
  });
  assert.equal(implementerMissingBeforeSlice.payload, undefined);
  assert.ok(
    implementerMissingBeforeSlice.diagnostics.some((message) =>
      message.includes('missing required field: Remaining contract IDs before slice'),
    ),
    `expected before-slice validation failure, got: ${implementerMissingBeforeSlice.diagnostics.join('; ')}`,
  );

  const implementerMissingGoal = extractSubprocessFinalOutput({
    eventLines: eventLinesForRoleHandoff(
      {
        ...implementerFields,
        'Remaining contract IDs before slice': 'C-1',
      },
      EMIT_IMPLEMENTER_HANDOFF_TOOL,
      COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
    ),
    contractId: COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
  });
  assert.equal(implementerMissingGoal.payload, undefined);
  assert.ok(
    implementerMissingGoal.diagnostics.some((message) => message.includes('missing required field: Slice goal')),
    `expected Slice goal validation failure, got: ${implementerMissingGoal.diagnostics.join('; ')}`,
  );

  const implementerComplete = extractSubprocessFinalOutput({
    eventLines: eventLinesForRoleHandoff(
      {
        ...implementerFields,
        'Remaining contract IDs before slice': 'C-1',
        'Slice goal': 'tighten structured role-handoff validation',
      },
      EMIT_IMPLEMENTER_HANDOFF_TOOL,
      COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
    ),
    contractId: COMPLETION_ROLE_IMPLEMENTER_CONTRACT_ID,
  });
  assert.ok(implementerComplete.payload, 'complete implementer handoff should parse');
  assert.equal(implementerComplete.payload.fields['Slice goal'], 'tighten structured role-handoff validation');

  const {
    COMPLETION_COOK_HANDOFF_CONTRACT_ID,
    EMIT_COOK_HANDOFF_TOOL,
  } = contractsMod;

  function eventLinesForCookHandoff(capsule) {
    const toolCallId = 'call-cook-handoff';
    return [
      JSON.stringify({ type: 'tool_execution_start', toolName: EMIT_COOK_HANDOFF_TOOL, toolCallId }),
      JSON.stringify({
        type: 'tool_execution_end',
        toolName: EMIT_COOK_HANDOFF_TOOL,
        toolCallId,
        result: {
          content: [{ type: 'text', text: 'cook handoff emitted' }],
          details: {
            contractId: COMPLETION_COOK_HANDOFF_CONTRACT_ID,
            schemaVersion: 1,
            capsule,
          },
        },
      }),
    ];
  }

  const unableToPrepare = resolveCookHandoffSubprocessResult({
    eventLines: eventLinesForCookHandoff({
      kind: 'cook_handoff',
      source: 'primary_agent',
      handoff_kind: 'unable_to_prepare',
      reason: 'discussion is planning-only',
    }),
  });
  assert.deepEqual(unableToPrepare, {
    kind: 'no_handoff',
    reason: 'discussion is planning-only',
  });

  const startableHandoff = resolveCookHandoffSubprocessResult({
    eventLines: eventLinesForCookHandoff({
      kind: 'cook_handoff',
      source: 'primary_agent',
      handoff_kind: 'implementation_workflow_handoff',
      mission: 'ship structured cook handoff observability',
      captured_at: '2026-01-01T00:00:00.000Z',
      source_turn_id: 'test-turn',
    }),
  });
  assert.equal(startableHandoff.kind, 'handoff');
  assert.match(startableHandoff.text, /```cook_handoff/);
  assert.match(startableHandoff.text, /ship structured cook handoff observability/);

  console.log('subprocess structured output test passed');
})();
NODE

echo "subprocess structured output test passed"
