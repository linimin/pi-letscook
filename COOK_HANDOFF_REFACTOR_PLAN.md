# /cook Handoff Boundary Refactor Plan

## Goal

Keep `/cook` as the only explicit completion-workflow entrypoint, while preventing the primary agent from starting long-running product implementation directly from ordinary main-chat discussion once a task has clearly matured into completion-workflow scope.

In short:

- ordinary chat may discuss, clarify, and propose
- `/cook` remains the explicit start of implementation workflow
- when the primary agent judges that a task is now mature enough for long-running completion work, it must stop short of implementation and hand the user off to `/cook`

---

## Problem Statement

Today, users often discuss a substantial repo change in the main session, then intend to run `/cook` once the task is sufficiently understood.

However, before the user enters `/cook`, the primary agent may already begin implementation in ordinary chat because:

- the task looks concrete enough to act on
- the primary agent has richer conversational context than outer extension heuristics
- the current `completion-protocol` skill only governs behavior after `/cook` has already entered the workflow

This creates a mismatch:

- the user intends `/cook` to mean “this is now complex enough to enter completion workflow”
- the system may instead start implementation early in ordinary chat

---

## Desired Product Behavior

### Ordinary main chat

The primary agent may:

- clarify requirements
- discuss tradeoffs
- propose a plan or implementation approach
- summarize mission, scope, acceptance, constraints, and risks
- help the user determine whether the task should enter `/cook`

The primary agent must not, once it judges the task is mature enough for completion workflow:

- start long-running product implementation in ordinary chat
- edit tracked product files as part of that long-running implementation
- bypass `/cook`
- silently take over the conversation into completion workflow

### `/cook`

`/cook` remains:

- the only explicit entrypoint into completion workflow
- the point where recent discussion is converted into a startup brief
- the place where the user confirms **Start** or **Cancel**
- the boundary after which canonical `.agent/**` workflow state may be written and role dispatch begins

---

## Core Design Decision

Do **not** try to solve this only with outer extension heuristics that guess whether the user wants long-running implementation.

Instead:

1. let the **primary agent** decide when a task has matured into completion-workflow scope
2. teach that behavior through a dedicated pre-`/cook` handoff contract
3. automatically inject that contract into ordinary main-chat turns
4. keep `/cook` itself as the explicit, user-controlled transition into workflow

This relies on the primary agent's richer context while preserving explicit user control.

---

## Architecture Change

### Existing separation

Current `skills/completion-protocol/**` is correctly scoped to:

- the workflow driver
- canonical `.agent/**` state
- mandatory completion-role dispatch
- review / audit / stop-wave rules

It is **not** the right place to define pre-`/cook` behavior in ordinary chat.

### New separation

Introduce a second layer:

- `completion-protocol` = post-`/cook`, in-workflow control-plane protocol
- new handoff skill = pre-`/cook`, ordinary-chat boundary and handoff behavior

This preserves clear responsibilities and avoids overloading the workflow protocol with ordinary-chat policy.

---

## Planned Deliverables

### 1. New skill: `cook-handoff-boundary`

Add a new skill at a path like:

```text
skills/cook-handoff-boundary/SKILL.md
```

This skill defines how the primary agent should behave in ordinary chat before `/cook` is invoked.

#### Responsibilities of this skill

- define the boundary between ordinary chat and `/cook`
- explain when a task is mature enough for completion workflow
- instruct the primary agent to stop before implementation and hand off to `/cook`
- provide approved handoff wording patterns
- explicitly forbid bypassing `/cook`

#### What it should not do

- it should not describe canonical `.agent/**` workflow mechanics
- it should not duplicate `completion-protocol`
- it should not select slices or role-dispatch logic

---

## Skill Contract Draft

The new skill should encode the following contract.

### Purpose

This skill governs ordinary main-chat behavior before completion workflow begins.

### Core rules

- ordinary chat is for discussion, clarification, and proposal formation
- `/cook` is the only explicit entrypoint into completion workflow
- when the primary agent judges that the task has matured into completion-workflow scope, it must stop short of implementation and direct the user to `/cook`

### Handoff criteria

The primary agent should consider `/cook` handoff appropriate when one or more of the following are true:

- the user has moved from exploration into “okay, let's do this” intent
- the agent has just produced a concrete plan or proposal and the next step would naturally be implementation
- the task spans multiple files, steps, or verification surfaces
- the task needs resumability, review, audit, or canonical workflow state
- the task is better treated as a long-running repo mission than a one-off answer or tiny fix

### Handoff behavior

When the agent determines the task should enter completion workflow, it should:

- stop before implementation
- not edit tracked product files in ordinary chat for that task
- instruct the user to run `/cook`
- briefly explain that `/cook` will generate a startup brief from recent discussion and request confirmation before workflow start

### Suggested response shape

Example handoff wording:

> This task is now mature enough for the `/cook` workflow. If you want me to start implementation, run `/cook`. I’ll use our recent discussion to generate a startup brief for confirmation before the workflow begins.

Optional short recap may include:

- mission
n- scope
- acceptance

But it must not present that recap as canonical plan state.

### Forbidden behaviors

Once the task is judged ready for completion workflow, the primary agent must not:

- directly begin long-running implementation in ordinary chat
- modify tracked product files as part of that workflow-level task
- act as though `/cook` had already been invoked
- silently rewrite the user's request into active workflow state

---

## Runtime Injection Plan

### Current state

The extension currently injects workflow-specific protocol context only for workflow-driver turns, especially those based on `/skill:completion-protocol ...`.

That means ordinary main-chat turns do not receive any explicit policy telling the primary agent to stop and hand off to `/cook` when a task has matured.

### Planned change

In `extensions/completion/index.ts`, add an ordinary-chat handoff reminder injection path in `before_agent_start`.

This new injection should:

- apply in ordinary main-chat turns
- not require the user to manually load a skill
- not activate completion workflow by itself
- only provide boundary guidance to the primary agent

### New helper surfaces

Expected new helpers may include functions like:

- `buildCookHandoffBoundaryReminder()`
- `shouldInjectCookHandoffBoundary(...)`
- `composeCookHandoffBoundaryPrompt()`

### Important constraint

This injected reminder must be clearly separate from:

- workflow-driver reminders
- stop-wave reminders
- completion-protocol system reminders

The ordinary-chat policy should remain short, stable, and clearly pre-`/cook` in scope.

---

## Ordinary-Chat Behavior After Refactor

### Allowed ordinary-chat flow

1. user discusses a substantial repo change
2. primary agent helps clarify and refine it
3. primary agent may produce a proposal or recommended approach
4. once the task is mature enough for completion workflow, the primary agent stops before implementation
5. primary agent tells the user to run `/cook`
6. user explicitly enters `/cook`
7. extension derives startup brief and asks for confirmation
8. completion workflow starts

### Disallowed ordinary-chat flow

1. user discusses a substantial repo change
2. primary agent judges it is ready for long-running work
3. primary agent immediately starts editing product files in ordinary chat

This disallowed flow is the behavior the refactor is meant to eliminate.

---

## `/cook` Flow After Refactor

The refactor should **not** change the meaning of `/cook` itself.

The existing `/cook` behavior should remain:

- derive startup brief from recent main-chat discussion
- require confirmation via existing Start / Cancel flow
- preserve confirmed startup brief as advisory intake only
- keep `completion-regrounder` authoritative for canonical `.agent/plan.json` and `.agent/active-slice.json`
- fail closed when recent discussion is still too weak or unreliable to support startup

The only new behavior is that ordinary chat should now more reliably funnel mature tasks into `/cook` instead of beginning implementation directly.

---

## File-Level Refactor Plan

### A. New skill file

Create:

```text
skills/cook-handoff-boundary/SKILL.md
```

Contents should include:

- description
- purpose
- boundary rules
- maturity criteria for `/cook` handoff
- approved handoff wording
- forbidden behaviors
- explicit relationship to `completion-protocol`

### B. Extension runtime changes

Update:

```text
extensions/completion/index.ts
```

Add:

- a new path resolver for the new skill if needed
- an ordinary-chat handoff reminder builder
- a `before_agent_start` branch for injecting the ordinary-chat handoff policy
- guard conditions that ensure this policy is injected in ordinary chat but not confused with the workflow-driver path

### C. Possibly add prompt-surface helpers

If prompt construction is already being centralized, consider placing reusable formatting in:

```text
extensions/completion/prompt-surfaces.ts
```

This depends on how existing prompt-surface responsibilities are currently factored.

### D. Documentation updates

Update:

- `README.md`
- `CHANGELOG.md`

Potentially also release or verifier docs if public behavior parity depends on them.

---

## Documentation Changes

### README

Document that:

- ordinary chat is for task shaping and discussion
- the primary agent may tell the user to run `/cook` once a task has matured into completion-workflow scope
- `/cook` is still the only explicit workflow entrypoint
- startup brief generation and confirmation remain behind `/cook`

### CHANGELOG

Add an entry describing:

- ordinary-chat `/cook` handoff boundary
- primary-agent stop-before-implementation behavior for mature workflow tasks
- `/cook` remaining explicit and confirmation-first

---

## Test Plan

