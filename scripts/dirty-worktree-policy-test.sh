#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required dirty-worktree policy text: ${snippet}`);
  }
};

assertIncludes('skills/completion-protocol/SKILL.md', 'auto-preserve them with a reversible mechanism such as a named git stash plus a `.agent/current/tmp/dirty-worktree-autostash.json` note');
assertIncludes('skills/completion-protocol/SKILL.md', 'Ask the user only when overlap, ownership ambiguity, or stash/restore conflicts make automatic isolation unsafe.');
assertIncludes('skills/completion-protocol/references/completion.md', 'Dirty-worktree auto-reconcile. If tracked worktree dirt is unrelated to the latest slice or current reconciliation surfaces and can be isolated safely');
assertIncludes('agents/completion-regrounder.md', 'Do not ask the user for this routine unrelated-dirty-worktree case.');
assertIncludes('agents/completion-implementer.md', 'auto-preserve them yourself with a reversible mechanism such as a named git stash plus a `.agent/current/tmp/dirty-worktree-autostash.json` note');
assertIncludes('docs/PROTOCOL.md', 'Active `/cook` workflows now also auto-reconcile routine unrelated tracked worktree dirt instead of bouncing that decision back to the user.');
assertIncludes('CHANGELOG.md', 'auto-preserve routine unrelated tracked worktree dirt with a reversible stash-plus-note flow');
NODE

echo "dirty-worktree policy test passed"
