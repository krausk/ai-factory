# LLM Provider Setup

The agent runtime (OpenHands) talks to models through LiteLLM, which is
provider-agnostic. The installed OpenHands CLI (v1.16.0 / SDK v1.21.0) does
**not** use a `config.toml` or a `--llm-config` flag — the actual mechanism
is the `--override-with-envs` flag plus three environment variables it reads
at invocation time: `LLM_MODEL`, `LLM_API_KEY`, and optionally
`LLM_BASE_URL`. (`openhands --help` is the source of truth here — CLI flags
have changed across OpenHands versions, so re-check it if this ever seems
wrong.) By default OpenHands ignores environment variables entirely; you
must pass `--override-with-envs` for these to take effect.

You only need to set up the provider(s) you actually intend to use.

## Anthropic (Claude)

1. Create/sign in at [console.anthropic.com](https://console.anthropic.com).
2. Go to **API Keys** and create a new key.
3. Put it in `.env`:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```
4. To run a task with it:
   ```bash
   LLM_MODEL=anthropic/claude-sonnet-4-5-20250929 LLM_API_KEY="$ANTHROPIC_API_KEY" \
     openhands --headless --override-with-envs -t "your task here"
   ```

## OpenAI

1. Create/sign in at [platform.openai.com](https://platform.openai.com).
2. Go to **API keys** and create a new secret key.
3. Put it in `.env`:
   ```
   OPENAI_API_KEY=sk-...
   ```
4. To run a task with it:
   ```bash
   LLM_MODEL=openai/gpt-4.1 LLM_API_KEY="$OPENAI_API_KEY" \
     openhands --headless --override-with-envs -t "your task here"
   ```

## Notes

- `LLM_MODEL` follows LiteLLM's `<provider>/<model>` naming; `LLM_API_KEY` is
  just whichever provider's key matches that prefix — OpenHands doesn't read
  `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` directly, those are only this repo's
  own naming for where the raw secrets live in `.env`.
- `scripts/pipeline-watch.sh` does this mapping automatically per pipeline
  stage (see `docs/PIPELINE.md`) — the above is for ad-hoc use of the
  generic `agent` service.
- Rebuilding the container isn't required after changing `.env` — just
  restart it (env vars are re-read from `env_file` on container start).
