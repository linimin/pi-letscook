# Cursor IDE → Pi /cook Handoff

Pi `/cook` cannot read Cursor IDE chat history. Hand off planning work with the **cook-handoff MCP**, a dedicated **git worktree**, or legacy file/inline paths.

## Recommended flow (MCP + worktree)

1. Plan in Cursor on your **main checkout**.
2. Use the **cook-handoff MCP** (see [CURSOR_HANDOFF_MCP.md](CURSOR_HANDOFF_MCP.md)):
   - `ensure_cook_worktree` → `.worktrees/cook-<slug>/`
   - `prepare_cook_handoff` → handoff file + pending sidecar
   - `preview_cook_handoff_confirmation` → startup brief in chat
   - User **Start** → `start_cook_workflow` returns a launch command; run it in the integrated Terminal (worktree cwd)
3. Monitor in the same chat via `poll_cook_workflow_updates` (see `cursor-handoff-monitor` skill).

```text
main checkout/                 .worktrees/cook-feature/
Cursor plans & edits      →    Pi /cook + .agent/current/
```

## Install Cursor assets

```bash
mkdir -p .cursor/skills .cursor/commands .cursor/mcp
cp -r node_modules/@linimin/pi-letscook/cursor/skills/cursor-handoff .cursor/skills/
cp -r node_modules/@linimin/pi-letscook/cursor/skills/cursor-handoff-monitor .cursor/skills/
cp node_modules/@linimin/pi-letscook/cursor/commands/prepare-cook-handoff.md .cursor/commands/
cp node_modules/@linimin/pi-letscook/cursor/mcp/cook-handoff.json.example .cursor/mcp/cook-handoff.json
```

Adjust MCP config paths for your install.

## Legacy / fallback paths

### Plain `/cook` auto-detect

If `.agent/tmp/cursor-handoff.json` exists and is fresh, plain `/cook` picks it up only while the MCP sidecar is still `pending_review` (or for legacy file-only handoffs with a fresh `captured_at`). After MCP **Start**, `/cook` and `/cook <prompt>` fail closed with a message to run the terminal command. Stale or unusable handoff files also fail closed instead of silently synthesizing a new brief.

```bash
pi
/cook
```

### Explicit import

```text
/cook import
/cook import path/to/handoff.json
```

### Inline prompt

```text
/cook <one-line mission>
```

## After workflow starts

- `/cook resume` — continue from `.agent/` state (in the **worktree** when using worktree flow)
- `/cook park` — pause for edits, then `/cook resume`
- `/cook cancel` — close the workflow

## Division of labor

| Surface | Role |
|---------|------|
| Cursor chat | Plan, confirm handoff, monitor progress |
| Cook worktree | Pi `/cook` execution + `.agent/current/**` |
| Main checkout | Ordinary edits while cook runs on worktree |
| Cursor SDK/CLI (optional) | Implementer and evaluator execution |

## What handoff does not do

- Does not auto-start without explicit Start (chat or Pi UI).
- Does not sync live Cursor chat into Pi after kickoff.
- Does not replace regrounder — file hints are advisory.

See also: [CURSOR_HANDOFF_MCP.md](CURSOR_HANDOFF_MCP.md), [CURSOR_BACKEND.md](CURSOR_BACKEND.md).
