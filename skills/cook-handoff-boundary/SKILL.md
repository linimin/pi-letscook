---
name: cook-handoff-boundary
description: Ordinary-chat contract for treating `/cook` as an optional workflow mode while still requiring primary-agent-authored handoff data whenever the user explicitly chooses workflow mode.
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
- Ordinary chat remains ordinary chat until the user explicitly chooses `/cook`.

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

## Required Behavior When The User Explicitly Chooses `/cook`

If the user explicitly asks to enter `/cook` workflow mode, the primary agent must:

- generate the handoff information itself in ordinary chat
- emit exactly one fresh `cook_handoff` capsule that captures the intended startup slice from the primary-agent view of the task
- tell the user to run `/cook` only after that explicit handoff exists
- not rely on `/cook` to infer, summarize, or guess the startup slice from recent discussion alone

In other words:

- primary agent authors the handoff
- `/cook` consumes and confirms that handoff
- `/cook` must not invent the mission from transcript guessing

## Required Capsule Format

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
- `first_slice_goal`, `first_slice_non_goals`, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first` are required for an implementation-ready handoff.
- Any capsule is startup intake for `/cook` only. It is not canonical `.agent/**` state, not active-slice state, and not a second repo contract source.

Suggested wording when the user chooses workflow mode:

> Got it — since you want `/cook`, I’ll first prepare the explicit startup handoff here from the current task context. After that, run `/cook` and it should confirm this handoff rather than guessing from recent discussion.

## Forbidden Behaviors

Before the user explicitly runs `/cook`, the primary agent must not:

- pretend `/cook` has already been invoked
- silently rewrite ordinary-chat discussion into active workflow state
- claim canonical `.agent/**` startup state exists when it does not
- refuse ordinary-chat implementation solely because `/cook` would also be possible

When the user does explicitly choose `/cook`, the system must not:

- let `/cook` invent the startup mission from recent discussion alone
- let `/cook` replace missing primary-agent handoff data with transcript guessing
- let `/cook` reopen or refocus workflow from guessed intent when no fresh explicit primary-agent handoff exists

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat behavior and explicit handoff preparation.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
