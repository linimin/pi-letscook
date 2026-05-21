# Deferred Primary-Agent Handoff on Explicit `/cook` Plan

## Goal

Change the `/cook` entry model so that:

- the primary agent does **not** proactively tell the user to use `/cook` in ordinary chat
- the primary agent does **not** proactively emit `cook_handoff` capsules in ordinary chat
- a handoff is created **only after the user explicitly enters `/cook`**
- that handoff is still synthesized from the **primary-agent view of recent context**, rather than by a thin fresh workflow agent guessing from partial context
- `/cook` remains confirmation-first before canonical workflow state is rewritten

In short:

1. ordinary chat stays ordinary chat
2. the user explicitly chooses `/cook`
3. `/cook` asks the primary-agent-style handoff synthesizer to prepare startup intake
4. the user confirms Start / Cancel
5. workflow begins

---

## Problem Statement

The current implementation couples two separate concerns:

1. **workflow entry trigger**
2. **handoff content generation**

Today, the primary agent is expected to:

- decide a task is workflow-worthy
- tell the user to run `/cook`
- often emit an explicit `cook_handoff` capsule in ordinary chat

Then `/cook` consumes that capsule.

This creates two product problems:

### 1. Premature workflow prompting
The primary agent changes the tone of ordinary chat by steering users toward `/cook` before they explicitly choose that mode.

### 2. Bad fallback quality if `/cook` must infer alone
If the explicit handoff is removed entirely and `/cook` relies on a fresh agent to infer startup from transcript alone, the inferred mission can be less accurate than what the primary agent would have produced using its richer conversational context.

The desired model is therefore **not**:

- proactive primary-agent `/cook` prompting
- nor thin `/cook`-side re-inference from scratch

The desired model is:

- **user-controlled `/cook` entry**
- **primary-agent-quality handoff synthesis at `/cook` entry time**

---

## Desired Product Behavior

## Ordinary chat

The primary agent may:

- clarify requirements
- discuss tradeoffs
- propose approaches
- refine scope
- summarize risks, constraints, and acceptance
- continue ordinary discussion even when the task becomes large or implementation-shaped

The primary agent should **not**:

- proactively tell the user to run `/cook`
- proactively emit `cook_handoff` capsules
- act as though workflow has already started
- rewrite ordinary-chat discussion into canonical workflow state

Ordinary chat stays advisory until the user explicitly chooses `/cook`.

## Explicit `/cook`

When the user explicitly runs `/cook`:

1. `/cook` becomes the only workflow entrypoint
2. `/cook` requests a startup handoff synthesis using primary-agent-style context
3. `/cook` presents the synthesized startup brief for Start / Cancel confirmation
4. only after confirmation does canonical `.agent/**` state change

This preserves explicit user control without sacrificing handoff quality.

---

## Core Design Decision

Separate these responsibilities:

### A. Entry authority
Only the **user** decides to enter workflow by explicitly running `/cook`.

### B. Handoff author
The **primary agent viewpoint** supplies the startup brief because it has the best conversational grounding.

### C. Workflow executor
The `/cook` workflow driver owns confirmation, canonical state, role dispatch, review, audit, and completion.

This means handoff generation becomes **deferred** until `/cook` entry, but the handoff source remains **primary-agent aligned**.

---

## New Interaction Model

## Before refactor

1. ordinary chat matures
2. primary agent tells user to run `/cook`
3. primary agent may emit `cook_handoff`
4. user runs `/cook`
5. `/cook` consumes the capsule

## After refactor

1. ordinary chat matures or continues naturally
2. primary agent does **not** prompt `/cook`
3. user explicitly runs `/cook`
4. `/cook` invokes deferred handoff synthesis using primary-agent-style context
5. `/cook` shows Start / Cancel confirmation
6. confirmed handoff becomes advisory startup intake
7. workflow starts

---

## Architecture Change

## 1. Remove proactive `/cook` prompting from ordinary-chat policy

Current ordinary-chat prompt surfaces explicitly instruct the primary agent to:

- stop and tell the user to run `/cook`
- emit an implementation-ready `cook_handoff` capsule when appropriate

That guidance must be replaced.

### New ordinary-chat policy
The primary agent should:

- remain helpful in normal discussion
- avoid proactive `/cook` steering
- avoid emitting startup capsules in ordinary chat
- simply continue answering until the user explicitly uses `/cook`

This keeps ordinary chat neutral.

