# LLM Provider Setup

The agent runtime (OpenHands) talks to models through LiteLLM, which is
provider-agnostic. `config.toml` at the repo root defines two named profiles;
pick one at run time with `--llm-config anthropic` or `--llm-config openai`.
You only need to set up the provider(s) you actually intend to use.

## Anthropic (Claude)

1. Create/sign in at [console.anthropic.com](https://console.anthropic.com).
2. Go to **API Keys** and create a new key.
3. Put it in `.env`:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```

`config.toml`'s `[llm.anthropic]` profile references
`anthropic/claude-sonnet-4-5-20250929` — LiteLLM reads `ANTHROPIC_API_KEY`
from the environment automatically based on the `anthropic/` model prefix,
so there's nothing else to configure. Check
[console.anthropic.com](https://console.anthropic.com) for current model
names/pricing if you want to switch models.

## OpenAI

1. Create/sign in at [platform.openai.com](https://platform.openai.com).
2. Go to **API keys** and create a new secret key.
3. Put it in `.env`:
   ```
   OPENAI_API_KEY=sk-...
   ```

`config.toml`'s `[llm.openai]` profile references `openai/gpt-4.1` — same
auto-detection via the `openai/` prefix and the `OPENAI_API_KEY` env var.

## Notes

- Never put real API keys in `config.toml` itself — that file is tracked in
  git. Keys only ever belong in `.env` (gitignored).
- Rebuilding the container isn't required after changing `.env` — just
  restart it (env vars are re-read from `env_file` on container start).
