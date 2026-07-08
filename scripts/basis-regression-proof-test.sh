#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d)"
cleanup() {
  local status=$?
  rm -rf "$TMPDIR"
  return $status
}
trap cleanup EXIT

cd "$PKG_ROOT"

node <<'NODE'
const fs = require('node:fs');

const read = (file) => fs.readFileSync(file, 'utf8');
const assertIncludes = (file, snippet) => {
  const text = read(file);
  if (!text.includes(snippet)) {
    throw new Error(`${file} is missing required basis-regression text: ${snippet}`);
  }
};

assertIncludes('docs/maintainer/protocol.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('docs/maintainer/protocol.md', 'failed_on_basis');
assertIncludes('docs/maintainer/protocol.md', 'passed_on_basis');
assertIncludes('docs/maintainer/protocol.md', 'not_run');
assertIncludes('docs/maintainer/protocol.md', 'not_applicable');
assertIncludes('skills/completion-protocol/SKILL.md', 'run-basis-regression-check.sh');
assertIncludes('skills/completion-protocol/SKILL.md', 'failed_on_basis');
assertIncludes('skills/completion-protocol/SKILL.md', 'not_run');
assertIncludes('skills/completion-protocol/SKILL.md', 'not_applicable');
assertIncludes('skills/completion-protocol/references/completion.md', 'run-basis-regression-check.sh');
assertIncludes('skills/completion-protocol/references/completion.md', 'failed_on_basis');
assertIncludes('skills/completion-protocol/references/completion.md', 'not_run');
assertIncludes('skills/completion-protocol/references/completion.md', 'not_applicable');
assertIncludes('agents/completion-implementer.md', 'bash scripts/run-basis-regression-check.sh');
assertIncludes('agents/completion-implementer.md', '`not_run`');
assertIncludes('agents/completion-reviewer.md', '`not_run`');
assertIncludes('agents/completion-reviewer.md', '`not_applicable`');
assertIncludes('scripts/release-check.sh', 'bash ./scripts/basis-regression-proof-test.sh');
assertIncludes('scripts/verify-completion-control-plane.js', 'basis_regression_status must not be not_applicable when basis_regression_required=true');
assertIncludes('scripts/verify-completion-control-plane.js', 'basis_regression_artifact_paths must not be empty when basis_regression_status records an executed basis check');
NODE

ROOT="$TMPDIR/repo"
mkdir -p "$ROOT"
cd "$ROOT"
git init -q
git config user.name 'Basis Regression Test'
git config user.email 'basis-regression-test@example.com'

cat > verify-fixed.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "expect fixed on $(git rev-parse --short HEAD)"
[[ "$(cat behavior.txt)" == "fixed" ]]
SH
chmod +x verify-fixed.sh

cat > verify-exists.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "shared verifier on $(git rev-parse --short HEAD)"
[[ -f verify-exists.sh ]]
SH
chmod +x verify-exists.sh

echo 'broken' > behavior.txt
git add behavior.txt verify-fixed.sh verify-exists.sh
git commit -qm 'basis snapshot'
BASIS_SHA="$(git rev-parse HEAD)"

echo 'fixed' > behavior.txt
git add behavior.txt
git commit -qm 'fix regression'
HEAD_SHA="$(git rev-parse HEAD)"

FAILED_JSON="$TMPDIR/failed-on-basis.json"
bash "$PKG_ROOT/scripts/run-basis-regression-check.sh" --basis "$BASIS_SHA" --verify-command 'bash ./verify-fixed.sh' >"$FAILED_JSON"

python3 - "$FAILED_JSON" "$ROOT" "$BASIS_SHA" "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
basis_sha = sys.argv[3]
head_sha = sys.argv[4]

assert payload['artifact_type'] == 'basis-regression-result', payload
assert payload['basis_regression_required'] is True, payload
assert payload['basis_regression_status'] == 'failed_on_basis', payload
assert payload['basis_commit'] == basis_sha, payload
assert payload['head_sha'] == head_sha, payload
assert 'failed on basis commit' in payload['basis_regression_reason'], payload
assert payload['head_command_exit_code'] == 0, payload
assert payload['basis_command_exit_code'] != 0, payload
paths = payload['basis_regression_artifact_paths']
assert len(paths) >= 3, payload
head_log = None
basis_log = None
for rel in paths:
    rel_path = Path(rel)
    assert not rel_path.is_absolute(), rel
    assert '..' not in rel_path.parts, rel
    abs_path = root / rel_path
    assert abs_path.exists(), abs_path
    if rel.endswith('head-command.log'):
        head_log = abs_path
    if rel.endswith('basis-command.log'):
        basis_log = abs_path
assert head_log is not None, payload
assert basis_log is not None, payload
assert 'expect fixed' in head_log.read_text(), head_log.read_text()
assert 'expect fixed' in basis_log.read_text(), basis_log.read_text()
PY

[[ "$(git worktree list --porcelain | grep -c '^worktree ')" == "1" ]] || {
  echo 'expected temp-worktree cleanup after failed_on_basis proof run' >&2
  exit 1
}

PASSED_JSON="$TMPDIR/passed-on-basis.json"
bash "$PKG_ROOT/scripts/run-basis-regression-check.sh" --basis "$BASIS_SHA" --verify-command 'bash ./verify-exists.sh' >"$PASSED_JSON"

python3 - "$PASSED_JSON" "$ROOT" "$BASIS_SHA" "$HEAD_SHA" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
basis_sha = sys.argv[3]
head_sha = sys.argv[4]

assert payload['basis_regression_required'] is True, payload
assert payload['basis_regression_status'] == 'passed_on_basis', payload
assert payload['basis_commit'] == basis_sha, payload
assert payload['head_sha'] == head_sha, payload
assert 'did not distinguish the regression' in payload['basis_regression_reason'], payload
assert payload['head_command_exit_code'] == 0, payload
assert payload['basis_command_exit_code'] == 0, payload
for rel in payload['basis_regression_artifact_paths']:
    abs_path = root / rel
    assert abs_path.exists(), abs_path
PY

[[ "$(git worktree list --porcelain | grep -c '^worktree ')" == "1" ]] || {
  echo 'expected temp-worktree cleanup after passed_on_basis proof run' >&2
  exit 1
}

NOT_RUN_JSON="$TMPDIR/not-run.json"
bash "$PKG_ROOT/scripts/run-basis-regression-check.sh" --status not_run --reason 'Provider credentials were unavailable for the temp-worktree rerun.' >"$NOT_RUN_JSON"
python3 - "$NOT_RUN_JSON" "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
assert payload['basis_regression_required'] is True, payload
assert payload['basis_regression_status'] == 'not_run', payload
assert payload['basis_regression_reason'] == 'Provider credentials were unavailable for the temp-worktree rerun.', payload
paths = payload['basis_regression_artifact_paths']
assert len(paths) == 1, payload
assert (root / paths[0]).exists(), paths[0]
PY

NOT_APPLICABLE_JSON="$TMPDIR/not-applicable.json"
bash "$PKG_ROOT/scripts/run-basis-regression-check.sh" --status not_applicable --reason 'This fixture represents a docs-only slice.' >"$NOT_APPLICABLE_JSON"
python3 - "$NOT_APPLICABLE_JSON" "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
assert payload['basis_regression_required'] is False, payload
assert payload['basis_regression_status'] == 'not_applicable', payload
assert payload['basis_regression_reason'] == 'This fixture represents a docs-only slice.', payload
paths = payload['basis_regression_artifact_paths']
assert len(paths) == 1, payload
assert (root / paths[0]).exists(), paths[0]
PY

if bash "$PKG_ROOT/scripts/run-basis-regression-check.sh" --status not_applicable --reason 'bad path' --artifact-dir ../unsafe >/dev/null 2>&1; then
  echo 'expected run-basis-regression-check.sh to reject unsafe artifact directories' >&2
  exit 1
fi

echo "basis regression proof test passed: $TMPDIR"
