# Primary-Agent Handoff Pipeline Refactor Plan

## Goal

Design the primary-agent → `/cook` handoff pipeline so `/cook` starts implementation workflow only when the upstream handoff is genuinely startable, while still preserving explicit handoff as the preferred startup-intake path.

The main failure mode to fix is:

- the primary agent correctly decides the task is large enough for `/cook`
- but emits a handoff whose content is still planning-oriented
- `/cook` accepts that handoff as `implementation_workflow_ready`
- workflow then drifts into planning instead of starting bounded repo changes

This refactor should make the pipeline distinguish:

1. **workflow-worthy** tasks
2. **implementation-ready** workflow handoffs

without relying on keyword matching.

---

## Core Product Principle

Do **not** decide implementation-readiness from words like `plan`, `architecture`, or `migration`.

Instead, decide from **startability structure**:

> Can `/cook` take this handoff and reasonably begin a first bounded implementation slice, with concrete repo-change surfaces and verification, without needing to rediscover the work definition first?

---

## Current Problem

The current pipeline improved startup alignment by preferring explicit primary-agent handoff capsules, but it still lets the primary agent label planning-shaped missions as `implementation_workflow_ready`.

That creates a semantic mismatch:

- the handoff is structurally mature enough for workflow entry
- but not mature enough for implementation startup

Result:

- `/cook` follows the handoff faithfully
- but produces planning behavior rather than implementation behavior

This is not mainly a stale-context problem.
It is a **handoff maturity classification** problem.

---

## Design Objectives

### 1. Keep explicit handoff as the preferred intake path
When a fresh, valid primary-agent handoff exists, `/cook` should still prefer it over broad recent-context re-inference.

### 2. Separate workflow readiness from implementation readiness
A task may be ready for long-running workflow without yet being ready for implementation startup.

### 3. Validate by structure, not wording
Use bounded-slice readiness, implementation surfaces, and verification readiness rather than keyword heuristics.

### 4. Keep `/cook` as an explicit workflow boundary
Do not reintroduce router-like silent takeover or implicit workflow entry.

### 5. Fail closed on ambiguous maturity
If the handoff does not clearly support implementation startup, `/cook` should reject it or route the user back to ordinary chat for a more concrete first slice.

---

## Proposed Model

## Two Distinct Handoff Levels

### A. `workflow_handoff`
Meaning:

- the task is big enough for `/cook`
- the work needs workflow-level handling
- but the first implementation slice is not yet concrete enough

Use this when the primary agent can say:

- this needs long-running workflow
- this is beyond a tiny fix
- this likely spans multiple files / steps / verification surfaces

but cannot yet say:

- here is the first bounded implementation slice
- here are the implementation surfaces
- here is how to verify that slice

### B. `implementation_workflow_handoff`
Meaning:

- the task is not only workflow-worthy
- it is also concrete enough to start implementation-oriented workflow now

Use this only when the primary agent can express a first bounded slice clearly enough that `/cook` can begin implementation workflow rather than further mission-definition work.

---

## Recommended Product Direction

For now, keep `/cook` focused on **implementation-oriented workflow**.

That means:

- `implementation_workflow_handoff` is accepted as startup intake for `/cook`
- `workflow_handoff` is either rejected for now or explicitly deferred back to ordinary chat until the first implementation slice is concrete

This keeps the product model clean:

- ordinary chat: clarify, discuss, narrow, decide
- `/cook`: begin bounded implementation workflow

A later version may support planning-oriented workflow explicitly, but that should be a deliberate product expansion, not an accidental side effect of loose handoff validation.

---

## Proposed Capsule Contract Changes

## Existing problem
The current capsule can carry mission/scope/constraints/acceptance and still be too abstract for implementation startup.

## New requirement
If a capsule claims implementation readiness, it must include **first-slice startability structure**.

## Proposed schema shape

```json
{
  "kind": "cook_handoff",
  "source": "primary_agent",
  "handoff_kind": "implementation_workflow_handoff",
  "captured_at": "2026-05-20T00:00:00Z",
  "source_turn_id": "assistant-turn-id",
  "mission": "...",
  "scope": ["..."],
  "constraints": ["..."],
  "non_goals": ["..."],
  "acceptance": ["..."],
  "risks": ["..."],
  "notes": ["..."],
  "task_type": "completion-workflow",
  "evaluation_profile": "completion-rubric-v1",
  "why_cook_now": "...",
  "first_slice_goal": "...",
  "first_slice_non_goals": ["..."],
  "implementation_surfaces": ["..."],
  "verification_commands": ["..."],
  "why_this_slice_first": "..."
}
```

