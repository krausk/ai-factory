# Running Multiple Agents in Parallel

The default setup ships one agent service (`agent` in `docker-compose.yml`).
To run several agents at once, each gets: its own compose service, its own
bridge network (so one agent's firewall/network state can't affect another),
its own `.env` file, and its own git worktree of the **target** repo (so
concurrent agents aren't fighting over the same working tree / index lock).
Remember: ai-factory itself isn't what's being worked on — every worktree
below is a worktree of `TARGET_REPO_PATH`, the project repo, not of this repo.

## Worked example: adding `agent-2`

1. **Create a git worktree of the target repo** for the second agent, on its
   own branch. Run this inside the *target* repo's checkout, not ai-factory:
   ```bash
   cd "$TARGET_REPO_PATH"
   git worktree add ../target-repo-worktrees/agent-2 -b agent-2/work
   ```
   Put the worktree wherever's convenient on the host (a sibling directory
   to the target repo works well); just note its absolute path for the next
   step.

2. **Add a service to `docker-compose.yml`**, copying the `agent` block:
   ```yaml
     agent-2:
       build:
         context: .
         dockerfile: .devcontainer/Dockerfile
       cap_add:
         - NET_ADMIN
         - NET_RAW
       networks:
         - agent-2-net
       env_file:
         - .env.agent-2
       volumes:
         - ${AGENT2_REPO_PATH}:/workspace:cached
       command: sleep infinity
   ```
   `AGENT2_REPO_PATH` goes in the top-level `.env` (compose variable
   substitution only reads that file, not per-agent `env_file`s) — set it to
   the absolute path of the worktree you created in step 1.
   And add the matching network:
   ```yaml
   networks:
     agent-net:
       driver: bridge
     agent-2-net:
       driver: bridge
   ```
   Giving each agent its **own** bridge network (rather than sharing one)
   matters here: iptables/ipset state lives at the network-namespace level,
   so a shared namespace would mean one agent's firewall rules apply to
   both.

3. **Create a separate secrets file**, `.env.agent-2` (gitignored — the
   `.env.*` pattern in `.gitignore` already covers this), with its own LLM
   and GitHub credentials (can be the same values as `.env`, or different
   ones if you want separate rate limits / separate GitHub identities per
   agent).

4. **Create a per-agent devcontainer config** so VS Code (or the CLI) can
   target this specific service — copy `.devcontainer/devcontainer.json` to
   e.g. `.devcontainer-agent-2/devcontainer.json` and change:
   ```json
   {
     "name": "ai-factory-agent-2",
     "dockerComposeFile": ["../docker-compose.yml"],
     "service": "agent-2",
     ...
   }
   ```
   Open that folder's devcontainer config (VS Code: **Dev Containers: Open
   Folder in Container...**, then pick the `.devcontainer-agent-2` config)
   or run `devcontainer up --workspace-folder . --config
   .devcontainer-agent-2/devcontainer.json`.

5. Repeat for `agent-3`, etc.

**Note on branches**: `agent-2/work` above is just the local base branch for
that worktree, not something to push straight to `main` — `main` is
protected on the target repo (see docs/GITHUB_TOKEN.md and the target repo's
AGENTS.md branch/PR workflow), so from inside the `agent-2` worktree the
agent should still cut a per-task branch off of `agent-2/work` (or off
`main`) for each bean and open a PR from that, same as the single-agent
setup.

## Why not `docker compose up --scale`

Compose's `--scale` gives you N identical, anonymous replicas of one
service. That works for stateless workloads, but each agent here needs a
distinct git worktree, distinct branch, and (usually) distinct credentials —
easier to reason about and address individually as named services than as
scaled replicas of one.

## Verifying isolation

After starting multiple agents, confirm each container actually has its own
firewall applied and its own working tree:

```bash
docker inspect <container> | grep -A5 CapAdd   # confirm NET_ADMIN/NET_RAW landed
docker compose exec agent-2 git status          # confirm it's on agent-2/work, not shared with agent-1
```
