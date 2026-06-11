#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
mkdir -p "$REPO/.cook" "$REPO/.agent/current" "$REPO/scripts"
cd "$REPO"

git init -q
git config user.name "stop-wave-epoch-test"
git config user.email "stop-wave-epoch-test@example.invalid"
printf '# stop wave epoch fixture\n' > README.md
cat > package.json <<'JSON'
{
  "name": "stop-wave-epoch-fixture",
  "private": true,
  "scripts": {
    "release-check": "bash ./scripts/release-check.sh",
    "verifier-fixture-check": "node -e \"process.stdout.write('fixture verifier ok')\""
  }
}
JSON
git add README.md package.json
git commit -q -m "fixture baseline"
HEAD_SHA="$(git rev-parse HEAD)"

cat > .agent/verify_completion_control_plane.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$SCRIPT_DIR/../scripts/verify-completion-control-plane.js" "$@"
SH
cat > .agent/verify_completion_stop.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export COMPLETION_REPO_VERIFY_COMMAND='npm run release-check >/dev/null'
export COMPLETION_REPO_VERIFY_CWD="$(cd "$SCRIPT_DIR/.." && pwd -P)"
exec bash "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" "$@"
SH
cp "$ROOT/scripts/verify-completion-control-plane.js" scripts/verify-completion-control-plane.js
cp "$ROOT/scripts/verify-completion-stop.sh" scripts/verify-completion-stop.sh
cat > scripts/release-check.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
export PI_COMPLETION_RUNNING_RELEASE_CHECK=1
COUNTER_FILE="${PI_STOP_WAVE_RELEASE_CHECK_COUNT_FILE:?}"
STATUS_FILE="${PI_STOP_WAVE_RELEASE_CHECK_STATUS_FILE:?}"
count="$(cat "$COUNTER_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s\n' "$count" > "$COUNTER_FILE"
if [[ "$count" -gt 1 ]]; then
  echo "recursive release-check invocation detected" >&2
  exit 97
fi
bash .agent/verify_completion_stop.sh >/dev/null
printf 'release-check-ok\n' > "$STATUS_FILE"
SH
chmod +x .agent/verify_completion_control_plane.sh .agent/verify_completion_stop.sh scripts/verify-completion-stop.sh scripts/release-check.sh

git add .agent/verify_completion_control_plane.sh .agent/verify_completion_stop.sh scripts/verify-completion-control-plane.js scripts/verify-completion-stop.sh scripts/release-check.sh
git commit -q -m "scaffold local completion helper files"
HEAD_SHA="$(git rev-parse HEAD)"

