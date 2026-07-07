# Cursor Role Backends

Pi remains the workflow driver and control plane. Optional Cursor backends run token-heavy completion roles under your Cursor subscription.

## Prerequisites

- Pi with a provider API key for the driver and control-plane roles
- `CURSOR_API_KEY` (or `PI_COMPLETION_CURSOR_API_KEY`) when Cursor backends are enabled
- Cursor CLI `agent` on `PATH` for evaluator roles (`--mode=ask`)
- Optional: `@cursor/sdk` installed for SDK implementer runs

## Enable

```bash
export PI_COMPLETION_CURSOR_ENABLED=1
export CURSOR_API_KEY="cursor_..."
```

## Default role mapping

| Role | Backend |
|------|---------|
| `completion-implementer` | Cursor SDK (`Agent.prompt` local) |
| `completion-reviewer` | Cursor CLI ask mode |
| `completion-auditor` | Cursor CLI ask mode |
| `completion-stop-judge` | Cursor CLI ask mode |
| `completion-regrounder` | Pi subprocess |
| `completion-bootstrapper` | Pi subprocess |
| scout / critic helpers | Pi subprocess |

## Configuration

| Variable | Purpose |
|----------|---------|
| `PI_COMPLETION_CURSOR_ENABLED` | Master switch (`1` / `true`) |
| `PI_COMPLETION_CURSOR_API_KEY` | Override Cursor API key |
| `PI_COMPLETION_CURSOR_CLI` | CLI binary (default: `agent`) |
| `PI_COMPLETION_CURSOR_MODEL` | Default model id (default: `composer-2.5`) |
| `PI_COMPLETION_CURSOR_MODEL_<ROLE>` | Per-role model override |
| `PI_COMPLETION_CURSOR_SDK_ROLES` | Comma-separated SDK roles |
| `PI_COMPLETION_CURSOR_CLI_ASK_ROLES` | Comma-separated CLI ask roles |

Per-role agent frontmatter in `agents/completion-*.md` (only honored when `PI_COMPLETION_CURSOR_ENABLED` is set):

```yaml
cursor_model: composer-2.5
role_backend: cursor-sdk   # or cursor-cli-ask | pi
```

## Behavior notes

- With `PI_COMPLETION_CURSOR_ENABLED` unset, behavior is unchanged (Pi subprocesses only); `role_backend` frontmatter is ignored.
- Pi subprocess roles still fail closed when structured `completion_emit_*` output is missing or invalid.
- Cursor eval roles use text report parsing when structured emit tools are unavailable.
- Configured Cursor roles fail closed if the CLI/SDK or API key is missing; they do not silently fall back to Pi.
- Cursor CLI ask runs use `--trust` so headless evaluator roles can run without interactive workspace approval. Prompts are written under `.agent/tmp/cursor-cli-role/` and passed via workspace-relative `@` references. Only enable Cursor backends in repos you trust.
- Cursor SDK implementer runs use `Agent.create` + `run.cancel()` so workflow abort can stop in-flight SDK work.
- Role runs fail when canonical transcription still reports errors after the one repair retry.

## Troubleshooting

- **SDK not found:** `npm install @cursor/sdk` in the environment running Pi.
- **CLI not found:** install Cursor CLI and ensure `agent` is on `PATH`, or set `PI_COMPLETION_CURSOR_CLI`.
- **Transcription repair loops:** check role report format against `agents/completion-*.md` fixed fields.

## Live verification (optional)

Validate workspace `@` prompt references against a real Cursor CLI install:

```bash
export CURSOR_LIVE_TEST=1
export CURSOR_API_KEY="cursor_..."
npm run cursor-cli-live-test
npm run cursor-sdk-live-test
```

Skipped by default in `release-check`. For environments without `pi` on PATH, run `npm run cursor-release-check` instead of the full `npm run release-check`. When `CURSOR_LIVE_TEST=1` and `CURSOR_API_KEY` are set, `cursor-release-check` runs both live probes automatically.

After `/cook import`, the handoff file is consumed only after kickoff is queued. On cleanup failure, Pi quarantines the file under `.agent/tmp/cursor-handoff.quarantined.*.json` to prevent accidental re-import.
