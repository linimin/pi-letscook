# Completion Protocol Notes

This document captures maintainer-facing protocol details and release-parity assertions for `@linimin/pi-letscook`. It is mainly useful if you maintain the extension, inspect canonical `.agent/**` state, or work on the packaged completion protocol itself.

## Public `/cook` Contract

You can still implement directly in ordinary chat when you do not need workflow state.

When you explicitly run `/cook`, it calls a same-entry primary-agent handoff synthesis step from the current task context or inline `/cook` prompt, then asks you to **Start** or **Cancel** before rewriting canonical workflow state.

If no primary-agent-generated handoff is startable, `/cook` fails closed before showing **Start** or **Cancel**.

Preview `/cook` capsules in ordinary chat may still help the conversation, but `/cook` does not consume them directly. It always synthesizes the startup handoff for the current workflow entry and fails closed when synthesis cannot produce a startable brief.

`/cook <prompt>` lets you provide explicit startup intent inline without bypassing synthesis or confirmation.

`/cook import` reads a `cook_handoff` JSON file (default: `.agent/tmp/cursor-handoff.json`) for Cursor IDE → Pi handoff. See `docs/CURSOR_HANDOFF.md`.

startup and next-round entry stay confirm-first, following same-entry primary-agent handoff synthesis -> fail closed.

Only explicit `/cook` enters workflow mode. In ordinary chat, do not load or follow `completion-protocol`, and do not call `completion_role`.

`/cook park` is available anytime an active workflow exists, including while `continuation_policy = continue`. It records a parked paused posture for ordinary direct edits with `requires_reground = true`. Stopped workflows also expose explicit same-session controls: rerun `/cook` or `/cook resume` to continue, and `/cook cancel` to close the workflow.

When a workflow reaches a closed `done` or `cancelled` posture, extension cleanup may remove the entire `.agent/` directory as expected closeout behavior.

`task_type` and `evaluation_profile` only come from explicit structured startup artifacts when those fields are present; otherwise `/cook` keeps the packaged `completion-workflow` / `completion-rubric-v1` defaults instead of inferring them from free-text discussion.

The confirmed startup brief may carry optional verifier-posture fields such as `recommended_first_slice_kind`. When deterministic verifier readiness is missing, regrounding should usually prefer a `verifier_scaffolding` first slice before broader product work.

routine internal re-grounding is not a stopped state by itself: when canonical reconciliation can continue safely, `requires_reground = true` stays under `continuation_policy = continue` and the driver auto-dispatches `completion-regrounder`.

Treat `.agent/current/startup-brief.json` as canonical startup intake, not the canonical slice plan. `completion-regrounder` still authors slices in `.agent/current/plan.json` from repo truth after Start.

While `continuation_policy == continue`, active workflows stay sticky: the driver keeps dispatching mandatory completion roles until canonical state becomes `await_user_input`, `blocked`, `paused`, or `done`.

## Structured Evaluation Rubrics

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

Reviewer, auditor, and stop-judge dispatch/reminder surfaces now thread canonical `evaluation_profile` plus direct-read pointers for the active-slice implementation contract and verification evidence so those read-only roles can recover from canonical state after compaction without depending on prose-only summaries.

Deterministic verification now also persists a durable canonical artifact in `.agent/current/verification-evidence.json`. Fresh scaffolds create an idle placeholder, implementers update it for the selected slice or current HEAD, reminder/recovery/evaluation surfaces thread its path and summary, and the package-owned verifier entrypoints (`scripts/verify-completion-control-plane.js` and `scripts/verify-completion-stop.sh`), `bash scripts/canonical-evidence-artifact-test.sh`, `npm run release-check`, plus the thin `.agent/verify_completion_*.sh` forwarders all fail closed when that artifact is missing, stale, or out of parity with the selected slice or current HEAD. The artifact stays additive and legacy-tolerant: `summary` remains the prose fallback, but structured records should also carry `evidence_quality`, `command_results`, `acceptance_coverage`, `flake_signals`, `open_gaps`, `basis_regression_required`, `basis_regression_status`, `basis_regression_reason`, and `basis_regression_artifact_paths`. Reminder/recovery/evaluation surfaces now summarize those fields concisely from the artifact path instead of dumping raw command output, and control-plane verification validates the structured shape plus repo-relative artifact-path safety when the additive fields are present.

Selective basis regression now lives in `bash scripts/run-basis-regression-check.sh`. For eligible bugfix or regression slices, point it at the locked `basis_commit` plus a verification command that already passes on current HEAD. It reruns that command in a disposable temp worktree at the basis commit and records `failed_on_basis` when the basis fails, `passed_on_basis` when the basis also passes, `not_run` when the negative-control check is intentionally skipped or cannot be executed truthfully, and `not_applicable` when the slice is not an eligible regression/bugfix. Record `basis_regression_required` plus a truthful `basis_regression_reason` instead of treating `not_run` or `not_applicable` as implicit passes.

