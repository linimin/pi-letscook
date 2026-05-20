---
name: cook-handoff-boundary
description: Ordinary-chat boundary contract for deciding when a task has matured enough that the primary agent must stop short of long-running implementation and hand the user off to `/cook`.
---

# /cook Handoff Boundary

Load or summarize this contract when the primary agent is operating in ordinary main chat before the user has explicitly entered `/cook`.

This skill governs the boundary between:

- ordinary main-chat discussion, clarification, and proposal work
- explicit transition into long-running completion workflow through `/cook`

## Core Contract

- Ordinary chat may be used to clarify requirements, discuss tradeoffs, propose implementation approaches, and refine scope with the user.
- `/cook` is the only explicit entrypoint into long-running completion workflow.
- When the primary agent judges that a task has matured into completion-workflow scope, it must stop short of long-running implementation and treat `/cook` as the workflow boundary.
- Before the user explicitly runs `/cook`, ordinary chat remains ordinary chat: the agent may still answer follow-up questions and refine requirements instead of switching into a handoff-only refusal mode.

## When To Hand Off To `/cook`

The primary agent should consider `/cook` handoff appropriate when one or more of the following are true:

- the user has clearly shifted from exploration into implementation intent
- the agent has just produced a concrete plan or proposal whose natural next step would be implementation
- the task spans multiple files, steps, or verification surfaces
- the task needs resumability, review, audit, or canonical workflow state
- the task is better treated as a long-running repo mission than a one-off answer or tiny fix

## Required Handoff Behavior

When the task is judged ready for completion workflow, the primary agent must:

- stop before long-running implementation
- not edit tracked product files in ordinary chat for that workflow-level task
- recommend bare `/cook` as the explicit workflow boundary once the task is implementation-ready
- explain that `/cook` starts a new workflow or next round only from a fresh valid explicit primary-agent handoff capsule from recent ordinary-chat discussion, while active workflows resume from canonical state unless a fresh valid explicit handoff proposes replacement
- distinguish a workflow-worthy handoff from an implementation-ready handoff
- only append an implementation-ready `/cook` handoff capsule when the first bounded implementation slice is concrete enough to start immediately
- if the user asks follow-up questions or refines requirements before running `/cook`, continue ordinary-chat discussion normally without acting as though workflow already started

Required capsule format:

````text
```cook_handoff
{
  "kind": "cook_handoff",
  "source": "primary_agent",
  "captured_at": "<ISO-8601 timestamp>",
  "source_turn_id": "<current assistant turn id>",
  "mission": "<startable implementation mission>",
  "scope": ["..."],
  "constraints": ["..."],
  "non_goals": ["..."],
  "acceptance": ["..."],
  "risks": ["..."],
  "notes": ["..."],
  "handoff_kind": "implementation_workflow_handoff",
  "first_slice_goal": "<bounded first slice goal>",
  "first_slice_non_goals": ["..."],
  "implementation_surfaces": ["path/or/surface"],
  "verification_commands": ["npm test -- example"],
  "why_this_slice_first": "<why this first slice should start the workflow>",
  "task_type": "completion-workflow",
  "evaluation_profile": "completion-rubric-v1",
  "why_cook_now": "<why the task is ready for /cook now>"
}
```
````

Notes:

- `constraints` may be replaced or supplemented by `non_goals` when clearer.
- `first_slice_goal`, `first_slice_non_goals`, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first` are required only for implementation-ready handoffs.
- If the work is workflow-worthy but that first slice is still vague, say that `/cook` will be the right next step once the first slice is concrete enough, then keep refining in ordinary chat without emitting this implementation-ready capsule yet.
- If later ordinary-chat discussion materially changes the startup brief before `/cook` runs, update or replace the capsule in a later assistant reply.
- The mission must be positively startable implementation work; do not use rejection or suppression text as the mission.
- The capsule is startup intake for `/cook` only. It is not canonical `.agent/**` state, not active-slice state, and not a second repo contract source.

Suggested wording:

> This task now looks like `/cook` workflow work, but we are still in ordinary chat until you explicitly run `/cook`. If you want to keep refining the first slice first, we can do that here. Once you want to start implementation workflow, run bare `/cook`. I’ve also attached an explicit `/cook` handoff capsule so `/cook` can confirm this startup brief directly before the workflow begins.

A short recap may include mission, scope, or acceptance, but that recap must not be presented as canonical plan state.

## Forbidden Behaviors

Once the task is judged ready for completion workflow, the primary agent must not:

- directly begin long-running implementation in ordinary chat
- modify tracked product files as part of that workflow-level task
- act as though `/cook` had already been invoked
- silently rewrite ordinary-chat discussion into active workflow state
- refuse ordinary-chat clarification or requirement-refinement turns solely because `/cook` would now be appropriate

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat handoff behavior.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
