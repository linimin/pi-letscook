#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PI_BIN="${PI_HELPER_CAPABILITY_PI_BIN:-pi}"
command -v "$PI_BIN" >/dev/null 2>&1 || {
  echo "[helper-runtime-capability-test] missing pi executable: $PI_BIN" >&2
  exit 1
}

TMPDIR="$(mktemp -d)"
cleanup() {
  local status=$?
  if [[ "${PI_HELPER_CAPABILITY_KEEP_TMP:-0}" == "1" ]]; then
    echo "[helper-runtime-capability-test] kept temp dir: $TMPDIR" >&2
  else
    rm -rf "$TMPDIR"
  fi
  return $status
}
trap cleanup EXIT

PACKAGE_ROOT_UNDER_TEST=""

prepare_packaged_root() {
  if [[ -n "${PI_HELPER_CAPABILITY_PACKAGE_ROOT:-}" ]]; then
    PACKAGE_ROOT_UNDER_TEST="$(cd "${PI_HELPER_CAPABILITY_PACKAGE_ROOT}" && pwd)"
    return
  fi

  local pack_json tarball_name package_name tarball_path
  pack_json="$(npm pack --json --pack-destination "$TMPDIR")"
  tarball_name="$(python3 - "$pack_json" <<'PY'
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
  package_name="$(python3 - "$ROOT/package.json" <<'PY'
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
  tarball_path="$TMPDIR/$tarball_name"
  PACKAGE_ROOT_UNDER_TEST="$TMPDIR/install/node_modules/$package_name"
  mkdir -p "$PACKAGE_ROOT_UNDER_TEST"
  tar -xzf "$tarball_path" -C "$PACKAGE_ROOT_UNDER_TEST" --strip-components=1
}

prepare_packaged_root

[[ -f "$PACKAGE_ROOT_UNDER_TEST/package.json" ]] || {
  echo "[helper-runtime-capability-test] packaged helper test root is missing package.json: $PACKAGE_ROOT_UNDER_TEST" >&2
  exit 1
}
if [[ "$(cd "$PACKAGE_ROOT_UNDER_TEST" && pwd)" == "$ROOT" ]]; then
  echo "[helper-runtime-capability-test] expected a packed or package-installed artifact, not the source tree" >&2
  exit 1
fi

HELPER_EXTENSION="$PACKAGE_ROOT_UNDER_TEST/extensions/helper-tools"
[[ -f "$HELPER_EXTENSION/index.ts" ]] || {
  echo "[helper-runtime-capability-test] helper-tools extension entrypoint is missing from packaged artifact: $HELPER_EXTENSION/index.ts" >&2
  exit 1
}

SYSTEM_PROMPT_FILE="$TMPDIR/helper-runtime-probe-system.md"
cat >"$SYSTEM_PROMPT_FILE" <<'EOF'
You are running a packaged helper-runtime capability probe.
Call the completion_helper_capability_probe tool exactly once.
After the tool returns, respond with exactly the JSON object from the tool result and nothing else.
Do not wrap the JSON in markdown or add commentary.
EOF

EVENTS_FILE="$TMPDIR/helper-runtime-events.jsonl"
STDERR_FILE="$TMPDIR/helper-runtime-stderr.txt"
PROMPT_TEXT="Run the packaged helper runtime capability probe now."

set +e
env \
  -u PI_COMPLETION_ROLE \
  -u PI_COMPLETION_HELPER \
  -u PI_COMPLETION_CALLER_ROLE \
  -u PI_COMPLETION_HELPER_ROOT \
  -u PI_COMPLETION_HELPER_CWD \
  -u PI_COMPLETION_ROLE_MODEL \
  "$PI_BIN" \
  --mode json \
  -p \
  --thinking off \
  --no-session \
  --no-extensions \
  --no-builtin-tools \
  --no-skills \
  --no-prompt-templates \
  --no-context-files \
  -e "$HELPER_EXTENSION" \
  --tools completion_helper_capability_probe \
  --append-system-prompt "$SYSTEM_PROMPT_FILE" \
  "$PROMPT_TEXT" \
  >"$EVENTS_FILE" 2>"$STDERR_FILE"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "[helper-runtime-capability-test] pi exited with status $status" >&2
  [[ -s "$STDERR_FILE" ]] && cat "$STDERR_FILE" >&2
  [[ -s "$EVENTS_FILE" ]] && tail -n 40 "$EVENTS_FILE" >&2
  exit $status
