# @linimin/pi-letscook

Give Pi a workflow mode for long-running coding tasks.

`pi-letscook` adds `/cook`, a way to keep larger repo changes reliable, reviewable, and aligned with the original goal. It is for the work that does not fit neatly in one chat turn: multi-step fixes, refactors, follow-up rounds, and tasks where you want the agent to keep going without losing the plot.

Use ordinary chat for quick answers and simple edits. Switch to `/cook` when you want Pi to carry a task across sessions, save local workflow state, and run built-in review/audit/verification rounds before calling the work done.

## When To Use It

Use `/cook` when you want Pi to:

- keep the same coding mission alive across sessions
- split a repo change into reviewable slices
- keep each slice tied to the original goal
- resume, refocus, park, or cancel work explicitly
- run review/audit/verification before marking the task done
- reduce drift during long-running work
- fail closed instead of starting from vague or planning-only input
- keep workflow state local to the repo, not just in chat history

For one-off answers, quick edits, brainstorming, or planning-only work, ordinary chat is usually enough.

## Install

```bash
pi install npm:@linimin/pi-letscook
```

Then run `/reload` in Pi.

## How It Works

1. Describe the repo change you want Pi to complete.
2. Run `/cook` or `/cook <prompt>`.
3. Pi prepares a startup brief.
4. Choose **Start** to begin, or **Cancel** to return to ordinary chat.
5. Later, run `/cook` or `/cook resume` to continue from saved workflow state.

Example:

```text
/cook add login redirect handling and the missing redirect tests
```

## Commands

- `/cook` starts or resumes a workflow.
- `/cook <prompt>` starts with inline task intent.
- `/cook resume` resumes saved workflow state.
- `/cook park` pauses a stopped workflow so you can edit normally.
- `/cook cancel` closes a stopped or parked workflow.

`/cook` is optional. Ordinary chat still works normally and can still edit the repo directly.

