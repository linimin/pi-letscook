#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

npx --prefix "$ROOT/mcp/cook-handoff" tsx <<'NODE'
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ensureCookWorktree } from './mcp/cook-handoff/src/worktree.ts';
import { writeCookHandoffFile } from './extensions/completion/cursor-handoff-service.ts';

const parent = await fsp.mkdtemp(path.join(os.tmpdir(), 'handoff-worktree-parent-'));
spawnSync('git', ['init'], { cwd: parent, stdio: 'ignore' });
spawnSync('git', ['config', 'user.email', 'test@example.com'], { cwd: parent, stdio: 'ignore' });
spawnSync('git', ['config', 'user.name', 'Test'], { cwd: parent, stdio: 'ignore' });
await fsp.writeFile(path.join(parent, 'README.md'), '# test\n', 'utf8');
spawnSync('git', ['add', 'README.md'], { cwd: parent, stdio: 'ignore' });
spawnSync('git', ['commit', '-m', 'init'], { cwd: parent, stdio: 'ignore' });

const first = await ensureCookWorktree({ repoRoot: parent, branch: 'cook/demo', slug: 'demo' });
assert.equal(first.created, true);
assert.ok(first.workspace_root.includes('.worktrees/cook-demo'));

const capsule = {
  kind: 'cook_handoff',
  source: 'primary_agent',
  captured_at: new Date().toISOString(),
  source_turn_id: 'wt-test',
  mission: 'Worktree handoff isolation test',
  scope: ['README.md'],
  constraints: [],
  non_goals: [],
  acceptance: ['worktree test passes'],
  risks: [],
  notes: [],
  handoff_kind: 'implementation_workflow_handoff',
  why_cook_now: 'test',
};
await writeCookHandoffFile(first.workspace_root, capsule, { workspace_root: first.workspace_root, branch: 'cook/demo' });
assert.ok(await fsp.access(path.join(first.workspace_root, '.agent/tmp/cursor-handoff.json')).then(() => true).catch(() => false));
assert.equal(await fsp.access(path.join(parent, '.agent/tmp/cursor-handoff.json')).then(() => true).catch(() => false), false);

const second = await ensureCookWorktree({ repoRoot: parent, branch: 'cook/demo', slug: 'demo' });
assert.equal(second.created, false);
assert.equal(path.resolve(second.workspace_root), path.resolve(first.workspace_root));

console.log('cursor-handoff-worktree-test passed');
NODE
