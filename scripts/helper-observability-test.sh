#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function assertIncludes(file, snippet) {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required helper observability text: ${snippet}`);
  }
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const statusMod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/status-surface.ts')).href);
  const {
    createLiveRoleActivity,
    applyLiveRoleEvent,
    buildInlineRunningLines,
    buildCompletionStatusSurface,
  } = statusMod;

  assertIncludes('extensions/completion/status-surface.ts', 'if (toolName === "completion_assist") {');
  assertIncludes('extensions/completion/status-surface.ts', 'if (eventType === "tool_execution_update") {');
  assertIncludes('extensions/completion/helper-runner.ts', 'onProgress: (event) => {');
  assertIncludes('extensions/completion/helper-runner.ts', 'stage: line,');
  assertIncludes('extensions/completion/helper-runner.ts', 'message: line,');

  process.env.PI_COMPLETION_TEST_NOW = '1400';
  const activity = createLiveRoleActivity('completion-implementer', 1000);
  const messages = [];

  assert.equal(
    applyLiveRoleEvent(
      activity,
      {
        type: 'tool_execution_start',
        toolName: 'completion_assist',
        args: {
          helper: 'scout',
          task: 'Inspect extensions/completion/index.ts',
        },
        at: 1100,
      },
      messages,
    ),
    true,
    'tool start events should still be tracked under the active role',
  );

  assert.equal(
    applyLiveRoleEvent(
      activity,
      {
        type: 'tool_execution_update',
        partialResult: {
          content: [{ type: 'text', text: 'helper scout: tool: completion_helper_read' }],
          details: {
            helper: 'scout',
            stage: 'helper scout: tool: completion_helper_read',
          },
        },
        at: 1200,
      },
      messages,
    ),
    true,
    'helper tool updates should refresh live role activity',
  );

  assert.equal(
    applyLiveRoleEvent(
      activity,
      {
        type: 'tool_execution_update',
        partialResult: {
          content: [{ type: 'text', text: 'helper scout: stage: read-source' }],
          details: {
            helper: 'scout',
            stage: 'helper scout: stage: read-source',
          },
        },
        at: 1300,
      },
      messages,
    ),
    true,
    'later helper stages should replace the current nested helper preview',
  );

  const lines = buildInlineRunningLines(activity);
  assert.equal(lines[0], 'running completion role completion-implementer');
  assert.ok(lines.includes('tool: helper scout: stage: read-source'), lines);
  assert.ok(lines.includes('progress: helper scout: stage: read-source'), lines);
  assert.ok(lines.includes('recent tools:'), lines);
  assert.ok(lines.some((line) => line.includes('helper scout: tool: completion_helper_read')), lines);

  const snapshot = {
    state: {
      current_phase: 'implement',
      next_mandatory_role: 'completion-implementer',
      unsatisfied_contract_ids: ['HELPER-V1-PR2-ROLE-INTEGRATION'],
      remaining_release_blockers: 1,
      remaining_high_value_gaps: 1,
      remaining_stop_judges: 2,
    },
    active: {
      slice_id: 'helper-v1-pr2-role-integration',
      goal: 'Expose completion_assist only to the allowed completion roles with exact JSON contracts, override-resistant tool visibility, and nested helper observability.',
    },
    profile: {
      required_stop_judges: 2,
      stop_aggregation_policy: 'unanimous-current-head-v1',
    },
  };

  const surface = buildCompletionStatusSurface(snapshot, activity);
  assert.equal(surface.activeRole, 'completion-implementer');
  assert.equal(surface.livePreview, 'helper scout: stage: read-source');
  assert.equal(surface.liveProgress, 'helper scout: stage: read-source');
  assert.deepEqual(surface.widgetLines, [], 'nested helper progress must not create a second top-level widget');
  assert.ok(surface.liveDetailsLines.some((line) => line.includes('helper scout: tool: completion_helper_read')), surface.liveDetailsLines);
  assert.ok(surface.liveDetailsLines.some((line) => line.includes('tool: helper scout: stage: read-source')), surface.liveDetailsLines);
  assert.ok(surface.liveDetailsLines.some((line) => line.includes('progress: helper scout: stage: read-source')), surface.liveDetailsLines);

  delete process.env.PI_COMPLETION_TEST_NOW;
})();
NODE

echo "helper observability test passed"
