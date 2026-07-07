# Cursor IDE → Pi /cook Handoff

Pi `/cook` cannot read Cursor IDE chat history. Hand off planning work with an explicit file or inline prompt in the same repository.

## Quick handoff

1. Plan in Cursor (Agent, Plan, or Ask mode).
2. Open a terminal in the **same repo**.
3. Run `pi`, then:

```text
/cook <one-line mission from Cursor>
```

## Planned handoff (recommended)

### 1. Install the companion Cursor assets

```bash
mkdir -p .cursor/skills .cursor/commands
cp -r node_modules/@linimin/pi-letscook/cursor/skills/cursor-handoff .cursor/skills/
cp node_modules/@linimin/pi-letscook/cursor/commands/prepare-cook-handoff.md .cursor/commands/
```

Or copy from a local checkout of this package under `cursor/`.

### 2. Prepare the handoff in Cursor

Run the **Prepare cook handoff** command (or invoke the `cursor-handoff` skill). Cursor writes:

```text
.agent/tmp/cursor-handoff.json
```

### 3. Start workflow in Pi

```bash
pi
/cook import
```

Review the startup brief, then choose **Start** or **Cancel**.

Optional explicit path:

```text
/cook import path/to/handoff.json
```

Override default path with `PI_COMPLETION_CURSOR_HANDOFF_PATH`.

After a successful import, Pi consumes or quarantines the handoff file so `/cook import` cannot accidentally reuse the same JSON. Archived `cursor-handoff.consumed.*` and `cursor-handoff.quarantined.*` files are rejected even when imported by explicit path.

## Plan doc handoff

Export a plan to `docs/plans/<name>.md`, then in Pi:

```text
/cook implement per docs/plans/<name>.md
```

## After workflow starts

- `/cook resume` — continue from `.agent/` state
- `/cook park` — pause for ordinary Cursor edits, then `/cook resume`
- `/cook cancel` — close the workflow

## Division of labor

| Surface | Role |
|---------|------|
| Cursor IDE | Explore, plan, write handoff file, quick edits while parked |
| Pi `/cook` | Durable mission, slices, dispatch, review/audit/stop |
| Cursor SDK/CLI (optional) | Implementer and evaluator execution |

## What handoff does not do

- Does not auto-start workflow from Cursor (Start/Cancel gate still required).
- Does not sync live Cursor chat into Pi after workflow starts.
- Does not replace regrounder — file hints are advisory; regrounder authors canonical slices from repo truth.
