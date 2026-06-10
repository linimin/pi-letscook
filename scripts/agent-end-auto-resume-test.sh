#!/usr/bin/env bash
set -euo pipefail

PKG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pi() {
  env -u PI_COMPLETION_ROLE command pi --no-extensions "$@"
}
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ROOT="$TMPDIR/repo"
CAPTURE="$TMPDIR/auto-resume-input.json"
PROMPT_SNAPSHOT="$TMPDIR/auto-resume-prompt.txt"
OUT="$TMPDIR/pi-agent-end-auto-resume.out"
ERR="$TMPDIR/pi-agent-end-auto-resume.err"
RESUME_PROMPT='AUTO-RESUME-REGRESSION queued from agent_end.'
TRANSFORMED_PROMPT='ok'

mkdir -p "$ROOT"
printf '# agent_end auto-resume regression fixture\n' > "$ROOT/README.md"

cd "$ROOT"
PI_COMPLETION_AUTO_RESUME_TEST_ROOT="$ROOT" \
PI_COMPLETION_AUTO_RESUME_CAPTURE_PATH="$CAPTURE" \
PI_COMPLETION_AUTO_RESUME_PROMPT_PATH="$PROMPT_SNAPSHOT" \
PI_COMPLETION_AUTO_RESUME_PROMPT="$RESUME_PROMPT" \
PI_COMPLETION_AUTO_RESUME_TRANSFORMED_PROMPT="$TRANSFORMED_PROMPT" \
pi -e "$PKG_ROOT/scripts/test-fixtures/agent-end-auto-resume-extension.ts" -p 'Warm up the agent-end auto-resume regression harness.' \
  >"$OUT" 2>"$ERR"

python3 - "$CAPTURE" "$PROMPT_SNAPSHOT" "$OUT" "$ERR" "$RESUME_PROMPT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

capture = json.loads(Path(sys.argv[1]).read_text())
prompt_snapshot = Path(sys.argv[2]).read_text()
combined = Path(sys.argv[3]).read_text() + Path(sys.argv[4]).read_text()
resume_prompt = sys.argv[5]
driver_prompt = json.loads(Path('.agent/current/tmp/driver-prompt.json').read_text())

assert capture['source'] == 'extension', 'auto-resume sendUserMessage should surface as an extension input event'
assert capture['text'] == resume_prompt, 'captured extension input should preserve the auto-resume prompt text'
assert capture['streamingBehavior'] == 'followUp', 'agent_end auto-resume must queue via followUp while the agent is still processing'
assert prompt_snapshot == resume_prompt + '\n', 'auto-resume prompt snapshot should preserve the queued prompt verbatim'
assert driver_prompt['kind'] == 'auto-resume', 'driver prompt metadata should record auto-resume for the queued continuation'
assert driver_prompt['prompt_hash'] == hashlib.sha256(resume_prompt.encode()).hexdigest(), 'driver prompt metadata should hash the queued auto-resume prompt'
assert 'Agent is already processing' not in combined, 'agent_end auto-resume should not hit the streamingBehavior runtime error'
assert 'Extension "<runtime>" error' not in combined, 'agent_end auto-resume should not surface a runtime extension error'
PY

echo "agent-end auto-resume test passed: $ROOT"
