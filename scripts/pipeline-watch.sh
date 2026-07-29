#!/bin/bash
# Polls Beans for the four pipeline stage tags and, for each bean that's
# ready (tag stage:<X>, status todo), claims it and execs the matching
# stage's OpenHands run in its dedicated container. See docs/PIPELINE.md.
#
# Runs on the HOST (not in a container) — the host already has `beans` and
# `gh` installed and can talk to Docker directly, so there's no need for a
# fifth orchestrator container with a mounted Docker socket (a meaningfully
# larger security surface for no real benefit here).
#
# Usage:
#   scripts/pipeline-watch.sh            # loop forever, poll every 60s
#   scripts/pipeline-watch.sh --once      # single pass, then exit (testing)
#   scripts/pipeline-watch.sh --interval 30
set -euo pipefail
cd "$(dirname "$0")/.."

# Beans data lives in TARGET_REPO_PATH (beans init runs there, in-container —
# docs/BEANS.md), not in this (ai-factory) repo, so every `beans` invocation
# below must run with that as its cwd. Read just this one var out of .env
# rather than sourcing the whole file, so provider secrets never touch this
# host script's environment or process list.
TARGET_REPO_PATH=$(grep -E '^TARGET_REPO_PATH=' .env | head -1 | cut -d= -f2-)
if [ -z "$TARGET_REPO_PATH" ] || [ ! -d "$TARGET_REPO_PATH" ]; then
    echo "TARGET_REPO_PATH is unset or doesn't exist (checked .env) — set it first (docs/SETUP.md)." >&2
    exit 1
fi

INTERVAL=60
ONCE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --once) ONCE=true; shift ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

LOG_DIR="pipeline/logs"
mkdir -p "$LOG_DIR"

# The installed OpenHands CLI has no config.toml/--llm-config mechanism —
# LLM selection is via `--override-with-envs` plus LLM_MODEL/LLM_API_KEY env
# vars (see docs/LLM_PROVIDERS.md; re-check `openhands --help` if this ever
# breaks, CLI flags have changed across OpenHands versions before). Map each
# stage to a model and to *which* of the container's own already-present
# env vars (from env_file: .env) holds the matching key — the actual key
# value is resolved inside the container's shell, never touching this host
# script or its process list. Review deliberately uses a different provider
# than development — reviewing code with a different model than the one
# that wrote it is a real, if partial, defense against the same model
# rubber-stamping its own work. Development runs against a local llama-server
# (docs/LLM_PROVIDERS.md) instead of a paid API — LLM_BASE_URL is only set
# for stages that need one, everything else talks to the provider's default.
declare -A LLM_MODEL=(
    [conception]=anthropic/claude-sonnet-4-5-20250929
    [refinement]=anthropic/claude-sonnet-4-5-20250929
    [development]=openai/gemma-4-31B-it-QAT-Q4_0.gguf
    [review]=openai/gpt-4.1
)
declare -A LLM_KEY_VAR=(
    [conception]=ANTHROPIC_API_KEY
    [refinement]=ANTHROPIC_API_KEY
    [development]=LOCAL_LLM_API_KEY
    [review]=OPENAI_API_KEY
)
declare -A LLM_BASE_URL=(
    [development]=http://host.docker.internal:8080/v1
)

log() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG_DIR/watch.log"
}

process_stage() {
    local stage="$1"
    local service="agent-$stage"
    local model="${LLM_MODEL[$stage]}"
    local key_var="${LLM_KEY_VAR[$stage]}"
    local base_url="${LLM_BASE_URL[$stage]:-}"

    local ids
    ids=$(cd "$TARGET_REPO_PATH" && beans list --tag "stage:$stage" --status todo -q || true)
    [ -z "$ids" ] && return 0

    local extra_env=()
    if [ -n "$base_url" ]; then
        extra_env=(-e "LLM_BASE_URL=$base_url")
    fi

    while IFS= read -r id; do
        [ -z "$id" ] && continue
        log "Claiming $id for stage:$stage"
        (cd "$TARGET_REPO_PATH" && beans update "$id" -s in-progress)

        local run_log="$LOG_DIR/${id}-${stage}-$(date +%s).log"
        log "Running $service (model=$model) for $id, logging to $run_log"

        if docker compose exec -T -e BEAN_ID="$id" "${extra_env[@]}" "$service" bash -c "
            export LLM_MODEL='$model'
            export LLM_API_KEY=\"\$$key_var\"
            openhands --headless --override-with-envs -f '/usr/local/share/ai-factory/pipeline-roles/$stage.md'
        " >"$run_log" 2>&1; then
            log "$id: $stage run finished (see $run_log)"
        else
            log "$id: $stage run FAILED (see $run_log) — left at status in-progress for manual recovery"
        fi
    done <<<"$ids"
}

run_once() {
    for stage in conception refinement development review; do
        process_stage "$stage"
    done
}

if [ "$ONCE" = true ]; then
    run_once
else
    log "Starting watch loop (interval: ${INTERVAL}s). Ctrl-C to stop."
    while true; do
        run_once
        sleep "$INTERVAL"
    done
fi
