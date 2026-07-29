# Setup

## Prerequisites

- Docker (or a compatible engine) with `docker compose` v2.
- VS Code with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers),
  **or** the standalone [`devcontainer` CLI](https://github.com/devcontainers/cli)
  (`npm install -g @devcontainers/cli`) if you'd rather not use VS Code at all.

## First-time setup

1. Copy the secrets template and fill it in:
   ```bash
   cp .env.example .env
   ```
   You need at least one LLM provider key (docs/LLM_PROVIDERS.md), a GitHub
   token (docs/GITHUB_TOKEN.md), and `TARGET_REPO_PATH` — an absolute path
   on the host to the repo you actually want the agent to develop. This repo
   (ai-factory) is only the tooling; `TARGET_REPO_PATH` is what gets
   bind-mounted as `/workspace` inside the container. It must already exist
   as a git repo on the host (clone it there first if it isn't). `.env` is
   gitignored — it never gets committed.

2. Review `.devcontainer/allowed-domains.txt`. It's pre-seeded with the LLM
   provider APIs and common package registries; add anything else a task
   will need (docs/FIREWALL.md).

3. Open **this** (ai-factory) folder in VS Code and choose **"Reopen in
   Container"** (or run `devcontainer up --workspace-folder .`) — not the
   target repo's folder. VS Code will open the container's `/workspace`,
   which is the target repo's content once the mount lands.

4. Watch the container's start-up log. `postCreateCommand` runs `beans init`
   and copies in `AGENTS.md` (both into the target repo, skipped if either
   already exists there) and checks GitHub auth; `postStartCommand` runs the
   firewall script and **will fail the container start if the firewall
   self-test doesn't pass** — that's intentional, it means the agent won't
   run unprotected.

5. Once inside the container, sanity-check the toolchain:
   ```bash
   beans version
   gh auth status
   openhands --version
   python3 -m playwright --version
   ```

## Running the agent

OpenHands reads LLM config from `LLM_MODEL`/`LLM_API_KEY` env vars, only
when `--override-with-envs` is passed (see docs/LLM_PROVIDERS.md):

```bash
LLM_MODEL=anthropic/claude-sonnet-4-5-20250929 LLM_API_KEY="$ANTHROPIC_API_KEY" \
  openhands --headless --override-with-envs -t "describe the task here"
# or, for OpenAI:
LLM_MODEL=openai/gpt-4.1 LLM_API_KEY="$OPENAI_API_KEY" \
  openhands --headless --override-with-envs -t "describe the task here"
```

See docs/BEANS.md for how task tracking ties into this, and
docs/MULTI_AGENT.md to run more than one agent at a time.
