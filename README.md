# @linimin/pi-letscook

Give Pi a workflow mode for long-running coding tasks.

`pi-letscook` adds `/cook`, a way to keep larger repo changes reliable, reviewable, and aligned with the original goal. Use ordinary chat for quick answers and simple edits. Switch to `/cook` when you want Pi to carry a task across sessions, save local workflow state, and run built-in review/audit/verification rounds before calling the work done.

## Install

```bash
pi install npm:@linimin/pi-letscook
```

Then run `/reload` in Pi.

## Quick start

```text
/cook add login redirect handling and the missing redirect tests
```

Pi prepares a startup brief. Choose **Start** to begin, or **Cancel** to return to ordinary chat. Later, run `/cook` or `/cook resume` to continue.

`/cook` is optional. Ordinary chat still works normally.

## Documentation

- [User guide](docs/user-guide.md) — commands, workflow concepts
- [Cursor integration](docs/integrations/cursor.md) — handoff, MCP, role backends
- [Technical overview](docs/design/technical-overview.md) — design rationale
- [Maintainer docs](docs/README.md#maintainers)
