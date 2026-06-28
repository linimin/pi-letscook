#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
cleanup() {
  local status=$?
  rm -rf "$TMPDIR"
  return $status
}
trap cleanup EXIT

pi() {
  env \
    -u PI_COMPLETION_ROLE \
    -u PI_COMPLETION_HELPER \
    -u PI_COMPLETION_CALLER_ROLE \
    -u PI_COMPLETION_HELPER_ROOT \
    -u PI_COMPLETION_HELPER_CWD \
    -u PI_COMPLETION_ROLE_MODEL \
    command pi --no-extensions "$@"
}

write_active_workflow_fixture() {
  local root="$1"
  mkdir -p "$root/.agent/current/tmp"
  (
    cd "$root"
    git init -q
    printf '# prompt budget fixture\n' > README.md
  )

  python3 - "$root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
current = root / '.agent' / 'current'
current.mkdir(parents=True, exist_ok=True)

state = {
    'schema_version': 1,
    'mission_anchor': 'Measure prompt budget regression surfaces.',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'current_phase': 'implement',
    'continuation_policy': 'continue',
    'continuation_reason': 'Prompt-budget fixture keeps the active workflow reminder startable.',
    'project_done': False,
    'requires_reground': False,
    'slices_since_last_reground': 0,
    'remaining_release_blockers': 0,
    'remaining_high_value_gaps': 1,
    'unsatisfied_contract_ids': ['PROMPT-BUDGET-01'],
    'release_blocker_ids': [],
    'next_mandatory_action': 'Run completion-reviewer for the latest slice.',
    'next_mandatory_role': 'completion-reviewer',
    'remaining_stop_judges': 2,
    'current_stop_wave_id': 1,
    'last_reground_at': '2026-01-01T00:00:00.000Z',
    'last_auditor_verdict': None,
    'contract_status': 'in_progress',
    'latest_completed_slice': 'prompt-budget-slice',
    'latest_verified_slice': 'prompt-budget-slice',
    'workflow_entry_status': 'active',
    'workflow_session_id': 'prompt-budget-session',
}
plan = {
    'schema_version': 1,
    'mission_anchor': state['mission_anchor'],
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
    'last_reground_at': state['last_reground_at'],
    'plan_basis': 'prompt_budget_fixture',
    'candidate_slices': [
        {
            'slice_id': 'prompt-budget-slice',
            'goal': 'Keep prompt reminders compact while preserving canonical routing truth.',
            'acceptance_criteria': [
                'Ordinary chat reminder stays available outside /cook.',
                'Active workflow system reminder stays concise and truthful.'
            ],
            'contract_ids': ['PROMPT-BUDGET-01'],
            'priority': 1,
            'status': 'selected',
            'why_now': 'Prompt-budget regressions should fail before broader workflow coverage runs.',
            'blocked_on': [],
            'evidence': ['Fixture selected for prompt-budget regression coverage.'],
        }
    ],
}
active = {
    'schema_version': 1,
    'mission_anchor': state['mission_anchor'],
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
    'status': 'selected',
    'slice_id': 'prompt-budget-slice',
    'goal': 'Keep prompt reminders compact while preserving canonical routing truth.',
    'contract_ids': ['PROMPT-BUDGET-01'],
    'acceptance_criteria': [
        'Ordinary chat reminder stays available outside /cook.',
        'Active workflow system reminder stays concise and truthful.'
    ],
    'priority': 1,
    'why_now': 'Prompt-budget regressions should fail before broader workflow coverage runs.',
    'blocked_on': [],
    'locked_notes': ['Keep the completion reminder anchored to canonical state only.'],
    'must_fix_findings': [],
    'implementation_surfaces': ['extensions/completion/prompt-surfaces.ts', 'extensions/completion/role-runner.ts'],
    'verification_commands': ['bash scripts/prompt-budget-test.sh', 'bash scripts/role-runner-contract-test.sh'],
    'basis_commit': 'prompt-budget-basis',
    'remaining_contract_ids_before': ['PROMPT-BUDGET-01'],
    'release_blocker_count_before': 0,
    'high_value_gap_count_before': 1,
}
startup_brief = {
    'kind': 'startup_brief',
    'source': 'recent_discussion',
    'confirmed': True,
    'captured_at': '2026-01-01T00:00:00.000Z',
    'goal_text': state['mission_anchor'],
    'mission': state['mission_anchor'],
    'scope': ['Measure prompt budgets for ordinary chat, /cook startup, and active workflow reminders.'],
    'constraints': ['Keep reminder copy concise without changing workflow semantics.'],
    'acceptance': ['Prompt budget regression checks pass.'],
    'risks': ['Over-trimming prompt text could hide critical workflow routing guidance.'],
    'notes': ['This fixture exists only for prompt-budget regression coverage.'],
    'verification_truth_mode': 'deterministic',
    'deterministic_verifier_ready': False,
    'verification_latency': 'fast',
    'verification_noise_risk': 'low',
    'verifier_gap': 'Deterministic reminder coverage is still being established for this workflow.',
    'recommended_first_slice_kind': 'verifier_scaffolding',
    'task_type': state['task_type'],
    'evaluation_profile': state['evaluation_profile'],
}
verification_evidence = {
    'schema_version': 1,
    'artifact_type': 'completion-verification-evidence',
    'subject_type': 'selected_slice',
    'slice_id': 'prompt-budget-slice',
    'goal': active['goal'],
    'contract_ids': active['contract_ids'],
    'basis_commit': active['basis_commit'],
    'head_sha': 'prompt-budget-head',
    'verification_commands': active['verification_commands'],
    'outcome': 'passed',
    'recorded_at': '2026-01-01T00:00:00.000Z',
    'evidence_quality': {
        'status': 'structured_complete',
        'summary': 'Prompt-budget fixture keeps structured evidence concise and fully populated.',
    },
    'command_results': [
        {
            'command': active['verification_commands'][0],
            'outcome': 'passed',
            'summary': 'Prompt-budget regression passed.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
        {
            'command': active['verification_commands'][1],
            'outcome': 'passed',
            'summary': 'Role-runner contract regression passed.',
            'artifact_paths': ['.agent/current/active-slice.json'],
        },
    ],
    'acceptance_coverage': [
        {
            'criterion': active['acceptance_criteria'][0],
            'status': 'covered',
            'summary': 'Ordinary chat reminder remains available in the fixture.',
            'artifact_paths': ['README.md'],
        },
        {
            'criterion': active['acceptance_criteria'][1],
            'status': 'covered',
            'summary': 'Active workflow reminder remains concise in the fixture.',
            'artifact_paths': ['.agent/current/verification-evidence.json'],
        },
    ],
    'flake_signals': [],
    'open_gaps': [],
    'basis_regression_required': False,
    'basis_regression_status': 'not_applicable',
    'basis_regression_reason': 'Basis regression is outside the prompt-budget fixture scope.',
    'basis_regression_artifact_paths': [],
    'summary': 'Prompt-budget fixture verification evidence remains aligned with the selected slice.',
}

(current / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
(current / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
(current / 'active-slice.json').write_text(json.dumps(active, indent=2) + '\n')
(current / 'startup-brief.json').write_text(json.dumps(startup_brief, indent=2) + '\n')
(current / 'verification-evidence.json').write_text(json.dumps(verification_evidence, indent=2) + '\n')
(current / 'slice-history.jsonl').write_text('')
(current / 'stop-check-history.jsonl').write_text('')
PY
}

write_startup_repo() {
  local root="$1"
  mkdir -p "$root"
  (
    cd "$root"
    git init -q
    printf '# prompt budget startup fixture\n' > README.md
  )
}

WORKFLOW_ROOT="$TMPDIR/workflow-repo"
STARTUP_ROOT="$TMPDIR/startup-repo"
ORDINARY_REMINDER="$TMPDIR/ordinary-reminder.txt"
KICKOFF_PROMPT="$TMPDIR/kickoff-prompt.txt"
RESUME_PROMPT="$TMPDIR/resume-prompt.txt"
PRIMARY_HANDOFF_PROMPT="$TMPDIR/primary-handoff-prompt.txt"
PRIMARY_HANDOFF_PROMPT_BUNDLE="$TMPDIR/primary-handoff-prompt-bundle.json"
BOOTSTRAPPER_ROLE_PROMPT_BUNDLE="$TMPDIR/bootstrapper-role-prompt.json"
REGROUNDER_ROLE_PROMPT_BUNDLE="$TMPDIR/regrounder-role-prompt.json"
REVIEWER_ROLE_PROMPT_BUNDLE="$TMPDIR/reviewer-role-prompt.json"
REVIEWER_REPAIR_ROLE_PROMPT_BUNDLE="$TMPDIR/reviewer-repair-role-prompt.json"
AUDITOR_ROLE_PROMPT_BUNDLE="$TMPDIR/auditor-role-prompt.json"
AUDITOR_REPAIR_ROLE_PROMPT_BUNDLE="$TMPDIR/auditor-repair-role-prompt.json"
STOP_JUDGE_ROLE_PROMPT_BUNDLE="$TMPDIR/stop-judge-role-prompt.json"
IMPLEMENTER_ROLE_PROMPT_BUNDLE="$TMPDIR/implementer-role-prompt.json"

write_active_workflow_fixture "$WORKFLOW_ROOT"
write_startup_repo "$STARTUP_ROOT"

(
  cd "$WORKFLOW_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_COOK_HANDOFF_REMINDER_PATH="$ORDINARY_REMINDER" \
  pi -e "$PKG_ROOT" -p "Summarize the repo briefly." \
    >"$TMPDIR/ordinary.out" 2>"$TMPDIR/ordinary.err"
)

BOOTSTRAP_HANDOFF="$(python3 - <<'PY'
import json
capsule = {
    'kind': 'cook_handoff',
    'source': 'primary_agent',
    'captured_at': '2026-01-01T00:00:00.000Z',
    'source_turn_id': 'prompt-budget',
    'mission': 'Measure primary-agent handoff prompt budget coverage.',
    'scope': [
        'Capture the startup prompt used for same-entry /cook handoff synthesis.',
        'Keep prompt-budget regression coverage deterministic.'
    ],
    'constraints': [
        'Do not depend on live model output during prompt-budget regression tests.'
    ],
    'acceptance': [
        'The primary-agent handoff prompt snapshot is written deterministically during the test.'
    ],
    'risks': [
        'Prompt growth could reintroduce unnecessary token burn during /cook startup.'
    ],
    'notes': [
        'This handoff exists only to let prompt-budget coverage bypass live model calls.'
    ],
    'handoff_kind': 'implementation_workflow_handoff',
    'task_type': 'completion-workflow',
    'evaluation_profile': 'completion-rubric-v1',
    'why_cook_now': 'The startup prompt budget should stay under deterministic regression limits.'
}
print('```cook_handoff\n' + json.dumps(capsule, ensure_ascii=False, indent=2) + '\n```')
PY
)"

(
  cd "$STARTUP_ROOT"
  PI_COMPLETION_CONTEXT_PROPOSAL_ACTION=accept \
  PI_COMPLETION_PRIMARY_HANDOFF_OUTPUT="$BOOTSTRAP_HANDOFF" \
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$KICKOFF_PROMPT" \
  PI_COMPLETION_TEST_PRIMARY_HANDOFF_PROMPT_PATH="$PRIMARY_HANDOFF_PROMPT" \
  PI_COMPLETION_TEST_PRIMARY_HANDOFF_PROMPT_BUNDLE_PATH="$PRIMARY_HANDOFF_PROMPT_BUNDLE" \
  pi -e "$PKG_ROOT" -p "/cook add prompt budget coverage and keep the startup prompt compact" \
    >"$TMPDIR/handoff.out" 2>"$TMPDIR/handoff.err"
)

(
  cd "$WORKFLOW_ROOT"
  PI_COMPLETION_SKIP_DRIVER_KICKOFF=1 \
  PI_COMPLETION_TEST_DRIVER_PROMPT_PATH="$RESUME_PROMPT" \
  pi -e "$PKG_ROOT" -p "/cook" \
    >"$TMPDIR/resume.out" 2>"$TMPDIR/resume.err"
)

capture_role_prompt_bundle() {
  local role="$1"
  local bundle_path="$2"
  local repair_prompt="${3:-}"
  local previous_output="${4:-}"
  local system_prompt_file="$TMPDIR/${role}-capture-system.md"
  local events_file="$TMPDIR/${role}-capture-events.jsonl"
  local stderr_file="$TMPDIR/${role}-capture-stderr.txt"
  cat >"$system_prompt_file" <<EOF
You are running a completion role prompt-budget probe.
Call the completion_role tool exactly once with role ${role} and task "Capture the real ${role} role prompt budget.".
After the tool returns, respond with exactly the tool result text and nothing else.
Do not add commentary.
EOF
  local -a env_args=(
    "PI_COMPLETION_TEST_CAPTURE_ROLE_PROMPT_ONLY=1"
    "PI_COMPLETION_TEST_ROLE_PROMPT_BUNDLE_PATH=$bundle_path"
    "PI_COMPLETION_TEST_FORCE_COMPLETION_ROLE=$role"
    "PI_COMPLETION_TEST_FORCE_COMPLETION_TASK=Capture the real ${role} role prompt budget."
  )
  if [[ -n "$repair_prompt" ]]; then
    env_args+=("PI_COMPLETION_TEST_FORCE_REPAIR_PROMPT=$repair_prompt")
    env_args+=("PI_COMPLETION_TEST_FORCE_PREVIOUS_OUTPUT=$previous_output")
  fi
  (
    cd "$WORKFLOW_ROOT"
    set +u
    env \
      -u PI_COMPLETION_ROLE \
      -u PI_COMPLETION_HELPER \
      -u PI_COMPLETION_CALLER_ROLE \
      -u PI_COMPLETION_HELPER_ROOT \
      -u PI_COMPLETION_HELPER_CWD \
      -u PI_COMPLETION_ROLE_MODEL \
      "${env_args[@]}" \
      pi \
        --no-extensions \
        --mode json \
        -p \
        --thinking off \
        --no-session \
        --no-extensions \
        --no-builtin-tools \
        --no-skills \
        --no-prompt-templates \
        --no-context-files \
        -e "$PKG_ROOT" \
        --tools completion_role \
        --append-system-prompt "$system_prompt_file" \
        "Continue the completion workflow and run ${role} now." \
        >"$events_file" 2>"$stderr_file"
    set -u
  )
}

capture_role_prompt_bundle "completion-bootstrapper" "$BOOTSTRAPPER_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-regrounder" "$REGROUNDER_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-reviewer" "$REVIEWER_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-reviewer" "$REVIEWER_REPAIR_ROLE_PROMPT_BUNDLE" "Reviewer repair prompt for prompt-budget coverage." $'MISSION ANCHOR: test\nRemaining contract IDs: TEST\nRubric:\n- Contract coverage: pass - ok\n- Correctness risk: pass - ok\n- Verification evidence: pass - ok\n- Docs/state parity: pass - ok\nFindings: none.\nAcceptable as-is: yes\nSmallest follow-up slice: tighten verification.'
capture_role_prompt_bundle "completion-auditor" "$AUDITOR_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-auditor" "$AUDITOR_REPAIR_ROLE_PROMPT_BUNDLE" "Auditor repair prompt for prompt-budget coverage." $'MISSION ANCHOR: test\nRemaining contract IDs: TEST\nRubric:\n- Contract coverage: concern - open work remains.\n- Correctness risk: concern - more work remains.\n- Verification evidence: concern - more work remains.\n- Docs/state parity: concern - canonical state still active.\nWhy the project is still not done: open work remains.\nOpen top-level contract IDs: TEST\nBlocker count: 1\nHigh-value gap count: 0\nTracked and unignored worktree is clean: yes\nWorktree blockers: modified README.md\nNext mandatory slice: reconcile latest slice\nStale or conflicting canonical state: no - aligned.\nPlan truthfully captures remaining slice backlog: yes - backlog remains aligned.'
capture_role_prompt_bundle "completion-stop-judge" "$STOP_JUDGE_ROLE_PROMPT_BUNDLE"
capture_role_prompt_bundle "completion-implementer" "$IMPLEMENTER_ROLE_PROMPT_BUNDLE"

python3 - "$PKG_ROOT" "$ORDINARY_REMINDER" "$KICKOFF_PROMPT" "$RESUME_PROMPT" "$PRIMARY_HANDOFF_PROMPT" "$PRIMARY_HANDOFF_PROMPT_BUNDLE" "$BOOTSTRAPPER_ROLE_PROMPT_BUNDLE" "$REGROUNDER_ROLE_PROMPT_BUNDLE" "$REVIEWER_ROLE_PROMPT_BUNDLE" "$REVIEWER_REPAIR_ROLE_PROMPT_BUNDLE" "$AUDITOR_ROLE_PROMPT_BUNDLE" "$AUDITOR_REPAIR_ROLE_PROMPT_BUNDLE" "$STOP_JUDGE_ROLE_PROMPT_BUNDLE" "$IMPLEMENTER_ROLE_PROMPT_BUNDLE" <<'PY'
import re
import sys
from pathlib import Path

pkg_root = Path(sys.argv[1])
ordinary_path = Path(sys.argv[2])
kickoff_prompt_path = Path(sys.argv[3])
resume_prompt_path = Path(sys.argv[4])
primary_prompt_path = Path(sys.argv[5])
primary_bundle_path = Path(sys.argv[6])
bootstrapper_bundle_path = Path(sys.argv[7])
regrounder_bundle_path = Path(sys.argv[8])
reviewer_bundle_path = Path(sys.argv[9])
reviewer_repair_bundle_path = Path(sys.argv[10])
auditor_bundle_path = Path(sys.argv[11])
auditor_repair_bundle_path = Path(sys.argv[12])
stop_judge_bundle_path = Path(sys.argv[13])
implementer_bundle_path = Path(sys.argv[14])
source_path = pkg_root / 'extensions' / 'completion' / 'prompt-surfaces.ts'
index_source_path = pkg_root / 'extensions' / 'completion' / 'index.ts'
references_dir = pkg_root / 'skills' / 'completion-protocol' / 'references'
completion_reference_path = references_dir / 'completion.md'
shared_runtime_quick_path = references_dir / 'runtime-quick.md'
quick_reference_paths = {
    'driver_quick_reference': references_dir / 'runtime-quick-driver.md',
    'bootstrapper_quick_reference': references_dir / 'runtime-quick-bootstrapper.md',
    'regrounder_quick_reference': references_dir / 'runtime-quick-regrounder.md',
    'implementer_quick_reference': references_dir / 'runtime-quick-implementer.md',
    'reviewer_quick_reference': references_dir / 'runtime-quick-reviewer.md',
    'auditor_quick_reference': references_dir / 'runtime-quick-auditor.md',
    'stop_judge_quick_reference': references_dir / 'runtime-quick-stop-judge.md',
}

for path in (
    ordinary_path,
    kickoff_prompt_path,
    resume_prompt_path,
    primary_prompt_path,
    primary_bundle_path,
    bootstrapper_bundle_path,
    regrounder_bundle_path,
    reviewer_bundle_path,
    reviewer_repair_bundle_path,
    auditor_bundle_path,
    auditor_repair_bundle_path,
    stop_judge_bundle_path,
    implementer_bundle_path,
    source_path,
    index_source_path,
    completion_reference_path,
    shared_runtime_quick_path,
    *quick_reference_paths.values(),
):
    if not path.exists():
        raise SystemExit(f'[prompt-budget-test] missing expected prompt-budget surface: {path}')

ordinary = ordinary_path.read_text().strip()
kickoff_prompt = kickoff_prompt_path.read_text().strip()
resume_prompt = resume_prompt_path.read_text().strip()
primary = primary_prompt_path.read_text().strip()
primary_bundle = __import__('json').loads(primary_bundle_path.read_text())
bootstrapper_bundle = __import__('json').loads(bootstrapper_bundle_path.read_text())
regrounder_bundle = __import__('json').loads(regrounder_bundle_path.read_text())
reviewer_bundle = __import__('json').loads(reviewer_bundle_path.read_text())
reviewer_repair_bundle = __import__('json').loads(reviewer_repair_bundle_path.read_text())
auditor_bundle = __import__('json').loads(auditor_bundle_path.read_text())
auditor_repair_bundle = __import__('json').loads(auditor_repair_bundle_path.read_text())
stop_judge_bundle = __import__('json').loads(stop_judge_bundle_path.read_text())
implementer_bundle = __import__('json').loads(implementer_bundle_path.read_text())
source = source_path.read_text()
index_source = index_source_path.read_text()
match = re.search(r'export function buildSystemReminder\([\s\S]*?\n}\n\nexport function buildResumeCapsule', source)
if not match:
    raise SystemExit('[prompt-budget-test] could not locate buildSystemReminder source block')
system_source = match.group(0)

text_checks = [
    ('ordinary_reminder', ordinary, 1800),
    ('kickoff_prompt', kickoff_prompt, 3200),
    ('resume_prompt', resume_prompt, 3000),
    ('primary_handoff_prompt', primary, 700),
    ('buildSystemReminder_source', system_source, 3200),
    ('shared_runtime_quick_reference', shared_runtime_quick_path.read_text().strip(), 4200),
    ('completion_full_reference', completion_reference_path.read_text().strip(), 18600),
]
for name, text, limit in text_checks:
    size = len(text)
    if size > limit:
        raise SystemExit(f'[prompt-budget-test] {name} exceeded budget: {size} > {limit}')
    print(f'{name}={size} chars (limit {limit})')

quick_reference_limits = {
    'driver_quick_reference': 1800,
    'bootstrapper_quick_reference': 1300,
    'regrounder_quick_reference': 1800,
    'implementer_quick_reference': 1600,
    'reviewer_quick_reference': 1000,
    'auditor_quick_reference': 1200,
    'stop_judge_quick_reference': 1400,
}
for name, path in quick_reference_paths.items():
    text = path.read_text().strip()
    limit = quick_reference_limits[name]
    size = len(text)
    if size > limit:
        raise SystemExit(f'[prompt-budget-test] {name} exceeded budget: {size} > {limit}')
    print(f'{name}={size} chars (limit {limit})')

if 'startupVerifierPostureLine' not in system_source:
    raise SystemExit('[prompt-budget-test] buildSystemReminder should accept a startupVerifierPostureLine input')
if 'Verification evidence structured:' not in system_source:
    raise SystemExit('[prompt-budget-test] buildSystemReminder should surface a structured verification evidence summary')
if 'verification_evidence_focus: read structured evidence fields directly from ${evidence.path}' not in source:
    raise SystemExit('[prompt-budget-test] evaluation handoff source should point roles at the structured verification evidence fields')
if '`- verification_evidence_structured: ${evidence.structuredSummary}`' not in source:
    raise SystemExit('[prompt-budget-test] prompt surfaces should expose a concise structured verification evidence summary line')
if 'Startup verifier posture:' not in index_source:
    raise SystemExit('[prompt-budget-test] index reminder source should label startup verifier posture explicitly')
if 'recommended_first_slice_kind=' not in index_source or 'deterministic_verifier_ready=' not in index_source:
    raise SystemExit('[prompt-budget-test] startup verifier posture summary should include canonical field names in index.ts')
if 'Canonical verification evidence structured summary is currently:' not in index_source:
    raise SystemExit('[prompt-budget-test] post-compaction reminder should expose the structured verification evidence summary in index.ts')

regrounder_quick = quick_reference_paths['regrounder_quick_reference'].read_text().strip()
implementer_quick = quick_reference_paths['implementer_quick_reference'].read_text().strip()
if 'verifier_scaffolding' not in regrounder_quick or 'deterministic verifier readiness is missing' not in regrounder_quick:
    raise SystemExit('[prompt-budget-test] regrounder quick reference should document verifier_scaffolding preference')
if 'verifier_scaffolding' not in implementer_quick:
    raise SystemExit('[prompt-budget-test] implementer quick reference should treat verifier_scaffolding as a valid slice kind')

bundle_checks = [
    ('primary_handoff_prompt_combined', primary_bundle, 2700),
    ('bootstrapper_role_prompt_combined', bootstrapper_bundle, 4150),
    ('regrounder_role_prompt_combined', regrounder_bundle, 6000),
    ('reviewer_role_prompt_combined', reviewer_bundle, 4900),
    ('reviewer_repair_role_prompt_combined', reviewer_repair_bundle, 5400),
    ('auditor_role_prompt_combined', auditor_bundle, 5750),
    ('auditor_repair_role_prompt_combined', auditor_repair_bundle, 6600),
    ('stop_judge_role_prompt_combined', stop_judge_bundle, 5650),
    ('implementer_role_prompt_combined', implementer_bundle, 7000),
]
for name, bundle, limit in bundle_checks:
    size = bundle.get('combined_prompt_chars')
    if not isinstance(size, int):
        raise SystemExit(f'[prompt-budget-test] {name} bundle did not report combined_prompt_chars')
    if size > limit:
        raise SystemExit(f'[prompt-budget-test] {name} exceeded budget: {size} > {limit}')
    print(f'{name}={size} chars (limit {limit})')

if primary_bundle.get('kind') != 'primary-handoff':
    raise SystemExit(f"[prompt-budget-test] primary handoff bundle kind mismatch: {primary_bundle.get('kind')!r}")
if bootstrapper_bundle.get('role') != 'completion-bootstrapper':
    raise SystemExit(f"[prompt-budget-test] bootstrapper bundle role mismatch: {bootstrapper_bundle.get('role')!r}")
if regrounder_bundle.get('role') != 'completion-regrounder':
    raise SystemExit(f"[prompt-budget-test] regrounder bundle role mismatch: {regrounder_bundle.get('role')!r}")
if reviewer_bundle.get('role') != 'completion-reviewer':
    raise SystemExit(f"[prompt-budget-test] reviewer bundle role mismatch: {reviewer_bundle.get('role')!r}")
if reviewer_repair_bundle.get('role') != 'completion-reviewer' or reviewer_repair_bundle.get('repair_mode') is not True:
    raise SystemExit('[prompt-budget-test] reviewer repair bundle should capture completion-reviewer in repair mode')
if auditor_bundle.get('role') != 'completion-auditor':
    raise SystemExit(f"[prompt-budget-test] auditor bundle role mismatch: {auditor_bundle.get('role')!r}")
if auditor_repair_bundle.get('role') != 'completion-auditor' or auditor_repair_bundle.get('repair_mode') is not True:
    raise SystemExit('[prompt-budget-test] auditor repair bundle should capture completion-auditor in repair mode')
if stop_judge_bundle.get('role') != 'completion-stop-judge':
    raise SystemExit(f"[prompt-budget-test] stop-judge bundle role mismatch: {stop_judge_bundle.get('role')!r}")
if implementer_bundle.get('role') != 'completion-implementer':
    raise SystemExit(f"[prompt-budget-test] implementer bundle role mismatch: {implementer_bundle.get('role')!r}")
if any(bundle.get('repair_mode') is not False for bundle in (bootstrapper_bundle, regrounder_bundle, reviewer_bundle, auditor_bundle, stop_judge_bundle, implementer_bundle)):
    raise SystemExit('[prompt-budget-test] normal role capture should stay outside repair mode')
if 'verifier_scaffolding' not in regrounder_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] regrounder combined prompt should mention verifier_scaffolding guidance')
if 'verifier_scaffolding' not in implementer_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] implementer combined prompt should mention verifier_scaffolding guidance')
if 'evidence_quality' not in implementer_bundle.get('combined_prompt', '') or 'command_results' not in implementer_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] implementer combined prompt should mention the structured verification evidence fields directly')
if 'verification_evidence_structured' not in reviewer_bundle.get('combined_prompt', '') or 'evidence_quality' not in reviewer_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] reviewer combined prompt should include structured verification evidence guidance')
if 'verification_evidence_structured' not in auditor_bundle.get('combined_prompt', '') or 'evidence_quality' not in auditor_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] auditor combined prompt should include structured verification evidence guidance')
if 'verification_evidence_structured' not in stop_judge_bundle.get('combined_prompt', '') or 'evidence_quality' not in stop_judge_bundle.get('combined_prompt', ''):
    raise SystemExit('[prompt-budget-test] stop-judge combined prompt should include structured verification evidence guidance')
PY

echo "prompt budget test passed: $TMPDIR"
