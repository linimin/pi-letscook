# completion runtime quick reference — regrounder

Use this as the default runtime brief for `completion-regrounder`.

Read the full `../SKILL.md` or `completion.md` only when this regrounder brief plus canonical `.agent/**` state still leave a protocol detail ambiguous.

## Canonical inputs

Read current repo truth plus these canonical workflow inputs as needed:

- `.agent/current/state.json`
- `.agent/current/startup-brief.json`
- `.agent/current/plan.json`
- `.agent/current/active-slice.json`
- `.agent/current/slice-history.jsonl`
- `.agent/current/stop-check-history.jsonl`
- `.agent/current/verification-evidence.json`

## Regrounder rules

- Reconcile canonical `.agent/current/plan.json`, `.agent/current/active-slice.json`, and `.agent/current/state.json` against repo truth.
- `startup-brief.json` is mission-level intake, not a canonical selected slice.
- Revalidate every slice's `acceptance_criteria`; reopen any `done` slice whose criteria no longer hold.
- If canonical state is ambiguous, stale, contradictory, or recovery requires it, keep routing through `completion-regrounder` rather than guessing.
- Manage `current_stop_wave_id` truthfully when stop evaluation restarts on the same HEAD.
- If unrelated dirty tracked files can be isolated safely, auto-preserve them with a reversible stash-plus-note flow under `.agent/current/tmp/dirty-worktree-autostash.json`.
- If overlap or stash/restore risk makes isolation unsafe, reopen or continue the latest slice and route back to `completion-implementer`.
- Do not edit tracked product files or create commits.
