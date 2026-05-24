#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');
const {
  REVIEWER_ACCEPTABLE_YES_WITH_FOLLOW_UP_ERROR,
  AUDITOR_CLEAN_YES_WITH_BLOCKERS_ERROR,
  buildRoleReportRepairPrompt,
} = require('./extensions/completion/role-reporting.js');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required report-repair text: ${snippet}`);
  }
};
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

assertIncludes('extensions/completion/role-runner.ts', 'import { buildRoleReportRepairPrompt, parseReportFields, transcribeRoleOutput, type TranscriptionResult } from "./transcription";');
assertIncludes('extensions/completion/role-runner.ts', 'Structured report repair mode:');
assertIncludes('extensions/completion/role-runner.ts', 'Retrying ${params.role} once to repair structured report consistency.');
assertIncludes('extensions/completion/transcription.ts', 'return roleReporting.buildRoleReportRepairPrompt(role, errors);');
assertIncludes('agents/completion-reviewer.md', 'Consistency rules:');
assertIncludes('agents/completion-reviewer.md', 'Never combine `Acceptable as-is: yes` with any real follow-up work.');
assertIncludes('agents/completion-auditor.md', 'Consistency rules:');
assertIncludes('agents/completion-auditor.md', 'Never combine `Tracked and unignored worktree is clean: yes` with any blocker text.');

const reviewerPrompt = buildRoleReportRepairPrompt('completion-reviewer', [REVIEWER_ACCEPTABLE_YES_WITH_FOLLOW_UP_ERROR]);
assert(typeof reviewerPrompt === 'string' && reviewerPrompt.includes('Smallest follow-up slice') && reviewerPrompt.includes('Do not add commentary.'), 'reviewer repair prompt should be generated for the repairable consistency error');
assert(buildRoleReportRepairPrompt('completion-reviewer', [REVIEWER_ACCEPTABLE_YES_WITH_FOLLOW_UP_ERROR, 'Missing Rubric heading for completion-reviewer.']) === undefined, 'reviewer repair should fail closed when other transcription errors are present');

const auditorPrompt = buildRoleReportRepairPrompt('completion-auditor', [AUDITOR_CLEAN_YES_WITH_BLOCKERS_ERROR]);
assert(typeof auditorPrompt === 'string' && auditorPrompt.includes('Worktree blockers') && auditorPrompt.includes('Do not add commentary.'), 'auditor repair prompt should be generated for the repairable consistency error');
assert(buildRoleReportRepairPrompt('completion-auditor', [AUDITOR_CLEAN_YES_WITH_BLOCKERS_ERROR, 'Auditor output must include a numeric Blocker count.']) === undefined, 'auditor repair should fail closed when other transcription errors are present');
assert(buildRoleReportRepairPrompt('completion-stop-judge', [AUDITOR_CLEAN_YES_WITH_BLOCKERS_ERROR]) === undefined, 'stop-judge should not receive reviewer/auditor repair prompts');
NODE

echo "report repair test passed"
