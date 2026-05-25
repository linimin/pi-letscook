#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMPLETION_REPO_VERIFY_COMMAND='npm run release-check >/dev/null'
exec bash "$SCRIPT_DIR/../scripts/verify-completion-stop.sh" "$@"
