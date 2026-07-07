---
name: cursor-handoff
description: Prepare a cook_handoff for Pi /cook via MCP with a dedicated cook worktree, chat confirmation, and monitoring.
---

# Cursor Handoff for Pi /cook (MCP + worktree)

Use when the user finished planning in Cursor and wants a long-running Pi `/cook` workflow without blocking their main checkout.

## What to do

1. Call MCP `ensure_cook_worktree` with a `slug` and `branch` (e.g. `auth-refactor`, `cook/auth-refactor`).
2. Call `prepare_cook_handoff` with `workspace_root` from the worktree result and a valid `cook_handoff` capsule.
3. Call `preview_cook_handoff_confirmation` with the same `workspace_root` and show the startup brief in chat.
4. On user **Start**, call `start_cook_workflow` with `workspace_root`, `confirmation_id`, and `action: "start"`.
5. Follow the `cursor-handoff-monitor` skill in the same chat after kickoff.

## Required JSON shape

See `get_cook_handoff_schema` or:

```json
{
  "kind": "cook_handoff",
  "source": "primary_agent",
  "captured_at": "<ISO-8601>",
  "source_turn_id": "cursor-handoff",
  "mission": "<concise implementation mission>",
  "scope": ["..."],
  "constraints": ["..."],
  "non_goals": ["..."],
  "acceptance": ["..."],
  "risks": ["..."],
  "notes": ["..."],
  "handoff_kind": "implementation_workflow_handoff",
  "task_type": "completion-workflow",
  "evaluation_profile": "completion-rubric-v1",
  "why_cook_now": "<why workflow mode helps>"
}
```

## Rules

- Always thread the same `workspace_root` through prepare → start → monitor.
- Do not start Pi manually unless MCP spawn fails; then run the returned `command` in the integrated terminal (worktree cwd).
- When `start_cook_workflow` returns `terminal.launch_required: true`, run the returned `command` in the integrated Terminal panel.
- Mission must be concrete and repo-change oriented.
- `handoff_kind` must be `implementation_workflow_handoff`.

## Closing instruction

After `prepare_cook_handoff`, say:

> Handoff saved in the cook worktree. Review the startup brief above and reply **Start** or **Cancel**. On Start I will launch Pi in the worktree and monitor progress here.