## 2. Replace explicit-handoff-only startup contract

Current `/cook` startup behavior requires a fresh explicit primary-agent handoff for new workflow start and next-round start.

That contract must change.

### New startup contract
For a new workflow or next round:

- bare `/cook` is a valid explicit entry by itself
- `/cook` must synthesize the startup handoff at that moment
- startup no longer depends on a pre-existing ordinary-chat `cook_handoff` capsule

## 3. Add deferred primary-agent handoff synthesis

Add a new synthesis step at `/cook` entry time:

- input: recent session discussion plus any active/done workflow safety context
- synthesis prompt: primary-agent-style handoff formation, not workflow-role planning
- output: structured startup brief / handoff candidate

This should behave like “what would the primary agent hand off right now, given this conversation?”

## 4. Preserve confirm-first startup

Even if the deferred synthesis is strong, it should still remain advisory until the user confirms.

No canonical workflow files should be rewritten until Start is chosen.

---

## Proposed Data Model

Introduce a deferred handoff source that is distinct from ordinary-chat capsules.

### Suggested source values

Current startup brief source values include:

- `recent_discussion`
- `primary_agent_handoff`

Recommended addition:

- `deferred_primary_agent_handoff`

This makes the intake truth visible in state, UI, and tests.

### Suggested semantics

- `primary_agent_handoff`: an explicit handoff capsule was authored before `/cook`
- `deferred_primary_agent_handoff`: the startup brief was synthesized only after the user explicitly invoked `/cook`, using primary-agent-style context
- `recent_discussion`: generic discussion-derived fallback not explicitly aligned to primary-agent handoff behavior

Under the new design, `deferred_primary_agent_handoff` should become the preferred path for fresh new-workflow startup.

---

## Deferred Handoff Synthesis Contract

The synthesizer should produce the same shape of startup information `/cook` needs today, but without requiring the primary agent to emit it proactively in ordinary chat.

## Required fields

- `mission`
- `scope`
- `constraints` and/or `non_goals`
- `acceptance`
- `risks`
- `notes`
- `task_type`
- `evaluation_profile`

## If implementation-ready startup remains required

Then the synthesizer should also produce:

- `first_slice_goal`
- `first_slice_non_goals`
- `implementation_surfaces`
- `verification_commands`
- `why_this_slice_first`

## Important distinction

These fields are produced **inside `/cook`**, but from a **primary-agent-quality synthesis step**.

They are **not** pre-authored ordinary-chat capsules.

---

## Recommended Runtime Flow

## New workflow startup

1. user runs `/cook`
2. driver detects there is no active workflow to resume, or the user is intentionally starting the next round
3. driver invokes deferred primary-agent handoff synthesis
4. synthesis returns either:
   - a startable startup proposal, or
   - an ambiguous / not-startable result
5. if startable, `/cook` shows confirmation UI
6. on Start, canonical workflow state is written
7. on Cancel, no canonical workflow state changes

## Active workflow resume

For an active workflow:

- bare `/cook` should still resume canonical state by default
- deferred handoff synthesis is only needed when the product wants to support explicit user-selected refocus / replace flows from `/cook`

## Done workflow next round

For a completed workflow:

- bare `/cook` should start deferred handoff synthesis for the next round
- the old “fresh explicit ordinary-chat handoff required” rule should be removed

---

## Failure Behavior

If deferred handoff synthesis cannot produce a trustworthy startup brief, `/cook` should fail closed with a message like:

> `/cook` could not derive a concrete startup brief from the recent discussion. Refine the mission, first slice, or verification intent in the main chat, then run /cook again.`

Important:

- do not silently guess a weak mission
- do not start workflow from vague planning-only output
- do not turn negative or suppression text into the mission

---

## Prompt and Policy Changes

## A. Ordinary-chat boundary reminder

Current ordinary-chat reminder text explicitly tells the primary agent to hand users off to `/cook` and sometimes emit a capsule.

Replace it with guidance like:

- remain in ordinary chat unless the user explicitly runs `/cook`
- do not proactively route the user into workflow
- do not emit `cook_handoff` capsules unless a future explicit preview mode is intentionally retained
- continue refining the task naturally in main chat

## B. `/cook` startup synthesis prompt

Add a dedicated prompt surface for deferred startup synthesis that says, in effect:

- synthesize the startup handoff the primary agent would provide now
- use the full recent session context
- prefer the latest clearly intended mission
- preserve constraints and risks
- produce a bounded first slice if possible
- fail conservatively if the first slice is not concrete enough

This prompt should be separate from:

- workflow-driver prompts
n- regrounder prompts
- ordinary-chat reminders

## C. Remove explicit-handoff-only wording from runtime copy

Any runtime strings that currently say new startup requires a fresh explicit primary-agent handoff should be updated to the new truth.

---

## File-Level Refactor Plan

## 1. `extensions/completion/prompt-surfaces.ts`

Update or replace:

- `buildCookHandoffBoundaryReminder()`

Goals:

- remove proactive `/cook` recommendation behavior
- remove default ordinary-chat capsule emission behavior
- add wording that ordinary chat remains ordinary until the user explicitly enters `/cook`

Add new helper(s), for example:

- `buildDeferredPrimaryAgentHandoffPrompt()`
- `buildDeferredPrimaryAgentHandoffGoalText()`

## 2. `extensions/completion/driver.ts`

Refactor startup routing logic.

Current logic assumes:

- new workflow startup requires fresh explicit primary-agent handoff

New logic should:

- accept bare `/cook` as the explicit entry signal
- request deferred primary-agent handoff synthesis for new-workflow startup and next-round startup
- keep active-workflow resume behavior for canonical continue
- preserve Start / Cancel confirmation before state rewrite

Also update fail-closed messages to describe the new startup contract truthfully.

## 3. `extensions/completion/proposal.ts`

Add deferred synthesis support.

Possible responsibilities:

- define a new assessment result for deferred primary-agent handoff
- keep existing proposal parsing utilities where useful
- decouple startup derivation from pre-authored ordinary-chat `cook_handoff` capsules
- preserve startability validation rules if implementation-ready structure is still required

Depending on the preferred design, explicit `cook_handoff` parsing may either:

- remain as a lower-priority compatibility path, or
- be removed entirely if the product no longer wants ordinary-chat capsules at all

## 4. `extensions/completion/index.ts`

Update public command description and any injected reminders so they no longer describe explicit ordinary-chat handoff as mandatory startup intake.

## 5. Tests under `scripts/**`

Rewrite tests that currently assert:

- new-workflow startup fails closed without fresh explicit primary-agent handoff
- done-workflow next-round startup fails closed without fresh explicit primary-agent handoff

Replace them with tests asserting:

- bare `/cook` triggers deferred primary-agent handoff synthesis
- startup confirmation reflects the synthesized handoff
- weak synthesis fails closed cleanly
- active workflow bare `/cook` still resumes canonical state

## 6. Documentation

Update:

- `README.md`
- `CHANGELOG.md`
- any release-check or packaging parity docs

so shipped behavior matches the new contract.

---

## Backward Compatibility Decision

A product decision is required here.

## Option A: hard switch

- remove ordinary-chat `cook_handoff` startup entirely
- only deferred synthesis on explicit `/cook` is allowed

Pros:

- cleaner product model
- simpler truth for users

Cons:

- larger migration from current implementation and tests

## Option B: compatibility path

- do not proactively emit capsules anymore
- but `/cook` can still consume an explicit capsule if one exists
- deferred synthesis becomes the preferred path

Pros:

- easier rollout
- fewer abrupt breakages

Cons:

- two intake paths remain in the system
- more complexity in routing and docs

Recommendation: **Option B first, then evaluate removing the old path later**.

---

## Test Plan

## 1. Ordinary-chat neutrality regression

Scenario:

- user discusses a workflow-worthy repo task in main chat

Expected:

- primary agent does not proactively tell the user to run `/cook`
- primary agent does not emit `cook_handoff`
- conversation remains ordinary chat

## 2. Bare `/cook` startup regression

Scenario:

- no active workflow
- recent ordinary-chat discussion contains a concrete implementation mission
- user runs `/cook`

Expected:

- deferred primary-agent handoff synthesis runs
- confirmation UI shows the synthesized mission/scope/acceptance
- Start writes canonical state

## 3. Weak startup fail-closed regression

Scenario:

- no active workflow
- recent discussion is vague or planning-only
- user runs `/cook`

Expected:

- deferred synthesis returns not-startable
- `/cook` fails closed
- no canonical state is written

## 4. Active workflow resume regression

Scenario:

- active canonical workflow exists
- user runs bare `/cook`

Expected:

- workflow resumes from canonical state
- no unnecessary startup synthesis runs for ordinary continuation

## 5. Done workflow next-round regression

Scenario:

- previous workflow is done
- recent discussion defines a fresh next-round mission
- user runs `/cook`

Expected:

- deferred synthesis derives the new next-round startup brief
- Start opens the next workflow round

## 6. Source-tracking regression

Expected:

- advisory startup brief source records `deferred_primary_agent_handoff`
- UI and state remain truthful about the intake path

## 7. Compatibility regression if Option B is kept

Scenario:

- an explicit old-style `cook_handoff` exists

Expected:

- `/cook` may still accept it
- but ordinary chat no longer proactively emits it

---

## Acceptance Criteria

This refactor is complete when all of the following are true:

1. The primary agent no longer proactively tells users to use `/cook` in ordinary chat.
2. The primary agent no longer proactively emits `cook_handoff` capsules in ordinary chat.
3. New-workflow startup can begin from explicit user `/cook` entry without requiring a pre-authored ordinary-chat handoff capsule.
4. `/cook` synthesizes startup intake using a primary-agent-style handoff step rather than a thin generic fallback alone.
5. Canonical workflow state is still only written after Start confirmation.
6. Active workflow bare `/cook` still resumes canonical state by default.
7. Done-workflow next-round startup works from explicit user `/cook` plus deferred synthesis.
8. Runtime copy, docs, and release checks all describe the new behavior truthfully.
9. Weak or vague startup synthesis still fails closed.

---

## Non-Goals

This refactor does **not** aim to:

- auto-enter `/cook` without the user explicitly invoking it
- make ordinary chat secretly become workflow mode
- remove Start / Cancel confirmation
- replace canonical workflow roles with startup synthesis
- force workflow startup from vague discussion
- make a fresh workflow agent guess from scratch if a primary-agent-aligned synthesis step is available

---

## Risks and Mitigations

## Risk: deferred synthesis still loses context

If the deferred synthesizer is not actually aligned with the primary-agent perspective, output quality may remain poor.

Mitigation:

- use the same session transcript and as much relevant prompt framing as possible
- explicitly frame the task as “synthesize the handoff the primary agent would give now”
- add regressions around nuanced mission preservation

## Risk: ordinary chat never surfaces workflow boundary clearly enough

If the primary agent never mentions `/cook`, some users may not realize workflow mode exists.

Mitigation:

- rely on explicit product docs and command discoverability instead of proactive prompting
- optionally expose `/cook` affordances in UI/help, not as primary-agent steering text

## Risk: startup ambiguity on vague requests

Without pre-authored capsule structure, `/cook` may see more ambiguous starts.

Mitigation:

- keep fail-closed behavior
- require concrete first-slice structure when needed
- return users to main chat for refinement

## Risk: dual intake paths create complexity

If compatibility mode is kept, code paths may be harder to reason about.

Mitigation:

- clearly prioritize deferred synthesis as the preferred path
- mark explicit ordinary-chat capsules as compatibility-only
- consider removing the compatibility path in a later cleanup

---

## Recommended Implementation Order

### Phase 1: ordinary-chat contract reset

1. remove proactive `/cook` prompting guidance
2. remove ordinary-chat default capsule-emission guidance
3. update public docs text

### Phase 2: deferred synthesis path

4. add prompt surface for deferred primary-agent handoff synthesis
5. add startup routing path in `/cook` for new workflow and next round
6. preserve confirmation-first behavior

### Phase 3: validation and source truthfulness

7. preserve or tighten startability validation
8. add `deferred_primary_agent_handoff` source tracking
9. update UI copy and fail-closed messaging

### Phase 4: regression conversion

10. rewrite explicit-handoff-only startup tests
11. add deferred-synthesis startup tests
12. preserve active-workflow resume regressions

---

## Final Summary

The product should move from:

- **primary agent proactively hands off to `/cook`**

to:

- **user explicitly chooses `/cook`, then `/cook` requests a primary-agent-quality handoff synthesis**

That preserves the best part of the current design — strong mission grounding from the primary-agent perspective — while removing the part you want to avoid: proactive `/cook` prompting and pre-authored ordinary-chat handoff capsules.

The result is a cleaner control boundary:

- ordinary chat stays ordinary until the user says otherwise
- `/cook` remains the only explicit workflow entrypoint
- startup quality still comes from primary-agent-aligned context rather than thin fresh-agent guesswork
- confirmation and canonical workflow rules remain intact