## Semantics of the new fields

### `first_slice_goal`
The first bounded implementation step that should anchor workflow startup.

### `first_slice_non_goals`
What the first slice explicitly does not attempt.
This prevents giant roadmap-like handoffs from pretending to be slice-ready.

### `implementation_surfaces`
The repo surfaces likely to change in the first slice.
Not necessarily exact files, but concrete modules / boundaries / surfaces.

### `verification_commands`
How the first slice can be checked.
This can be deterministic commands or clearly named verification surfaces if exact commands are not yet known.

### `why_this_slice_first`
Why this slice is the right first implementation step rather than another possible entry point.

---

## Startability Validation Rules

`/cook` should validate implementation readiness using structure.

## A handoff is implementation-startable only if all are true

### 1. It defines a bounded first slice
The handoff must identify a concrete first slice, not just a broad program of work.

### 2. It identifies implementation surfaces
The first slice must map to concrete repo-change surfaces.

### 3. It provides verification intent
The first slice must have a verification path, not only future planning claims.

### 4. Acceptance is repo-change-oriented
Acceptance must describe outcomes that can be satisfied by actual repo changes, not just better understanding, clearer planning, or completed analysis.

### 5. The workflow can proceed without rediscovering the mission
If `completion-regrounder` would still need to first decide what the first implementation slice even is, the handoff is not implementation-ready.

---

## Anti-Pattern Definition

A handoff should be rejected as non-startable when it is structurally complete but still requires another round of mission-definition work before implementation can begin.

Typical examples:

- inventory current ownership before deciding what to move first
- define target architecture before choosing the first repo change
- write a migration roadmap so implementation slices can start later
- classify responsibilities before selecting a bounded initial slice

These are not invalid tasks.
They are just not valid **implementation startup handoffs**.

---

## Primary-Agent Skill Refactor

## Why this matters
The primary agent is the upstream source of handoff quality.
If the skill contract is loose, the pipeline will keep producing planning-shaped capsules.

## Skill responsibilities should become explicit
The primary agent must learn to distinguish three states:

### 1. ordinary-chat scope
- keep discussing
- no `/cook` handoff yet

### 2. workflow-worthy but not implementation-ready
- task is too large for an ordinary one-shot response
- but first bounded implementation slice is not concrete yet
- do **not** emit implementation-ready capsule

### 3. implementation-ready
- first bounded slice is clear
- implementation surfaces are known
- verification path exists
- now emit implementation-ready capsule

## Skill rule to add

> Only emit an implementation-ready `/cook` handoff when you can state the first bounded implementation slice, its non-goals, its implementation surfaces, and how that slice will be verified.

## Skill guidance to add
The primary agent should ask itself:

- If `/cook` starts from this handoff, would the next meaningful action be repo changes or more mission-definition work?
- Can the first slice be stated without needing another architecture workshop first?
- Are the first-slice surfaces and verification path concrete enough to anchor startup?

If not, the agent should continue ordinary-chat narrowing instead of emitting an implementation-ready capsule.

---

## `/cook` Intake Refactor

## New priority order

1. latest fresh valid explicit handoff capsule
2. recent discussion for freshness and drift validation
3. canonical workflow context for safety checks
4. context re-inference only as fallback

This priority should stay.
What changes is the validation depth.

## New intake flow

### Step 1: find explicit handoff
Look for the latest assistant-authored `cook_handoff` capsule.

### Step 2: validate freshness and drift
Keep existing freshness / contradiction checks.

### Step 3: validate handoff kind
If it is not an implementation startup handoff, do not start implementation workflow.

### Step 4: validate startability structure
Require:

- `first_slice_goal`
- `first_slice_non_goals`
- `implementation_surfaces`
- `verification_commands`
- repo-change-oriented acceptance

### Step 5: accept or fail closed
If valid:
- use the handoff as startup brief backbone

If invalid:
- fail closed with a precise message telling the user to refine the first implementation slice in ordinary chat before rerunning `/cook`

---

## Fail-Closed Messaging

When the handoff is workflow-worthy but not implementation-startable, `/cook` should say something like:

