#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[completion-stop] verifying control plane and .agent/verification-evidence.json parity"
bash .agent/verify_completion_control_plane.sh

if [[ "${PI_COMPLETION_RUNNING_RELEASE_CHECK:-0}" == "1" ]]; then
  echo "[completion-stop] release-check is already in progress; skipping nested npm run release-check >/dev/null recursion"
  npm run evaluator-calibration-test >/dev/null
  echo "completion stop verification passed"
  exit 0
fi

echo "[completion-stop] delegating to npm run release-check >/dev/null for broad packaged verification, evaluator calibration, and contract coverage"
PI_COMPLETION_RUNNING_RELEASE_CHECK=1 npm run release-check >/dev/null

echo "completion stop verification passed"
