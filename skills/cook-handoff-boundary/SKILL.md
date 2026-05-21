---
name: cook-handoff-boundary
description: Ordinary-chat contract for treating `/cook` as an optional workflow mode while still allowing direct repo implementation in main chat when workflow state is unnecessary.
---

# /cook Handoff Boundary

Load or summarize this contract when the primary agent is operating in ordinary main chat before the user has explicitly entered `/cook`.

This skill governs the relationship between:

- ordinary main-chat discussion and direct implementation
- optional transition into long-running completion workflow through `/cook`

## Core Contract

- Ordinary chat may be used to clarify requirements, discuss tradeoffs, refine scope, and directly implement requested repo changes.
- `/cook` is an explicit workflow entrypoint for users who want resumability, review, audit, or canonical `.agent/**` workflow state.
- `/cook` is optional. It is not required just because the work spans multiple files or looks substantial.
- Ordinary chat remains ordinary chat until the user explicitly runs `/cook`.

## What Ordinary Chat May Do

The primary agent may:

- answer follow-up questions
- discuss tradeoffs
- refine scope and constraints
- summarize likely mission, acceptance, or risks
- directly edit repo files when that is the most helpful response
- complete multi-file implementation in ordinary chat when workflow state is unnecessary

The primary agent should not:

- proactively tell the user to run `/cook` just because the task looks workflow-worthy
- proactively emit a `cook_handoff` capsule by default
- act as though workflow has already started when it has not
- silently rewrite ordinary-chat discussion into canonical workflow state

## When `/cook` Is Helpful

The primary agent may mention `/cook` as an optional tool when it would genuinely help, for example when:

- the work should be resumable across sessions
- the user wants a tracked mission in canonical `.agent/**` state
- the task benefits from explicit review / audit / stop-wave flow
- the user wants a confirm-first workflow boundary before a long-running effort

But even in those cases:

- do not force `/cook`
- do not frame `/cook` as mandatory for direct repo edits
- continue helping directly in ordinary chat unless the user explicitly chooses workflow mode

## Required Behavior Before Explicit `/cook`

Before the user explicitly runs `/cook`, the primary agent must:

- keep the interaction in ordinary chat
- directly implement requested repo changes when appropriate instead of blocking on workflow mode
- continue ordinary discussion naturally if the user keeps refining the task
- avoid claiming that canonical workflow state already exists unless `/cook` actually started it

## Deferred Handoff Model

When the user explicitly runs `/cook`:

- `/cook` synthesizes a startup brief from recent discussion using primary-agent-style context
- `/cook` shows Start / Cancel confirmation before canonical workflow state is rewritten
- that synthesized startup brief is advisory intake only until the user confirms startup

This means the primary agent does not need to proactively attach startup capsules during ordinary chat just because the task looks ready.

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

> We can continue directly in ordinary chat if you want. If you prefer resumable workflow state, explicit review flow, or a confirm-first startup gate, you can run `/cook` and it will synthesize a startup brief from our recent discussion before workflow begins.

A short recap may include mission, scope, or acceptance, but that recap must not be presented as canonical plan state.

## Forbidden Behaviors

Before the user explicitly runs `/cook`, the primary agent must not:

- pretend `/cook` has already been invoked
- silently rewrite ordinary-chat discussion into active workflow state
- claim canonical `.agent/**` startup state exists when it does not
- refuse ordinary-chat implementation solely because `/cook` would also be possible

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat behavior.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
