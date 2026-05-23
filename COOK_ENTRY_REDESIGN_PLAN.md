# /cook Entry Redesign Plan

## Goal

Redesign the transition from ordinary main chat into completion workflow so that:

- entering workflow is stable and predictable
- `/cook` remains the only explicit workflow entrypoint
- main-chat discussion is durably captured once the user chooses workflow mode
- `completion-regrounder` remains authoritative for canonical slice planning
- workflow dispatch no longer depends on fragile synthetic-turn detection or in-memory-only routing state

In short:

- ordinary chat refines intent
- `/cook` confirms and canonicalizes startup intent
- workflow begins immediately from canonical state
- `completion-regrounder` turns startup intent into canonical slices

---

## Executive Summary

The current extension does two hard things at once during `/cook` entry:

1. derive a startup brief from recent discussion
2. activate the workflow driver through synthetic prompt routing

The first part is broadly sound.

The second part is fragile because it currently depends on transient runtime conditions such as:

- in-memory routing activation
- a synthetic `/skill:completion-protocol ...` message becoming the active turn
- auto-continue bookkeeping keyed by fingerprints and queue state

This creates a product mismatch:

- the user believes `/cook` + **Start** means “workflow has started”
- the implementation often treats `/cook` + **Start** as “queue a later turn that may become the real driver turn”

This redesign removes that mismatch.

### Core product decision

After the user explicitly runs `/cook` and confirms **Start**:

- the primary agent should immediately write a confirmed startup-intake artifact into `.agent/**`
- the workflow should be considered canonically active at that point
- the driver should dispatch directly from canonical state
- `completion-regrounder` should then reconcile repo truth and build the canonical slice plan

### Core authority split

- **Primary agent at `/cook` entry**: capture and confirm user intent
- **`completion-regrounder`**: reconcile repo truth and author canonical `plan.json` / `active-slice.json`

This keeps the existing workflow architecture but fixes the unstable entry layer.

---

## Problem Statement

The current `/cook` entry path is harder to reason about than the actual workflow.

### Observed user-facing problems

- users can explicitly invoke `/cook` and still fail to enter workflow reliably
- the UI can show canonical workflow state while role dispatch remains blocked
- the system can say the next mandatory role is `completion-regrounder` while simultaneously refusing `completion_role`
- reloads, session changes, or prompt-shape differences can break entry or resume behavior
- the workflow itself is comparatively strong, but the handoff from main chat to workflow feels brittle

### Root cause

The system currently spreads workflow-entry truth across three different layers:

1. **canonical repo state** in `.agent/**`
2. **runtime memory state** such as activated routing roots
3. **turn-shape detection** such as “is the current turn the special synthetic driver prompt?”

That means “has the user entered workflow?” is not represented by one durable source of truth.

### Consequence

The user-level action:

- run `/cook`
- confirm **Start**

is not identical to the system-level state:

- workflow driver is authorized to dispatch completion roles

That mismatch is the main design flaw this plan addresses.

---

## Design Principles

### 1. Explicit user entry remains mandatory

`/cook` stays the only explicit workflow entrypoint.

The redesign must not make ordinary chat silently auto-enter completion workflow.

### 2. `Start` means workflow is active

Once the user confirms **Start**, workflow activation must be canonical and durable.

There must not be a hidden second hop where activation depends on a later synthetic prompt being recognized correctly.

### 3. Canonical intent before canonical plan

When `/cook` starts, the primary agent should canonicalize startup intent first.

Only after that should `completion-regrounder` canonicalize the execution plan and slices.

### 4. Regrounder remains canonical planning authority

The primary agent may capture:

- mission
- scope
- constraints
- acceptance
- risks
- first-slice hints

But it should not become the final authority for:

- `plan.json`
- selected slices
- `active-slice.json`
- post-reconciliation workflow state

### 5. Dispatch authorization should depend on canonical workflow state, not prompt text

The ability to call `completion_role` should not depend on whether the latest turn text matches a special `/skill:...` pattern.

### 6. Resume should be attach-based, not prompt-reconstruction-based

When canonical workflow state already exists, `/cook` should attach to it and continue from `.agent/**`, not reconstruct driver legitimacy from ephemeral message history.

---

## Product Model After Redesign

### Ordinary main chat

Ordinary chat continues to support:

- requirement clarification
- tradeoff discussion
- direct implementation when workflow mode is unnecessary
- optional recommendation to use `/cook`

