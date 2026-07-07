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
  assessCookHandoffStartability,
  buildCookHandoffConfirmationLayout,
  computeHandoffContentHash,
  isPendingHandoffFresh,
  isTimestampFreshEnough,
  normalizeCookHandoffCapsule,
  readHandoffFileHash,
  readPendingCookHandoff,
  resolveWorkspaceRoot,
  validateCookHandoffSchema,
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

const capsule = normalizeCookHandoffCapsule({
  kind: 'cook_handoff',
  source: 'primary_agent',
  captured_at: new Date().toISOString(),
  source_turn_id: 'test',
  mission: 'Add cursor handoff service coverage',
  scope: ['extensions/completion'],
  constraints: [],
  non_goals: [],
  acceptance: ['npm run cursor-handoff-service-test passes'],
  risks: [],
  notes: [],
  handoff_kind: 'implementation_workflow_handoff',
  why_cook_now: 'test',
});

assert.equal(validateCookHandoffSchema(capsule).ok, true);
assert.equal(isTimestampFreshEnough(capsule.captured_at), true);
assert.equal(isPendingHandoffFresh({ capturedAt: capsule.captured_at }), true);
assert.equal(isPendingHandoffFresh({}), false);

const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-service-'));
const written = await writeCookHandoffFile(tmp, capsule, { workspace_root: tmp, branch: 'cook/test' });
assert.ok(written.confirmationId);
const pending = await readPendingCookHandoff(tmp, path.basename(tmp), deps);
assert.equal(pending.state, 'pending');
assert.equal(resolvePlainCookPendingImport(pending).kind, 'import');
assert.ok(pending.proposal);
assert.ok(pending.sidecar?.handoff_sha256);
const layout = buildCookHandoffConfirmationLayout(pending.proposal);
assert.ok(layout.proposalBody.includes('cursor handoff service'));

const assessment = await assessCookHandoffStartability(tmp, capsule, path.basename(tmp), deps);
assert.equal(assessment.startable, true);

const hash = await readHandoffFileHash(tmp);
assert.equal(hash, pending.sidecar?.handoff_sha256);
assert.equal(hash, computeHandoffContentHash(await fsp.readFile(path.join(tmp, '.agent/tmp/cursor-handoff.json'), 'utf8')));

assert.throws(
  () => resolveWorkspaceRoot({ workspaceRoot: tmp, sidecar: { workspace_root: path.join(tmp, 'other') } }),
  /workspace_root mismatch/,
);

const staleTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-stale-'));
await fsp.mkdir(path.join(staleTmp, '.agent/tmp'), { recursive: true });
await fsp.writeFile(path.join(staleTmp, '.agent/tmp/cursor-handoff.json'), JSON.stringify({
  ...capsule,
  captured_at: '2000-01-01T00:00:00.000Z',
}, null, 2));
const stalePending = await readPendingCookHandoff(staleTmp, path.basename(staleTmp), deps);
assert.equal(stalePending.state, 'stale');
assert.equal(resolvePlainCookPendingImport(stalePending).kind, 'fail');

const legacyTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-legacy-'));
await fsp.mkdir(path.join(legacyTmp, '.agent/tmp'), { recursive: true });
await fsp.writeFile(path.join(legacyTmp, '.agent/tmp/cursor-handoff.json'), JSON.stringify({
  ...capsule,
  captured_at: new Date().toISOString(),
}, null, 2) + '\n');
const legacyPending = await readPendingCookHandoff(legacyTmp, path.basename(legacyTmp), deps);
assert.equal(legacyPending.state, 'pending');
assert.equal(legacyPending.sidecar?.source, 'legacy-file');

console.log('cursor-handoff-service-test passed');
NODE
