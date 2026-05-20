# @linimin/pi-letscook

`/cook` turns main-chat discussion about concrete repo changes into a resumable repo workflow stored in repo-local `.agent/**` state.

`/cook` is the explicit workflow boundary for starting, continuing, refocusing, or beginning the next round of long-running repo work.

## Use it when

- work spans multiple sessions
- you want one mission tracked in repo state instead of chat memory
- you want clear continue / refocus / next-round behavior
- you want review, audit, and verification tied to the repo

## Skip it when

- you only need a one-off answer
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
3. In the main chat, describe the concrete repo change you want and let the primary agent hand you off to `/cook` when the first slice is ready.
4. Run `/cook`.
5. Review the startup brief and choose **Start** or **Cancel**.
6. Later, run `/cook` again to resume from canonical state or confirm an explicit replacement or next-round handoff.

```text
/cook
```

## Common actions

| If you want to... | Do this |
|---|---|
| Start a long-running task | Discuss the concrete repo change in the main chat, wait for a fresh primary-agent handoff, then run `/cook` |
| Continue the current workflow | Run `/cook` |
| Refocus or start the next round | Discuss the new concrete repo change in the main chat, wait for a fresh primary-agent handoff, then run `/cook` |

## What `/cook` expects

- a fresh valid explicit primary-agent `/cook` handoff capsule from the immediately preceding ordinary-chat turn whenever `/cook` is starting a new workflow or the next round after a completed workflow
- for that handoff capsule to start workflow immediately, it must already be implementation-startable: a bounded `first_slice_goal`, repo-change-oriented acceptance, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first`
- enough detail in the main chat for the primary agent to form that bounded handoff capsule before you run `/cook`
- README/CHANGELOG updates still count as concrete repo changes
- assistant-produced summaries and plan/spec/design-doc/proposal-only artifacts still do not count unless they include the explicit structured `/cook` handoff capsule
- recent main-chat discussion can still validate or supplement an accepted explicit handoff, but it no longer starts a new workflow by itself

If no fresh valid handoff exists for new-workflow or next-round entry, `/cook` fails closed, leaves canonical `.agent/**` state unchanged, and tells you to get an explicit primary-agent handoff in the main chat before rerunning `/cook`.

If a fresh explicit handoff exists but is still workflow-worthy rather than implementation-startable, `/cook` also fails closed instead of silently treating that capsule as planning support or canonical workflow state.

If you pass inline arguments to `/cook`, it also fails closed and tells you to move that intent into the main chat before rerunning bare `/cook`.

## Workflow entry

Only explicit `/cook` enters the workflow. Ordinary prompts stay in the main chat and go straight to the primary agent.

If a task has clearly matured into completion-workflow scope, the primary agent should hand you off to `/cook` instead of starting long-running implementation directly in ordinary chat.

That handoff should include an explicit structured `/cook` capsule in the assistant reply so `/cook` can confirm the already-formed mission instead of re-deriving it from broad ambient context.

The capsule is still advisory startup intake, not canonical workflow state, and new-workflow or next-round entry only proceeds when it already names the first bounded slice, repo-change-oriented acceptance, implementation surfaces, and verification commands.

Important behavior:
- `/cook` is the canonical workflow boundary and manual entry point
- startup and next-round entry stay confirm-first and require a fresh valid explicit primary-agent handoff
- active workflows resume from canonical `.agent/**` state unless a fresh valid explicit handoff proposes a replacement
- explicit slash commands other than `/cook` continue normally in the main chat
- ordinary main-chat discussion may clarify or propose, but mature long-running implementation should be handed off to `/cook`

## Typical examples

Start a new workflow after a fresh primary-agent handoff:

```text
I want to add login redirect handling and tests.
# let the primary agent hand you off to /cook
/cook
```

## What happens when you run `/cook`

`/cook` first looks for a fresh explicit primary-agent handoff capsule. New-workflow entry and done-workflow next-round entry start only when that capsule is fresh, valid, and implementation-startable; otherwise `/cook` fails closed instead of deriving startup from recent discussion. When a workflow is already active and no fresh valid explicit handoff is present, `/cook` resumes from canonical `.agent/**` state instead of deriving replacement startup from recent discussion.

| Repo state | What you'll see |
|---|---|
| No workflow yet | If a fresh explicit handoff capsule exists and is implementation-startable, you get a startup brief built from that handoff and choose **Start** or **Cancel**. Otherwise `/cook` fails closed, leaves canonical state unchanged, and tells you to get a fresh explicit primary-agent handoff. Weak, unreliable, stale, planning-only, or non-startable explicit-handoff intake also fails closed. |
| Active workflow exists | Usually a resume of the current workflow from canonical `.agent/**` state. If a fresh explicit handoff capsule points to a different concrete repo change, `/cook` shows a chooser first and only rewrites canonical state after you confirm the replacement. Ambiguous intake stays conservative. |
| Previous workflow is `done` | A fresh explicit handoff capsule can still start the next implementation round behind **Start** or **Cancel**. Without one, `/cook` fails closed instead of deriving the next round from recent discussion. |

## Confirmation and fail-closed behavior

`/cook` never silently starts or rewrites canonical `.agent/**` state on unclear input.

- startup, next-round, and refocus proposals are approval-only
- actions are **Start** and **Cancel**
- **Cancel** is side-effect free: discuss changes in the main chat and rerun `/cook`
- weak, ambiguous, stale, invalid, assistant-produced, or planning-only intake does not start a workflow
- when a fresh explicit handoff suggests replacing an active workflow, `/cook` shows a chooser before any canonical state rewrite

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