Ordinary chat does **not**:

- activate completion roles
- write canonical workflow execution state
- pretend workflow has already started

### `/cook` intake

When the user runs `/cook`:

1. derive or synthesize a startup brief from the current discussion
2. show **Start / Cancel** confirmation
3. on **Start**, persist the confirmed startup brief into `.agent/**`
4. canonically mark the workflow as active
5. begin workflow driver dispatch immediately from canonical state

### Workflow execution

After workflow starts:

- `completion-regrounder` reads the startup brief and repo truth
- `completion-regrounder` creates or rebuilds canonical slices
- all later role dispatch proceeds from canonical `.agent/**` state

---

## Architecture Change

## Current model

Today, the extension effectively treats `/cook` as:

- an intake command
- followed by a synthetic self-message
- followed by a special driver-turn detection rule
- followed by guarded role dispatch

This creates fragile coupling between:

- command handling
- system prompt injection
- queue timing
- current-turn text shape
- routing guard authorization

## Target model

The redesign introduces a clean separation:

### Layer A — ordinary chat boundary

Responsible for:

- keeping ordinary chat ordinary
- allowing direct implementation when desired
- optionally recommending `/cook`

### Layer B — `/cook` intake and activation

Responsible for:

- startup-brief synthesis
- Start / Cancel confirmation
- canonical startup-intent persistence
- canonical workflow activation
- attach or replace decisions for existing workflows

### Layer C — workflow driver

Responsible for:

- reading canonical `.agent/**`
- dispatching mandatory roles
- resuming after reload or compaction
- not depending on prompt-shape heuristics for legitimacy

---

## New Canonical Artifacts

## 1. Startup brief artifact

Introduce a durable startup-intake artifact under `.agent/**`.

Recommended path:

```text
.agent/startup-brief.json
```

Alternative: keep using `advisory_startup_brief` nested inside `state.json`, but make it a formal first-class contract. The preferred design is a dedicated file because it is easier to reason about, inspect, diff, and validate.

### Purpose

This file captures what the primary agent and user agreed to at `/cook` entry.

It is:

- canonical intake for workflow startup
- durable across reload and compaction
- advisory input to regrounding

It is **not**:

- the canonical slice plan
- selected-slice state
- a substitute for `plan.json`

### Suggested schema

```json
{
  "schema_version": 1,
  "artifact_type": "completion-startup-brief",
  "source": "primary_agent",
  "confirmed": true,
  "confirmed_at": "<ISO-8601>",
  "mission": "<mission anchor>",
  "goal_text": "<displayable startup summary>",
  "scope": ["..."],
  "constraints": ["..."],
  "acceptance": ["..."],
  "risks": ["..."],
  "notes": ["..."],
  "first_slice_goal_hint": "<optional bounded first-slice hint>",
  "first_slice_non_goals_hint": ["..."],
  "implementation_surfaces_hint": ["..."],
  "verification_commands_hint": ["..."],
  "why_this_slice_first_hint": "<optional rationale>",
  "task_type": "completion-workflow",
  "evaluation_profile": "completion-rubric-v1"
}
```

## 2. Canonical workflow-entry state

Extend `.agent/state.json` so workflow-entry activation is durable and inspectable.

### Suggested fields

```json
{
  "workflow_entry_status": "active",
  "workflow_entry_source": "/cook",
  "workflow_entry_confirmed_at": "<ISO-8601>",
  "workflow_session_id": "<opaque durable id>",
  "startup_brief_path": ".agent/startup-brief.json"
}
```

These fields should represent:

- whether workflow was explicitly entered
- when it was entered
- what canonical startup-intake artifact it is bound to
- which workflow session or lease is currently active

This replaces the need to rely on transient in-memory routing activation as the source of truth.

---

## Authority Model

## What the primary agent should do at `/cook`

After the user chooses workflow mode and confirms **Start**, the primary agent should:

- write the confirmed startup brief into `.agent/startup-brief.json`
- initialize or refocus canonical workflow state
- set canonical workflow-entry status to active
- preserve the startup brief as advisory intake for later regrounding
- immediately hand off to `completion-regrounder`

The primary agent may also persist advisory hints such as:

- first slice goal hint
- implementation surfaces hint
- verification commands hint
- why this slice first

These hints are useful for regrounding but are not final canonical slice commitments.

