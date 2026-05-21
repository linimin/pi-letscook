---
name: cook-handoff-boundary
description: Ordinary-chat boundary contract for keeping main chat advisory until the user explicitly enters `/cook`, while preventing long-running implementation from starting before that explicit workflow entry.
---

# /cook Handoff Boundary

Load or summarize this contract when the primary agent is operating in ordinary main chat before the user has explicitly entered `/cook`.

This skill governs the boundary between:

- ordinary main-chat discussion, clarification, and proposal work
- explicit transition into long-running completion workflow through `/cook`

## Core Contract

- Ordinary chat may be used to clarify requirements, discuss tradeoffs, propose implementation approaches, and refine scope.
- `/cook` is the only explicit entrypoint into long-running completion workflow.
- Ordinary chat remains ordinary chat until the user explicitly runs `/cook`.
- Before that explicit `/cook` entry, the primary agent must stop short of long-running implementation for workflow-level tasks.

## What Ordinary Chat May Do

The primary agent may:

- answer follow-up questions
- discuss tradeoffs
- refine scope and constraints
- summarize likely mission, acceptance, or risks
- help the user determine whether the work seems large enough for `/cook`

The primary agent should not:

- proactively tell the user to run `/cook`
- proactively emit a `cook_handoff` capsule by default
- act as though workflow has already started
- rewrite ordinary-chat discussion into canonical workflow state

## When Work Looks Workflow-Worthy

The primary agent should treat work as workflow-worthy when one or more of the following are true:

- the task spans multiple files, steps, or verification surfaces
- the next natural step would be bounded repo implementation rather than more explanation
- the work needs resumability, review, audit, or canonical workflow state
- the task is better treated as a long-running repo mission than a one-off answer or tiny fix

Even then, the boundary remains:

- ordinary chat can still keep refining the task
- only explicit `/cook` starts workflow

## Required Behavior Before Explicit `/cook`

When a task has matured into workflow-level work, the primary agent must:

- stop before long-running implementation
- not edit tracked product files for that workflow-level task in ordinary chat
- continue ordinary discussion naturally if the user keeps asking questions or refining scope
- wait for the user to explicitly run `/cook` before treating the conversation as workflow startup

## Deferred Handoff Model

When the user explicitly runs `/cook`:

- `/cook` will synthesize a startup brief from recent discussion using primary-agent-style context
- `/cook` will show Start / Cancel confirmation before canonical workflow state is rewritten
- that synthesized startup brief is advisory intake only, not canonical `.agent/**` state by itself

This means the primary agent does **not** need to proactively attach startup capsules during ordinary chat just because the task looks ready.

## Optional Preview Behavior

Only if the user explicitly asks for a preview startup brief or handoff capsule in ordinary chat may the primary agent provide one.

Optional preview capsule format:

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
- `first_slice_goal`, `first_slice_non_goals`, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first` are required only for an implementation-ready preview capsule.
- Any preview capsule is startup intake for `/cook` only. It is not canonical `.agent/**` state, not active-slice state, and not a second repo contract source.

Suggested wording:

> We are still in ordinary chat until you explicitly run `/cook`. If you want, we can keep refining the first slice here. When you do run `/cook`, it will synthesize a startup brief from our recent discussion and show Start / Cancel before workflow begins.

A short recap may include mission, scope, or acceptance, but that recap must not be presented as canonical plan state.

## Forbidden Behaviors

Before the user explicitly runs `/cook`, the primary agent must not:

- directly begin long-running implementation in ordinary chat
- modify tracked product files as part of that workflow-level task
- act as though `/cook` had already been invoked
- silently rewrite ordinary-chat discussion into active workflow state
- refuse ordinary-chat clarification only because `/cook` would now be appropriate

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat boundary behavior.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
