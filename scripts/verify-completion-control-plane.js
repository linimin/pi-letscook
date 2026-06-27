#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REQUIRED_TRACKED_CONTRACT_FILES = [];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail('Failed to read ' + file + ': ' + error.message);
  }
}

function asString(value) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

function asNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function asStringArray(value) {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === 'string' && item.trim().length > 0)
    : [];
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function sameStringArrays(left, right) {
  return left.length === right.length && left.every((item, index) => item === right[index]);
}

function isSafeArtifactPath(value) {
  const candidate = asString(value);
  if (!candidate) return false;
  const withForwardSlashes = candidate.replace(/\\/g, '/');
  if (withForwardSlashes.startsWith('/')) return false;
  if (/^[A-Za-z]:\//.test(withForwardSlashes)) return false;
  const normalized = path.posix.normalize(withForwardSlashes);
  if (normalized === '.' || normalized.startsWith('../') || normalized.includes('/../')) return false;
  return true;
}

function ensureArtifactPaths(value, label) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) {
    fail(`${label} must be an array of repo-relative artifact paths when present`);
  }
  for (const [index, item] of value.entries()) {
    if (!isSafeArtifactPath(item)) {
      fail(`${label}[${index}] must be a safe repo-relative artifact path`);
    }
  }
  return value;
}

function validateStructuredEntryArray(value, label) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) fail(`${label} must be an array when present`);
  return value;
}

function validateEvidenceQuality(evidence) {
  if (evidence.evidence_quality === undefined || evidence.evidence_quality === null) return undefined;
  if (!isRecord(evidence.evidence_quality)) {
    fail('.agent/current/verification-evidence.json evidence_quality must be an object when present');
  }
  const status = asString(evidence.evidence_quality.status);
  if (!status) {
    fail('.agent/current/verification-evidence.json evidence_quality.status must be present when evidence_quality is provided');
  }
  if (!asString(evidence.evidence_quality.summary)) {
    fail('.agent/current/verification-evidence.json evidence_quality.summary must be present when evidence_quality is provided');
  }
  return status;
}

function validateCommandResults(evidence, verificationCommands) {
  const label = '.agent/current/verification-evidence.json command_results';
  const entries = validateStructuredEntryArray(evidence.command_results, label);
  const seen = new Set();
  const allowedCommands = new Set(verificationCommands);
  for (const [index, entry] of entries.entries()) {
    const entryLabel = `${label}[${index}]`;
    if (!isRecord(entry)) fail(`${entryLabel} must be an object`);
    const command = asString(entry.command);
    if (!command) fail(`${entryLabel}.command must be a non-empty string`);
    if (seen.has(command)) fail(`${label} must not repeat command values`);
    seen.add(command);
    if (verificationCommands.length > 0 && !allowedCommands.has(command)) {
      fail(`${entryLabel}.command must match .agent/current/verification-evidence.json verification_commands`);
    }
    const outcome = asString(entry.outcome);
    if (!outcome || !['passed', 'failed', 'not_run'].includes(outcome)) {
      fail(`${entryLabel}.outcome must be passed, failed, or not_run`);
    }
    if (entry.summary !== undefined && !asString(entry.summary)) {
      fail(`${entryLabel}.summary must be a non-empty string when present`);
    }
    ensureArtifactPaths(entry.artifact_paths, `${entryLabel}.artifact_paths`);
  }
  return entries;
}

function validateStructuredStatusEntries(value, label, keyField, allowedStatuses) {
  const entries = validateStructuredEntryArray(value, label);
  const seen = new Set();
  for (const [index, entry] of entries.entries()) {
    const entryLabel = `${label}[${index}]`;
    if (!isRecord(entry)) fail(`${entryLabel} must be an object`);
    const keyValue = asString(entry[keyField]);
    if (!keyValue) fail(`${entryLabel}.${keyField} must be a non-empty string`);
    if (seen.has(keyValue)) fail(`${label} must not repeat ${keyField} values`);
    seen.add(keyValue);
    const status = asString(entry.status);
    if (!status || !allowedStatuses.includes(status)) {
      fail(`${entryLabel}.status must be one of: ${allowedStatuses.join(', ')}`);
    }
    if (entry.summary !== undefined && !asString(entry.summary)) {
      fail(`${entryLabel}.summary must be a non-empty string when present`);
    }
    ensureArtifactPaths(entry.artifact_paths, `${entryLabel}.artifact_paths`);
  }
  return entries;
}

