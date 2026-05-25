#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$ROOT/.agent"

cat > "$ROOT/.agent/verify_completion_control_plane.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../scripts/verify-completion-control-plane.js" ]]; then
  exec node "$SCRIPT_DIR/../scripts/verify-completion-control-plane.js" "$@"
fi
exec node "$SCRIPT_DIR/../node_modules/@linimin/pi-letscook/scripts/verify-completion-control-plane.js" "$@"
SH

cat > "$ROOT/.agent/verify_completion_stop.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
export COMPLETION_REPO_VERIFY_COMMAND="${COMPLETION_REPO_VERIFY_COMMAND:-npm run release-check >/dev/null}"
export COMPLETION_REPO_VERIFY_CWD="${COMPLETION_REPO_VERIFY_CWD:-$REPO_ROOT}"
if [[ -f "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" ]]; then
  exec bash "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" "$@"
fi
exec bash "$SCRIPT_DIR/../node_modules/@linimin/pi-letscook/scripts/verify-completion-stop.sh" "$@"
SH

chmod +x "$ROOT/.agent/verify_completion_control_plane.sh" "$ROOT/.agent/verify_completion_stop.sh"
