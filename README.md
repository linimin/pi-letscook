# @linimin/pi-letscook

`/cook` is optional workflow mode for turning main-chat discussion about concrete repo changes into a resumable repo workflow stored in repo-local `.agent/**` state. Internal V1 helper subagents (`completion_assist`) are available only to allowed completion roles beneath the single canonical `/cook` control plane; they are not a public generic subagent framework.

You can still implement directly in ordinary chat when you do not need workflow state. Use `/cook` when you want confirm-first startup, resumability, review/audit flow, or canonical `.agent/**` control.

## Use it when

- work spans multiple sessions
- you want one mission tracked in repo state instead of chat memory
- you want clear continue / refocus / next-round behavior
- you want review, audit, and verification tied to the repo
- you want a confirm-first workflow boundary before canonical state is written

## Skip it when

- you only need a one-off answer
- you want the agent to implement directly in ordinary chat
- you are brainstorming
- you are writing planning docs but are not ready to start concrete repo changes

## Install

```bash
pi install npm:@linimin/pi-letscook
```

Then run `/reload` in Pi.

## 30-second quick start

1. Install the package:
   `pi install npm:@linimin/pi-letscook`
2. Run `/reload` in Pi.
3. In the main chat, either implement directly with the agent or refine the concrete repo change you want.
4. When you want workflow mode, run `/cook` or `/cook <prompt>`.
5. Review the startup brief and choose **Start** or **Cancel**.
6. Later, run `/cook` or `/cook resume` to continue from canonical state, `/cook park` to park a stopped workflow for ordinary direct edits, or `/cook cancel` to close a stopped workflow.

```text
/cook
/cook tighten the login redirect fix and land the missing tests
```

## Common actions

| If you want to... | Do this |
|---|---|
| Implement directly without workflow | Ask in ordinary chat and let the agent modify the repo directly |
| Start a tracked workflow | Discuss the concrete repo change in ordinary chat, then run `/cook` when you want workflow mode, or run `/cook <prompt>` when you want to provide explicit startup intent inline |
| Continue the current workflow | Run `/cook` or `/cook resume` |
| Park a stopped workflow for ordinary direct edits | Run `/cook park` when canonical state is already stopped (`await_user_input`, `blocked`, or `paused`) |
| Cancel a stopped workflow | Run `/cook cancel` when canonical state is already stopped or parked |
| Refocus or start the next round | Discuss the new concrete repo change in ordinary chat, then run `/cook` when you want workflow mode |

## What `/cook` expects

- enough current task context for `/cook` to reuse a fresh explicit `cook_handoff`, synthesize one in the same entry, or—only when no handoff is available—validate a recent-discussion startup brief for a concrete repo-change mission
- a mission-level repo-change brief that can truthfully start workflow, even when the first slice still needs regrounding
- scope, constraints, acceptance, and risk context strong enough for `completion-regrounder` to reconcile canonical slices from repo truth after Start
- README/CHANGELOG updates still count as concrete repo changes
- assistant-produced summaries and plan/spec/design-doc/proposal-only artifacts still do not count as workflow-ready startup input by themselves; `/cook` still needs either a concrete handoff or a validated recent-discussion repo-change brief
- `/cook` follows this startup precedence: fresh explicit `cook_handoff` -> same-entry primary-agent handoff synthesis -> validated `recent_discussion` startup analysis -> fail closed

If explicit or synthesized handoff data still cannot prepare a concrete workflow startup brief, `/cook` may use validated `recent_discussion` startup analysis as a bounded fallback only when the recent discussion clearly describes a concrete repo-change mission. Weak, ambiguous, planning-only, `not_repo_change`, or otherwise unclear startup analysis still fails closed, leaves canonical `.agent/**` state unchanged, and tells you to refine the mission, repo-change intent, or key constraints in the main chat before rerunning `/cook`.

If a fresh explicit handoff exists but its acceptance or initial-slice details are still weak, `/cook` treats that capsule as startup input instead of as an automatic blocker. The same-entry primary-agent handoff synthesis step may tighten the mission, acceptance, or advisory first-slice hints from recent discussion before Start / Cancel confirmation.

If you pass inline arguments to `/cook`, `/cook` treats them as explicit startup intent for this workflow entry. It still synthesizes a primary-agent startup brief, shows **Start** / **Cancel**, and only writes canonical state after confirmation.

