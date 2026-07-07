#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

npx --prefix "$ROOT/mcp/cook-handoff" tsx <<'NODE'
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { handleCookHandoffTool } from './mcp/cook-handoff/src/tools.ts';
import { readCookHandoffSidecar, readPendingCookHandoff } from './extensions/completion/cursor-handoff-service.ts';
import {
  assessMissionAnchor,
  isWeakMissionAnchor,
  missionAnchorsStrictlyEquivalent,
  normalizeMissionAnchorText,
  stripCodeBlocks,
} from './extensions/completion/proposal.ts';

const deps = {
  asString: (v) => typeof v === 'string' && v.trim() ? v.trim() : undefined,
  asStringArray: (v) => Array.isArray(v) ? v.filter((x) => typeof x === 'string' && x.trim()) : [],
  assessMissionAnchor,
  normalizeMissionAnchorText,
  isWeakMissionAnchor,
  missionAnchorsStrictlyEquivalent,
  stripCodeBlocks,
};

const capsule = {
  kind: 'cook_handoff',
  source: 'primary_agent',
  captured_at: new Date().toISOString(),
  source_turn_id: 'mcp-test',
  mission: 'MCP tool chain test mission',
  scope: ['mcp/cook-handoff'],
  constraints: [],
  non_goals: [],
  acceptance: ['MCP tests pass'],
  risks: [],
  notes: [],
  handoff_kind: 'implementation_workflow_handoff',
  why_cook_now: 'test',
};

const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-mcp-'));
const other = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-mcp-other-'));

const prepared = JSON.parse((await handleCookHandoffTool('prepare_cook_handoff', {
  workspace_root: tmp,
  capsule,
})).content[0].text);
assert.equal(prepared.ok, true);

await fsp.mkdir(path.join(other, '.agent/tmp'), { recursive: true });
await fsp.copyFile(
  path.join(tmp, '.agent/tmp/cursor-handoff.pending.json'),
  path.join(other, '.agent/tmp/cursor-handoff.pending.json'),
);
const mismatch = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: other,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
})).content[0].text);
assert.equal(mismatch.ok, false);
assert.equal(mismatch.code, 'workspace_root_mismatch');

const preview = JSON.parse((await handleCookHandoffTool('preview_cook_handoff_confirmation', {
  workspace_root: tmp,
})).content[0].text);
assert.equal(preview.ok, true);
assert.ok(preview.handoff_sha256);

const originalHandoff = await fsp.readFile(path.join(tmp, '.agent/tmp/cursor-handoff.json'), 'utf8');
await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.json'), JSON.stringify({
  ...capsule,
  mission: 'tampered mission',
}, null, 2));
const tamperedPreview = JSON.parse((await handleCookHandoffTool('preview_cook_handoff_confirmation', {
  workspace_root: tmp,
})).content[0].text);
assert.equal(tamperedPreview.ok, false);
assert.equal(tamperedPreview.code, 'handoff_integrity_mismatch');

const tamperedDryRun = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
  dry_run: true,
})).content[0].text);
assert.equal(tamperedDryRun.ok, false);
assert.equal(tamperedDryRun.code, 'handoff_integrity_mismatch');

await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.json'), originalHandoff);
const dryRun = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
  dry_run: true,
})).content[0].text);
assert.equal(dryRun.ok, true);
assert.equal((await readCookHandoffSidecar(tmp))?.status, 'pending_review');

const started = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
})).content[0].text);
assert.equal(started.ok, true);
assert.equal(started.monitoring.enabled, false);
assert.equal(started.monitoring.awaiting_terminal_launch, true);
assert.equal((await readCookHandoffSidecar(tmp))?.status, 'awaiting_terminal_launch');

const awaiting = await readPendingCookHandoff(tmp, path.basename(tmp), deps);
assert.equal(awaiting.state, 'awaiting_launch');

const retry = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
})).content[0].text);
assert.equal(retry.ok, true);
assert.ok((await readCookHandoffSidecar(tmp))?.confirmed_at);

const spawnFailTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-spawn-fail-'));
const preparedFail = JSON.parse((await handleCookHandoffTool('prepare_cook_handoff', {
  workspace_root: spawnFailTmp,
  capsule,
})).content[0].text);
const previousBinary = process.env.PI_BINARY;
process.env.PI_BINARY = '/definitely-missing-pi-binary';
const spawnFailed = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: spawnFailTmp,
  confirmation_id: preparedFail.confirmation_id,
  action: 'start',
  spawn_mode: 'background',
})).content[0].text);
if (previousBinary === undefined) delete process.env.PI_BINARY;
else process.env.PI_BINARY = previousBinary;
assert.equal(spawnFailed.ok, false);
assert.equal(spawnFailed.code, 'spawn_failed');
const failedSidecar = await readCookHandoffSidecar(spawnFailTmp);
assert.equal(failedSidecar?.status, 'confirmed');
assert.ok(failedSidecar?.last_spawn_error);

await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.pending.json'), JSON.stringify({
  ...(await readCookHandoffSidecar(tmp)),
  status: 'kickoff_started',
}, null, 2) + '\n');
const recovered = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  confirmation_id: prepared.confirmation_id,
  action: 'start',
})).content[0].text);
assert.equal(recovered.ok, true);
assert.equal((await readCookHandoffSidecar(tmp))?.status, 'awaiting_terminal_launch');

const blockedTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-blocked-'));
const blockedPrepared = JSON.parse((await handleCookHandoffTool('prepare_cook_handoff', {
  workspace_root: blockedTmp,
  capsule,
})).content[0].text);
const blockedCurrent = path.join(blockedTmp, '.agent', 'current');
await fsp.mkdir(blockedCurrent, { recursive: true });
await fsp.writeFile(path.join(blockedCurrent, 'state.json'), JSON.stringify({
  mission_anchor: 'blocked test',
  workflow_entry_status: 'active',
  continuation_policy: 'continue',
}, null, 2));
await fsp.writeFile(path.join(blockedCurrent, 'plan.json'), JSON.stringify({ mission_anchor: 'blocked test', candidate_slices: [] }, null, 2));
await fsp.writeFile(path.join(blockedCurrent, 'active-slice.json'), JSON.stringify({ mission_anchor: 'blocked test', status: 'planned' }, null, 2));
await fsp.writeFile(path.join(blockedCurrent, 'startup-brief.json'), JSON.stringify({
  kind: 'startup_brief',
  mission: 'blocked test',
  scope: [],
  constraints: [],
  acceptance: [],
  risks: [],
  notes: [],
}, null, 2));
await fsp.writeFile(path.join(blockedCurrent, 'verification-evidence.json'), JSON.stringify({ goal: 'blocked test', summary: 'pending' }, null, 2));
await fsp.writeFile(path.join(blockedCurrent, 'slice-history.jsonl'), '', 'utf8');
await fsp.writeFile(path.join(blockedCurrent, 'stop-check-history.jsonl'), '', 'utf8');
await fsp.writeFile(path.join(blockedTmp, '.agent/tmp/cursor-handoff.pending.json'), JSON.stringify({
  ...(await readCookHandoffSidecar(blockedTmp)),
  status: 'kickoff_started',
}, null, 2) + '\n');
const blockedWithWorkflow = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: blockedTmp,
  confirmation_id: blockedPrepared.confirmation_id,
  action: 'start',
})).content[0].text);
assert.equal(blockedWithWorkflow.ok, false);
assert.equal(blockedWithWorkflow.code, 'kickoff_already_started');

const cancelled = JSON.parse((await handleCookHandoffTool('start_cook_workflow', {
  workspace_root: tmp,
  action: 'cancel',
})).content[0].text);
assert.equal(cancelled.ok, true);
assert.equal(cancelled.cancelled, true);

console.log('cursor-handoff-mcp-test passed');
NODE
