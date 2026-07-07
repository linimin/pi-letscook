#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

node <<'NODE'
const fs = require('node:fs');
const read = (f) => fs.readFileSync(f, 'utf8');
const need = (f, s) => { if (!read(f).includes(s)) throw new Error(`${f} missing ${s}`); };

need('cursor/skills/cursor-handoff-monitor/SKILL.md', 'poll_cook_workflow_updates');
need('cursor/skills/cursor-handoff-monitor/SKILL.md', 'workflow_active');
need('cursor/skills/cursor-handoff-monitor/SKILL.md', 'awaiting_background_spawn');
need('cursor/skills/cursor-handoff/SKILL.md', 'ensure_cook_worktree');
need('cursor/skills/cursor-handoff/SKILL.md', 'start_cook_workflow');
need('mcp/cook-handoff/src/tools.ts', 'poll_cook_workflow_updates');
need('docs/CURSOR_HANDOFF_MCP.md', 'workspace_root');

console.log('cursor-handoff-monitor-skill-test passed');
NODE
