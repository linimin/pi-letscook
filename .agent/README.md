# Completion Control Plane

This repository uses the `completion` workflow for long-running coding tasks.

## Tracked repo-level workflow contract

- `.agent/README.md`
- `.agent/config/workflow.json`
- `.agent/config/profile.json`
- `.agent/profile.json` *(temporary compatibility shim for the current workflow round)*
- `.agent/verify_completion_stop.sh` *(thin forwarding stub to the package-owned stop verifier)*
- `.agent/verify_completion_control_plane.sh` *(thin forwarding stub to the package-owned control-plane verifier)*

## Ignored runtime state

- `.agent/current/state.json`
- `.agent/current/startup-brief.json`
- `.agent/current/plan.json`
- `.agent/current/active-slice.json`
- `.agent/current/slice-history.jsonl`
- `.agent/current/stop-check-history.jsonl`
- `.agent/current/verification-evidence.json`
- `.agent/current/*.log`
- `.agent/current/tmp/`

`.agent/config/workflow.json` defines the canonical storage contract: tracked repo policy stays under `.agent/config/**`, runtime state lives under `.agent/current/**`, archive is disabled, and replacement/cancel/done paths must delete `.agent/current/`.

Package-owned verification logic ships in `scripts/verify-completion-control-plane.js` and `scripts/verify-completion-stop.sh`. The tracked `.agent/verify_completion_*.sh` files stay intentionally small and just forward repo-local verification requests into those package-owned entrypoints.

`.agent/config/profile.json` carries the stop-wave defaults for this repo, including `required_stop_judges` and `stop_aggregation_policy`. The packaged default is `required_stop_judges: 2` plus `stop_aggregation_policy: "unanimous-current-head-v1"`. Canonical `.agent/current/state.json current_stop_wave_id` carries the current stop-wave epoch so the same HEAD may restart stop evaluation without requiring a synthetic tracked commit.

`.agent/current/startup-brief.json` preserves the confirmed `/cook` startup intent as canonical intake for re-grounding. It does not replace `.agent/current/plan.json` or `.agent/current/active-slice.json`, which remain under regrounder authority.

`.agent/current/verification-evidence.json` is the durable canonical record of deterministic verification for the selected slice or current HEAD. Recovery, review, audit, and stop-check reminder surfaces consume it instead of temp-only artifacts or conversational summaries when it is populated.

The source of truth for long-running completion work is canonical tracked `.agent/config/**`, ignored `.agent/current/**`, package-owned verifier entrypoints, and current repo truth.

Project: pi-letscook