## What `completion-regrounder` should do next

`completion-regrounder` should remain responsible for:

- reading current repo truth
- validating or rejecting startup hints against repo reality
- rebuilding or reconciling `plan.json`
- selecting or refreshing the canonical active slice
- deciding `next_mandatory_role`
- handling drift, reopened slices, and worktree blockers

This preserves the strongest current part of the design: canonical planning authority lives with regrounding, not with chat intake.

---

## New `/cook` Behavior

## Case 1 — no existing workflow

### Current flawed behavior

- synthesize proposal
- Start/Cancel
- write some state
- queue synthetic driver prompt
- hope a later turn becomes the true workflow driver

### New behavior

1. user runs `/cook`
2. extension derives a fresh explicit startup brief
3. extension shows **Start / Cancel**
4. on **Start**:
   - scaffold `.agent/**` if needed
   - write `.agent/startup-brief.json`
   - mark workflow-entry status active
   - write canonical initial state with `next_mandatory_role = completion-regrounder`
   - immediately enter driver dispatch
5. driver invokes `completion-regrounder`

There is no hidden second activation hop.

## Case 2 — active workflow exists

### New behavior

1. user runs `/cook`
2. extension loads canonical state
3. extension attaches to the existing active workflow
4. if a replacement mission is proposed, show replace/continue chooser
5. after confirmation, continue directly from canonical `next_mandatory_role`

No synthetic driver-prompt text should be required to prove legitimacy.

## Case 3 — previous workflow is done

### New behavior

1. user runs `/cook`
2. extension treats previous workflow as historical context only
3. extension derives a new startup brief for the next round
4. on **Start**, it writes a new startup brief and reactivates workflow state
5. `completion-regrounder` canonicalizes the new round

---

## Guard and Authorization Redesign

## Current guard behavior to replace

Today, `completion_role` authorization effectively depends on:

- role subprocess context, or
- in-memory routing activation + special driver-turn detection

This is fragile.

## Target authorization model

`completion_role` should be allowed when one of the following is true:

1. the current process is already a completion role subprocess
2. the extension is executing inside an active `/cook` command flow
3. canonical state says workflow entry is active and the current workflow session or lease is valid

### Important consequence

The guard should no longer care whether the latest turn text happens to equal a synthetic `/skill:completion-protocol ...` message.

### Recommended implementation direction

Replace prompt-shape authorization with a durable driver-session or workflow-lease model.

Possible approaches:

- a `workflow_session_id` written into `state.json`
- a short-lived but durable lease artifact in `.agent/tmp/`
- a driver session token tracked by the extension and recoverable from canonical state

The exact mechanism may vary, but the source of authority must be reconstructible after reload.

---

## Driver Redesign

## Current problem

The current driver logic is split across:

- command handling
- prompt queuing
- queued prompt tracking
- auto-continue fingerprint tracking
- current-turn prompt detection

This makes it hard to understand when workflow is truly active.

## Target driver model

The workflow driver should become an explicit internal control path.

### Desired properties

- `/cook` Start enters the driver immediately
- role dispatch happens from canonical state
- auto-continue and resume read canonical state first
- compaction recovery re-attaches to canonical workflow state
- driver legitimacy does not depend on message text shape

### Two acceptable implementation patterns

#### Preferred

Make `/cook` directly invoke the workflow driver routine instead of sending a synthetic message to the user channel.

#### Fallback if API constraints require an agent turn

If the extension must still create a synthetic prompt for technical reasons, that prompt should carry a durable session or lease identifier, and the guard should validate that identifier rather than raw prompt wording.

Even in the fallback design, the source of truth should still be canonical workflow-entry state.

---

## File-Level Refactor Plan

## `extensions/completion/driver.ts`

### Responsibilities to keep

- derive startup proposals
- confirm Start / Cancel
- handle existing workflow replacement or continuation choice

### Responsibilities to change

- stop treating queued driver prompts as the primary activation mechanism
- stop making workflow legitimacy depend on the later synthetic prompt being recognized
- write the startup brief artifact on Start
- write canonical workflow-entry activation state on Start
- directly trigger driver dispatch or durable attach

### Planned refactor areas

- simplify or remove `queueCompletionDriverPrompt()` as the central activation path
- simplify or remove fingerprint-based parked/in-flight state as an authorization dependency
- separate intake confirmation from driver execution