## Workflow entry

Only explicit `/cook` enters workflow mode. Ordinary prompts stay in the main chat and go straight to the primary agent.

`/cook <prompt>` is still the same explicit workflow command. The inline prompt is startup intent, not canonical state.

Ordinary chat can still directly implement repo changes. `/cook` is for the cases where you want workflow control rather than just implementation help, and the primary agent should prepare the handoff before you run it.

When you explicitly run `/cook`, it first checks for a fresh explicit primary-agent handoff. If one is missing, it calls a same-entry primary-agent handoff synthesis step from the current task context or inline `/cook` prompt, then asks you to **Start** or **Cancel** before rewriting canonical workflow state.

If no explicit or synthesized handoff is startable, `/cook` may still use validated `recent_discussion` startup analysis as a bounded fallback before showing **Start** or **Cancel**.

Explicit `/cook` capsules are still valid startup intake, but they are no longer the only path because `/cook` can synthesize the primary-agent handoff in the same entry when needed or, when no handoff is available, fall back to validated `recent_discussion` startup analysis.

Important behavior:
- `/cook` is an optional workflow boundary and manual entry point
- `/cook <prompt>` lets you provide explicit startup intent inline without bypassing synthesis or confirmation
- startup and next-round entry stay confirm-first, following explicit primary-agent handoff -> same-entry primary-agent handoff synthesis -> validated `recent_discussion` startup analysis -> fail closed
- active workflows resume from canonical `.agent/**` state unless a concrete replacement proposal is available from explicit handoff, same-entry synthesis, or validated `recent_discussion` analysis in the same `/cook` entry
- stopped workflows now have explicit same-session controls: rerun `/cook` or `/cook resume` to continue, `/cook park` to park for ordinary direct edits with `requires_reground = true`, and `/cook cancel` to close the workflow
- explicit slash commands other than `/cook` continue normally in the main chat
- ordinary main-chat discussion may clarify, propose, or directly implement repo changes without entering workflow mode

## Typical examples

Start a new workflow from recent main-chat discussion:

```text
I want to add login redirect handling and tests.
# discuss/refine in main chat
/cook
```

Start a new workflow directly from explicit inline startup intent:

```text
/cook add login redirect handling and the missing redirect tests
```

## What happens when you run `/cook`

`/cook` first checks for a fresh explicit primary-agent handoff capsule. New-workflow entry and done-workflow next-round entry use that handoff when it already exists; otherwise `/cook` calls a same-entry primary-agent handoff synthesis step from current context or inline prompt. If no explicit or synthesized handoff is startable, `/cook` may still use validated `recent_discussion` startup analysis as a bounded fallback for a concrete repo-change mission before it continues to Start / Cancel. Any initial-slice details included there are advisory hints only; `completion-regrounder` still authors the canonical slice plan after Start. Active workflows still resume canonical state by default unless a concrete replacement proposal is available from explicit handoff, same-entry synthesis, or validated recent-discussion analysis in the same `/cook` entry. None of this prevents ordinary-chat implementation when you choose not to enter workflow mode.

| Repo state | What you'll see |
|---|---|
| No workflow yet | `/cook` consumes a fresh explicit primary-agent handoff when one already exists, or synthesizes one from the primary-agent view in the same entry, then asks you to choose **Start** or **Cancel**. If no explicit or synthesized handoff is available, `/cook` may still use validated `recent_discussion` startup analysis as a bounded fallback. If a fresh explicit handoff is weak, `/cook` first tries to tighten mission, acceptance, or advisory slice hints through same-entry startup synthesis before failing closed. Weak, planning-only, non-repo-change, or unclear startup analysis still fails closed. |
| Active workflow exists | Usually a resume of the current workflow from canonical `.agent/**` state. If canonical state is stopped (`await_user_input`, `blocked`, or `paused`), rerunning `/cook` or `/cook resume` resumes from canonical state, `/cook park` records a parked paused posture so ordinary chat may edit directly until a later reground, and `/cook cancel` closes the workflow. If a concrete replacement proposal exists already, is synthesized in the same `/cook` entry, or is validated from recent discussion and points to a different mission, `/cook` shows a chooser first and only rewrites canonical state after you confirm the replacement. Ambiguous, low-confidence, or missing replacement analysis stays conservative. |
| Previous workflow is `done` | `/cook` can start the next implementation round from a fresh explicit primary-agent handoff or from the same-entry primary-agent handoff synthesis step behind **Start** or **Cancel**. If neither is available, the same bounded validated `recent_discussion` fallback still applies. Startup hints may still be advisory; `completion-regrounder` derives the canonical next slices after Start. |

