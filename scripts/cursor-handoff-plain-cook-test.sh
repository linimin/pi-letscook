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
  readPendingCookHandoff,
  resolvePlainCookPendingImport,
  writeCookHandoffFile,
} from './extensions/completion/cursor-handoff-service.ts';
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
  source_turn_id: 'plain-cook-test',
  mission: 'Plain cook pending import decision test',
  scope: ['extensions/completion'],
  constraints: [],
  non_goals: [],
  acceptance: ['plain cook test passes'],
  risks: [],
  notes: [],
  handoff_kind: 'implementation_workflow_handoff',
  why_cook_now: 'test',
};

const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'plain-cook-'));
await writeCookHandoffFile(tmp, capsule, { workspace_root: tmp });
const pending = await readPendingCookHandoff(tmp, path.basename(tmp), deps);
assert.equal(resolvePlainCookPendingImport(pending).kind, 'import');

await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.pending.json'), JSON.stringify({
  ...(pending.sidecar),
  status: 'awaiting_terminal_launch',
}, null, 2) + '\n');
const awaiting = await readPendingCookHandoff(tmp, path.basename(tmp), deps);
const awaitingDecision = resolvePlainCookPendingImport(awaiting);
assert.equal(awaitingDecision.kind, 'fail');
assert.match(awaitingDecision.error ?? '', /awaiting terminal launch/i);
assert.match(awaitingDecision.error ?? '', /\/cook <prompt>/i);

const staleTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'plain-cook-stale-'));
await fsp.mkdir(path.join(staleTmp, '.agent/tmp'), { recursive: true });
await fsp.writeFile(path.join(staleTmp, '.agent/tmp/cursor-handoff.json'), JSON.stringify({
  ...capsule,
  captured_at: '2000-01-01T00:00:00.000Z',
}, null, 2) + '\n');
const stalePending = await readPendingCookHandoff(staleTmp, path.basename(staleTmp), deps);
assert.equal(resolvePlainCookPendingImport(stalePending).kind, 'fail');

await fsp.writeFile(path.join(tmp, '.agent/tmp/cursor-handoff.pending.json'), JSON.stringify({
  ...(awaiting.sidecar),
  status: 'kickoff_started',
}, null, 2) + '\n');
const kickoffPending = await readPendingCookHandoff(tmp, path.basename(tmp), deps);
assert.equal(resolvePlainCookPendingImport(kickoffPending, { hasActiveWorkflow: true }).kind, 'ignore');
assert.equal(resolvePlainCookPendingImport(kickoffPending, { hasActiveWorkflow: false }).kind, 'fail');
assert.match(resolvePlainCookPendingImport(kickoffPending, { hasActiveWorkflow: false }).error ?? '', /cancel/i);

console.log('cursor-handoff-plain-cook-test passed');
NODE
