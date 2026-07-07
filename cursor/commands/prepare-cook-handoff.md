# Prepare cook handoff

Prepare a long-running Pi `/cook` workflow using the **cook-handoff MCP** and a **dedicated cook worktree**.

## Steps

1. `ensure_cook_worktree` — create `.worktrees/cook-<slug>/`
2. `prepare_cook_handoff` — write handoff in that `workspace_root`
3. `preview_cook_handoff_confirmation` — show startup brief in chat
4. User **Start** → `start_cook_workflow`
5. Enable `cursor-handoff-monitor` skill for progress updates

Follow the `cursor-handoff` skill contract. Do not implement product changes here.
