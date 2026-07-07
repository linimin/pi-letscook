---
name: cursor-handoff
description: Prepare a cook_handoff JSON file for Pi /cook import after planning in Cursor IDE.
---

# Cursor Handoff for Pi /cook

Use this when the user has finished planning in Cursor and wants to hand off to the Pi long-running `/cook` workflow in the same repository.

## What to do

1. Read the user's planning context: mission, scope, constraints, acceptance criteria, risks, and optional first-slice hints.
2. Write a valid `cook_handoff` JSON file to `.agent/tmp/cursor-handoff.json` in the repo root.
3. Ensure `.agent/tmp/` exists.
4. Tell the user to open a terminal in this repo, run `pi`, then `/cook import`.

## Required JSON shape

```json
{
  "kind": "cook_handoff",
  "source": "primary_agent",
  "captured_at": "<ISO-8601 timestamp>",
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

Optional hints: `first_slice_goal`, `implementation_surfaces`, `verification_commands`, `why_this_slice_first`.

## Rules

- Do not start the Pi workflow from Cursor. Only write the handoff file.
- Mission must be concrete and repo-change oriented.
- Acceptance criteria must be verifiable.
- `handoff_kind` must be `implementation_workflow_handoff`.

## Closing instruction

After writing the file, say:

> Handoff saved to `.agent/tmp/cursor-handoff.json`. Open a terminal in this repo, run `pi`, then `/cook import` to enter workflow mode with Start/Cancel confirmation.
