# Agent Instructions

This repository is the **AI Factory**: a dev-container setup for running you
(an OpenHands-driven coding agent) unsupervised, with a firewalled network,
a real browser for testing, and Beans for task tracking.

## Before you do anything else

Run the `beans prime` command and heed its output. This loads the current
task list and project context tracked in `.beans/`. See docs/BEANS.md.

## Branch and PR workflow

`main` is protected on GitHub — direct pushes are rejected for everyone,
agents included, and there's no bypass. This is enforced remotely, not just
a convention, so plan for it rather than discovering it after a failed push:

1. Before starting work on a bean, create a branch off `main`:
   `git checkout -b <bean-id>-short-description`.
2. Commit your work on that branch as you go (see the bean-ID convention
   below).
3. Push the branch (`git push -u origin <branch>`) and open a PR:
   `gh pr create --fill` (or with an explicit `--title`/`--body`
   referencing the bean). Do this once the bean's work is ready for review,
   not as a last step you might skip.
4. Do not attempt to merge the PR yourself unless a task explicitly asks
   you to — leave it open for a human to review and merge, unless told
   otherwise.

## Working conventions

- When making a commit, include the relevant bean ID(s) in the commit message
  (e.g. `Fix login redirect (myproj-42)`).
- Keep beans up to date as you work: create one for unplanned work you
  discover, update status as you progress, archive on completion.
- Network access from this container is allowlisted (see docs/FIREWALL.md).
  If a task requires reaching a domain that isn't already allowed, say so
  explicitly rather than silently failing or working around it — add the
  domain to `.devcontainer/allowed-domains.txt` and note that the firewall
  needs a container restart to pick it up.
- A real browser (Playwright/Chromium) is available for end-to-end/UI
  testing. Use it to verify UI-facing changes actually work, not just that
  unit tests pass.
- You are running unsupervised: prefer safe, reversible actions. Do not
  force-push, rewrite shared branch history, or delete data you didn't
  create in this session without it being an explicit part of the task.
