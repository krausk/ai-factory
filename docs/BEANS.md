# Beans (task tracking)

[Beans](https://github.com/hmans/beans) is a git-native issue tracker: tasks
are plain markdown files stored in `.beans/` right alongside the code, so
history, review, and diffing all work the normal git way — and, more
importantly, the coding agent can read and write them directly through the
`beans` CLI.

## What's already wired up

- `beans` (the Go CLI) is built into the container image.
- `post-create.sh` runs `beans init` the first time the container is
  created, generating `.beans.yml` and `.beans/` at the repo root — commit
  these, they're meant to be tracked in git.
- `AGENTS.md` instructs the agent: **"before you do anything else, run
  `beans prime` and heed its output"** — this is Beans' own documented
  integration hook, and it's what loads current task context into the
  agent's view of the project before it starts working.

## Using it yourself

```bash
beans help        # list all commands
beans tui          # interactive terminal UI for browsing/managing tasks
```

## Talking to the agent about tasks

Once Beans is primed, the usual natural-language requests work as documented
upstream:

```
Are there any tasks we should be tracking for this project? If so, please create beans for them.
What should we work on next?
It's time to tackle myproj-123.
```

Per `AGENTS.md`, the agent is also instructed to reference bean IDs in commit
messages (e.g. `Fix login redirect (myproj-42)`), so completed work stays
traceable back to the task that prompted it. Completed/archived beans double
as project memory the agent can query for context about past work.
