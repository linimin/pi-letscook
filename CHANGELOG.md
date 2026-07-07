# Changelog

## Unreleased

### Added

- added cook-handoff MCP (`mcp/cook-handoff/`) with worktree-first flow: `ensure_cook_worktree`, prepare/preview/start tools, and chat monitoring via `get_cook_workflow_status` / `poll_cook_workflow_updates`
- added `cursor-handoff-service.ts`, plain `/cook` auto-detect for pending `.agent/tmp/cursor-handoff.json`, and `PI_COMPLETION_CURSOR_HANDOFF_CONFIRMED` to skip duplicate Pi confirm after Cursor Start
- added `cursor/skills/cursor-handoff-monitor`, `docs/CURSOR_HANDOFF_MCP.md`, and handoff regression scripts wired into `cursor-release-check`
- added optional Cursor role backends: Pi driver unchanged; `completion-implementer` can run via `@cursor/sdk`, evaluator roles via Cursor CLI `--mode=ask` when `PI_COMPLETION_CURSOR_ENABLED=1`
- added `RoleRunnerBackend` spawn abstraction in `role-runner-backend.ts` with `PI_COMPLETION_TEST_ROLE_SPAWN_RESULT_JSON` fixture support
- added Cursor desktop handoff via `/cook import` and `.agent/tmp/cursor-handoff.json`, plus companion `cursor/skills/cursor-handoff` and `cursor/commands/prepare-cook-handoff.md`
- added `docs/CURSOR_BACKEND.md` and `docs/CURSOR_HANDOFF.md`

### Fixed

- hardened cook-handoff MCP: require `workspace_root`, bind confirmation to `handoff_sha256`, honest agent-terminal launch (`launch_required`), optional verified background spawn, cancel clears pending state, stricter stale-handoff TTL, workflow event sync for monitoring deltas, `awaiting_terminal_launch` sidecar status, idempotent start guards, legacy file-only auto-detect, dry-run without sidecar mutation, plain `/cook` and inline `/cook <prompt>` fail-closed after MCP start, stale handoff fail-closed, deferred monitoring until workflow exists, preview integrity checks, spawn-failure sidecar recovery, and stale kickoff_started recovery
- added prompt/protocol/docs/test parity for the auto-reground continuation rule so the workflow driver no longer implies that every re-ground must stop for a manual `/cook resume`
- made `/cook park` available anytime an active workflow exists, including while `continuation_policy = continue`, so users can unlock ordinary direct edits without waiting for a stopped posture; resume still routes through canonical reground
- suppressed stale queued `COMPLETION WORKFLOW DRIVER` follow-ups after `/cook park` by requiring authoritative driver-prompt metadata and swallowing extension follow-ups that no longer match canonical state
- made `/cook cancel` supersede queued driver-prompt metadata and clear the in-memory continuation tracker so exact pre-cancel follow-ups cannot stay authoritative

## 0.1.91