fi

python3 - "$EVENTS_FILE" "$STDERR_FILE" "$PACKAGE_ROOT_UNDER_TEST" "$HELPER_EXTENSION" <<'PY'
import json
import sys
from pathlib import Path

PROBE_TOOL = 'completion_helper_capability_probe'

def fail(message: str) -> None:
    raise SystemExit(f'[helper-runtime-capability-test] {message}')

def load_events(path: Path):
    events = []
    for index, raw in enumerate(path.read_text().splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            events.append(json.loads(raw))
        except json.JSONDecodeError as exc:
            fail(f'invalid JSON event on line {index}: {exc}')
    if not events:
        fail('pi emitted no JSON events')
    return events

def content_text(message: dict) -> str:
    content = message.get('content')
    if not isinstance(content, list):
        return ''
    parts = []
    for item in content:
        if isinstance(item, dict) and item.get('type') == 'text' and isinstance(item.get('text'), str):
            parts.append(item['text'])
    return ''.join(parts).strip()


events_path = Path(sys.argv[1])
stderr_path = Path(sys.argv[2])
expected_root = Path(sys.argv[3]).resolve()
expected_extension = Path(sys.argv[4]).resolve()
events = load_events(events_path)

probe_start = next((event for event in events if event.get('type') == 'tool_execution_start' and event.get('toolName') == PROBE_TOOL), None)
if probe_start is None:
    fail('assistant never invoked completion_helper_capability_probe')
probe_call_id = probe_start.get('toolCallId')
if not isinstance(probe_call_id, str) or not probe_call_id:
    fail('probe tool call did not include toolCallId')

probe_updates = [
    event for event in events
    if event.get('type') == 'tool_execution_update' and event.get('toolCallId') == probe_call_id
]
if not probe_updates:
    fail('missing tool_execution_update events for completion_helper_capability_probe')

probe_end = next(
    (
        event for event in events
        if event.get('type') == 'tool_execution_end' and event.get('toolCallId') == probe_call_id
    ),
    None,
)
if probe_end is None:
    fail('missing tool_execution_end for completion_helper_capability_probe')
result = probe_end.get('result')
if not isinstance(result, dict):
    fail('tool_execution_end result is not an object')
payload = result.get('details')
if not isinstance(payload, dict):
    fail('probe tool result did not include structured details payload')

if payload.get('ok') is not True:
    fail(f'probe payload did not report ok=true: {payload}')
if payload.get('probe') != PROBE_TOOL:
    fail(f'probe payload returned unexpected probe id: {payload.get("probe")}')
if Path(payload.get('packageRoot', '')).resolve() != expected_root:
    fail(f'probe payload packageRoot mismatch: {payload.get("packageRoot")} != {expected_root}')
if Path(payload.get('extensionDir', '')).resolve() != expected_extension:
    fail(f'probe payload extensionDir mismatch: {payload.get("extensionDir")} != {expected_extension}')
if payload.get('mode') != 'json':
    fail(f'probe payload reported unexpected ctx.mode: {payload.get("mode")}')
if not isinstance(payload.get('packageVersion'), str) or not payload.get('packageVersion'):
    fail('probe payload did not report packageVersion')

flags = payload.get('observedFlags')
if not isinstance(flags, dict):
    fail('probe payload omitted observedFlags')
for key in ('modeJson', 'noExtensions', 'noBuiltinTools', 'noSkills', 'noPromptTemplates', 'noContextFiles', 'noSession', 'printMode'):
    if flags.get(key) is not True:
        fail(f'expected observedFlags.{key} to be true, got {flags.get(key)!r}')

extension_args = payload.get('extensionArgs')
if not isinstance(extension_args, list) or not extension_args:
    fail('probe payload omitted extensionArgs')
resolved_extension_args = {str(Path(value).resolve()) for value in extension_args if isinstance(value, str)}
if str(expected_extension) not in resolved_extension_args:
    fail(f'expected explicit -e path {expected_extension} in extensionArgs, got {sorted(resolved_extension_args)}')
if payload.get('toolsArg') != PROBE_TOOL:
    fail(f'expected --tools {PROBE_TOOL}, got {payload.get("toolsArg")!r}')

helper_assets = payload.get('helperAssets')
if not isinstance(helper_assets, dict):
    fail('probe payload omitted helperAssets')
for helper_name, relative_path in {'scout': 'helpers/scout.md', 'critic': 'helpers/critic.md'}.items():
    asset = helper_assets.get(helper_name)
    if not isinstance(asset, dict):
        fail(f'probe payload omitted helper asset report for {helper_name}')
    if asset.get('exists') is not True:
        fail(f'packaged helper asset {helper_name} is missing according to the probe payload')
    if asset.get('relativePath') != relative_path:
        fail(f'helper asset {helper_name} reported unexpected relativePath: {asset.get("relativePath")}')
    if not isinstance(asset.get('sha256'), str) or len(asset.get('sha256')) != 64:
        fail(f'helper asset {helper_name} reported invalid sha256: {asset.get("sha256")}')
    if not isinstance(asset.get('size'), int) or asset.get('size') <= 0:
        fail(f'helper asset {helper_name} reported invalid size: {asset.get("size")}')

stages = []
for event in probe_updates:
    partial = event.get('partialResult')
    if not isinstance(partial, dict):
        continue
    details = partial.get('details')
    if isinstance(details, dict) and isinstance(details.get('stage'), str):
        stages.append(details['stage'])
if 'loaded-extension' not in stages or 'verified-assets' not in stages:
    fail(f'probe tool updates did not expose the expected progress stages, got: {stages}')

assistant_updates = [
    event for event in events
    if event.get('type') == 'message_update'
    and isinstance(event.get('assistantMessageEvent'), dict)
    and event['assistantMessageEvent'].get('type') in {'text_delta', 'text_end'}
]
if not assistant_updates:
    fail('missing assistant message_update text events for final result capture')

assistant_messages = [
    event.get('message') for event in events
    if event.get('type') == 'message_end'
    and isinstance(event.get('message'), dict)
    and event['message'].get('role') == 'assistant'
]
if not assistant_messages:
    fail('missing assistant message_end event')
final_text = content_text(assistant_messages[-1])
if not final_text:
    stderr = stderr_path.read_text().strip()
    fail(f'assistant emitted no final text output. stderr: {stderr}')
try:
    final_payload = json.loads(final_text)
except json.JSONDecodeError as exc:
    fail(f'assistant final text was not exact JSON: {exc}: {final_text!r}')

for key in ('ok', 'probe', 'packageRoot', 'extensionDir', 'toolsArg'):
    if final_payload.get(key) != payload.get(key):
        fail(f'assistant final JSON mismatched probe payload for {key}: {final_payload.get(key)!r} != {payload.get(key)!r}')
final_flags = final_payload.get('observedFlags')
if not isinstance(final_flags, dict) or final_flags.get('noBuiltinTools') is not True or final_flags.get('noContextFiles') is not True:
    fail('assistant final JSON did not preserve observed helper flag proof')

print(f'helper runtime capability probe verified packaged helper-tools loading at {expected_root}')
PY

echo "helper runtime capability test passed: $PACKAGE_ROOT_UNDER_TEST"
