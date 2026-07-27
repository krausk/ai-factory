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
   You need at least one LLM provider key (docs/LLM_PROVIDERS.md) and a
   GitHub token (docs/GITHUB_TOKEN.md). `.env` is gitignored — it never gets
   committed.

2. Review `.devcontainer/allowed-domains.txt`. It's pre-seeded with the LLM
   provider APIs and common package registries; add anything else a task
   will need (docs/FIREWALL.md).

3. Open the folder in VS Code and choose **"Reopen in Container"** (or run
   `devcontainer up --workspace-folder .`).

4. Watch the container's start-up log. `postCreateCommand` runs `beans init`
   and checks GitHub auth; `postStartCommand` runs the firewall script and
   **will fail the container start if the firewall self-test doesn't pass**
   — that's intentional, it means the agent won't run unprotected.

5. Once inside the container, sanity-check the toolchain:
   ```bash
   beans --version
   gh auth status
   openhands --version
   python3 -m playwright --version
   ```

## Running the agent

```bash
openhands --headless -t "describe the task here" --llm-config anthropic
# or: --llm-config openai
```

See docs/BEANS.md for how task tracking ties into this, and
docs/MULTI_AGENT.md to run more than one agent at a time.