function validateAcceptanceCoverage(evidence, acceptanceCriteria) {
  const label = '.agent/current/verification-evidence.json acceptance_coverage';
  const entries = validateStructuredStatusEntries(evidence.acceptance_coverage, label, 'criterion', ['covered', 'partial', 'not_covered']);
  const allowedCriteria = new Set(acceptanceCriteria);
  for (const [index, entry] of entries.entries()) {
    const criterion = asString(entry.criterion);
    if (acceptanceCriteria.length > 0 && criterion && !allowedCriteria.has(criterion)) {
      fail(`${label}[${index}].criterion must match .agent/current/active-slice.json acceptance_criteria`);
    }
  }
  return entries;
}

function validateBasisRegressionMetadata(evidence) {
  if (evidence.basis_regression_required !== undefined && typeof evidence.basis_regression_required !== 'boolean') {
    fail('.agent/current/verification-evidence.json basis_regression_required must be boolean when present');
  }
  if (evidence.basis_regression_status !== undefined && evidence.basis_regression_status !== null) {
    const status = asString(evidence.basis_regression_status);
    if (!status || !['failed_on_basis', 'passed_on_basis', 'not_run', 'not_applicable'].includes(status)) {
      fail('.agent/current/verification-evidence.json basis_regression_status must be failed_on_basis, passed_on_basis, not_run, or not_applicable when present');
    }
  }
  if (evidence.basis_regression_reason !== undefined && evidence.basis_regression_reason !== null && !asString(evidence.basis_regression_reason)) {
    fail('.agent/current/verification-evidence.json basis_regression_reason must be a non-empty string when present');
  }
  ensureArtifactPaths(evidence.basis_regression_artifact_paths, '.agent/current/verification-evidence.json basis_regression_artifact_paths');
}

function validateStructuredVerificationEvidence(evidence, verificationCommands, acceptanceCriteria) {
  const qualityStatus = validateEvidenceQuality(evidence);
  const commandResults = validateCommandResults(evidence, verificationCommands);
  const acceptanceCoverage = validateAcceptanceCoverage(evidence, acceptanceCriteria);
  validateStructuredStatusEntries(evidence.flake_signals, '.agent/current/verification-evidence.json flake_signals', 'signal', ['none', 'watch', 'suspected']);
  validateStructuredStatusEntries(evidence.open_gaps, '.agent/current/verification-evidence.json open_gaps', 'gap', ['watch', 'open', 'none']);
  validateBasisRegressionMetadata(evidence);

  const overallOutcome = asString(evidence.outcome);
  if (qualityStatus === 'not_recorded' && overallOutcome && overallOutcome !== 'not_recorded') {
    fail('.agent/current/verification-evidence.json evidence_quality.status must not stay not_recorded once outcome is recorded');
  }
  if (overallOutcome === 'passed' && commandResults.length > 0) {
    const resultByCommand = new Map(commandResults.map((entry) => [asString(entry.command), asString(entry.outcome)]));
    for (const command of verificationCommands) {
      if (!resultByCommand.has(command)) {
        fail('.agent/current/verification-evidence.json command_results must cover every verification command when outcome=passed');
      }
    }
    for (const outcome of resultByCommand.values()) {
      if (outcome !== 'passed') {
        fail('.agent/current/verification-evidence.json command_results outcomes must all be passed when overall outcome=passed');
      }
    }
  }
  if (overallOutcome === 'passed' && acceptanceCoverage.length > 0) {
    const coverageByCriterion = new Map(acceptanceCoverage.map((entry) => [asString(entry.criterion), asString(entry.status)]));
    for (const criterion of acceptanceCriteria) {
      if (!coverageByCriterion.has(criterion)) {
        fail('.agent/current/verification-evidence.json acceptance_coverage must cover every active acceptance criterion when outcome=passed');
      }
    }
    for (const status of coverageByCriterion.values()) {
      if (status !== 'covered') {
        fail('.agent/current/verification-evidence.json acceptance_coverage statuses must all be covered when overall outcome=passed');
      }
    }
  }
}

function runGit(args, options = {}) {
  const result = spawnSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (!options.allowFailure && result.status !== 0) {
    const stderr = asString(result.stderr) ?? 'git command failed';
    fail(`git ${args.join(' ')} failed: ${stderr}`);
  }
  return result;
}

function gitHeadSha() {
  const result = runGit(['rev-parse', 'HEAD'], { allowFailure: true });
  return result.status === 0 ? asString(result.stdout) : undefined;
}

