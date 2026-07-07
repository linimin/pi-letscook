#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

npx --prefix "$ROOT/mcp/cook-handoff" tsx <<'NODE'
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { appendWorkflowEvent } from './extensions/completion/workflow-events.ts';
import { getCookWorkflowStatus, pollCookWorkflowUpdates } from './extensions/completion/workflow-monitor.ts';

const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'workflow-status-'));
const missing = await getCookWorkflowStatus(tmp);
assert.ok('error' in missing);

const current = path.join(tmp, '.agent', 'current');
await fsp.mkdir(current, { recursive: true });
await fsp.writeFile(path.join(current, 'state.json'), JSON.stringify({
  mission_anchor: 'status test',
  workflow_entry_status: 'active',
  continuation_policy: 'continue',
  task_type: 'completion-workflow',
  evaluation_profile: 'completion-rubric-v1',
}, null, 2));
await fsp.writeFile(path.join(current, 'plan.json'), JSON.stringify({
  mission_anchor: 'status test',
  slices: [{ slice_id: 's1', status: 'selected', goal: 'first slice' }],
}, null, 2));
await fsp.writeFile(path.join(current, 'active-slice.json'), JSON.stringify({
  slice_id: 's1',
  status: 'selected',
  goal: 'first slice',
  mission_anchor: 'status test',
}, null, 2));
await fsp.writeFile(path.join(current, 'startup-brief.json'), JSON.stringify({
  kind: 'startup_brief',
  mission: 'status test',
  scope: [],
  constraints: [],
  acceptance: [],
  risks: [],
  notes: [],
}, null, 2));
await fsp.writeFile(path.join(current, 'verification-evidence.json'), JSON.stringify({
  goal: 'status test',
  summary: 'pending',
}, null, 2));
await fsp.writeFile(path.join(current, 'slice-history.jsonl'), '', 'utf8');
await fsp.writeFile(path.join(current, 'stop-check-history.jsonl'), '', 'utf8');

const status = await getCookWorkflowStatus(tmp);
assert.ok(!('error' in status));
assert.equal(status.mission, 'status test');
assert.equal(status.slices_total, 1);

const event = await appendWorkflowEvent(tmp, {
  kind: 'kickoff_started',
  headline: 'Kickoff started',
  detail: 'status test',
});

await fsp.writeFile(path.join(current, 'state.json'), JSON.stringify({
  mission_anchor: 'status test',
  workflow_entry_status: 'parked',
  continuation_policy: 'paused',
  task_type: 'completion-workflow',
  evaluation_profile: 'completion-rubric-v1',
  continuation_reason: 'parked for test',
}, null, 2));

const polledParked = await pollCookWorkflowUpdates({ workspaceRoot: tmp });
assert.ok(!('error' in polledParked));
assert.ok(polledParked.events.some((entry) => entry.kind === 'parked'));

const polled = await pollCookWorkflowUpdates({ workspaceRoot: tmp, sinceEventId: event.id });
assert.ok(!('error' in polled));
assert.ok(polled.events.length >= 1);
const polledAgain = await pollCookWorkflowUpdates({ workspaceRoot: tmp, sinceEventId: polled.events.at(-1)?.id });
assert.equal(polledAgain.events.length, 0);

const baselineTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'workflow-baseline-'));
const baselineCurrent = path.join(baselineTmp, '.agent', 'current');
await fsp.mkdir(baselineCurrent, { recursive: true });
await fsp.writeFile(path.join(baselineCurrent, 'state.json'), JSON.stringify({
  mission_anchor: 'baseline test',
  workflow_entry_status: 'active',
  continuation_policy: 'continue',
  task_type: 'completion-workflow',
  evaluation_profile: 'completion-rubric-v1',
}, null, 2));
await fsp.writeFile(path.join(baselineCurrent, 'plan.json'), JSON.stringify({
  mission_anchor: 'baseline test',
  candidate_slices: [],
}, null, 2));
await fsp.writeFile(path.join(baselineCurrent, 'active-slice.json'), JSON.stringify({
  mission_anchor: 'baseline test',
  status: 'planned',
}, null, 2));
await fsp.writeFile(path.join(baselineCurrent, 'startup-brief.json'), JSON.stringify({
  kind: 'startup_brief',
  mission: 'baseline test',
  scope: [],
  constraints: [],
  acceptance: [],
  risks: [],
  notes: [],
}, null, 2));
await fsp.writeFile(path.join(baselineCurrent, 'verification-evidence.json'), JSON.stringify({
  goal: 'baseline test',
  summary: 'pending',
}, null, 2));
await fsp.writeFile(path.join(baselineCurrent, 'slice-history.jsonl'), '', 'utf8');
await fsp.writeFile(path.join(baselineCurrent, 'stop-check-history.jsonl'), '', 'utf8');
const baselinePoll = await pollCookWorkflowUpdates({ workspaceRoot: baselineTmp });
assert.ok(!('error' in baselinePoll));
assert.ok(baselinePoll.events.some((entry) => entry.kind === 'workflow_active'));

console.log('cursor-handoff-workflow-status-test passed');
NODE