## Confirmation and fail-closed behavior

`/cook` never silently starts or rewrites canonical `.agent/**` state on unclear input.

- startup, next-round, and refocus proposals are approval-only
- actions are **Start** and **Cancel**
- **Cancel** is side-effect free: discuss changes in the main chat and rerun `/cook`
- weak, ambiguous, stale, invalid, assistant-produced, or planning-only intake does not start a workflow
- `task_type` and `evaluation_profile` only come from explicit structured startup artifacts when those fields are present; otherwise `/cook` keeps the packaged `completion-workflow` / `completion-rubric-v1` defaults instead of inferring them from free-text discussion
- when a concrete replacement mission suggests replacing an active workflow, `/cook` shows a chooser before any canonical state rewrite

When you accept startup or refocus, `/cook` persists the chosen workflow state in canonical `.agent/**` files before the re-ground round begins.

The confirmed startup brief is also preserved there in `.agent/current/startup-brief.json` as canonical intake for later re-grounding. It may carry optional `*_hint` fields for an initial slice, but those hints are advisory and do not replace `.agent/current/plan.json` or `.agent/current/active-slice.json`, which remain under regrounder authority.

The pre-`/cook` handoff capsule itself is not canonical workflow state. It is only startup intake for `/cook`.

## Observability

When canonical `.agent/**` state exists and no role is actively running, the extension shows a completion widget sourced from that state. The widget summarizes:

- current phase
- selected slice
- next mandatory role
- remaining work counts

There is no completion status line.

While a `completion_role` subprocess is running:

- the non-running widget is suppressed
- tool activity is shown separately from assistant-reported progress
- running-role output distinguishes tool work from `PROGRESS`, `RATIONALE`, `NEXT`, `VERIFYING`, and `STATE-DELTA`
- waiting and stalled states are surfaced deterministically from timestamps

## Maintainer and protocol details

The sections below are mainly useful if you maintain the extension, inspect canonical `.agent/**` state, or work on the packaged completion protocol itself.

## Structured evaluation rubrics

The packaged completion workflow now defines a shared structured evaluation-rubric contract for the read-only evaluation roles:

- `completion-reviewer`
- `completion-auditor`
- `completion-stop-judge`

Those roles now use the same rubric section and exact dimension names:

- `Contract coverage`
- `Correctness risk`
- `Verification evidence`
- `Docs/state parity`

Each rubric line uses the same verdict words:

- `pass` — no material issue remains for that dimension
- `concern` — a real caveat or remaining gap exists, but it does not by itself force rejection or `NO-STOP`
- `fail` — a blocking issue or contradictory truth exists, so the role's final verdict must not be positive

The packaged control plane now also carries canonical routing signals:

- `task_type: completion-workflow`
- `evaluation_profile: completion-rubric-v1`

Those identifiers are persisted in package defaults plus runtime `.agent/current/state.json`, `.agent/current/plan.json`, and `.agent/current/active-slice.json`, then surfaced in kickoff/reminder/resume text and reviewer/auditor/stop-judge evaluation handoffs so downstream roles can rely on canonical signaling instead of prose inference alone.

The active-slice exact implementer handoff is now the canonical implementation contract for selected, in-progress, committed, and done slices. In addition to the locked slice goal, acceptance criteria, contract IDs, blocked-on list, `priority`, and `why_now`, the v2 contract requires:

- `implementation_surfaces` — the repo surfaces expected to change or stay in parity for the slice
- `verification_commands` — the focused and broader deterministic checks the implementer is expected to run before committing
- `locked_notes` / `must_fix_findings` — canonical scope locks plus review follow-up obligations for the current slice
- `basis_commit` — the clean HEAD the slice was selected against
- `remaining_contract_ids_before` plus `release_blocker_count_before` / `high_value_gap_count_before` — the locked before-slice counters the implementer must preserve in reports and later handoffs

