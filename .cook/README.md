# Completion Workflow Config

This repository uses the `completion` workflow for long-running coding tasks.

## Tracked repo-level workflow contract

- `.cook/README.md`
- `.cook/workflow.json`
- `.cook/profile.json`

## Ignored local runtime state

- `.agent/current/state.json`
- `.agent/current/startup-brief.json`
- `.agent/current/plan.json`
- `.agent/current/active-slice.json`
- `.agent/current/slice-history.jsonl`
- `.agent/current/stop-check-history.jsonl`
- `.agent/current/verification-evidence.json` *(durable canonical record of deterministic verification for the selected slice or current HEAD)*
- `.agent/current/*.log`
- `.agent/current/tmp/`
- local `.agent/verify_completion_stop.sh`
- local `.agent/verify_completion_control_plane.sh`

`.cook/workflow.json` defines the canonical storage contract: tracked repo policy lives under `.cook/**`, runtime state lives under ignored `.agent/**`, archive is disabled, and replacement/cancel/done paths must delete `.agent/current/`.

Package-owned verification logic ships in `scripts/verify-completion-control-plane.js` and `scripts/verify-completion-stop.sh`.
Runtime-generated `.agent/verify_completion_*.sh` forwarders are local convenience entrypoints only and are intentionally not tracked.

`.cook/profile.json` carries the stop-wave defaults for this repo, including `required_stop_judges` and `stop_aggregation_policy`.
