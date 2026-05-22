---
name: cook-handoff-boundary
description: Ordinary-chat contract for treating `/cook` as an optional workflow mode while requiring `/cook` to capture a primary-agent-authored startup plan instead of guessing from recent discussion.
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
- load or follow `completion-protocol` while still in ordinary chat
- call `completion_role` before the user has explicitly entered `/cook`
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

If the user explicitly runs or clearly chooses `/cook` workflow mode, the system behavior should be:

1. call a primary-agent startup-plan synthesis step immediately from the current task context
2. use that synthesized startup plan to show Start / Cancel confirmation in the same `/cook` entry
3. after Start, write the approved startup plan into `.agent/startup-plan.json` / `.agent/startup-plan.md`, then let `completion-regrounder` derive canonical slices from repo truth

That means:

- `/cook` must not infer or guess canonical slices from recent discussion alone
- `/cook` should always synthesize the startup plan fresh in the same entry from current task context
- `/cook` should not directly reuse an old preview capsule as canonical or approval-ready workflow state
- `/cook` should not require a manual rerun just to consume a startup plan it can synthesize immediately from the primary-agent view

## Optional Preview Behavior

Only if the user explicitly asks for a preview startup plan or handoff capsule in ordinary chat may the primary agent provide one.

Optional preview capsule format:

````text
```cook_handoff
{
  "kind": "cook_handoff",
  "source": "primary_agent",
  "captured_at": "<ISO-8601 timestamp>",
  "source_turn_id": "<current assistant turn id>",
  "mission": "<approved workflow mission>",
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
- `first_slice_goal`, `first_slice_non_goals`, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first` are optional sequencing hints. They help `completion-regrounder` split slices later when they are already obvious, but the approved startup plan may still be startable without them.
- Any capsule is advisory preview only. It is not canonical `.agent/**` state, not active-slice state, not a second repo contract source, and not something `/cook` should directly reuse without same-entry primary-agent synthesis.

Suggested wording:

> We can continue directly in ordinary chat if you want. If you prefer workflow mode, run `/cook` and it should capture an approved startup plan for Start / Cancel confirmation, then hand that plan to `completion-regrounder` for slice derivation.

## Forbidden Behaviors

Before the user explicitly runs `/cook`, the primary agent must not:

- pretend `/cook` has already been invoked
- load or follow `completion-protocol`
- call `completion_role` or any completion subagent
- silently rewrite ordinary-chat discussion into active workflow state
- claim canonical `.agent/**` startup state exists when it does not
- refuse ordinary-chat implementation solely because `/cook` would also be possible

When the user does explicitly choose `/cook`, the system must not:

- let `/cook` invent canonical slices from recent discussion alone
- let `/cook` replace missing startup-plan data with generic transcript guessing
- let `/cook` directly consume an old preview capsule instead of rerunning same-entry primary-agent startup-plan synthesis
- require a second `/cook` invocation when same-entry primary-agent startup-plan synthesis is possible

## Relationship To `completion-protocol`

This skill is only about pre-`/cook` ordinary-chat behavior and `/cook` startup-plan expectations.

After the user explicitly enters `/cook`, the separate `completion-protocol` skill governs:

- canonical `.agent/**` workflow state
- workflow-driver behavior
- mandatory completion-role dispatch
- review, audit, and stop-wave rules
