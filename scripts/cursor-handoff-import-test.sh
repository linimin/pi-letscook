#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  if (!read(file).includes(snippet)) {
    throw new Error(`${file} is missing: ${snippet}`);
  }
};

assertIncludes('extensions/completion/cursor-handoff.ts', 'DEFAULT_CURSOR_HANDOFF_PATH');
assertIncludes('extensions/completion/cursor-handoff.ts', 'loadCursorHandoffProposal');
assertIncludes('extensions/completion/cursor-handoff.ts', 'consumeCursorHandoffFile');
assertIncludes('extensions/completion/cursor-handoff.ts', 'isArchivedCursorHandoffPath');
assertIncludes('extensions/completion/driver.ts', 'cookImportHandoffPath');
assertIncludes('extensions/completion/driver.ts', 'raw === "import"');
assertIncludes('extensions/completion/driver.ts', 'importHandoffError');
assertIncludes('extensions/completion/driver.ts', 'pendingImportHandoffPath');
assertIncludes('extensions/completion/cursor-handoff.ts', 'quarantineCursorHandoffFile');
assertIncludes('extensions/completion/driver.ts', 'quarantined to');
assertIncludes('extensions/completion/index.ts', 'importHandoffError');
assertIncludes('extensions/completion/index.ts', 'loadCursorHandoffProposal');
const assertNotIncludes = (file, snippet) => {
  if (read(file).includes(snippet)) {
    throw new Error(`${file} should not include: ${snippet}`);
  }
};
assertNotIncludes('extensions/completion/index.ts', 'consumeCursorHandoffFile');
assertIncludes('extensions/completion/startup-intent.ts', 'importedHandoffProposal');
assertIncludes('cursor/skills/cursor-handoff/SKILL.md', 'cook_handoff');
assertIncludes('cursor/skills/cursor-handoff/SKILL.md', 'ensure_cook_worktree');
assertIncludes('cursor/commands/prepare-cook-handoff.md', 'start_cook_workflow');
assertIncludes('extensions/completion/cursor-handoff-service.ts', 'readPendingCookHandoff');

function cookHandoffBlockFromJsonText(raw) {
  const trimmed = raw.trim();
  if (trimmed.includes('```cook_handoff')) return trimmed;
  if (trimmed.startsWith('{')) {
    return '```cook_handoff\n' + trimmed + '\n```';
  }
  return trimmed;
}

const sample = cookHandoffBlockFromJsonText(JSON.stringify({ kind: 'cook_handoff', mission: 'test' }));
if (!sample.includes('```cook_handoff')) {
  throw new Error('cookHandoffBlockFromJsonText should wrap JSON');
}

function isArchivedCursorHandoffPath(handoffPath) {
  const base = path.basename(handoffPath);
  return base.startsWith('cursor-handoff.consumed.') || base.startsWith('cursor-handoff.quarantined.');
}

if (!isArchivedCursorHandoffPath('.agent/tmp/cursor-handoff.consumed.2026.json')) {
  throw new Error('consumed handoff paths should be archived');
}
if (!isArchivedCursorHandoffPath('.agent/tmp/cursor-handoff.quarantined.2026.json')) {
  throw new Error('quarantined handoff paths should be archived');
}
if (isArchivedCursorHandoffPath('.agent/tmp/cursor-handoff.json')) {
  throw new Error('active handoff path should not be archived');
}

console.log('cursor-handoff-import-test passed');
NODE
