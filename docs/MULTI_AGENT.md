# Running Multiple Agents in Parallel

The default setup ships one agent service (`agent` in `docker-compose.yml`).
To run several agents at once, each gets: its own compose service, its own
bridge network (so one agent's firewall/network state can't affect another),
its own `.env` file, and its own git worktree (so concurrent agents aren't
fighting over the same working tree / index lock).

## Worked example: adding `agent-2`

1. **Create a git worktree** for the second agent, on its own branch:
   ```bash
   git worktree add ../worktrees/agent-2 -b agent-2/work
   ```
   (`worktrees/` lives as a sibling to the repo and is gitignored — see
   `.gitignore`.)

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
         - ../worktrees/agent-2:/workspace:cached
       command: sleep infinity
   ```
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
