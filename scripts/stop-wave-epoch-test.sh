#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
mkdir -p "$REPO/.agent"
cd "$REPO"

git init -q
git config user.name "stop-wave-epoch-test"
git config user.email "stop-wave-epoch-test@example.invalid"
printf '# stop wave epoch fixture\n' > README.md
git add README.md
git commit -q -m "fixture baseline"
HEAD_SHA="$(git rev-parse HEAD)"

cp "$ROOT/.agent/README.md" .agent/README.md
cp "$ROOT/.agent/mission.md" .agent/mission.md
cp "$ROOT/.agent/profile.json" .agent/profile.json
cp "$ROOT/.agent/verify_completion_control_plane.sh" .agent/verify_completion_control_plane.sh
cp "$ROOT/.agent/verify_completion_stop.sh" .agent/verify_completion_stop.sh
chmod +x .agent/verify_completion_control_plane.sh .agent/verify_completion_stop.sh
python3 - <<'PY'
from pathlib import Path
path = Path('.agent/verify_completion_stop.sh')
text = path.read_text()
path.write_text(text.replace('npm run release-check >/dev/null', 'true'))
PY

git add .agent/README.md .agent/mission.md .agent/profile.json .agent/verify_completion_control_plane.sh .agent/verify_completion_stop.sh
git commit -q -m "scaffold tracked completion contract files"
HEAD_SHA="$(git rev-parse HEAD)"

HEAD_SHA="$HEAD_SHA" python3 - <<'PY'
import json
import os
from pathlib import Path
head = os.environ['HEAD_SHA']
mission = 'Stop-wave epoch regression fixture.'
profile = json.loads(Path('.agent/profile.json').read_text())
state = {
    'schema_version': 1,
    'mission_anchor': mission,
    'workflow_entry_status': 'active',
    'workflow_entry_source': '/cook',
    'workflow_entry_confirmed_at': '2026-05-24T00:00:00Z',
    'workflow_session_id': 'stop-wave-epoch-fixture',
    'startup_brief_path': '.agent/startup-brief.json',
    'current_phase': 'stop_wave',
    'continuation_policy': 'continue',
    'continuation_reason': 'Restart stop wave on the same HEAD after earlier no-stop evidence became stale.',
    'project_done': False,
    'task_type': profile['task_type'],
    'evaluation_profile': profile['evaluation_profile'],
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
    'task_type': profile['task_type'],
    'evaluation_profile': profile['evaluation_profile'],
}
plan = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': profile['task_type'],
    'evaluation_profile': profile['evaluation_profile'],
    'last_reground_at': '2026-05-24T00:00:00Z',
    'plan_basis': 'stop_wave_epoch_fixture',
    'candidate_slices': [],
}
active = {
    'schema_version': 1,
    'mission_anchor': mission,
    'task_type': profile['task_type'],
    'evaluation_profile': profile['evaluation_profile'],
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
Path('.agent/state.json').write_text(json.dumps(state, indent=2) + '\n')
Path('.agent/startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
Path('.agent/plan.json').write_text(json.dumps(plan, indent=2) + '\n')
Path('.agent/active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
Path('.agent/verification-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
Path('.agent/stop-check-history.jsonl').write_text(json.dumps({
    'schema_version': 1,
    'type': 'judgment',
    'recorded_at': 1,
    'head_sha': head,
    'stop_wave_id': 1,
    'can_stop': False,
    'blocker_count': 1,
    'high_value_gap_count': 0,
}) + '\n')
Path('.agent/slice-history.jsonl').write_text('')
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
with Path('.agent/stop-check-history.jsonl').open('a', encoding='utf8') as fh:
    for record in records:
        fh.write(json.dumps(record) + '\n')
PY

bash .agent/verify_completion_stop.sh >/dev/null

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
      statePath: path.join(process.cwd(), '.agent/state.json'),
      stopHistoryPath: path.join(process.cwd(), '.agent/stop-check-history.jsonl'),
      sliceHistoryPath: path.join(process.cwd(), '.agent/slice-history.jsonl'),
    },
    headSha,
    recordedAt: 4,
  });
  if (result.errors.length > 0) throw new Error(result.errors.join(' | '));
  const lines = fs.readFileSync('.agent/stop-check-history.jsonl', 'utf8').trim().split('\n').map((line) => JSON.parse(line));
  const last = lines[lines.length - 1];
  if (last.stop_wave_id !== 2) throw new Error('transcribed stop judgment must include current stop_wave_id 2');
})();
NODE

echo "stop-wave epoch test passed"
