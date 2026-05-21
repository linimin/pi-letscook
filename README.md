# @linimin/pi-letscook

`/cook` is optional workflow mode for turning main-chat discussion about concrete repo changes into a resumable repo workflow stored in repo-local `.agent/**` state.

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
4. When you want workflow mode, run `/cook`.
5. Review the startup brief and choose **Start** or **Cancel**.
6. Later, run `/cook` again to resume from canonical state or confirm a primary-agent-authored replacement or next-round handoff.

```text
/cook
```

## Common actions

| If you want to... | Do this |
|---|---|
| Implement directly without workflow | Ask in ordinary chat and let the agent modify the repo directly |
| Start a tracked workflow | Ask the primary agent in ordinary chat to prepare the explicit `/cook` handoff, then run `/cook` |
| Continue the current workflow | Run `/cook` |
| Refocus or start the next round | Ask the primary agent in ordinary chat to prepare the fresh explicit `/cook` handoff for the new slice, then run `/cook` |

## What `/cook` expects

- a fresh explicit primary-agent `cook_handoff` capsule for any new-workflow, next-round, or replacement startup
- a mission and first slice concrete enough for the primary agent to author the startup handoff directly
- acceptance and verification intent that can support a truthful first workflow round
- README/CHANGELOG updates still count as concrete repo changes
- assistant-produced summaries and plan/spec/design-doc/proposal-only artifacts still do not count unless the primary agent turns them into an explicit `cook_handoff` capsule
- `/cook` does not synthesize startup from recent discussion when handoff data is missing; the primary agent must provide the handoff

If no fresh explicit primary-agent handoff exists, `/cook` fails closed, leaves canonical `.agent/**` state unchanged, and tells you to ask the primary agent in the main chat to emit a fresh `cook_handoff` capsule before rerunning `/cook`.

If a fresh explicit handoff exists but is still workflow-worthy rather than implementation-startable, `/cook` also fails closed instead of silently treating that capsule as planning support or canonical workflow state.

If you pass inline arguments to `/cook`, it also fails closed and tells you to move that intent into the main chat before rerunning bare `/cook`.

## Workflow entry

Only explicit `/cook` enters workflow mode. Ordinary prompts stay in the main chat and go straight to the primary agent.

Ordinary chat can still directly implement repo changes. `/cook` is for the cases where you want workflow control rather than just implementation help, and the primary agent should prepare the handoff before you run it.

When you explicitly run `/cook`, it should consume the explicit primary-agent handoff you already prepared in ordinary chat, then ask you to **Start** or **Cancel** before rewriting canonical workflow state.

Explicit `/cook` capsules are the required startup intake for new-workflow, next-round, and replacement entry.

Important behavior:
- `/cook` is an optional workflow boundary and manual entry point
- startup and next-round entry stay confirm-first, but they start from explicit primary-agent handoff data rather than recent-discussion guessing
- active workflows resume from canonical `.agent/**` state unless a fresh explicit primary-agent handoff proposes a concrete replacement mission
- explicit slash commands other than `/cook` continue normally in the main chat
- ordinary main-chat discussion may clarify, propose, or directly implement repo changes without entering workflow mode

## Typical examples

Start a new workflow from recent main-chat discussion:

```text
I want to add login redirect handling and tests.
# discuss/refine in main chat
/cook
```

## What happens when you run `/cook`

`/cook` first checks for a fresh explicit primary-agent handoff capsule. New-workflow entry, done-workflow next-round entry, and active-workflow replacement should use that handoff instead of guessing from recent discussion. If no fresh explicit handoff exists, `/cook` fails closed for startup/refocus and resumes canonical state only when continuing the existing workflow. None of this prevents ordinary-chat implementation when you choose not to enter workflow mode.

