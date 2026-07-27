# AI Factory

A dev-container setup for running autonomous coding agents **unsupervised**:
firewalled network access, real coding/testing tools (including a browser),
task tracking that survives across sessions, and the ability to run several
agents in parallel.

## Stack

| Concern | Choice |
|---|---|
| Agent runtime | [OpenHands](https://github.com/OpenHands/OpenHands) — provider-agnostic (LiteLLM), headless CLI mode, built-in Docker sandbox, built-in Playwright browser tool, GitHub issue→PR resolver |
| Isolation | VS Code Dev Containers + Docker Compose |
| Egress control | Default-deny `iptables`/`ipset` firewall with a user-editable domain allowlist |
| Browser automation | Playwright (official `mcr.microsoft.com/playwright/python` base image) |
| Task tracking | [Beans](https://github.com/hmans/beans) — git-native issue tracker, CLI-driven, agent-readable |
| Source control | `gh` CLI, fine-grained PAT (or GitHub App for scale) |
| Parallelism | One Compose service per agent, each with its own network + git worktree |

## Layout

```
.devcontainer/
  devcontainer.json     VS Code Dev Container config → docker-compose service "agent"
  Dockerfile             Playwright base + OpenHands + Beans + gh CLI + firewall script
  init-firewall.sh        Default-deny egress firewall, self-testing
  allowed-domains.txt     Edit this to allow a task to reach a new domain
  post-create.sh          One-time setup: beans init, gh auth, playwright browsers
docker-compose.yml        Agent service definition (see docs/MULTI_AGENT.md to scale out)
config.toml               OpenHands LLM profiles (Anthropic + OpenAI)
AGENTS.md                 Instructions read by the agent itself
.env.example              Secrets template — copy to .env, never commit .env
.env.review.example       Review agent's separate GitHub identity — copy to .env.review
pipeline/roles/           Per-stage instructions for the conception/refinement/development/review pipeline
scripts/
  pipeline-up.sh          Bring up the four pipeline containers
  pipeline-watch.sh        Watches Beans and drives beans through the pipeline
  approve-spec.sh          The one human checkpoint: approve a spec for development
docs/
  SETUP.md                Start here
  LLM_PROVIDERS.md         Getting Anthropic/OpenAI API keys
  GITHUB_TOKEN.md          Getting a GitHub token, scoped appropriately
  FIREWALL.md              How the firewall works, how to extend it
  BEANS.md                 How task tracking works
  MULTI_AGENT.md           Running several agents at once
  PIPELINE.md              The conception → refinement → development → review pipeline
```

## Quickstart

```bash
cp .env.example .env   # fill in API keys, see docs/LLM_PROVIDERS.md and docs/GITHUB_TOKEN.md
# Open in VS Code → "Reopen in Container", or:
devcontainer up --workspace-folder .
```

Then, inside the container:

```bash
openhands --headless -t "your task here" --llm-config anthropic
```

Full walkthrough: [docs/SETUP.md](docs/SETUP.md).

## Multi-stage pipeline

For an idea to flow through conception → refinement → development → review
with only two points of human input (approving the spec, merging the final
PR), see [docs/PIPELINE.md](docs/PIPELINE.md).
# ruleset test Tue Jul 28 12:12:57 AM CEST 2026
