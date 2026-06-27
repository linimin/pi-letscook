#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run-basis-regression-check.sh --basis <commit> --verify-command <command> [--artifact-dir <repo-relative-dir>]
  bash scripts/run-basis-regression-check.sh --status <not_run|not_applicable> --reason <text> [--basis <commit>] [--artifact-dir <repo-relative-dir>]

Run the supplied verification command on current HEAD and again in a disposable temp
worktree checked out at the basis commit. The script prints a JSON artifact with
basis_regression_required, basis_regression_status, basis_regression_reason, and
safe repo-relative artifact paths that can be copied into
.agent/current/verification-evidence.json.

Status-only mode records a truthful non-pass posture without executing the temp-worktree flow:
- not_run: basis regression was eligible but intentionally skipped or could not be run truthfully
- not_applicable: the slice is not an eligible bugfix/regression slice for basis regression
EOF
}

fail() {
  echo "[basis-regression] $*" >&2
  exit 1
}

normalize_repo_relative_path() {
  python3 - "$1" <<'PY'
import posixpath
import re
import sys

candidate = (sys.argv[1] or '').strip().replace('\\', '/')
if not candidate:
    raise SystemExit(1)
if candidate.startswith('/'):
    raise SystemExit(1)
if re.match(r'^[A-Za-z]:/', candidate):
    raise SystemExit(1)
normalized = posixpath.normpath(candidate)
if normalized == '.' or normalized.startswith('../') or '/../' in normalized:
    raise SystemExit(1)
print(normalized)
PY
}

safe_repo_relative_path() {
  local normalized
  if ! normalized="$(normalize_repo_relative_path "$1")"; then
    fail "artifact paths must stay repo-relative and must not escape the repo root: $1"
  fi
  printf '%s\n' "$normalized"
}

read_active_basis_commit() {
  if [[ ! -f .agent/current/active-slice.json ]]; then
    return 0
  fi
  python3 - <<'PY'
import json
from pathlib import Path

path = Path('.agent/current/active-slice.json')
try:
    payload = json.loads(path.read_text())
except Exception:
    raise SystemExit(0)
value = payload.get('basis_commit')
if isinstance(value, str) and value.strip():
    print(value.strip())
PY
}