| Repo state | What you'll see |
|---|---|
| No workflow yet | `/cook` consumes a fresh explicit primary-agent handoff and asks you to choose **Start** or **Cancel**. Missing, stale, planning-only, or non-startable handoffs fail closed. |
| Active workflow exists | Usually a resume of the current workflow from canonical `.agent/**` state. If a fresh explicit primary-agent handoff points to a different concrete replacement mission, `/cook` shows a chooser first and only rewrites canonical state after you confirm the replacement. Ambiguous or missing replacement handoff stays conservative. |
| Previous workflow is `done` | `/cook` can start the next implementation round only from a fresh explicit primary-agent handoff behind **Start** or **Cancel**. Missing, weak, or planning-only next-round handoffs fail closed. |

## Confirmation and fail-closed behavior

`/cook` never silently starts or rewrites canonical `.agent/**` state on unclear input.

- startup, next-round, and refocus proposals are approval-only
- actions are **Start** and **Cancel**
- **Cancel** is side-effect free: discuss changes in the main chat and rerun `/cook`
- weak, ambiguous, stale, invalid, assistant-produced, or planning-only intake does not start a workflow
- when a concrete replacement mission suggests replacing an active workflow, `/cook` shows a chooser before any canonical state rewrite

When you accept startup or refocus, `/cook` persists the chosen workflow state in canonical `.agent/**` files before the re-ground round begins.

The confirmed startup brief is also preserved there as advisory intake for later re-grounding. It does not replace `.agent/plan.json` or `.agent/active-slice.json`, which remain under regrounder authority.

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

Those identifiers are persisted in `.agent/profile.json`, `.agent/state.json`, `.agent/plan.json`, and `.agent/active-slice.json`, then surfaced in kickoff/reminder/resume text and reviewer/auditor/stop-judge evaluation handoffs so downstream roles can rely on canonical signaling instead of prose inference alone.

The active-slice exact implementer handoff is now the canonical implementation contract for selected, in-progress, committed, and done slices. In addition to the locked slice goal, acceptance criteria, contract IDs, blocked-on list, `priority`, and `why_now`, the v2 contract requires:

- `implementation_surfaces` — the repo surfaces expected to change or stay in parity for the slice
- `verification_commands` — the focused and broader deterministic checks the implementer is expected to run before committing
- `locked_notes` / `must_fix_findings` — canonical scope locks plus review follow-up obligations for the current slice
- `basis_commit` — the clean HEAD the slice was selected against
- `remaining_contract_ids_before` plus `release_blocker_count_before` / `high_value_gap_count_before` — the locked before-slice counters the implementer must preserve in reports and later handoffs

The selected plan slice must mirror that exact contract across goal, contract IDs, acceptance criteria, blocked-on state, `priority` / `why_now`, `implementation_surfaces`, `verification_commands`, locked notes, must-fix findings, `basis_commit`, and the before-slice counters. `.agent/verify_completion_control_plane.sh` plus the reminder/compaction-resume surfaces now fail closed on that drift instead of only checking slice-id presence, so implementers can recover from canonical state rather than prose-only summaries.

Reviewer, auditor, and stop-judge dispatch/reminder surfaces now also thread the current active-slice implementation contract (`implementation_surfaces`, `verification_commands`, locked notes, must-fix findings, `basis_commit`, and before-slice counters) alongside the canonical `evaluation_profile` so those read-only roles can reason from canonical state after compaction.

Deterministic verification now also persists a durable canonical artifact in `.agent/verification-evidence.json`. Fresh scaffolds create an idle placeholder, implementers update it for the selected slice or current HEAD, reminder/recovery/evaluation surfaces thread its path and summary, and `.agent/verify_completion_control_plane.sh`, `bash scripts/canonical-evidence-artifact-test.sh`, `npm run release-check`, and `bash .agent/verify_completion_stop.sh` fail closed when that artifact is missing, stale, or out of parity with the selected slice or current HEAD.

Canonical reviewer/auditor/stop-judge transcription now fails closed on malformed rubric-bearing reports: the shared rubric heading plus all four rubric dimensions must be present, required role fields must remain intact, and reviewer/stop-judge yes/no verdicts cannot contradict rubric `fail` lines.