The selected plan slice must mirror that exact contract across goal, contract IDs, acceptance criteria, blocked-on state, `priority` / `why_now`, `implementation_surfaces`, `verification_commands`, locked notes, must-fix findings, `basis_commit`, and the before-slice counters. The package-owned `scripts/verify-completion-control-plane.js` entrypoint plus the thin `.agent/verify_completion_control_plane.sh` forwarder and the reminder/compaction-resume surfaces now fail closed on that drift instead of only checking slice-id presence, so implementers can recover from canonical state rather than prose-only summaries.

Reviewer, auditor, and stop-judge dispatch/reminder surfaces now also thread the current active-slice implementation contract (`implementation_surfaces`, `verification_commands`, locked notes, must-fix findings, `basis_commit`, and before-slice counters) alongside the canonical `evaluation_profile` so those read-only roles can reason from canonical state after compaction.

Deterministic verification now also persists a durable canonical artifact in `.agent/current/verification-evidence.json`. Fresh scaffolds create an idle placeholder, implementers update it for the selected slice or current HEAD, reminder/recovery/evaluation surfaces thread its path and summary, and the package-owned verifier entrypoints (`scripts/verify-completion-control-plane.js` and `scripts/verify-completion-stop.sh`), `bash scripts/canonical-evidence-artifact-test.sh`, `npm run release-check`, plus the thin `.agent/verify_completion_*.sh` forwarders all fail closed when that artifact is missing, stale, or out of parity with the selected slice or current HEAD.

The package ships internal helper subagents (`completion_assist`) beneath the allowed completion roles only. Helper prompts live in package-owned `helpers/`, the guarded helper-tools extension lives in `extensions/helper-tools/`, and release-check now wires the full helper regression suite (runtime capability, packaging smoke, authority boundary, artifact layout, runtime contract, role gating, structured output, observability) in fail-closed order.

Canonical reviewer/auditor/stop-judge transcription now fails closed on malformed rubric-bearing reports: the shared rubric heading plus all four rubric dimensions must be present, required role fields must remain intact, and reviewer/stop-judge yes/no verdicts cannot contradict rubric `fail` lines.

Evaluator calibration now also fails closed on semantically lenient but well-formed reports. `npm run evaluator-calibration-test` drives the packaged transcription path through reviewer yes-with-follow-up, auditor open-contracts-with-`Next mandatory slice: none`, and stop-judge yes-with-open-contracts fixtures while still accepting truthful passing reports. It also rejects the reproducible `none; ...` bypass family for reviewer follow-up, auditor worktree blockers, and stop-judge open-contract reporting, while still accepting the reviewer routing forms `Smallest follow-up slice: none; proceed to completion-auditor.`, `Smallest follow-up slice: none, proceed to completion-auditor.`, and `Smallest follow-up slice: none - proceed to auditor.` with terminal punctuation or whitespace only. The role runner now also does one targeted repair retry for the common reviewer yes-with-follow-up and auditor clean-with-blockers contradictions before surfacing a transcription warning, while the canonical transcription gate itself remains fail-closed. Both `npm run release-check` and the package-owned `scripts/verify-completion-stop.sh` entrypoint — including the thin `.agent/verify_completion_stop.sh` forwarder — include this calibration gate.

Deterministic active-slice contract regression now lives in `bash scripts/active-slice-contract-test.sh`, and `npm run release-check` pulls it into the packaged release gate before `npm pack --dry-run`.

Deterministic verification for this packaged contract also lives in `npm run rubric-contract-test`, which now exercises reviewer, auditor, and stop-judge transcription paths while the bootstrap/refocus/context regressions plus control-plane verifier fail closed when required canonical signaling is missing.

Active `/cook` workflows now also auto-reconcile routine unrelated tracked worktree dirt instead of bouncing that decision back to the user. When the dirty tracked files are outside the latest slice or current reconciliation surfaces and can be isolated safely, the workflow should preserve them with a reversible mechanism such as a named git stash plus a `.agent/current/tmp/dirty-worktree-autostash.json` note, continue the mandatory step on a clean worktree, and restore them before handing control back. Only overlapping changes, ownership ambiguity, or stash/restore conflicts should force a user-facing decision.

## Canonical files

