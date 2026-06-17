#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
cleanup() {
  local status=$?
  if [[ "${PI_HELPER_PACKAGING_KEEP_TMP:-0}" == "1" ]]; then
    echo "[helper-packaging-smoke-test] kept temp dir: $TMPDIR" >&2
  else
    rm -rf "$TMPDIR"
  fi
  return $status
}
trap cleanup EXIT

PACK_JSON="$(npm pack --json --pack-destination "$TMPDIR")"
TARBALL_NAME="$(python3 - "$PACK_JSON" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
if not isinstance(payload, list) or not payload:
    raise SystemExit('npm pack --json returned no package payload')
filename = payload[0].get('filename')
if not isinstance(filename, str) or not filename:
    raise SystemExit('npm pack --json omitted the tarball filename')
print(filename)
PY
)"
PACKAGE_NAME="$(python3 - "$ROOT/package.json" <<'PY'
import json
import sys
from pathlib import Path
package = json.loads(Path(sys.argv[1]).read_text())
name = package.get('name')
if not isinstance(name, str) or not name:
    raise SystemExit('package.json is missing name')
print(name)
PY
)"
TARBALL_PATH="$TMPDIR/$TARBALL_NAME"
TAR_CONTENTS="$TMPDIR/tar-contents.txt"
tar -tzf "$TARBALL_PATH" >"$TAR_CONTENTS"

python3 - "$TAR_CONTENTS" <<'PY'
import sys
from pathlib import Path

required = {
    'package/helpers/scout.md',
    'package/helpers/critic.md',
    'package/extensions/helper-tools/index.ts',
    'package/scripts/helper-runtime-capability-test.sh',
    'package/scripts/helper-packaging-smoke-test.sh',
}
contents = set(Path(sys.argv[1]).read_text().splitlines())
missing = sorted(required - contents)
if missing:
    raise SystemExit('[helper-packaging-smoke-test] packed tarball is missing required helper assets: ' + ', '.join(missing))
PY

PACKAGE_ROOT_UNDER_TEST="$TMPDIR/install/node_modules/$PACKAGE_NAME"
mkdir -p "$PACKAGE_ROOT_UNDER_TEST"
tar -xzf "$TARBALL_PATH" -C "$PACKAGE_ROOT_UNDER_TEST" --strip-components=1

python3 - "$PACKAGE_ROOT_UNDER_TEST/package.json" "$PACKAGE_ROOT_UNDER_TEST" <<'PY'
import json
import sys
from pathlib import Path

package_json = Path(sys.argv[1])
package_root = Path(sys.argv[2])
package = json.loads(package_json.read_text())
files = package.get('files')
if not isinstance(files, list):
    raise SystemExit('[helper-packaging-smoke-test] packaged package.json is missing files[]')
if 'helpers' not in files:
    raise SystemExit('[helper-packaging-smoke-test] package.json files[] must include helpers for packaged helper prompts')

scripts = package.get('scripts')
if not isinstance(scripts, dict):
    raise SystemExit('[helper-packaging-smoke-test] packaged package.json is missing scripts{}')
for script_name in ('helper-runtime-capability-test', 'helper-packaging-smoke-test'):
    if not isinstance(scripts.get(script_name), str) or not scripts.get(script_name):
        raise SystemExit(f'[helper-packaging-smoke-test] package.json scripts.{script_name} is missing')

pi_manifest = package.get('pi')
if not isinstance(pi_manifest, dict):
    raise SystemExit('[helper-packaging-smoke-test] packaged package.json is missing pi manifest')
extensions = pi_manifest.get('extensions')
if not isinstance(extensions, list):
    raise SystemExit('[helper-packaging-smoke-test] packaged pi.extensions is missing')
if './extensions/helper-tools' in extensions:
    raise SystemExit('[helper-packaging-smoke-test] helper-tools extension must stay explicit-load only during the capability-gate slice')
if './extensions/completion' not in extensions:
    raise SystemExit('[helper-packaging-smoke-test] packaged pi.extensions unexpectedly dropped ./extensions/completion')

for rel_path in ('helpers/scout.md', 'helpers/critic.md', 'extensions/helper-tools/index.ts'):
    target = package_root / rel_path
    if not target.is_file():
        raise SystemExit(f'[helper-packaging-smoke-test] extracted packaged artifact is missing {rel_path}')
    if target.stat().st_size <= 0:
        raise SystemExit(f'[helper-packaging-smoke-test] extracted packaged artifact has empty file {rel_path}')
PY

if [[ "${PI_HELPER_PACKAGING_SKIP_RUNTIME:-0}" != "1" ]]; then
  PI_HELPER_CAPABILITY_PACKAGE_ROOT="$PACKAGE_ROOT_UNDER_TEST" bash "$ROOT/scripts/helper-runtime-capability-test.sh"
fi

echo "helper packaging smoke test passed: $PACKAGE_ROOT_UNDER_TEST"