The package ships internal helper subagents (`completion_assist`) beneath the allowed completion roles only. Helper prompts live in package-owned `helpers/`, the guarded helper-tools extension lives in `extensions/helper-tools/`, and release-check now wires the full helper regression suite (runtime capability, packaging smoke, authority boundary, artifact layout, runtime contract, role gating, structured output, observability) in fail-closed order. The release gate also covers the dedicated subprocess structured-output wiring used by the role runner.

Canonical reviewer/auditor/stop-judge transcription now fails closed on malformed rubric-bearing reports: the shared rubric heading plus all four rubric dimensions must be present, required role fields must remain intact, and reviewer/stop-judge yes/no verdicts cannot contradict rubric `fail` lines.

Evaluator calibration now also fails closed on semantically lenient but well-formed reports. `npm run evaluator-calibration-test` drives the packaged transcription path through reviewer yes-with-follow-up, auditor open-contracts-with-`Next mandatory slice: none`, and stop-judge yes-with-open-contracts fixtures while still accepting truthful passing reports. It also rejects the reproducible `none; ...` bypass family for reviewer follow-up, auditor worktree blockers, and stop-judge open-contract reporting, while still accepting the reviewer routing forms `Smallest follow-up slice: none; proceed to completion-auditor.`, `Smallest follow-up slice: none, proceed to completion-auditor.`, and `Smallest follow-up slice: none - proceed to auditor.` with terminal punctuation or whitespace only. The role runner now also does one targeted repair retry for the common reviewer yes-with-follow-up and auditor clean-with-blockers contradictions before surfacing a transcription warning, while the canonical transcription gate itself remains fail-closed. Both `npm run release-check` and the package-owned `scripts/verify-completion-stop.sh` entrypoint — including the thin `.agent/verify_completion_stop.sh` forwarder — include this calibration gate.

Deterministic active-slice contract regression now lives in `bash scripts/active-slice-contract-test.sh`, and `npm run release-check` pulls it into the packaged release gate before `npm pack --dry-run`.

Deterministic verification for this packaged contract also lives in `npm run rubric-contract-test`, which now exercises reviewer, auditor, and stop-judge transcription paths while the bootstrap/refocus/context regressions plus control-plane verifier fail closed when required canonical signaling is missing.

Active `/cook` workflows now also auto-reconcile routine unrelated tracked worktree dirt instead of bouncing that decision back to the user. When the dirty tracked files are outside the latest slice or current reconciliation surfaces and can be isolated safely, the workflow should preserve them with a reversible mechanism such as a named git stash plus a `.agent/current/tmp/dirty-worktree-autostash.json` note, continue the mandatory step on a clean worktree, and restore them before handing control back. Only overlapping changes, ownership ambiguity, or stash/restore conflicts should force a user-facing decision.

## Optional Cursor role backends

When `PI_COMPLETION_CURSOR_ENABLED=1`, completion roles may execute through Cursor instead of Pi subprocesses while the Pi driver and `.agent/**` control plane stay unchanged. Default mapping: implementer via `@cursor/sdk`, reviewer/auditor/stop-judge via Cursor CLI `--mode=ask`, regrounder/bootstrapper/helpers remain on Pi. See `docs/CURSOR_BACKEND.md`.

For Cursor-backed roles only, `resolveRoleSubprocessOutput` falls back to fixed text report parsing when structured emit tool events are absent, so Cursor eval roles can still pass canonical transcription when reports match the packaged rubric format. Pi subprocess roles do not use this fallback.

## Canonical Files

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

### Tracked vs Ignored Files

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

## Release Verification

Run validation from the package root:

```bash
npm run verify-completion-control-plane
npm run verify-completion-stop
npm run release-check
```

`npm run release-check` is the broad packaged-release verifier. It begins with `npm run verify-completion-control-plane`, then runs the helper runtime capability probe plus packed-artifact helper smoke so package-installed `pi -e ...` loading, the required helper CLI flag set, published helper assets, and JSON-mode progress/final-result capture fail closed before the broader suite continues. After that it asserts the shipped `/cook` public parity surfaces in `docs/PROTOCOL.md`, `CHANGELOG.md`, and the `/cook` help/fail-closed copy in `extensions/completion/index.ts`, reruns the startup/refocus/context/worktree-root checks — including the critique-aware `/cook` confirmation regression and the smoke auto-resume prompt path — includes prompt-budget coverage, agent-end auto-resume delivery coverage, basis-regression proof, deterministic canonical evidence artifact coverage, and includes deterministic active-slice contract coverage plus observability coverage, evaluator calibration, and the rubric-contract regression. It also covers completion-role gating, dirty-worktree policy, stop-wave epoch, legacy cleanup, structured-report repair coverage, and finishes with `npm pack --dry-run`.