HEAD_SHA="$HEAD_SHA" python3 - <<'PY'
import json
import os
from pathlib import Path
head = os.environ['HEAD_SHA']
mission = 'Stop-wave epoch regression fixture.'
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-05-24T00:00:00Z',
    'workflow_session_id': 'stop-wave-epoch-fixture',
    'startup_brief_path': '.agent/current/startup-brief.json',
    'current_phase': 'stop_wave',
    'continuation_policy': 'continue',
    'continuation_reason': 'Restart stop wave on the same HEAD after earlier no-stop evidence became stale.',
    'project_done': False,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 0,
    'remaining_high_value_gaps': 0,
    'unsatisfied_contract_ids': [],
    'release_blocker_ids': [],
    'next_mandatory_action': 'Collect stop-wave judgments for the restarted epoch.',
    'next_mandatory_role': 'completion-stop-judge',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 2,
    'last_reground_at': '2026-05-24T00:00:00Z',
    'last_auditor_verdict': 'pass',
    'contract_status': 'stop_wave_pending_judgments',
    'latest_completed_slice': head,
    'latest_verified_slice': head,
}
startup_brief = {
    'schema_version': 1,
    'artifact_type': 'completion-startup-brief',
    'source': 'test',
    'confirmed': True,
    'confirmed_at': '2026-05-24T00:00:00Z',
    'mission': mission,
    'goal_text': f'Mission: {mission}',
    'scope': [],
    'constraints': [],
    'acceptance': [],
    'risks': [],
    'notes': ['stop-wave epoch test fixture'],
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'last_reground_at': '2026-05-24T00:00:00Z',
    'plan_basis': 'stop_wave_epoch_fixture',
    'candidate_slices': [],
}
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'status': 'idle',
    'slice_id': None,
    'goal': None,
    'contract_ids': [],
    'acceptance_criteria': [],
    'priority': None,
    'why_now': None,
    'blocked_on': [],
    'locked_notes': [],
    'must_fix_findings': [],
    'implementation_surfaces': [],
    'verification_commands': [],
    'basis_commit': None,
    'remaining_contract_ids_before': [],
    'release_blocker_count_before': None,
    'high_value_gap_count_before': None,
}
evidence = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'none',
    'slice_id': None,
    'goal': None,
    'contract_ids': [],
    'basis_commit': None,
    'head_sha': None,
    'verification_commands': [],
    'outcome': 'not_recorded',
    'recorded_at': None,
    'summary': 'No selected-slice verification evidence is required for the stop-wave epoch fixture.',
}
Path('.agent/current/state.json').write_text(json.dumps(state, indent=2) + '\n')
Path('.agent/current/startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
Path('.agent/current/plan.json').write_text(json.dumps(plan, indent=2) + '\n')
Path('.agent/current/active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
Path('.agent/current/verification-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
Path('.agent/current/stop-check-history.jsonl').write_text(json.dumps({
    'schema_version': 1,
    'type': 'judgment',
    'recorded_at': 1,
    'head_sha': head,
    'stop_wave_id': 1,
    'can_stop': False,
    'blocker_count': 1,
    'high_value_gap_count': 0,
}) + '\n')
Path('.agent/current/slice-history.jsonl').write_text('')
PY

HEAD_SHA="$HEAD_SHA" python3 - <<'PY'
import os, subprocess
combined = subprocess.run(['bash', '.agent/verify_completion_stop.sh'], text=True, capture_output=True)
text = combined.stdout + combined.stderr
assert combined.returncode != 0, 'expected stop verifier to fail before current stop-wave judgments are recorded'
assert f'Need 2 valid current-HEAD judgments for HEAD {os.environ["HEAD_SHA"]} in stop_wave_id 2; found 0.' in text, text
assert 'Current HEAD has a can_stop=no judgment' not in text, text
PY

HEAD_SHA="$HEAD_SHA" python3 - <<'PY'
import json, os
from pathlib import Path
head = os.environ['HEAD_SHA']
records = [
    {
        'schema_version': 1,
        'type': 'judgment',
        'recorded_at': 2,
        'head_sha': head,
        'stop_wave_id': 2,
        'can_stop': True,
        'blocker_count': 0,
        'high_value_gap_count': 0,
    },
    {
        'schema_version': 1,
        'type': 'judgment',
        'recorded_at': 3,
        'head_sha': head,
        'stop_wave_id': 2,
        'can_stop': True,
        'blocker_count': 0,
        'high_value_gap_count': 0,
    },
]
with Path('.agent/current/stop-check-history.jsonl').open('a', encoding='utf8') as fh:
    for record in records:
        fh.write(json.dumps(record) + '\n')
PY

RECONCILE="$TMPDIR/reconcile"
mkdir -p "$RECONCILE"
ln -s "$REPO/.agent" "$RECONCILE/.agent"
ln -s "$REPO/.cook" "$RECONCILE/.cook"
ln -s "$REPO/.git" "$RECONCILE/.git"

REPO="$REPO" RECONCILE="$RECONCILE" python3 - <<'PY'
import os, subprocess
env = {**os.environ, 'COMPLETION_REPO_VERIFY_COMMAND': 'npm run verifier-fixture-check >/dev/null'}
env.pop('PI_COMPLETION_RUNNING_RELEASE_CHECK', None)
env.pop('COMPLETION_REPO_VERIFY_CWD', None)
result = subprocess.run(
    ['bash', os.path.join(os.environ['REPO'], 'scripts', 'verify-completion-stop.sh')],
    cwd=os.environ['RECONCILE'],
    text=True,
    capture_output=True,
    env=env,
)
text = result.stdout + result.stderr
assert result.returncode != 0, 'expected package-owned stop verifier to fail when repo verification inherits a cwd without package.json'
assert 'package.json' in text, text
PY

RELEASE_CHECK_COUNT_FILE="$TMPDIR/release-check-count.txt"
RELEASE_CHECK_STATUS_FILE="$TMPDIR/release-check-status.txt"
REPO="$REPO" RECONCILE="$RECONCILE" RELEASE_CHECK_COUNT_FILE="$RELEASE_CHECK_COUNT_FILE" RELEASE_CHECK_STATUS_FILE="$RELEASE_CHECK_STATUS_FILE" python3 - <<'PY'
import os
import subprocess
import time

reconcile = os.environ['RECONCILE']
repo = os.environ['REPO']
counter_file = os.environ['RELEASE_CHECK_COUNT_FILE']
status_file = os.environ['RELEASE_CHECK_STATUS_FILE']
env = {
    **os.environ,
    'PI_STOP_WAVE_RELEASE_CHECK_COUNT_FILE': counter_file,
    'PI_STOP_WAVE_RELEASE_CHECK_STATUS_FILE': status_file,
}
env.pop('PI_COMPLETION_RUNNING_RELEASE_CHECK', None)
env.pop('COMPLETION_REPO_VERIFY_COMMAND', None)
env.pop('COMPLETION_REPO_VERIFY_CWD', None)
result = subprocess.run(
    ['bash', '.agent/verify_completion_stop.sh'],
    cwd=reconcile,
    text=True,
    capture_output=True,
    timeout=20,
    env=env,
)
text = result.stdout + result.stderr
assert result.returncode == 0, text
assert os.path.exists(counter_file), 'expected release-check counter file to be created'
assert open(counter_file, 'r', encoding='utf8').read().strip() == '1', text
assert os.path.exists(status_file), 'expected release-check status file to be created'
assert open(status_file, 'r', encoding='utf8').read().strip() == 'release-check-ok', text
assert '[completion] running repo-level verification from ' in text, text

time.sleep(0.2)
process_table = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
leaks = [
    line for line in process_table.splitlines()
    if repo in line and ('verify-completion-stop.sh' in line or 'release-check.sh' in line)
]
assert not leaks, 'expected no leaked stop-verifier or release-check processes after wrapper completion: ' + ' | '.join(leaks)
PY

ROOT_PATH="$ROOT" node - <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { parseReportFields, transcribeCanonicalRoleReport } = require(path.join(process.env.ROOT_PATH, 'extensions/completion/role-reporting.js'));
(async () => {
  const report = `MISSION ANCHOR: epoch mission\nRemaining contract IDs: none\nRubric:\n- Contract coverage: pass - All implementation slices are accepted on HEAD.\n- Correctness risk: pass - No remaining blocker or high-value gap is evident.\n- Verification evidence: pass - Final verification passes for the current head.\n- Docs/state parity: pass - Docs, config, and canonical state match shipped behavior.\nCan the project stop now: yes\nExact remaining open top-level contract IDs: none\nBlocker count: 0\nHigh-value gap count: 0\nLatest completed slice commit: abcdef1234567890abcdef1234567890abcdef12\nDocs/config/runbooks match shipped behavior: yes\nTracked and unignored worktree is clean: yes\nBrief justification: Stop-wave epoch transcription should capture the active stop_wave_id.`;
  const headSha = require('node:child_process').execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const result = await transcribeCanonicalRoleReport({
    role: 'completion-stop-judge',
    output: report,
    reportFields: parseReportFields(report),
    snapshotFiles: {
      statePath: path.join(process.cwd(), '.agent/current/state.json'),
      stopHistoryPath: path.join(process.cwd(), '.agent/current/stop-check-history.jsonl'),
      sliceHistoryPath: path.join(process.cwd(), '.agent/current/slice-history.jsonl'),
    },
    headSha,
    recordedAt: 4,
  });
  if (result.errors.length > 0) throw new Error(result.errors.join(' | '));
  const lines = fs.readFileSync('.agent/current/stop-check-history.jsonl', 'utf8').trim().split('\n').map((line) => JSON.parse(line));
  const last = lines[lines.length - 1];
  if (last.stop_wave_id !== 2) throw new Error('transcribed stop judgment must include current stop_wave_id 2');
})();
NODE

echo "stop-wave epoch test passed"
