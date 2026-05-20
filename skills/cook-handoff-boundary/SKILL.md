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

- Ordinary chat may be used to clarify requirements, discuss tradeoffs, and propose implementation approaches.
- `/cook` is the only explicit entrypoint into long-running completion workflow.
- When the primary agent judges that a task has matured into completion-workflow scope, it must stop short of implementation and direct the user to `/cook`.

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
- tell the user to run `/cook`
- explain that `/cook` will derive a startup brief from recent discussion and ask for confirmation before workflow start

Suggested wording:

> This task is now mature enough for the `/cook` workflow. If you want me to start implementation, run `/cook`. I’ll use our recent discussion to generate a startup brief for confirmation before the workflow begins.

A short recap may include mission, scope, or acceptance, but that recap must not be presented as canonical plan state.

## Forbidden Behaviors

Once the task is judged ready for completion workflow, the primary agent must not:

- directly begin long-running implementation in ordinary chat
- modify tracked product files as part of that workflow-level task
- act as though `/cook` had already been invoked
- silently rewrite ordinary-chat discussion into active workflow state

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat handoff behavior.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