> `/cook` found a fresh explicit handoff, but it is not concrete enough to start implementation workflow yet. Clarify the first bounded implementation slice, expected implementation surfaces, and verification path in the main chat, then rerun /cook.`

Important:
- do not silently reinterpret planning handoff as implementation mission
- do not generate a fake startup brief from broad planning scope
- do not let negative or rejection text become a Startable mission

---

## Relationship With `completion-regrounder`

The regrounder should remain the canonical planning authority for `.agent/**` state.
But it should not be forced to rediscover the first implementation slice from a vague startup handoff.

Correct division:

### primary agent
forms the implementation-ready first-slice handoff

### `/cook`
validates and confirms it

### regrounder
translates it into canonical workflow state and candidate slices

If the handoff still requires the regrounder to perform first-slice discovery, then the handoff was not implementation-ready yet.

---

## UI / UX Implications

No immediate UI expansion is required for this refactor.
The first priority is semantic correctness of the pipeline.

Optional future UI work can happen later, such as:

- a non-blocking handoff suggestion surface
- explicit user override to stay in ordinary chat
- clearer feedback when a handoff is workflow-worthy but not implementation-startable

But the pipeline should first be made correct without relying on extra UI.

---

## Suggested Implementation Phases

## Phase 1: skill contract tightening
Update `skills/cook-handoff-boundary/SKILL.md` and related reminder wording so the primary agent only emits implementation-ready capsule handoff when first-slice structure exists.

Deliverables:
- revised handoff criteria
- implementation-ready checklist
- explicit examples of valid vs invalid implementation-ready handoff

## Phase 2: schema tightening
Add the new first-slice structure fields to the capsule contract:

- `first_slice_goal`
- `first_slice_non_goals`
- `implementation_surfaces`
- `verification_commands`
- `why_this_slice_first`

Deliverables:
- shared type updates
- prompt reminder updates
- docs updates

## Phase 3: `/cook` startability validator
Update intake so explicit handoff is accepted only when implementation-startable by structure.

Deliverables:
- validator implementation
- fail-closed path
- startup brief source preservation

## Phase 4: regression coverage
Add tests for:

1. valid implementation-ready handoff starts workflow
2. planning-shaped but fresh handoff is rejected
3. stale handoff falls back or fails closed
4. done-workflow + fresh valid handoff still starts correctly
5. negative/rejection rationale never becomes startup mission

---

## Test Matrix

### Case 1: valid first-slice handoff
Expected:
- `/cook` accepts capsule
- startup brief matches first slice
- workflow begins implementation-oriented path

### Case 2: broad migration handoff without first slice
Expected:
- `/cook` rejects as not implementation-startable
- no canonical state rewrite
- user is told to clarify the first slice in ordinary chat

### Case 3: valid handoff but later drift
Expected:
- explicit handoff is ignored
- fallback path applies or fail closed

### Case 4: completed prior workflow + fresh implementation-ready handoff
Expected:
- new handoff overrides stale done-state mission source
- done-state remains safety context only

### Case 5: negative rationale masquerading as mission
Expected:
- rejected
- no Startable startup brief shown

---

## Acceptance Criteria

This refactor is complete when all of the following are true:

1. Explicit primary-agent handoff remains the preferred startup-intake path for `/cook`.
2. `/cook` no longer accepts planning-shaped handoffs as implementation startup merely because they are fresh and structurally well-formed.
3. Implementation readiness is decided by startability structure, not keyword matching.
4. A valid implementation-ready handoff must identify the first bounded slice, implementation surfaces, and verification path.
5. If the handoff is not implementation-startable, `/cook` fails closed rather than drifting into planning.
6. Finished prior workflow state does not override a fresh valid implementation-ready handoff.
7. Negative suppression or rejection text never becomes a Startable mission.
8. Canonical `.agent/**` authority stays with workflow roles; the handoff capsule remains startup intake only.

---

## Non-Goals

This refactor does **not** aim to:

- add router-like implicit workflow takeover
- remove explicit `/cook` as the workflow boundary
- replace `completion-regrounder` as canonical planning authority
- support full planning-only workflow startup unless explicitly designed later
- infer implementation readiness from keywords alone
- make arbitrary assistant summaries authoritative

---

## Final Summary

The right fix is not to teach `/cook` more planning words to reject.
The right fix is to make the pipeline distinguish:

- **big enough for workflow**
- **concrete enough for implementation startup**

The primary agent should only emit implementation-ready handoff when it can define the first bounded implementation slice, its surfaces, and its verification path.

Then `/cook` should validate that structure and either:

- start implementation workflow from it
- or fail closed and ask for a more concrete first slice

That keeps explicit handoff as the primary intake path while preventing planning-shaped missions from accidentally launching implementation workflow.
