# Prepare cook handoff

Prepare a `cook_handoff` JSON file at `.agent/tmp/cursor-handoff.json` from the current planning discussion so Pi `/cook import` can start the long-running workflow.

Follow the `cursor-handoff` skill contract exactly. Do not implement product changes here; only write the handoff file and tell the user to run `pi` then `/cook import`.
