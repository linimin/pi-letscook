#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export COMPLETION_REPO_VERIFY_COMMAND='npm run release-check >/dev/null'
export COMPLETION_REPO_VERIFY_CWD="$(cd "$SCRIPT_DIR/.." && pwd -P)"
exec bash "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" "$@"
