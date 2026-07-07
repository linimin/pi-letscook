#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

npx --prefix "$ROOT/mcp/cook-handoff" tsx <<'NODE'
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import {
  consumeCursorConfirmedKickoffEnv,
  markHandoffConfirmed,
  writeCookHandoffFile,
} from './extensions/completion/cursor-handoff-service.ts';
import { CURSOR_HANDOFF_CONFIRMED_ENV } from './extensions/completion/cursor-handoff-service.ts';

const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-kickoff-'));
const capsule = {
  kind: 'cook_handoff',
  source: 'primary_agent',
  captured_at: new Date().toISOString(),
  source_turn_id: 'kickoff-test',
  mission: 'Kickoff gate test mission',
  scope: ['src'],
  constraints: [],
  non_goals: [],
  acceptance: ['tests pass'],
  risks: [],
  notes: [],
  handoff_kind: 'implementation_workflow_handoff',
  why_cook_now: 'test',
};
const written = await writeCookHandoffFile(tmp, capsule, { workspace_root: tmp });
await markHandoffConfirmed(tmp, written.confirmationId);
const rejected = await consumeCursorConfirmedKickoffEnv(tmp, 'wrong-id');
assert.equal(rejected.accepted, false);
const accepted = await consumeCursorConfirmedKickoffEnv(tmp, written.confirmationId);
assert.equal(accepted.accepted, true);
assert.equal(CURSOR_HANDOFF_CONFIRMED_ENV, 'PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED');

await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.json'), JSON.stringify({
  ...capsule,
  mission: 'tampered mission',
}, null, 2));
const tampered = await consumeCursorConfirmedKickoffEnv(tmp, written.confirmationId);
assert.equal(tampered.accepted, false);
assert.match(tampered.reason ?? '', /changed since prepare/);

const spawnSrc = await fsp.readFile('./mcp/cook-handoff/src/spawn-pi.ts', 'utf8');
assert.match(spawnSrc, /PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED/);
assert.match(spawnSrc, /launch_required/);
assert.match(spawnSrc, /agent_terminal/);

console.log('cursor-handoff-cursor-kickoff-test passed');
NODE