Evaluator calibration now also fails closed on semantically lenient but well-formed reports. `npm run evaluator-calibration-test` drives the packaged transcription path through reviewer yes-with-follow-up, auditor open-contracts-with-`Next mandatory slice: none`, and stop-judge yes-with-open-contracts fixtures while still accepting truthful passing reports. It also rejects the reproducible `none; ...` bypass family for reviewer follow-up, auditor worktree blockers, and stop-judge open-contract reporting, while still accepting only the exact reviewer routing text `Smallest follow-up slice: none; proceed to completion-auditor.` with terminal punctuation or whitespace only. Both `npm run release-check` and `bash .agent/verify_completion_stop.sh` include this calibration gate.

Deterministic active-slice contract regression now lives in `bash scripts/active-slice-contract-test.sh`, and `npm run release-check` pulls it into the packaged release gate before `npm pack --dry-run`.

Deterministic verification for this packaged contract also lives in `npm run rubric-contract-test`, which now exercises reviewer, auditor, and stop-judge transcription paths while the bootstrap/refocus/context regressions plus control-plane verifier fail closed when required canonical signaling is missing.

## Canonical files

This package stores canonical workflow state under:

```text
.agent/
  README.md
  mission.md
  profile.json
  verify_completion_stop.sh
  verify_completion_control_plane.sh
  state.json
  plan.json
  active-slice.json
  slice-history.jsonl
  stop-check-history.jsonl
  verification-evidence.json
  tmp/
```

Canonical truth is the combination of:

- current repo truth, and
- canonical `.agent/**` state

### Tracked vs ignored files

Tracked repo-contract files:

- `.agent/README.md`
- `.agent/mission.md`
- `.agent/profile.json`
- `.agent/verify_completion_stop.sh`
- `.agent/verify_completion_control_plane.sh`

Ignored execution-state files:

- `.agent/state.json`
- `.agent/plan.json`
- `.agent/active-slice.json`
- `.agent/slice-history.jsonl`
- `.agent/stop-check-history.jsonl`
- `.agent/verification-evidence.json`
- `.agent/*.log`
- `.agent/tmp/`

In short:

- tracked `.agent` files define the repo-level workflow contract
- ignored `.agent` files are the local control-plane state for the current run

## Package layout

- `extensions/completion/index.ts` — main extension implementation
- `skills/completion-protocol/` — shared protocol documentation
- `agents/completion-*.md` — package-local completion role prompts
- `scripts/` — smoke, regression, and release checks

## Development

Run validation from the package root:

```bash
npm run smoke-test
npm run refocus-test
npm run context-proposal-test
bash scripts/canonical-evidence-artifact-test.sh
npm run observability-status-test
npm run evaluator-calibration-test
npm run rubric-contract-test
npm run release-check
```

`npm run release-check` is the broad packaged-release verifier. It begins with `bash .agent/verify_completion_control_plane.sh`, so missing or stale `.agent/verification-evidence.json` parity fails closed before the broader suite runs, then asserts the shipped `/cook` public parity surfaces in `README.md`, `CHANGELOG.md`, and the `/cook` help/fail-closed copy in `extensions/completion/index.ts`, reruns the startup/refocus/context checks — including the critique-aware `/cook` confirmation regression and the smoke auto-resume prompt path — includes deterministic canonical evidence artifact coverage and includes deterministic active-slice contract coverage plus observability coverage, evaluator calibration, and the rubric-contract regression, and finishes with `npm pack --dry-run`.

The direct package-root verifier commands above intentionally self-isolate the repo-local extension when they shell back into `pi`, so you should not need to wrap them with `pi --no-extensions` even if `@linimin/pi-letscook` is also installed globally on the same machine.

## Release

See [PUBLISHING.md](https://github.com/linimin/pi-letscook/blob/main/PUBLISHING.md) for GitHub and npm release steps.

## Notes

- Canonical truth lives in repo-local `.agent/**` files.
- The main Pi session is the workflow driver.
- Package-local role prompts are loaded directly by the extension and do not depend on `~/.pi/agent/agents`.
- Reviewer, auditor, and stop-judge are enforced as read-only roles.
- Reviewer, auditor, and stop-judge share the packaged rubric dimensions `Contract coverage`, `Correctness risk`, `Verification evidence`, and `Docs/state parity` with `pass|concern|fail` verdicts.