## `extensions/completion/index.ts`

### Responsibilities to keep

- extension lifecycle hooks
- status surface refresh
- command registration
- tool registration

### Responsibilities to change

- stop using `isCompletionDriverPromptTurn()` as a primary authorization signal
- stop depending on in-memory activation set as canonical workflow-entry truth
- allow `/cook` execution context and canonical workflow-entry state to authorize `completion_role`
- keep ordinary-chat boundary reminders, but decouple them from entry authorization

## `extensions/completion/policy-guards.ts`

### Responsibilities to keep

- read-only restrictions for reviewer/auditor/stop-judge
- control-plane edit restrictions for bootstrapper/regrounder
- protection against nested completion-role dispatch

### Responsibilities to change

- replace “explicit driver turn” authorization based on prompt shape with authorization based on:
  - command-flow context, or
  - canonical workflow-entry active state, or
  - durable workflow session/lease

## `extensions/completion/state-store.ts`

### Planned additions

- startup brief path resolution
- read/write helpers for the startup brief artifact
- new workflow-entry fields in default state
- migration logic for older repos without startup-brief support

## `extensions/completion/prompt-surfaces.ts`

### Responsibilities to keep

- startup confirmation layout
- ordinary-chat boundary reminder

### Planned additions

- startup-brief rendering helpers
- clear separation between:
  - startup brief display
  - workflow routing display
  - regrounding authority display

## `skills/completion-protocol/SKILL.md`

### Planned updates

- clarify that `/cook` first canonicalizes startup intent
- clarify that startup brief is canonical intake but not canonical slice plan
- explicitly state that `completion-regrounder` converts startup intent + repo truth into slices
- remove or soften language that implies synthetic driver prompts are the workflow root of truth

## `skills/cook-handoff-boundary/SKILL.md`

### Planned updates

- make it explicit that `/cook` writes a startup brief and then begins workflow from canonical state
- make it explicit that the primary agent should prepare implementation-ready intake, not final canonical slices

---

## Schema and State Migration Plan

## Goals

- preserve existing repos using current `.agent/**` layout
- avoid breaking in-progress workflows unnecessarily
- allow gradual adoption of startup-brief-first entry

## Migration steps

### 1. Add new optional state fields

Older state remains readable. New fields are added when `/cook` is next used.

### 2. Add startup brief artifact lazily

Do not require `.agent/startup-brief.json` to exist for old workflows immediately.

When a new workflow starts or an old workflow is explicitly re-entered through the new `/cook`, create it.

### 3. Backward-compatible resume

If an old workflow lacks a startup brief:

- resume from existing canonical state
- do not block role dispatch solely because the startup brief is missing
- allow regrounder to continue using the old state model

### 4. Optional one-time repair path

If desired, `completion-bootstrapper` or `completion-regrounder` may create a missing startup brief placeholder for old workflows, but this should not be mandatory for correctness.

---

## Testing Plan

The redesign must be covered with deterministic tests focused on entry stability.

## New test categories

### 1. Start means active

Validate that after `/cook` + **Start**:

- canonical workflow-entry state is active
- startup brief exists
- the driver may legally dispatch `completion-regrounder`
- no synthetic-turn shape is required to authorize dispatch

### 2. Reload resilience

Validate that after `/cook` + **Start** and then reload/session replacement:

- the workflow may still resume from canonical state
- `completion_role` is not blocked purely because in-memory activation was lost

### 3. Existing active workflow attach

Validate that rerunning `/cook` on an active workflow:

- attaches to the canonical workflow
- dispatches from `next_mandatory_role`
- does not require a synthetic driver prompt to be recognized first

### 4. Replace/refocus still confirm-first

Validate that an active workflow with a distinct new startup brief still:

- offers continue vs replace
- writes updated startup brief only after confirmation
- sends the refocused mission to regrounding

### 5. Done workflow starts next round cleanly

Validate that `/cook` on a done workflow:

- treats the old workflow as historical
- writes a new startup brief
- begins a fresh regrounding wave

### 6. Guard correctness

Validate that `completion_role` is:

- still forbidden in ordinary chat
- still forbidden for nested role dispatch
- still forbidden for read-only roles to bypass write restrictions
- now allowed from valid canonical workflow-entry state even without special prompt wording

### 7. Startup brief authority boundaries

Validate that:

- primary agent startup hints do not directly become canonical slices
- regrounder may revise or ignore first-slice hints when repo truth demands it

---

## Suggested Test Files and Coverage Updates

Potential updates likely needed in:

- `scripts/smoke-test.sh`
- `scripts/refocus-test.sh`
- `scripts/context-proposal-test.sh`
- `scripts/role-runner-contract-test.sh`
- `scripts/observability-status-test.sh`
- new entry-stability regression test(s)

Potential new deterministic assertions:

- startup brief file existence and schema parity
- workflow-entry active-state parity after Start
- reload-safe dispatch authorization
- no reliance on `/skill:completion-protocol` prompt text in guard logic

---

## Incremental Implementation Plan

## Phase 1 — canonical startup brief

Implement:

- `.agent/startup-brief.json`
- write-on-Start behavior
- state fields for workflow-entry activation
- backward-compatible loading helpers

Deliverable:

- startup intent becomes durable and inspectable

## Phase 2 — authorization rewrite

Implement:

- new guard logic based on canonical workflow-entry state or driver session
- remove prompt-shape dependence from `completion_role` authorization

Deliverable:

- `/cook` entry no longer fails because the current turn was not recognized as the special synthetic driver prompt

## Phase 3 — driver simplification

Implement:

- direct driver dispatch from `/cook` Start
- simplify or remove queued synthetic prompt as the primary activation path
- reduce or eliminate fingerprint/in-flight parked bookkeeping as an authorization dependency

Deliverable:

- the driver path matches the product model more closely

## Phase 4 — resume and attach cleanup

Implement:

- `/cook` attach behavior for active workflows
- reload-safe canonical re-entry
- compaction recovery alignment with the new session model

Deliverable:

- resume behavior becomes stable and easier to understand

## Phase 5 — docs, skills, and tests

Implement:

- README updates
- skill updates
- migration notes
- deterministic regression coverage

Deliverable:

- public behavior, internal contract, and tests all match

---

## Non-Goals

This redesign does **not** aim to:

- replace `completion-regrounder` as canonical planning authority
- eliminate confirm-first `/cook` startup
- allow ordinary chat to dispatch completion roles
- collapse the role topology into a single agent
- remove fail-closed startup validation
- redesign the reviewer/auditor/stop-judge rubric model

---

## Risks and Mitigations

## Risk 1 — accidental weakening of ordinary-chat boundary

If authorization is loosened incorrectly, ordinary chat might gain workflow powers.

### Mitigation

Keep `/cook` as the only activation source and tie dispatch authority to canonical workflow-entry state written only by confirmed `/cook`.

## Risk 2 — startup brief mistaken for canonical plan

A durable startup artifact could be misread as the plan itself.

### Mitigation

Use explicit naming and docs:

- startup brief = confirmed intake
- `plan.json` = canonical slice backlog
- `active-slice.json` = canonical active contract

## Risk 3 — migration complexity for older workflows

Existing repos may lack the new startup brief file.

### Mitigation

Make the startup brief additive and backward-compatible.

## Risk 4 — driver simplification may affect observability

Removing synthetic prompt plumbing may impact status surfaces.

### Mitigation

Preserve status surfaces, but source them from canonical state and live role activity instead of prompt-shape assumptions.

---

## Open Questions

1. Should the startup brief be a separate file or a first-class object nested in `state.json`?
   - recommendation: separate file

2. Does the Pi extension API permit direct driver dispatch from the `/cook` command handler without a synthetic user message?
   - if yes, prefer that path
   - if no, use a durable workflow-session or lease model instead of prompt-shape detection

3. Should startup brief history be retained across refocus and next rounds?
   - recommendation: latest startup brief canonical, old briefs archived optionally in history if needed

4. Should a workflow session id be durable across the whole workflow or renewed on every `/cook` attach?
   - recommendation: durable per workflow round, renewable on explicit refocus or next-round start

---

## Final Recommendation

Adopt the following product rule as the center of the redesign:

> `/cook` should canonicalize startup intent first, then start workflow immediately from canonical state; `completion-regrounder` should remain the authority that converts startup intent plus repo truth into canonical slices.`

That one rule resolves the main instability in the current design while preserving the strongest existing parts of the completion workflow.

---

## Proposed Deliverable Name

This document should serve as the root redesign plan for the `/cook` entry architecture and may be referenced during implementation, documentation updates, and release gating.