### 1. Ordinary-chat handoff regression

Scenario:

- user describes a substantial repo change in ordinary chat
- context is mature enough that the next natural step would be implementation

Expected result:

- primary agent does not begin long-running implementation
- primary agent instructs the user to run `/cook`
- no tracked product files are modified as part of ordinary-chat implementation

### 2. Post-plan handoff regression

Scenario:

- primary agent has just proposed a concrete plan or approach
- user signals intent to proceed

Expected result:

- the primary agent stops at `/cook` handoff
- it does not immediately start repo edits in ordinary chat

### 3. Non-trigger ordinary-chat regression

Scenario:

- lightweight discussion, brainstorming, or normal Q&A

Expected result:

- primary agent does not over-trigger `/cook`
- ordinary chat remains natural and useful

### 4. Existing `/cook` regression preservation

Confirm that the refactor does not break:

- startup brief generation
- Start / Cancel confirmation
- advisory intake semantics
- fail-closed startup behavior
- `completion-regrounder` authority over canonical plan state

### 5. Release-check integration

Update release verification so the shipped package fails closed if:

- the ordinary-chat handoff behavior drifts
- docs no longer describe the shipped behavior truthfully
- runtime behavior and public docs diverge

---

## Acceptance Criteria

This refactor is complete when all of the following are true:

1. In ordinary main chat, the primary agent can still discuss and refine substantial repo tasks.
2. When the primary agent judges a task is mature enough for long-running completion workflow, it does not begin product implementation directly in ordinary chat.
3. In that mature state, the primary agent instead instructs the user to run `/cook`.
4. `/cook` remains the only explicit workflow entrypoint.
5. Existing `/cook` startup-brief-first behavior remains intact.
6. `completion-protocol` remains scoped to post-`/cook` workflow behavior only.
7. The new pre-`/cook` handoff behavior is encoded in a separate skill or prompt contract.
8. The extension automatically injects that handoff guidance into ordinary main-chat turns rather than relying on users to load a skill manually.
9. Deterministic regressions and release checks cover the new ordinary-chat handoff behavior.

---

## Non-Goals

This refactor does **not** aim to:

- auto-run `/cook` on behalf of the user
- auto-take over ordinary chat into completion workflow
- move startup brief generation out of `/cook`
- make the startup brief canonical plan state
- replace `completion-regrounder` as the authority over `.agent/plan.json`
- detect workflow intent solely via brittle external heuristics
- eliminate ordinary-chat discussion and proposal work before `/cook`

---

## Risks and Mitigations

### Risk: Over-triggering `/cook`

The primary agent may become too eager and route ordinary discussions into `/cook` prematurely.

Mitigation:

- clearly describe maturity criteria in the new skill
- distinguish between discussion/proposal and implementation kickoff
- add non-trigger regressions for brainstorming and small requests

### Risk: Under-triggering `/cook`

The primary agent may still occasionally begin ordinary-chat implementation.

Mitigation:

- use explicit stop-before-implementation wording in the injected reminder
- add regression coverage focused on mature-task handoff cases
- tighten prompt wording if drift is observed

### Risk: Boundary confusion with `completion-protocol`

If the pre-`/cook` and post-`/cook` contracts are mixed together, maintenance and behavior will become confusing.

Mitigation:

- keep the new handoff skill separate
- document the relationship explicitly
- preserve `completion-protocol` as the in-workflow control-plane source of truth

---

## Recommended Implementation Order

### Phase 1: Contract definition

1. add `skills/cook-handoff-boundary/SKILL.md`
2. write the pre-`/cook` ordinary-chat contract clearly
3. document its separation from `completion-protocol`

### Phase 2: Runtime wiring

4. add ordinary-chat boundary prompt injection in `extensions/completion/index.ts`
5. keep it cleanly separated from workflow-driver injection

### Phase 3: Docs and parity

6. update `README.md`
7. update `CHANGELOG.md`
8. align any release-parity checks with the new public behavior

### Phase 4: Testing

9. add ordinary-chat handoff regressions
10. add post-plan handoff regressions
11. add non-trigger regressions
12. include them in release verification

---

## Final Summary

The refactor should formalize a clean two-stage model:

### Stage 1: Ordinary chat

- discuss
- clarify
- propose
- decide when the task is mature
- stop at the `/cook` handoff boundary

### Stage 2: `/cook` workflow

- derive startup brief from recent discussion
- require confirmation
- enter canonical completion workflow
- use `completion-protocol` for driver and role dispatch

That split preserves explicit user control, uses the primary agent's contextual judgment where it is strongest, and prevents premature implementation outside the intended completion workflow boundary.
