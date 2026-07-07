# Cook Handoff MCP

Stdio MCP server for Cursor → Pi `/cook` handoff with dedicated worktree support.

## Tools

| Tool | Purpose |
|------|---------|
| `ensure_cook_worktree` | Create `.worktrees/cook-<slug>/` |
| `prepare_cook_handoff` | Validate + write handoff + sidecar |
| `preview_cook_handoff_confirmation` | Startup brief layout for chat confirm |
| `start_cook_workflow` | Confirm + return Pi `/cook` launch command (or optional background spawn) |
| `validate_cook_handoff` | Schema/startability check |
| `get_cook_handoff_status` | Pending/confirmed/stale status |
| `get_cook_handoff_schema` | Example capsule |
| `get_cook_workflow_status` | `.agent/current` snapshot |
| `poll_cook_workflow_updates` | Event deltas for monitoring |

## Setup

```bash
cd mcp/cook-handoff && npm install
```

Copy [`cursor/mcp/cook-handoff.json.example`](../../cursor/mcp/cook-handoff.json.example) into your Cursor MCP config and adjust `PI_LETSCOOK_EXTENSION_PATH` to the installed `@linimin/pi-letscook` package root.

## Environment

| Variable | Purpose |
|----------|---------|
| `PI_LETSCOOK_EXTENSION_PATH` | Path passed to `pi -e` (default: package root) |
| `PI_BINARY` | Pi executable (default: `pi`) |
| `WORKSPACE_ROOT` | Fallback workspace root when tool omits it |

## Happy path

1. `ensure_cook_worktree({ slug, branch })`
2. `prepare_cook_handoff({ workspace_root, capsule })`
3. `preview_cook_handoff_confirmation({ workspace_root })` → user Start in chat
4. `start_cook_workflow({ workspace_root, confirmation_id, action: "start" })` → run returned `command` in Terminal when `launch_required` is true
5. `poll_cook_workflow_updates({ workspace_root, since_event_id })` until done

`workspace_root` must stay consistent across steps.