write_result() {
  local result_abs="$1"
  local result_rel="$2"
  BASIS_RESULT_ABS="$result_abs" \
  BASIS_RESULT_REL="$result_rel" \
  BASIS_HEAD_SHA="$HEAD_SHA" \
  BASIS_COMMIT_VALUE="${BASIS_COMMIT:-}" \
  BASIS_REQUIRED_VALUE="$BASIS_REQUIRED_VALUE" \
  BASIS_STATUS_VALUE="$BASIS_STATUS_VALUE" \
  BASIS_REASON_VALUE="$BASIS_REASON_VALUE" \
  BASIS_VERIFY_COMMAND_VALUE="${VERIFY_COMMAND:-}" \
  BASIS_HEAD_EXIT_VALUE="${BASIS_HEAD_EXIT_VALUE:-}" \
  BASIS_BASIS_EXIT_VALUE="${BASIS_BASIS_EXIT_VALUE:-}" \
  BASIS_HEAD_LOG_REL_VALUE="${BASIS_HEAD_LOG_REL_VALUE:-}" \
  BASIS_BASIS_LOG_REL_VALUE="${BASIS_BASIS_LOG_REL_VALUE:-}" \
  python3 - <<'PY'
import json
import os
from pathlib import Path


def optional_int(name: str):
    raw = os.environ.get(name, '').strip()
    if raw == '':
        return None
    return int(raw)

artifact_paths = [
    path for path in [
        os.environ['BASIS_RESULT_REL'],
        os.environ.get('BASIS_HEAD_LOG_REL_VALUE', '').strip(),
        os.environ.get('BASIS_BASIS_LOG_REL_VALUE', '').strip(),
    ] if path
]

payload = {
    'schema_version': 1,
    'artifact_type': 'basis-regression-result',
    'head_sha': os.environ.get('BASIS_HEAD_SHA') or None,
    'basis_commit': os.environ.get('BASIS_COMMIT_VALUE') or None,
    'basis_regression_required': os.environ.get('BASIS_REQUIRED_VALUE') == 'true',
    'basis_regression_status': os.environ['BASIS_STATUS_VALUE'],
    'basis_regression_reason': os.environ['BASIS_REASON_VALUE'],
    'basis_regression_artifact_paths': artifact_paths,
    'verify_command': os.environ.get('BASIS_VERIFY_COMMAND_VALUE') or None,
    'head_command_exit_code': optional_int('BASIS_HEAD_EXIT_VALUE'),
    'basis_command_exit_code': optional_int('BASIS_BASIS_EXIT_VALUE'),
}

result_path = Path(os.environ['BASIS_RESULT_ABS'])
result_path.parent.mkdir(parents=True, exist_ok=True)
result_path.write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
print(json.dumps(payload, indent=2))
PY
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
cd "$REPO_ROOT"
HEAD_SHA="$(git rev-parse HEAD)"

BASIS_COMMIT=""
VERIFY_COMMAND=""
STATUS_OVERRIDE=""
REASON=""
ARTIFACT_DIR_INPUT=".agent/current/tmp/basis-regression"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --basis)
      [[ $# -ge 2 ]] || fail "--basis requires a commit"
      BASIS_COMMIT="$2"
      shift 2
      ;;
    --verify-command)
      [[ $# -ge 2 ]] || fail "--verify-command requires a shell command"
      VERIFY_COMMAND="$2"
      shift 2
      ;;
    --status)
      [[ $# -ge 2 ]] || fail "--status requires not_run or not_applicable"
      STATUS_OVERRIDE="$2"
      shift 2
      ;;
    --reason)
      [[ $# -ge 2 ]] || fail "--reason requires non-empty text"
      REASON="$2"
      shift 2
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || fail "--artifact-dir requires a repo-relative directory"
      ARTIFACT_DIR_INPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

ARTIFACT_DIR_REL="$(safe_repo_relative_path "$ARTIFACT_DIR_INPUT")"
ARTIFACT_DIR_ABS="$REPO_ROOT/$ARTIFACT_DIR_REL"
mkdir -p "$ARTIFACT_DIR_ABS"

if [[ -z "$BASIS_COMMIT" ]]; then
  BASIS_COMMIT="$(read_active_basis_commit || true)"
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR_REL="$ARTIFACT_DIR_REL/$RUN_ID"
RUN_DIR_ABS="$REPO_ROOT/$RUN_DIR_REL"
mkdir -p "$RUN_DIR_ABS"
RESULT_REL="$RUN_DIR_REL/result.json"
RESULT_ABS="$REPO_ROOT/$RESULT_REL"

BASIS_REQUIRED_VALUE="false"
BASIS_STATUS_VALUE=""
BASIS_REASON_VALUE=""
BASIS_HEAD_EXIT_VALUE=""
BASIS_BASIS_EXIT_VALUE=""
BASIS_HEAD_LOG_REL_VALUE=""
BASIS_BASIS_LOG_REL_VALUE=""

BASIS_WORKTREE_DIR=""
cleanup() {
  if [[ -n "$BASIS_WORKTREE_DIR" ]]; then
    git worktree remove --force "$BASIS_WORKTREE_DIR" >/dev/null 2>&1 || true
    rm -rf "$BASIS_WORKTREE_DIR"
  fi
}
trap cleanup EXIT

if [[ -n "$STATUS_OVERRIDE" ]]; then
  [[ -z "$VERIFY_COMMAND" ]] || fail "--status mode does not accept --verify-command"
  case "$STATUS_OVERRIDE" in
    not_run)
      BASIS_REQUIRED_VALUE="true"
      ;;
    not_applicable)
      BASIS_REQUIRED_VALUE="false"
      ;;
    *)
      fail "--status must be not_run or not_applicable"
      ;;
  esac
  [[ -n "${REASON// }" ]] || fail "--reason is required in --status mode"
  BASIS_STATUS_VALUE="$STATUS_OVERRIDE"
  BASIS_REASON_VALUE="$REASON"
  write_result "$RESULT_ABS" "$RESULT_REL"
  exit 0
fi

[[ -n "$VERIFY_COMMAND" ]] || fail "--verify-command is required unless --status is used"
[[ -n "$BASIS_COMMIT" ]] || fail "--basis is required when .agent/current/active-slice.json does not provide basis_commit"
git rev-parse --verify "${BASIS_COMMIT}^{commit}" >/dev/null 2>&1 || fail "basis commit does not resolve to a commit: $BASIS_COMMIT"

BASIS_REQUIRED_VALUE="true"
BASIS_HEAD_LOG_REL_VALUE="$RUN_DIR_REL/head-command.log"
BASIS_HEAD_LOG_ABS="$REPO_ROOT/$BASIS_HEAD_LOG_REL_VALUE"

set +e
(
  cd "$REPO_ROOT"
  bash -lc "$VERIFY_COMMAND"
) >"$BASIS_HEAD_LOG_ABS" 2>&1
BASIS_HEAD_EXIT_VALUE="$?"
set -e

if [[ "$BASIS_HEAD_EXIT_VALUE" != "0" ]]; then
  BASIS_STATUS_VALUE="not_run"
  BASIS_REASON_VALUE="Verification command failed on current HEAD, so the temp-worktree basis regression check could not be completed truthfully."
  write_result "$RESULT_ABS" "$RESULT_REL"
  exit 0
fi

BASIS_WORKTREE_DIR="$(mktemp -d "$RUN_DIR_ABS/basis-worktree-XXXXXX")"
git worktree add --quiet --detach "$BASIS_WORKTREE_DIR" "$BASIS_COMMIT" >/dev/null
BASIS_BASIS_LOG_REL_VALUE="$RUN_DIR_REL/basis-command.log"
BASIS_BASIS_LOG_ABS="$REPO_ROOT/$BASIS_BASIS_LOG_REL_VALUE"

set +e
(
  cd "$BASIS_WORKTREE_DIR"
  bash -lc "$VERIFY_COMMAND"
) >"$BASIS_BASIS_LOG_ABS" 2>&1
BASIS_BASIS_EXIT_VALUE="$?"
set -e

if [[ "$BASIS_BASIS_EXIT_VALUE" == "0" ]]; then
  BASIS_STATUS_VALUE="passed_on_basis"
  BASIS_REASON_VALUE="Verification command passed on current HEAD and on basis commit $BASIS_COMMIT, so the negative-control check did not distinguish the regression."
else
  BASIS_STATUS_VALUE="failed_on_basis"
  BASIS_REASON_VALUE="Verification command passed on current HEAD but failed on basis commit $BASIS_COMMIT."
fi

write_result "$RESULT_ABS" "$RESULT_REL"
