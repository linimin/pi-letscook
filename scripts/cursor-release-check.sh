#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[cursor-release-check] running control-plane validation and cursor backend regressions"
npm run verify-completion-control-plane
bash ./scripts/role-runner-contract-test.sh
bash ./scripts/cursor-role-config-test.sh
bash ./scripts/cursor-role-runner-contract-test.sh
bash ./scripts/cursor-role-output-test.sh
bash ./scripts/cursor-handoff-import-test.sh
bash ./scripts/cursor-handoff-service-test.sh
bash ./scripts/cursor-handoff-auto-detect-test.sh
bash ./scripts/cursor-handoff-cursor-kickoff-test.sh
bash ./scripts/cursor-handoff-worktree-test.sh
bash ./scripts/cursor-handoff-workflow-status-test.sh
bash ./scripts/cursor-handoff-mcp-test.sh
bash ./scripts/cursor-handoff-plain-cook-test.sh
bash ./scripts/cursor-handoff-monitor-skill-test.sh
bash ./scripts/cursor-cli-live-test.sh
bash ./scripts/cursor-sdk-live-test.sh
echo "cursor release check passed"