This package stores canonical workflow state under:

```text
.agent/
  current/
    state.json
    startup-brief.json
    plan.json
    active-slice.json
    slice-history.jsonl
    stop-check-history.jsonl
    verification-evidence.json
    tmp/
  verify_completion_stop.sh          # local thin forwarder to the package-owned stop verifier
  verify_completion_control_plane.sh # local thin forwarder to the package-owned control-plane verifier
```

Canonical truth is the combination of:

- current repo truth, and
- canonical `.agent/**` state

### Tracked vs ignored files

Tracked repo-contract files:

- none — workflow policy comes from package defaults and workflow runtime stays local under `.agent/**`

The canonical storage contract is package-owned defaults plus ignored `.agent/**` runtime state. Runtime-generated `.agent/verify_completion_*.sh` forwarders are local convenience entrypoints only and are not tracked. When a workflow reaches a closed `done` or `cancelled` posture, extension cleanup may remove the entire `.agent/` directory as expected closeout behavior.

Ignored execution-state files:

- `.agent/current/state.json`
- `.agent/current/startup-brief.json`
- `.agent/current/plan.json`
- `.agent/current/active-slice.json`
- `.agent/current/slice-history.jsonl`
- `.agent/current/stop-check-history.jsonl`
- `state.json current_stop_wave_id` in `.agent/current/state.json` defines the current stop-wave epoch so the same HEAD can restart stop evaluation without requiring a synthetic tracked commit.
- `.agent/current/verification-evidence.json`
- `.agent/current/*.log`
- `.agent/current/tmp/`

In short:

- package defaults define the workflow policy
- ignored `.agent/**` files are the local control-plane state for the current run

## Package layout

- `extensions/completion/index.ts` — main extension implementation
- `extensions/helper-tools/index.ts` — explicit-load helper capability probe extension used by release-gated helper runtime checks
- `skills/completion-protocol/` — shared protocol documentation
- `agents/completion-*.md` — package-local completion role prompts
- `helpers/` — package-owned helper prompt assets published ahead of later helper-runtime slices
- `scripts/` — smoke, regression, and release checks

## Development

Run validation from the package root:

```bash
npm run verify-completion-control-plane
npm run verify-completion-stop
npm run smoke-test
npm run refocus-test
npm run context-proposal-test
bash scripts/canonical-evidence-artifact-test.sh
bash scripts/helper-runtime-capability-test.sh
bash scripts/helper-packaging-smoke-test.sh
npm run observability-status-test
npm run evaluator-calibration-test
npm run rubric-contract-test
npm run release-check
```

`npm run release-check` is the broad packaged-release verifier. It begins with `npm run verify-completion-control-plane`, then runs the helper runtime capability probe plus packed-artifact helper smoke so package-installed `pi -e ...` loading, the required helper CLI flag set, published helper assets, and JSON-mode progress/final-result capture fail closed before the broader suite continues. After that it asserts the shipped `/cook` public parity surfaces in `README.md`, `CHANGELOG.md`, and the `/cook` help/fail-closed copy in `extensions/completion/index.ts`, reruns the startup/refocus/context checks — including the critique-aware `/cook` confirmation regression and the smoke auto-resume prompt path — includes deterministic canonical evidence artifact coverage and includes deterministic active-slice contract coverage plus observability coverage, evaluator calibration, and the rubric-contract regression, and finishes with `npm pack --dry-run`.

The direct package-root verifier commands above intentionally self-isolate the repo-local extension when they shell back into `pi`, so you should not need to wrap them with `pi --no-extensions` even if `@linimin/pi-letscook` is also installed globally on the same machine.

## Release

See [PUBLISHING.md](https://github.com/linimin/pi-letscook/blob/main/PUBLISHING.md) for GitHub and npm release steps.

## Notes

- Canonical truth lives in repo-local `.agent/**` files.
- The main Pi session is the workflow driver.
- Package-local role prompts are loaded directly by the extension and do not depend on `~/.pi/agent/agents`.
- Reviewer, auditor, and stop-judge are enforced as read-only roles.
- Reviewer, auditor, and stop-judge share the packaged rubric dimensions `Contract coverage`, `Correctness risk`, `Verification evidence`, and `Docs/state parity` with `pass|concern|fail` verdicts.
