---
name: cursor-handoff-monitor
description: Monitor an active Pi /cook workflow in Cursor chat using cook-handoff MCP poll tools.
---

# Monitor Pi /cook after Cursor handoff

Use **after** `start_cook_workflow` succeeds in the same chat.

When the start response has `monitoring.enabled: false`, wait until Pi has started in the worktree before polling:

- `awaiting_terminal_launch: true` — run the returned command in the integrated Terminal panel first
- `awaiting_background_spawn: true` — Pi was spawned in the background; wait for `.agent/current` to appear

## What to do

1. Keep the `workspace_root` from the handoff sidecar / start response.
2. Poll `poll_cook_workflow_updates({ workspace_root, since_event_id })` after kickoff and when the user asks for status.
3. Post **only meaningful deltas** — new slice progress, `workflow_active`, `blocked`, `parked`, `done`, `cancelled`.
4. Use `get_cook_workflow_status({ workspace_root })` when poll returns no events but state is unclear.

## User guidance

| State | Tell the user |
|-------|----------------|
| **workflow_active** | Workflow is running; slice selection or reground may still be in progress |
| **parked** | Edit on main if desired; run `/cook resume` in the **worktree** terminal |
| **blocked** / **await_user_input** | Respond in the worktree terminal with what Pi needs |
| **done** | Workflow complete; review branch / open PR from worktree |

## Rules

- Monitoring is **read-only** from `.agent/` — do not sync chat back into Pi.
- Stop polling when workflow is `done` or `cancelled`, or Pi exits.
- Do not spam chat on empty polls.
- `workflow_not_found` before Pi starts is expected when `monitoring.enabled` is false.
