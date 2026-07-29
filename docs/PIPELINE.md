# Multi-Stage Agent Pipeline

A rough idea can move through four specialized stages — **conception →
refinement → development → review** — with a human touching it at exactly
two points: approving the spec before code gets written, and merging the
final PR. Everything else is unsupervised.

## Bean state machine

Pipeline position lives in **tags** (Beans' status field is a fixed enum —
`todo/draft/in-progress/completed/scrapped` — with no native concept of
"stage", so stage is just another tag):

| Tag | Status | Meaning | Set by |
|---|---|---|---|
| `stage:conception` | `todo` | New idea, ready to work | you, when seeding an idea |
| `stage:conception` | `in-progress` | Watcher claimed it | the watcher (a lock, so it isn't picked up twice) |
| `stage:refinement` | `todo` | Ready for refinement | conception agent's own last action |
| `stage:refinement` | `completed` | Spec ready, **awaiting your approval** | refinement agent (does not auto-advance) |
| `stage:development` | `todo` | Approved, ready to code | **you**, via `scripts/approve-spec.sh` — or a review bounce-back |
| `stage:review` | `todo` | PR opened, ready to review | development agent's own last action |
| `stage:review` | `completed` | Approved by the review agent, **awaiting your merge** | review agent |
| `needs-human` *(not a stage)* | — | Iteration cap hit, or the agent got stuck | review or development agent |

The watcher (`scripts/pipeline-watch.sh`) only ever does one mutation: on
finding `(tag, status=todo)` for one of the four stage tags, it flips status
to `in-progress` (claiming it, so a second poll cycle doesn't double-invoke)
and runs that stage's agent. Every other transition is the agent's own
final instructed action — see `pipeline/roles/*.md` for exactly what each
stage does before handing off.

**The one mandatory checkpoint**: refinement never advances the bean itself.
It marks its own work `completed` and stops. Nothing else happens until you
read the spec and run `scripts/approve-spec.sh <bean-id>`.

**Iteration cap**: if review requests changes 3 times without approving,
it stops bouncing the bean back to development and tags it `needs-human`
instead — which drops it out of every watcher rule. Re-tag it manually
(e.g. back to `stage:development`/`todo`) once you've looked at why it's
stuck.

## Setup

1. **Bring up the pipeline containers** (idempotent, safe to re-run):
   ```bash
   scripts/pipeline-up.sh
   ```
   This starts the four `agent-*` compose services and runs the firewall
   init + auth setup that VS Code's Dev Containers tooling would otherwise
   do automatically — plain `docker compose up` doesn't trigger
   `postCreateCommand`/`postStartCommand`, so headless use needs this
   explicit step.

2. **Set up the review agent's separate GitHub identity** (see below) and
   put its token in `.env.review` (copy from `.env.review.example`).

3. **Start the watcher**:
   ```bash
   scripts/pipeline-watch.sh              # loops forever, polls every 60s
   scripts/pipeline-watch.sh --once        # single pass, useful for testing
   scripts/pipeline-watch.sh --interval 30
   ```
   Run this somewhere long-lived (a terminal you leave open, `tmux`/`screen`,
   or a systemd user unit) — it's a host-side script, not something that
   runs inside a container. Logs go to `pipeline/logs/`.

## Seeding an idea

```bash
beans create "Short title" -t feature -d "A sentence or two describing the idea" \
  --tag stage:conception -s todo
```

The next watcher pass picks it up.

## Review agent identity (manual, one-time)

The review stage approves PRs using a **second GitHub account**, distinct
from whatever account the development agent uses — this is what makes its
approval a real gate rather than the same identity approving its own work
(which GitHub blocks anyway) or a rubber stamp. Setting this up needs a
couple of manual steps I can't do for you:

1. Create a second, free GitHub account (e.g. `yourname-reviewbot`).
2. Add it as a collaborator on this repo (Settings → Collaborators) — or
   tell me its username and I can send the invite via `gh api`.
3. Generate a fine-grained PAT for it (same process as
   `docs/GITHUB_TOKEN.md`, just on the bot account), scoped to just this
   repo, with:
   - Contents: Read
   - Pull requests: Read and write
   - Metadata: Read (auto-selected)
4. `cp .env.review.example .env.review` and fill in that token +
   the bot's username.

Branch protection on `main` is a **Ruleset** (not classic branch
protection): it requires 1 approving review for everyone, but your own
GitHub account is on the bypass list, so your own PRs still merge without
needing a second approver — only the pipeline's PRs (opened under your main
token's identity) strictly need the review agent's approval.

## Models per stage

The installed OpenHands CLI has no `config.toml`/`--llm-config` mechanism —
LLM selection is via `--override-with-envs` plus `LLM_MODEL`/`LLM_API_KEY`
env vars (see docs/LLM_PROVIDERS.md). `scripts/pipeline-watch.sh` maps each
stage to a model this way: conception and refinement use Anthropic; review
deliberately uses OpenAI instead — reviewing code with a different model
than the one that wrote it is a real, if partial, defense against a model
rubber-stamping its own work. Development runs against a local llama-server
on the host GPU (`LLM_BASE_URL=http://host.docker.internal:8080/v1`) instead
of a paid API, since it's higher-volume, more mechanical work than spec
writing or review. Change the `LLM_MODEL` / `LLM_KEY_VAR` / `LLM_BASE_URL`
maps at the top of the script if you want a different split.

## Limitations / not built (yet)

- **One bean through the pipeline at a time.** All four stages share the
  same workspace mount. Running multiple beans through development/review
  concurrently would need per-bean git worktrees, the same pattern as
  `docs/MULTI_AGENT.md` — not built here.
- **No timeout recovery.** If an agent crashes mid-run, its bean is left at
  `status: in-progress` with nothing to notice or retry it — you'll need to
  spot this manually (e.g. `beans list --status in-progress`) and reset the
  status yourself.
