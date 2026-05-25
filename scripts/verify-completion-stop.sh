#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "$SCRIPT_DIR/verify-completion-control-plane.js"

CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
export COMPLETION_STOP_HEAD="$CURRENT_HEAD"

node <<'NODE'
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

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

function gitHeadSha() {
  const result = spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (result.status !== 0) {
    fail('git rev-parse HEAD failed: ' + (asString(result.stderr) ?? 'unknown git error'));
  }
  return asString(result.stdout);
}

const profile = readJson('.agent/config/profile.json');
const state = readJson('.agent/current/state.json');
const requiredStopJudges = asNumber(profile.required_stop_judges);
if (!Number.isInteger(requiredStopJudges) || requiredStopJudges < 1) {
  fail('.agent/config/profile.json required_stop_judges must be a positive integer before stop verification can run.');
}
const stopAggregationPolicy = asString(profile.stop_aggregation_policy);
if (stopAggregationPolicy !== 'unanimous-current-head-v1') {
  fail('.agent/config/profile.json stop_aggregation_policy must be unanimous-current-head-v1 before stop verification can run.');
}

const currentPhase = asString(state.current_phase) ?? 'unknown';
const stopWaveActive = currentPhase === 'stop_wave' || currentPhase === 'done';
const currentStopWaveId = asNumber(state.current_stop_wave_id) ?? 0;
if (!Number.isInteger(currentStopWaveId) || currentStopWaveId < 0) {
  fail('.agent/current/state.json current_stop_wave_id must be a non-negative integer before stop verification can run.');
}
const activeStopWaveId = stopWaveActive ? currentStopWaveId || 1 : currentStopWaveId;
const rawHistory = fs.existsSync('.agent/current/stop-check-history.jsonl') ? fs.readFileSync('.agent/current/stop-check-history.jsonl', 'utf8') : '';
const seededHeadSha = asString(process.env.COMPLETION_STOP_HEAD);
if (!seededHeadSha && !stopWaveActive && rawHistory.trim().length === 0) {
  console.log('[completion] current phase ' + currentPhase + ' is not stop_wave/done; current-HEAD stop judgments are not required yet');
  process.exit(0);
}
const headSha = seededHeadSha ?? gitHeadSha();
const currentHeadJudgments = [];
for (const [index, rawLine] of rawHistory.split(/\r?\n/).entries()) {
  const line = rawLine.trim();
  if (!line) continue;
  let parsed;
  try {
    parsed = JSON.parse(line);
  } catch (error) {
    fail('.agent/current/stop-check-history.jsonl contains invalid JSON at line ' + (index + 1) + ': ' + error.message);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    fail('.agent/current/stop-check-history.jsonl line ' + (index + 1) + ' must be a JSON object judgment record.');
  }
  if (parsed.type !== 'judgment') continue;
  if (asString(parsed.head_sha) !== headSha) continue;
  const recordStopWaveId = asNumber(parsed.stop_wave_id) ?? 0;
  if (!Number.isInteger(recordStopWaveId) || recordStopWaveId < 0) {
    fail('Current-HEAD judgment at line ' + (index + 1) + ' must carry a non-negative integer stop_wave_id.');
  }
  if (recordStopWaveId !== activeStopWaveId) continue;
  if (typeof parsed.can_stop !== 'boolean') {
    fail('Current-HEAD judgment at line ' + (index + 1) + ' must carry boolean can_stop.');
  }
  const blockerCount = asNumber(parsed.blocker_count);
  const highValueGapCount = asNumber(parsed.high_value_gap_count);
  if (blockerCount === undefined || highValueGapCount === undefined) {
    fail('Current-HEAD judgment at line ' + (index + 1) + ' must carry numeric blocker_count and high_value_gap_count.');
  }
  if (parsed.can_stop === false) {
    fail('Current HEAD has a can_stop=no judgment at line ' + (index + 1) + '.');
  }
  if (blockerCount > 0 || highValueGapCount > 0) {
    fail('Current-HEAD judgment at line ' + (index + 1) + ' cannot pass stop verification while blocker_count or high_value_gap_count is non-zero.');
  }
  currentHeadJudgments.push(parsed);
}

if (!stopWaveActive && currentHeadJudgments.length === 0) {
  console.log('[completion] current phase ' + currentPhase + ' is not stop_wave/done; current-HEAD stop judgments are not required yet');
  process.exit(0);
}

if (currentHeadJudgments.length < requiredStopJudges) {
  fail('Need ' + requiredStopJudges + ' valid current-HEAD judgments for HEAD ' + headSha + ' in stop_wave_id ' + activeStopWaveId + '; found ' + currentHeadJudgments.length + '.');
}

console.log('[completion] stop-wave policy unanimous-current-head-v1 satisfied for HEAD ' + headSha + ' in stop_wave_id ' + activeStopWaveId + ' with ' + currentHeadJudgments.length + ' valid current-HEAD judgments');
NODE

REPO_VERIFY_COMMAND="${COMPLETION_REPO_VERIFY_COMMAND:-}"
REPO_VERIFY_CWD="${COMPLETION_REPO_VERIFY_CWD:-}"
if [[ -n "$REPO_VERIFY_COMMAND" ]]; then
  if [[ "${PI_COMPLETION_RUNNING_RELEASE_CHECK:-}" == "1" ]]; then
    echo "[completion] repo-level verification already active; skipping forwarded repo verifier to avoid recursion"
    exit 0
  fi
  if [[ -z "$REPO_VERIFY_CWD" ]]; then
    REPO_VERIFY_CWD="$(pwd -P)"
  fi
  if [[ ! -d "$REPO_VERIFY_CWD" ]]; then
    echo "[completion] repo-level verification cwd does not exist: $REPO_VERIFY_CWD" >&2
    exit 1
  fi
  echo "[completion] running repo-level verification from $REPO_VERIFY_CWD: $REPO_VERIFY_COMMAND"
  (
    cd "$REPO_VERIFY_CWD"
    bash -lc "$REPO_VERIFY_COMMAND"
  )
else
  echo "[completion] no repo-specific verifier auto-detected; control-plane verification only"
fi
