# Completion Control Plane

This repository uses the `completion` workflow for long-running coding tasks.

## Canonical tracked contract files

- `.agent/README.md`
- `.agent/mission.md`
- `.agent/profile.json`
- `.agent/verify_completion_stop.sh`
- `.agent/verify_completion_control_plane.sh`

## Ignored canonical execution state

- `.agent/state.json`
- `.agent/startup-plan.json`
- `.agent/startup-plan.md`
- `.agent/plan.json`
- `.agent/active-slice.json`
- `.agent/slice-history.jsonl`
- `.agent/stop-check-history.jsonl`
- `.agent/verification-evidence.json`
- `.agent/*.log`
- `.agent/tmp/`

`.agent/startup-plan.json` plus `.agent/startup-plan.md` preserve the approved workflow startup plan captured at `/cook`. `completion-regrounder` consumes that plan as planning input, then derives canonical slices in `.agent/plan.json` from current repo truth.

`.agent/verification-evidence.json` is the durable canonical record of deterministic verification for the selected slice or current HEAD. Recovery, review, audit, and stop-check reminder surfaces consume it instead of temp-only artifacts or conversational summaries when it is populated.

The source of truth for long-running completion work is canonical `.agent/**` state plus current repo truth.

Project: pi-letscook