function ensureTrackedContractFiles() {
  for (const file of REQUIRED_TRACKED_CONTRACT_FILES) {
    const result = runGit(['ls-files', '--error-unmatch', file], { allowFailure: true });
    if (result.status !== 0) {
      fail(`Required tracked completion contract file is missing from git index: ${file}`);
    }
  }
}

function ensureCommitExists(commitish, label) {
  const result = runGit(['rev-parse', '--verify', `${commitish}^{commit}`], { allowFailure: true });
  if (result.status !== 0) {
    fail(`${label} must resolve to an existing commit: ${commitish}`);
  }
}

function trackedDiffFiles(fromCommit, toCommit) {
  const result = runGit(['diff', '--name-only', '--diff-filter=ACMR', `${fromCommit}..${toCommit}`]);
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

const workflow = {
  schema_version: 1,
  protocol_id: 'completion',
  layout_version: 5,
  config_dir: null,
  runtime_dir: '.agent/current',
  archive_policy: 'disabled',
};
const profile = {
  schema_version: 1,
  protocol_id: 'completion',
  required_stop_judges: 2,
  stop_aggregation_policy: 'unanimous-current-head-v1',
  priority_policy_id: 'completion-default',
  task_type: 'completion-workflow',
  evaluation_profile: 'completion-rubric-v1',
};
const runtimeFiles = [
  '.agent/current/state.json',
  '.agent/current/plan.json',
  '.agent/current/active-slice.json',
  '.agent/current/verification-evidence.json',
];
const runtimePresent = runtimeFiles.filter((file) => fs.existsSync(file));
const runtimeFullyPresent = runtimePresent.length === runtimeFiles.length;
if (runtimePresent.length > 0 && !runtimeFullyPresent) {
  fail('Completion runtime state is partial: either all canonical .agent/current runtime files must exist or none of them may exist.');
}
const state = runtimeFullyPresent ? readJson('.agent/current/state.json') : undefined;
const startupBrief = fs.existsSync('.agent/current/startup-brief.json') ? readJson('.agent/current/startup-brief.json') : undefined;
const plan = runtimeFullyPresent ? readJson('.agent/current/plan.json') : undefined;
const active = runtimeFullyPresent ? readJson('.agent/current/active-slice.json') : undefined;
const evidence = runtimeFullyPresent ? readJson('.agent/current/verification-evidence.json') : undefined;

ensureTrackedContractFiles();

if (!runtimeFullyPresent) {
  if (startupBrief) fail('.agent/current/startup-brief.json must not exist when canonical runtime state is absent');
  process.exit(0);
}

for (const [file, record] of [
  ['package defaults', profile],
  ['.agent/current/state.json', state],
  ['.agent/current/plan.json', plan],
  ['.agent/current/active-slice.json', active],
]) {
  if (!asString(record.task_type)) fail(file + ' is missing task_type');
  if (!asString(record.evaluation_profile)) fail(file + ' is missing evaluation_profile');
}

const taskType = asString(profile.task_type);
const evaluationProfile = asString(profile.evaluation_profile);
const requiredStopJudges = asNumber(profile.required_stop_judges);
const stopAggregationPolicy = asString(profile.stop_aggregation_policy);
if (asString(workflow.protocol_id) !== 'completion') fail('package default workflow protocol_id must be completion');
if (asString(workflow.runtime_dir) !== '.agent/current') fail('package default workflow runtime_dir must be .agent/current');
if (workflow.config_dir !== null) fail('package default workflow config_dir must be null');
if (asString(workflow.archive_policy) != 'disabled') fail('package default workflow archive_policy must be disabled');
if (!Number.isInteger(requiredStopJudges) || requiredStopJudges < 1) {
  fail('package default profile required_stop_judges must be a positive integer');
}
if (stopAggregationPolicy !== 'unanimous-current-head-v1') {
  fail('package default profile stop_aggregation_policy must be unanimous-current-head-v1');
}
if (asString(state.task_type) !== taskType) fail('.agent/current/state.json task_type must match package default task_type');
if (asString(plan.task_type) !== taskType) fail('.agent/current/plan.json task_type must match package default task_type');
if (asString(active.task_type) !== taskType) fail('.agent/current/active-slice.json task_type must match package default task_type');
if (asString(state.evaluation_profile) !== evaluationProfile) fail('.agent/current/state.json evaluation_profile must match package default evaluation_profile');
if (asString(plan.evaluation_profile) !== evaluationProfile) fail('.agent/current/plan.json evaluation_profile must match package default evaluation_profile');
if (asString(active.evaluation_profile) !== evaluationProfile) fail('.agent/current/active-slice.json evaluation_profile must match package default evaluation_profile');
const remainingStopJudges = asNumber(state.remaining_stop_judges);
if (remainingStopJudges === undefined) fail('.agent/current/state.json remaining_stop_judges must be numeric');
if (remainingStopJudges < 0) fail('.agent/current/state.json remaining_stop_judges must not be negative');
const currentStopWaveId = asNumber(state.current_stop_wave_id);
if (currentStopWaveId !== undefined) {
  if (!Number.isInteger(currentStopWaveId) || currentStopWaveId < 0) {
    fail('.agent/current/state.json current_stop_wave_id must be a non-negative integer');
  }
}

if (asString(evidence.artifact_type) !== 'completion-verification-evidence') {
  fail('.agent/current/verification-evidence.json artifact_type must be completion-verification-evidence');
}

const workflowEntryStatus = asString(state.workflow_entry_status);
if (workflowEntryStatus === 'active' || startupBrief) {
  if (!startupBrief) fail('.agent/current/startup-brief.json must exist when workflow entry is active');
  if (asString(startupBrief.artifact_type) !== 'completion-startup-brief') {
    fail('.agent/current/startup-brief.json artifact_type must be completion-startup-brief');
  }
  if (!asString(state.workflow_session_id)) {
    fail('.agent/current/state.json workflow_session_id must be present when workflow entry is active');
  }
  if (asString(state.startup_brief_path) !== '.agent/current/startup-brief.json') {
    fail('.agent/current/state.json startup_brief_path must point to .agent/current/startup-brief.json');
  }
  if (asString(startupBrief.mission) !== asString(state.mission_anchor)) {
    fail('.agent/current/startup-brief.json mission must match .agent/current/state.json mission_anchor');
  }
  if (asString(startupBrief.task_type) !== taskType) {
    fail('.agent/current/startup-brief.json task_type must match package default task_type');
  }
  if (asString(startupBrief.evaluation_profile) !== evaluationProfile) {
    fail('.agent/current/startup-brief.json evaluation_profile must match package default evaluation_profile');
  }
}

const exactStatuses = new Set(['selected', 'in_progress', 'committed', 'done']);
const activeStatus = asString(active.status);
const exactHandoff = exactStatuses.has(activeStatus || '');
const planSlices = Array.isArray(plan.candidate_slices) ? plan.candidate_slices : [];
const activeSliceId = asString(active.slice_id);
const planSlice = activeSliceId ? planSlices.find((slice) => asString(slice && slice.slice_id) === activeSliceId) : undefined;

if (exactHandoff && !planSlice) {
  fail('slice_id must match a slice in .agent/current/plan.json when status carries an exact handoff');
}

const structuredEvidenceVerificationCommands = exactHandoff ? asStringArray(active.verification_commands) : asStringArray(evidence.verification_commands);
const structuredEvidenceAcceptanceCriteria = exactHandoff ? asStringArray(active.acceptance_criteria) : [];
validateStructuredVerificationEvidence(evidence, structuredEvidenceVerificationCommands, structuredEvidenceAcceptanceCriteria);

if (exactHandoff) {
  const requiredStringFields = ['goal', 'why_now', 'basis_commit'];
  for (const field of requiredStringFields) {
    if (!asString(active[field])) fail('.agent/current/active-slice.json is missing ' + field + ' when status carries an exact handoff');
  }
  const requiredArrayFields = ['contract_ids', 'acceptance_criteria', 'blocked_on', 'locked_notes', 'must_fix_findings', 'implementation_surfaces', 'verification_commands', 'remaining_contract_ids_before'];
  for (const field of requiredArrayFields) {
    if (!Array.isArray(active[field])) fail('.agent/current/active-slice.json is missing ' + field + ' when status carries an exact handoff');
  }
  const requiredNumberFields = ['priority', 'release_blocker_count_before', 'high_value_gap_count_before'];
  for (const field of requiredNumberFields) {
    if (asNumber(active[field]) === undefined) fail('.agent/current/active-slice.json is missing ' + field + ' when status carries an exact handoff');
  }

  const mismatchFields = [];
  if (asString(planSlice.slice_id) !== activeSliceId) mismatchFields.push('slice_id');
  if (asString(planSlice.goal) !== asString(active.goal)) mismatchFields.push('goal');
  if (!sameStringArrays(asStringArray(planSlice.contract_ids), asStringArray(active.contract_ids))) mismatchFields.push('contract_ids');
  if (!sameStringArrays(asStringArray(planSlice.acceptance_criteria), asStringArray(active.acceptance_criteria))) mismatchFields.push('acceptance_criteria');
  if (!sameStringArrays(asStringArray(planSlice.blocked_on), asStringArray(active.blocked_on))) mismatchFields.push('blocked_on');
  if (asNumber(planSlice.priority) !== asNumber(active.priority)) mismatchFields.push('priority');
  if (asString(planSlice.why_now) !== asString(active.why_now)) mismatchFields.push('why_now');
  const planMirrorFields = ['locked_notes', 'must_fix_findings', 'implementation_surfaces', 'verification_commands', 'basis_commit', 'remaining_contract_ids_before', 'release_blocker_count_before', 'high_value_gap_count_before'];
  for (const field of planMirrorFields) {
    const planValue = planSlice[field];
    const activeValue = active[field];
    if (Array.isArray(planValue) || Array.isArray(activeValue)) {
      if (!sameStringArrays(asStringArray(planValue), asStringArray(activeValue))) mismatchFields.push(field);
      continue;
    }
    if (typeof planValue === 'number' || typeof activeValue === 'number') {
      if (asNumber(planValue) !== asNumber(activeValue)) mismatchFields.push(field);
      continue;
    }
    if (asString(planValue) !== asString(activeValue)) mismatchFields.push(field);
  }
  if (mismatchFields.length > 0) {
    fail('.agent/current/active-slice.json must match the selected .agent/current/plan.json slice across: ' + mismatchFields.join(', '));
  }

  if (asString(evidence.subject_type) !== 'selected_slice') {
    fail('subject_type must be selected_slice when active slice exact handoff requires verification evidence');
  }
  if (asString(evidence.slice_id) !== activeSliceId) fail('.agent/current/verification-evidence.json slice_id must match .agent/current/active-slice.json slice_id');
  if (asString(evidence.goal) !== asString(active.goal)) fail('.agent/current/verification-evidence.json goal must match .agent/current/active-slice.json goal');
  if (!sameStringArrays(asStringArray(evidence.contract_ids), asStringArray(active.contract_ids))) fail('.agent/current/verification-evidence.json contract_ids must match .agent/current/active-slice.json contract_ids');
  if (asString(evidence.basis_commit) !== asString(active.basis_commit)) fail('.agent/current/verification-evidence.json basis_commit must match .agent/current/active-slice.json basis_commit');
  if (!sameStringArrays(asStringArray(evidence.verification_commands), asStringArray(active.verification_commands))) {
    fail('.agent/current/verification-evidence.json verification_commands must match .agent/current/active-slice.json verification_commands');
  }
  if (!asString(evidence.recorded_at)) fail('.agent/current/verification-evidence.json recorded_at must be present for selected-slice evidence');
  if (asString(evidence.outcome) === 'not_recorded') fail('.agent/current/verification-evidence.json outcome must not be not_recorded for selected-slice evidence');
  const headSha = gitHeadSha();
  if (headSha && asString(evidence.head_sha) !== headSha) {
    fail('.agent/current/verification-evidence.json head_sha must match current HEAD');
  }

  const basisCommit = asString(active.basis_commit);
  if (basisCommit && headSha) {
    ensureCommitExists(basisCommit, '.agent/current/active-slice.json basis_commit');
    const ancestorCheck = runGit(['merge-base', '--is-ancestor', basisCommit, headSha], { allowFailure: true });
    if (ancestorCheck.status !== 0) {
      fail(`.agent/current/active-slice.json basis_commit must be an ancestor of current HEAD: ${basisCommit} -> ${headSha}`);
    }
    const changedFiles = trackedDiffFiles(basisCommit, headSha);
    const implementationSurfaces = new Set(asStringArray(active.implementation_surfaces));
    const missingSurfaces = changedFiles.filter((file) => !implementationSurfaces.has(file));
    if (missingSurfaces.length > 0) {
      fail('.agent/current/active-slice.json implementation_surfaces must cover every tracked file changed from basis_commit to current HEAD; missing: ' + missingSurfaces.join(', '));
    }
  }
} else {
  const subjectType = asString(evidence.subject_type);
  if (subjectType === 'none') {
    if (asString(evidence.outcome) && asString(evidence.outcome) !== 'not_recorded') {
      fail('.agent/current/verification-evidence.json outcome must stay not_recorded when subject_type=none');
    }
  }
}