### Added
- landed helper-v1-pr3-release-parity: wired full helper regression suite (role-gating, authority-boundary, structured-output, observability, artifact-layout, runtime-contract, capability, packaging) into fail-closed `scripts/release-check.sh`; aligned README, CHANGELOG, PUBLISHING.md and skills/completion-protocol/** with internal non-authoritative `completion_assist` posture beneath `/cook`

### Added

- added a PR0 helper capability gate with a dormant explicit-load `extensions/helper-tools/` probe extension, published `helpers/scout.md` / `helpers/critic.md` assets, and fail-closed `scripts/helper-runtime-capability-test.sh` / `scripts/helper-packaging-smoke-test.sh` coverage for packaged `pi -e ...` loading, required helper CLI flags, and JSON-mode progress/final-result capture
- wired the helper capability and packaging probes into `npm run release-check`, `package.json`, README, and PUBLISHING guidance so helper rollout stays blocked until package-installed runtime assumptions are proven on the supported Pi CLI

### Fixed

- removed fresh explicit `cook_handoff` capsule precedence from `/cook` startup so every workflow entry now synthesizes a fresh primary-agent handoff from current context or inline prompt instead of directly consuming earlier preview capsules
- removed the remaining startup-analysis fallback from `/cook`, so workflow entry now succeeds only when same-entry primary-agent handoff synthesis produces a startable startup brief and otherwise fails closed
- removed the remaining main-path `/cook` free-text `task_type` / `evaluation_profile` inference so startup and refocus now keep the packaged `completion-workflow` / `completion-rubric-v1` defaults unless an explicit structured artifact supplies routing fields
- tightened same-entry explicit-handoff startup synthesis so only explicit handoffs that still need startup tightening can be replaced by synthesized structured output, removing generic semantic mission matching while preserving explicit-precedence for already-complete handoffs
- added live startup-analysis prompt parity plus planning-only and `not_repo_change` fail-closed regression coverage so heuristic cleanup cannot silently reintroduce discussion-derived routing hints, reopen non-repo-change startup paths, or drift public contract text
- aligned `/cook` startup docs/help plus smoke/release parity checks with the shipped same-entry handoff-synthesis -> fail-closed contract so public contract text matches startup behavior

## 0.1.89

### Fixed

- added explicit stopped-workflow `/cook resume`, `/cook park`, and `/cook cancel` controls so blocked, await-user-input, and paused workflows no longer strand the primary agent in a same-repo dead zone
- split completion-workflow hard locks from mere workflow presence so stopped workflows stay locked until Park or Cancel is recorded canonically, while `continuation_policy == continue` keeps the existing hard-lock and auto-resume behavior
- made `/cook park` clear stale active-slice handoff state, reset canonical selected-slice verification evidence, and force `requires_reground = true` before any later parked-workflow continuation
- made `/cook cancel` close stopped workflows cleanly so stale hard locks and auto-resume do not survive ordinary-chat continuation in the repo
- bounded completion-state discovery to the current Git worktree root so nested worktrees no longer inherit an ancestor checkout's `.agent/current/state.json`
- tightened the `process.cwd()` fallback so completion-state discovery only consults it within the same Git checkout, preventing parent-process cwd from leaking ancestor `.agent` state into child worktree sessions
- added a worktree-root-boundary regression and wired it into `npm run release-check`, while also fixing the affected local test harness wrappers and the refocus bootstrap readiness typo uncovered during validation

## 0.1.88

### Fixed

- clarified across the workflow driver prompt, completion protocol docs, and role prompts that repo-local `.agent/verify_completion_*.sh` forwarders are local helper entrypoints rather than tracked repo-contract files
- taught the workflow driver to treat `.agent/` removal after canonical `done` or `cancelled` closeout as expected cleanup instead of narrating it as a control-plane anomaly or recreating helper forwarders just to summarize completion
- added release-check parity coverage for the new closeout-cleanup wording so stale `tracked contract file` language and false anomaly framing fail closed

## 0.1.87

### Fixed

- queued completion-driver prompts with `deliverAs: "followUp"` so `agent_end` auto-resume no longer throws Pi's `Agent is already processing` runtime error when the workflow driver requeues itself during session teardown
- added a dedicated `agent-end-auto-resume-test` regression that exercises the real `agent_end -> autoContinueWorkflowIfNeeded()` path and asserts the extension-injected resume prompt arrives with `streamingBehavior: followUp`
- wired the new regression into `npm run release-check` so future driver changes cannot silently drop safe auto-resume queueing again

## 0.1.86

### Fixed

- made closed-workflow cleanup probe-first by reading `.agent/current/state.json` directly for explicit terminal `done`/`cancelled` signals instead of requiring a full `loadCompletionSnapshot()` success before deleting `.agent/`
- ran immediate closed-workflow cleanup after `completion_role` returns and before ordinary-chat workflow-context injection so finished workflows stop leaving residue that can prompt stray continuation attempts
- added regression coverage for incomplete-snapshot closed cleanup, post-close ordinary-chat boundary suppression, and immediate post-role cleanup ordering so the reported stale-regrounder residue path stays fixed

## 0.1.85

### Fixed

- changed completed-workflow cleanup to remove the entire `.agent/` directory instead of leaving root helper scripts, tombstones, or other closed-workflow artifacts behind
- preserved fresh `/cook` restart and ordinary post-close routing after full `.agent/` removal, including normal non-role verification paths
- hardened release verification so full `.agent/` cleanup coverage, stale-evidence fail-closed checks, and release-check recursion handling stay terminating and truthful

## 0.1.84

### Changed

- shifted `/cook` startup from an implementation-ready first-slice gate toward a workflow-startable startup brief so explicit workflow entry now preserves mission-level intent even when first-slice details remain advisory
- turned weak fresh explicit `cook_handoff` capsules into startup input instead of automatic blockers by letting same-entry primary-agent synthesis tighten acceptance and initial-slice hints before workflow confirmation
- started persisting structured startup hint fields (`first_slice_goal_hint`, `first_slice_non_goals_hint`, `implementation_surfaces_hint`, `verification_commands_hint`, `why_this_slice_first_hint`) in canonical startup intake while keeping `completion-regrounder` authoritative for canonical slice planning
- updated startup confirmation copy, regrounder/protocol guidance, and regression coverage so startup hints are treated as advisory until regrounding authors the canonical slices
- made `.agent/current/startup-brief.json` the canonical startup-intake source for new workflow state, kept legacy `state.json advisory_startup_brief` only as a migration input, and taught snapshot loading to rebuild missing startup-brief files from older runtime state
- started recording queued driver-prompt metadata under `.agent/current/tmp/driver-prompt.json` so workflow attach and resume can lean on canonical prompt/session fingerprints instead of raw prompt-shape detection alone

## 0.1.79

### Fixed

- tightened the packaged `completion-reviewer` and `completion-auditor` prompt contracts with explicit consistency invariants, positive/negative examples, and final self-check reminders so contradictory structured verdict fields are less likely to drift into role output
- added a one-shot structured-report repair retry for the common reviewer yes-with-follow-up and auditor clean-with-blockers contradictions before surfacing a completion transcription warning, while keeping canonical transcription itself fail-closed for other malformed reports
- added deterministic `report-repair-test` coverage and wired it into `npm run release-check` so future refactors cannot silently drop the targeted repair path or the stricter prompt guidance

## 0.1.78

### Changed

- restored optional inline `/cook <prompt>` entry so users can provide explicit startup intent without first restating it in ordinary chat, while still requiring same-entry primary-agent startup synthesis plus Start/Cancel confirmation before canonical state is rewritten
- taught active-workflow replacement and done-workflow next-round startup to accept inline `/cook` prompt intent instead of failing closed on inline arguments, and aligned smoke/refocus/context regressions with that contract
- updated README/help text so `/cook` now documents optional inline prompt intent as part of the supported workflow entry surface

## 0.1.77

### Fixed

- introduced `current_stop_wave_id` / `stop_wave_id` stop-wave epochs so the same HEAD can restart stop evaluation after stale no-stop history without requiring a synthetic tracked commit
- taught stop-judge transcription, verifier policy, protocol docs, and release regression coverage to scope stop-wave aggregation to the active epoch instead of permanently poisoning a HEAD on the first `can_stop=no`

## 0.1.76

### Fixed

- taught the completion protocol and core role prompts to auto-preserve routine unrelated tracked worktree dirt with a reversible stash-plus-note flow instead of asking the user to choose between stash/cleanup/background continuation for every dirty-worktree checkpoint
- refined sticky `/cook` continuation detection so clear workflow-follow-up turns stay inside the active workflow while unrelated ordinary chat stays outside it, and aligned smoke/release regressions with that split

## 0.1.75

### Fixed

- stopped treating a fresh but under-specified explicit `cook_handoff` as an automatic startup blocker; `/cook` now uses the user's explicit entry as implementation intent and lets same-entry primary-agent startup synthesis tighten the first slice before it gives up
- aligned startup, sticky-workflow, and canonical-evidence regressions with the new implementation-first `/cook` behavior so long-running workflows no longer bounce users back into handoff-authoring loops
- taught the completion protocol and core role prompts to auto-preserve routine unrelated tracked worktree dirt with a reversible stash-plus-note flow instead of asking the user to choose between stash/cleanup/background continuation for every dirty-worktree checkpoint

## 0.1.74

### Fixed

- made active `/cook` workflows sticky across routine continuation turns, exact await-user-input replies, and mandatory completion-role dispatch so long-running workflows keep moving without repeated manual `/cook` re-entry while unrelated ordinary chat stays outside workflow mode
- updated smoke, canonical-evidence, release-check, and completion-role gating regressions to enforce the new sticky active-workflow self-healing behavior
- stopped letting fresh but under-specified explicit `cook_handoff` capsules block `/cook` startup by default; `/cook` now treats the user's entry as implementation intent and tries same-entry primary-agent startup synthesis to tighten the first slice before failing closed

## 0.1.73

### Fixed

- made active `/cook` workflows sticky across subsequent turns so completion-role dispatch and workflow context continue to self-heal from canonical active state instead of depending on prompt-shaped driver turns
- extended sticky active-workflow self-heal to canonical `continuation_policy=continue` slices with a next mandatory role so implementer/reviewer/auditor dispatch no longer depends on the latest user turn resembling `/cook`
- taught `agent_end` to keep auto-dispatch moving when a completion role just finished and canonical state still says `continue`, instead of stopping after prose handoff summaries until the user manually reruns `/cook`
- stopped pushing users to rerun `/cook` for routine active-workflow continuation, exact await-user-input replies, or canonical-continue self-heal when canonical workflow state is already active
- added regression coverage so release-check fails if sticky active-workflow dispatch falls back to prompt-only gating again

## 0.1.72

### Fixed

- relaxed reviewer no-follow-up routing parsing so `Acceptable as-is: yes` now also accepts `none, proceed to completion-auditor` and `none - proceed to auditor` in addition to the original exact allowance, reducing avoidable completion transcription warnings without weakening the follow-up-slice guard
- fixed completion-role continuation gating so an already-active `/cook` workflow with `continuation_policy: continue` can keep dispatching mandatory follow-up roles even when the harness no longer recognizes the current turn text as an explicit `/cook` or workflow-driver prompt, while still blocking ordinary main-chat turns from calling `completion_role`
- fixed `/cook` await-user-input resumptions so a user's exact reply in the active workflow can dispatch the mandatory follow-up completion role without forcing an extra `/cook` rerun
- added a dedicated `completion-role-gating-test` regression so release-check now fails if active-workflow continuation falls back to the old prompt-only dispatch gate, await-user-input replies lose workflow dispatch rights, or ordinary main-chat turns stop being rejected

## 0.1.71

### Changed

- clarified the packaged `completion-auditor` output contract so `Stale or conflicting canonical state` must begin with `yes` or `no`, matching the canonical transcription gate
- added rubric-contract coverage to keep the stricter auditor yes/no guidance from drifting and to reduce avoidable transcription warnings during audit

## 0.1.70

### Changed

- added a visible `/cook startup plan` overlay while same-entry primary-agent startup synthesis is running so users no longer wait on a silent UI before Start/Cancel appears
- reused the same cancellable overlay/heartbeat pattern for `/cook` startup subprocesses so progress updates, elapsed time, and waiting state stay visible during startup-plan synthesis

## 0.1.69

### Changed

- preserved the confirmed `/cook` startup intent in canonical `.agent/current/startup-brief.json` so workflow entry is durable before regrounding authors canonical slices
- moved workflow-session legitimacy away from in-memory routing activation and legacy `/skill:completion-protocol` prompt dependence toward canonical workflow-session state plus explicit `/cook` entry turns
- simplified completion-driver continuation bookkeeping so explicit `/cook` kickoff/resume no longer rely on transient in-flight markers while auto-resume keeps only minimal duplicate-suppression state
- updated smoke coverage, verifier expectations, and shipped docs/skills to describe canonical startup-brief intake plus active `/cook` workflow sessions truthfully

## 0.1.68

### Changed

- simplified `/cook` startup sourcing so workflow proposals now come only from same-entry primary-agent startup-plan synthesis
- stopped `/cook` from directly adopting old preview capsules or falling back to transcript-derived startup proposals
- kept preview capsules advisory-only for humans while active-workflow replacement and next-round startup now depend on same-entry primary-agent synthesis from current task context

## 0.1.67

### Changed

- rewrote `/cook` startup around an approved startup plan that is captured under `.agent/startup-plan.json` / `.agent/startup-plan.md` after Start instead of leaving startup intent only as advisory intake in `state.json`
- kept `/cook` confirm-first while handing the approved startup plan to `completion-regrounder`, which now derives canonical slices from repo truth instead of treating startup intake like an implementation-ready first-slice contract
- relaxed primary-agent `/cook` preview requirements so explicit startup plans may carry optional sequencing hints (`first_slice_goal`, `implementation_surfaces`, `verification_commands`) without requiring them before workflow startup can begin
- updated workflow reminders, recovery capsules, regrounder/bootstrapper instructions, and public docs so canonical startup-plan persistence and regrounder-owned slice derivation stay truthful

## 0.1.66

### Changed

- blocked `completion_role` outside explicit `/cook` workflow-driver turns so ordinary chat can no longer silently dispatch completion subagents on its own
- tightened ordinary-chat reminders and skill contracts to forbid loading `completion-protocol` before explicit `/cook`
- expanded smoke and release-parity checks to keep the ordinary-chat vs `/cook` boundary enforced in shipped behavior

## 0.1.62

### Changed

- made ordinary chat implementation-first again so the primary agent may directly edit repo files without requiring `/cook` when workflow state is unnecessary
- repositioned `/cook` as optional workflow mode for confirm-first startup, resumability, review/audit flow, and canonical `.agent/**` state rather than as a mandatory implementation boundary
- updated ordinary-chat boundary docs, reminders, and release-parity checks so they no longer tell the agent to block repo edits pending explicit `/cook`

## 0.1.61

### Changed

- removed proactive primary-agent `/cook` prompting and default ordinary-chat `cook_handoff` emission so main chat stays advisory until the user explicitly runs `/cook`
- changed bare `/cook` startup and done-workflow next-round entry to synthesize a deferred primary-agent startup brief from recent discussion instead of requiring a pre-authored explicit handoff capsule
- kept active-workflow bare `/cook` resumable from canonical `.agent/**` state by default while allowing `/cook` to confirm a concrete replacement mission derived from explicit entry context
- updated public parity and shipped package contents so the tracked `.agent` contract files are included in package tarballs and packaged smoke/release verification can scaffold canonical state truthfully

## 0.1.58

### Changed

- tightened implementation-ready explicit `/cook` handoffs so fresh capsules must already carry a bounded first slice, repo-change-oriented acceptance, implementation surfaces, verification commands, and why-that-slice-first structure before workflow startup
- made fresh explicit but non-startable `/cook` handoffs fail closed with a dedicated operator message instead of falling back to broader recent discussion or silently drifting into planning
- expanded regressions and public parity so valid, vague, stale, done-workflow, and negative explicit-handoff cases stay truthful across runtime behavior, docs, and `npm run release-check`

## 0.1.57

### Changed

- made explicit primary-agent `/cook` handoff the preferred startup-intake path by teaching ordinary-chat handoff turns to emit a structured `cook_handoff` capsule and letting `/cook` prefer that capsule over broad context re-inference when it is fresh, valid, and implementation-startable
- tightened implementation-ready explicit handoffs so the structured capsule must already carry a bounded `first_slice_goal`, repo-change-oriented acceptance, `implementation_surfaces`, `verification_commands`, and `why_this_slice_first` before `/cook` will start workflow from it
- kept the pre-`/cook` handoff capsule as advisory startup intake only, not canonical `.agent/**` workflow state, while still using context-derived startup as the fallback only when no fresh explicit handoff is blocking startup
- kept context-derived startup as a fallback only when there is no fresh explicit handoff blocking startup, so stale or invalidated capsules can still fall back to recent discussion while fresh non-startable handoffs fail closed instead of silently rewriting canonical state
- made finished-workflow suppression stay a safety layer instead of a replacement mission when a fresh explicit `/cook` handoff exists, and blocked negative rejection/suppression text from becoming a Startable startup mission
- removed inline `/cook` arguments from the shipped entry path again so explicit bare `/cook` is the only public command, and fail closed when recent discussion is insufficient or unreliable
- added a pre-`/cook` ordinary-chat handoff boundary so the primary agent is instructed to stop at `/cook` once a task has matured into completion-workflow scope instead of starting long-running implementation directly in ordinary chat

## 0.1.54

### Changed

- removed workflow-aware prompt interception so only explicit `/cook` or `/cook <hint>` enters the workflow; ordinary prompts now always stay on the main chat path
- updated docs and release checks to describe explicit `/cook` entry instead of router-managed natural-language takeover

## 0.1.53

### Changed

- removed assist mode from public routing behavior so natural-language entry is now either off or router, and made router the default trigger mode while keeping `/cook` as the canonical workflow boundary
- removed obsolete cook planning docs that no longer match the shipped router-only workflow entry behavior

## 0.1.52

### Changed

- updated README/help/release parity copy to describe the shipped `off` / `assist` / `router` natural-language routing behavior truthfully while keeping `/cook` as the canonical confirm-first workflow boundary and manual fallback
- documented the explicit router-mode **Send as normal chat** recovery path as a user choice, not as a silent downgrade, and kept public copy scoped to currently shipped router behavior rather than future auto-mode plans
- made `npm run release-check` fail closed on the shipped workflow-aware router docs/help contract while continuing to rerun `bash ./scripts/cook-trigger-routing-test.sh` alongside the existing `/cook` smoke/refocus/context regressions

## 0.1.51

### Added

- shipped assist-mode natural-language handoff that can offer to route `開始做`, `開始實作`, or `go ahead` style execution handoffs into the canonical `/cook` flow before the primary agent starts implementation work, while keeping `/cook` as the explicit workflow boundary and approval gate
- added `bash ./scripts/cook-trigger-routing-test.sh` to `npm run release-check` so packaged release parity now covers the natural-language takeover path alongside the existing `/cook` startup/refocus/context regressions

### Changed

- streamlined the README into a more user-facing guide with a 30-second quick start, common actions table, clearer natural-language handoff expectations, and shorter `/cook` usage explanations

## 0.1.50

### Changed

- simplified the README opening so people can tell at a glance whether this extension helps with their workflow, while preserving the existing `/cook` behavior and release-parity guidance

## 0.1.49

### Changed

- restored optional `/cook <hint>` support as a soft intent hint that biases context analysis, proposal ranking, active-workflow disambiguation, and next-round startup without bypassing fail-closed routing or the approval-only Start/Cancel gate

## 0.1.48

### Fixed

- stopped injecting active completion workflow routing into ordinary non-`/cook` main-chat turns after a repo had been activated earlier in the same Pi process, so stale canonical stop-wave state can no longer pull unrelated user requests into `completion-regrounder` unless a fresh `/cook` driver prompt is actually in flight

## 0.1.47

### Changed

- removed inline `/cook <text>` argument support so bare `/cook` is now the only supported workflow entrypoint
- made runtime, deterministic regressions, README guidance, and packaged release parity fail closed when command arguments are passed instead of discussion driving proposal derivation
- made bare `/cook` weight the latest clear implementation intent ahead of older background discussion, preserve alternate recent missions for chooser-driven disambiguation, and summarize each candidate directly in the active-workflow chooser instead of forcing a single guessed replacement path
- made bare `/cook` suppress reopening already completed or already verified work by comparing recent discussion against canonical mission, active-slice, and verification-evidence context before startup/refocus proposal confirmation

## 0.1.44

### Fixed

- inject a done-workflow boundary prompt into ordinary primary-agent turns so finished completion state is treated as historical context only and the agent must not resume/reground/refocus the workflow unless the user explicitly reruns `/cook`

## 0.1.43

### Fixed

- stopped injecting completion-workflow reminder and compaction-resume context into ordinary primary-agent turns after canonical `continuation_policy` reaches `done`, so users must rerun `/cook` before the workflow protocol reactivates

## 0.1.42

### Changed

- historically allowed `/cook <hint>` as an analyst-only high-priority prompt that focused proposal derivation without bypassing the existing approval-only Start/Cancel confirmation gate or canonical fail-closed routing; that inline-argument path has since been removed so bare `/cook` is now the only supported entrypoint

## 0.1.41

### Changed

- fixed the `/cook proposal analyst` startup overlay so `Ctrl+C` cancels the in-flight analysis the same way as `Esc`, and updated the helper text to advertise both cancellation paths

## 0.1.40

### Changed

- treated bare `/cook` README/CHANGELOG/docs-only deliverables as concrete repo-change missions instead of preserving generic planning phrasing
- made bare `/cook` ignore assistant/branch/compaction summary artifacts for startup/refocus readiness and fail closed on plan/spec/design-doc/proposal-only context without rewriting canonical state
- refreshed the context-proposal regressions, README guidance, and packaged release parity so the new execution-ready bare `/cook` behavior stays truthful
- internalized the repo-local `pi --no-extensions` isolation inside the packaged verifier scripts so direct `npm run smoke-test`, direct `npm run release-check`, and direct `bash .agent/verify_completion_stop.sh` stay truthful even when `@linimin/pi-letscook` is also installed globally on the same machine

## 0.1.39

### Changed

- aligned public docs and packaged release-gate parity around bare `/cook` as the only supported workflow entrypoint
- updated operator-facing fail-closed guidance to send users back to the main chat to clarify the mission before rerunning bare `/cook`
- refreshed `scripts/release-check.sh` so packaged parity now fails closed on the bare-only contract while still covering the supported startup, refocus, and context flows

## 0.1.38

### Changed

- normalized discussion-derived `/cook` missions through shared proposal finalization so planning-phrased startup, next-round, and bare active-refocus discussions now resolve to implementation-result missions only when scope or acceptance clearly point to shipped code/test/doc/runtime changes
- preserved genuine planning missions for explicit plan/spec/design-doc/migration-plan/proposal and support-docs-only discussions, while keeping ambiguous generic scope fail-closed instead of promoting it into a new mission
- aligned analyst-derived and strict structured-fallback `/cook` proposal paths behind the same mission-normalization rules, added deterministic regressions for planning-only preservation and ambiguous-scope fail-closed behavior, and kept the existing approval-only Start/Cancel rewrite gate intact

## 0.1.37

### Changed

- documented `/cook` as the single public discussion-first workflow command for startup, active-workflow continue/refocus, and done-workflow next-round flows
- reframed the public docs/help copy around `/cook` as the discussion-first workflow entrypoint and documented the conservative fail-closed clarification path before the later runtime removal
- documented the fail-closed ambiguous-discussion behavior and approval-only Start/Cancel gate before canonical-state writes
- added release-gated public-parity assertions for README/help/changelog `/cook` single-command copy so docs drift fails closed before packaging
- simplified the README opening so first-time users can understand the problem `/cook` solves, what the extension provides, and how to start using it without reading the full control-plane details first

## 0.1.35

### Changed

- brightened the remaining `/cook` completion UI helper text by removing the last `dim` styling from proposal intro/footer/scroll hints and running activity metadata, using plain/default text for higher contrast while keeping stalled activity as warning-colored

## 0.1.34

### Changed

- added evaluator calibration fixtures for semantically lenient but well-formed reviewer/auditor/stop-judge reports and made packaged transcription reject those cases fail closed while still accepting truthful passing fixtures
- tightened the reproducible `none; ...` reviewer/auditor/stop-judge bypass checks while still accepting only the exact reviewer `none; proceed to completion-auditor` routing allowance with terminal punctuation or whitespace only
- wired `npm run evaluator-calibration-test` into `npm run release-check` and `.agent/verify_completion_stop.sh` as part of the packaged release gate
- fixed the smoke auto-resume prompt regression so the packaged release check writes `auto-resume-prompt.txt` again and passes on clean HEAD
- promoted `.agent/active-slice.json` to implementation-contract v2 across implementer instructions, fail-closed active-vs-plan parity checks, recovery/reminder surfaces, and a dedicated release-gated regression
- added durable canonical verification evidence at `.agent/verification-evidence.json`, threaded it through docs and recovery surfaces, and made release/stop verification fail closed on missing, stale, wrong-head, or protocol-doc-drift evidence artifacts
- made `/cook` startup and replacement confirmation approval-only by removing inline Edit and mission-anchor editing paths; the proposal gate now offers only Start or Cancel, and cancel points users back to the main chat before rerunning `/cook`
- kept the separate existing-workflow chooser (`Continue current workflow` / `Abandon current workflow and start this new one` / `Cancel`) while updating the replacement path, README, and deterministic context/refocus regressions to match the new approval-only gate truthfully

## 0.1.33

### Changed

- kept full mission text in `/cook` confirmation instead of truncating mission anchors during derivation
- refined `/cook` activity and completion-role text contrast by reducing overuse of `dim` styling in high-value status surfaces

## 0.1.32

### Changed

- made `/cook` auto-continue workflows from canonical state when `continuation_policy == continue`, so the primary driver re-queues the canonical resume prompt after intermediate role turns instead of parking silently on known mandatory steps
- added smoke coverage for the new auto-resume driver prompt behavior and a guarded parked-state warning path to avoid infinite requeue loops on an unchanged mandatory state

## 0.1.31

### Changed

- defined a shared structured evaluation-rubric contract for `completion-reviewer`, `completion-auditor`, and `completion-stop-judge`, including the exact rubric dimensions `Contract coverage`, `Correctness risk`, `Verification evidence`, and `Docs/state parity` with `pass|concern|fail` verdict semantics
- added canonical `task_type: completion-workflow` and `evaluation_profile: completion-rubric-v1` signaling across the packaged control-plane defaults, verifier schema, and kickoff/reminder/resume surfaces
- expanded the exact active-slice implementer handoff with canonical `implementation_surfaces` and `verification_commands` fields, and now surface them alongside `priority` / `why_now` in reminder and compaction-resume text
- documented the rubric-driven evaluation contract plus canonical routing-profile signaling in the packaged completion protocol and README without adding profile-specific rubric-output enforcement yet
- strengthened the smoke/refocus/context regressions so bootstrap and refocus preserve the new canonical signaling and fail closed when required `task_type` / `evaluation_profile` fields are removed
- strengthened the smoke regression and control-plane verifier so selected-slice handoffs now fail closed when the expanded implementation-contract fields are missing
- threaded canonical `evaluation_profile` plus direct-read pointers for the active-slice implementation contract and verification evidence into reviewer/auditor/stop-judge reminder and dispatch surfaces so those read-only roles can recover from canonical state instead of prose-only summaries
- made reviewer/auditor/stop-judge transcription fail closed on malformed rubric-bearing outputs while still accepting valid reports, and added deterministic transcription coverage for all three roles in `npm run rubric-contract-test`
- kept deterministic `rubric-contract-test` coverage wired into `npm run release-check`
- made the `/cook` confirmation UI critique-aware by rendering critique/risk notes plus recommended `task_type` / `evaluation_profile` routing hints in dedicated sections while keeping the existing Start/Edit/Cancel flow
- persisted accepted startup/refocus routing choices canonically by writing the selected `task_type` / `evaluation_profile` into the canonical control-plane files and recording the accepted critique outcome in continuation state, with `context-proposal-test` and `release-check` covering the shipped flow

## 0.1.30

### Changed

- clarified the README next-round example so the goal text no longer repeats `/cook` in a way that looks like part of the command syntax

## 0.1.29

### Changed

- tightened the README opening description so it correctly presents this package as a Pi extension that adds `/cook`, rather than implying `/cook` is built into Pi itself

## 0.1.28

### Changed

- added model-assisted `/cook` startup proposal analysis for natural recent discussion with a live `/cook proposal analyst` progress overlay, removed the built-in discussion-parser fallback for discussion-only startup, and preserved explicit-goal mission anchoring even when analyst output is unavailable
- replaced the crowded built-in `/cook` startup proposal selector presentation with a custom confirmation UI that separates proposal content from explicit Start, Edit, and Cancel actions
- fixed `/cook proposal analyst` overlay input handling and improved proposal body readability in the confirmation UI

## 0.1.27

### Changed

- added package metadata for npm and pi.dev discovery, fixed README publishing links for npm rendering, and refined install and workflow guidance after the `v0.1.26` tag

## 0.1.26

### Changed

- clarified the README install guidance and `/cook` behavior matrix, including tracked-vs-ignored `.agent` file explanations, active-workflow replacement examples, and safer `/reload` guidance for completion work

## 0.1.25

### Changed

- `/cook` with no goal can now propose a context-derived startup plan for confirmation when no active workflow exists, including starting a fresh next round after the previous workflow already reached `done`
- historically added goal-anchored startup proposals from inline `/cook` arguments before canonical writes, plus more explicit active-workflow replacement wording and direct next-round startup after a completed workflow; that old inline-argument path is no longer supported now that bare `/cook` is the only public entrypoint

## 0.1.24

### Changed

- removed the completion status line entirely; the remaining completion widget appears only when no role is actively running

## 0.1.23

### Changed

- renamed the public workflow command from `/complete` to `/cook`
- aligned the published package/install identity around `@linimin/pi-letscook` and `pi-letscook`
- removed the completion status line entirely; the remaining completion widget now appears only when no role is actively running
- kept the richer live role observability lanes and waiting/stalled signaling without reintroducing a status-line surface
- added this current release entry so the shipped `/cook`, package rename, and current completion UI behavior are documented without rewriting older `/complete` history

## 0.1.22

### Changed

- clarified the existing-workflow continue/refocus selection UI with a clearer prompt, current-vs-proposed mission summary, and shorter option descriptions

## 0.1.21

### Changed

- kept the persistent completion status line from canonical `.agent/**` state and live role activity, while suppressing the widget whenever a role is actively running
- separated live running-role observability into distinct tool activity, role judgment, verification, and state-delta lanes with waiting/stalled signaling
- added deterministic observability status regression coverage to the release-check path
- refreshed README and release-verifier guidance so the shipped observability surfaces and verification flow are documented truthfully

## 0.1.18

### Changed

- reduced the public slash-command surface to a single `/complete` entrypoint
- `/complete` with no goal now resumes from canonical `.agent/**` state when present
- `/complete <new goal>` now asks whether to continue the current mission or refocus canonical mission state before continuing
- removed dedicated resume, reground, panel, history, verify, and pause slash commands in favor of the always-visible workflow status
- pruned helper code that only supported the removed slash commands
- added a regression test for existing-workflow refocus handling and included it in release checks

## 0.1.16

### Improved

- richer operator-facing live role execution display with progress, rationale, next-step, verification, and state-delta parsing
- elapsed-time tracking for running completion roles
- no emoji in workflow-specific status, widget, panel, or role execution displays
- role prompts now emit structured `PROGRESS`, `RATIONALE`, `NEXT`, `VERIFYING`, and `STATE-DELTA` lines for observability

## 0.1.15

### Changed

- removed `/completion-status`; rely on the persistent widget/footer and `/completion-panel` for state inspection

## 0.1.14

### Changed

- removed `/completion-init` and made `/complete <goal>` the single bootstrap-and-run entrypoint
- smoke test now validates bootstrap through `/complete`
- docs updated to treat `/complete` as the canonical initialization path

## 0.1.13

### Improved

- persistent footer/widget status is now more compact and useful for day-to-day workflow use
- always-visible status now surfaces live role/action summaries without requiring the panel to be open
- widget lines now favor concise mission, goal, reason, and live activity previews over verbose raw fields

## 0.1.12

### Improved

- `/completion-panel` now live-follows current running role activity
- side panel and print-mode panel output now include current role, current action, recent activity, and assistant-progress previews while a completion role is running

## 0.1.11

### Added

- `/completion-panel` command for an on-demand right-side completion workflow panel
- live panel view for canonical mission, current phase, active slice, remaining work, and recent history
- print-mode fallback that renders panel contents as plain text when interactive UI is unavailable

## 0.1.10

### Improved

- ambiguous bootstrap goals can now trigger developer confirmation or editing of the proposed `MISSION ANCHOR`
- `/complete` and `/completion-init` keep auto-bootstrap for clear goals but ask before writing weak or underspecified anchors into canonical state
- mission-anchor confirmation uses extension UI instead of relying on model-side clarification later in the workflow

## 0.1.9

### Improved

- bootstrap now derives a cleaner `MISSION ANCHOR` from vague `/complete` and `/completion-init` goals
- weak or underspecified goals now fall back to a stable repo-based mission anchor instead of using raw ambiguous text
- common phrasing noise like `/complete`, `please`, and `end-to-end` is normalized before seeding canonical mission state

## 0.1.8

### Fixed

- removed duplicate prompt-template aliases for `/complete`, `/complete-resume`, and `/completion-status`
- package now exposes those names only as extension commands, avoiding duplicate command entries in pi

## 0.1.7

### Fixed

- generated `verify_completion_control_plane.sh` now validates canonical `plan.json` and `active-slice.json` structure instead of only checking JSON parseability
- exact implementer handoff states now require `priority` and `why_now`, matching the completion protocol docs and role expectations
- scaffolded `active-slice.json` now includes `priority` and `why_now` placeholders to avoid schema drift during later role updates
- `ensureGitignore` now repairs duplicated or drifted completion-protocol ignore blocks instead of bailing out on the first marker match
- smoke test now covers the selected active-slice handoff schema regression and fails closed when `priority`/`why_now` are missing

## 0.1.6

### Fixed

- additional stale-context guards for command handlers and completion role execution
- avoid stale ctx access through cwd, hasUI, ui, and system-prompt lookups after session replacement or reload

## 0.1.5

### Fixed

- stale extension context handling after session replacement or reload
- guarded UI status, widget, theme, and notify calls to avoid stale-ctx runtime errors

## 0.1.4

### Improved

- stronger implementer instructions for roadmap-level drift discovered during implementation
- explicit requirement to hand plan repair back to `completion-regrounder` instead of silently redesigning slices
- implementer report now includes `Plan adjustment required: yes/no - ...`

## 0.1.3

### Improved

- richer live progress visibility for `completion_role`
- current action, recent activity, and assistant-progress previews while roles are running
- less opaque role execution UX during long-running workflow steps

## 0.1.2

### Improved

- stronger post-compaction driver recovery instructions
- transient post-compaction recovery marker with automatic cleanup after recovery turn
- stricter canonical-file-first continuation guidance after compaction

## 0.1.1

### Improved

- print-mode output for `/completion-status`, `/completion-history`, `/completion-verify`, and `/completion-pause`
- package-local runtime polish for release workflow

## 0.1.0

Initial packaged release of `pi-completion-workflow`.

### Added

- pi package manifest with extension, skills, prompts, and role agents
- canonical `.agent/**` scaffolding via `/completion-init`
- workflow entrypoints: `/complete` and `/complete-resume`
- workflow inspection commands: `/completion-status`, `/completion-history`, `/completion-verify`
- pause and re-ground commands
- isolated `completion_role` execution for role-based subagents
- canonical transcription of reviewer, auditor, regrounder, and stop-judge outputs
- custom compaction continuity support
- release smoke test script
