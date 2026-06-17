#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKGTST_ROOT="$ROOT" node --no-warnings <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

async function withTempDir(run) {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'pi-letscook-helper-boundary-'));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

function utf8Length(value) {
  return Buffer.byteLength(value, 'utf8');
}

async function assertRejectsContains(fn, needle) {
  let message = '';
  try {
    await fn();
  } catch (error) {
    message = error && error.message ? error.message : String(error);
  }
  assert.ok(message, `expected rejection containing ${needle}`);
  assert.ok(message.includes(needle), `expected rejection containing ${needle}, got: ${message}`);
}

(async () => {
  const pkgRoot = process.env.PKGTST_ROOT;
  const mod = await import(pathToFileURL(path.join(pkgRoot, 'extensions/completion/helper-proxy-tools.ts')).href);
  const {
    executeHelperRead,
    executeHelperGrep,
    executeHelperFind,
    executeHelperLs,
  } = mod;

  await withTempDir(async (tmpRoot) => {
    const repoRoot = path.join(tmpRoot, 'repo');
    const outsideRoot = path.join(tmpRoot, 'outside');
    await fsp.mkdir(path.join(repoRoot, 'subdir'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'many'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'a-dir'), { recursive: true });
    await fsp.mkdir(path.join(repoRoot, 'z-dir'), { recursive: true });
    await fsp.mkdir(path.join(outsideRoot, 'escape-dir'), { recursive: true });

    await fsp.writeFile(path.join(repoRoot, 'top.txt'), 'root-line-1\nneedle root\nroot-line-3\n', 'utf8');
    await fsp.writeFile(path.join(repoRoot, 'subdir', 'local.txt'), 'needle local\n', 'utf8');
    await fsp.writeFile(path.join(repoRoot, 'a-match.txt'), 'needle-path-sort first\n', 'utf8');
    await fsp.writeFile(path.join(repoRoot, 'z-match.txt'), 'needle-path-sort second\n', 'utf8');
    await fsp.writeFile(path.join(outsideRoot, 'outside.txt'), 'outside secret\n', 'utf8');
    await fsp.writeFile(path.join(outsideRoot, 'escape-dir', 'nested.txt'), 'outside dir secret\n', 'utf8');
    await fsp.symlink(path.join(outsideRoot, 'outside.txt'), path.join(repoRoot, 'escape-file.txt'));
    await fsp.symlink(path.join(outsideRoot, 'escape-dir'), path.join(repoRoot, 'escape-dir'));

    const hugeLines = Array.from({ length: 260 }, (_, index) => `line-${String(index + 1).padStart(3, '0')}-` + 'x'.repeat(180));
    await fsp.writeFile(path.join(repoRoot, 'huge.txt'), hugeLines.join('\n') + '\n', 'utf8');

    const grepLines = [];
    for (let index = 0; index < 120; index += 1) {
      grepLines.push(`needle-${String(index).padStart(3, '0')}-` + 'y'.repeat(320));
    }
    await fsp.writeFile(path.join(repoRoot, 'grep-many.txt'), grepLines.join('\n') + '\n', 'utf8');

    for (let index = 0; index < 220; index += 1) {
      const fileName = `file-${String(index).padStart(3, '0')}.txt`;
      await fsp.writeFile(path.join(repoRoot, 'many', fileName), `many-${index}\n`, 'utf8');
    }

    const env = {
      ...process.env,
      PI_COMPLETION_HELPER_ROOT: repoRoot,
      PI_COMPLETION_HELPER_CWD: path.join(repoRoot, 'subdir'),
    };

    const readRootFile = await executeHelperRead({ path: 'top.txt', offset: 2, limit: 2 }, env);
    assert.equal(readRootFile.path, 'top.txt');
    assert.equal(readRootFile.startLine, 2);
    assert.equal(readRootFile.endLine, 3);
    assert.equal(readRootFile.content, 'needle root\nroot-line-3');
    assert.equal(readRootFile.truncated, false);

    const readHuge = await executeHelperRead({ path: 'huge.txt', limit: 999 }, env);
    assert.equal(readHuge.path, 'huge.txt');
    assert.equal(readHuge.startLine, 1);
    assert.equal(readHuge.endLine, 200, 'read limit should clamp to 200 lines');
    assert.equal(readHuge.truncated, true, 'huge read should report truncation');
    assert.ok(utf8Length(readHuge.content) <= 24 * 1024, 'read content must stay within 24 KiB');

    await assertRejectsContains(() => executeHelperRead({ path: '/etc/passwd' }, env), 'repo-relative, not absolute');
    await assertRejectsContains(() => executeHelperRead({ path: '../outside.txt' }, env), 'parent segments');
    await assertRejectsContains(() => executeHelperRead({ path: 'escape-file.txt' }, env), 'symlink or realpath');

    const grepSorted = await executeHelperGrep({ pattern: 'needle-path-sort' }, env);
    assert.equal(grepSorted.basePath, '.');
    const sortedPaths = grepSorted.matches.map((entry) => entry.path);
    assert.deepEqual(sortedPaths, ['a-match.txt', 'z-match.txt'], 'grep matches must be lexicographically sorted by path');

    const grepRootResult = await executeHelperGrep({ pattern: 'needle root' }, env);
    assert.equal(grepRootResult.matches.some((entry) => entry.path === 'top.txt'), true, 'grep must search from repo root instead of helper cwd');

    const grepResult = await executeHelperGrep({ pattern: 'needle-', maxMatches: 999 }, env);
    assert.equal(grepResult.basePath, '.');
    assert.equal(grepResult.truncated, true, 'grep should report truncation when matches/caps are hit');
    assert.ok(grepResult.matches.length > 0, 'grep should return matches');
    assert.ok(grepResult.matches.every((entry) => utf8Length(entry.text) <= 240), 'grep preview lines must stay within 240 bytes');
    assert.ok(utf8Length(JSON.stringify(grepResult)) <= 24 * 1024, 'grep payload must stay within 24 KiB');

    const findResult = await executeHelperFind({ path: 'many', maxResults: 999 }, env);
    assert.equal(findResult.basePath, 'many');
    assert.equal(findResult.results.length, 200, 'find maxResults should clamp to 200');
    assert.equal(findResult.truncated, true, 'find should report truncation when maxResults are hit');
    const sortedFindPaths = [...findResult.results.map((entry) => entry.path)].sort((left, right) => left.localeCompare(right));
    assert.deepEqual(findResult.results.map((entry) => entry.path), sortedFindPaths, 'find results must be sorted lexicographically');

    const rootFind = await executeHelperFind({ path: '.', type: 'any', maxResults: 20 }, env);
    assert.ok(rootFind.results.every((entry) => entry.path !== 'escape-dir' && entry.path !== 'escape-file.txt'), 'find must omit outside-root symlink escapes');
    await assertRejectsContains(() => executeHelperFind({ path: '../outside' }, env), 'parent segments');

    const lsResult = await executeHelperLs({ path: 'many', maxResults: 999 }, env);
    assert.equal(lsResult.path, 'many');
    assert.equal(lsResult.entries.length, 200, 'ls maxResults should clamp to 200');
    assert.equal(lsResult.truncated, true, 'ls should report truncation when maxResults are hit');
    const lsNames = lsResult.entries.map((entry) => entry.name);
    assert.deepEqual(lsNames, [...lsNames].sort((left, right) => left.localeCompare(right)), 'ls entries must be sorted by name');

    const rootLs = await executeHelperLs({ path: '.' }, env);
    assert.ok(rootLs.entries.some((entry) => entry.path === 'top.txt'), 'ls should include repo-root files');
    assert.ok(rootLs.entries.every((entry) => entry.path !== 'escape-dir' && entry.path !== 'escape-file.txt'), 'ls must omit outside-root symlink escapes');
    await assertRejectsContains(() => executeHelperLs({ path: '/tmp' }, env), 'repo-relative, not absolute');
  });

  console.log('helper authority boundary test passed');
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
NODE
