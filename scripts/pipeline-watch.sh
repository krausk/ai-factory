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
# rubber-stamping its own work.
declare -A LLM_MODEL=(
    [conception]=anthropic/claude-sonnet-4-5-20250929
    [refinement]=anthropic/claude-sonnet-4-5-20250929
    [development]=anthropic/claude-sonnet-4-5-20250929
    [review]=openai/gpt-4.1
)
declare -A LLM_KEY_VAR=(
    [conception]=ANTHROPIC_API_KEY
    [refinement]=ANTHROPIC_API_KEY
    [development]=ANTHROPIC_API_KEY
    [review]=OPENAI_API_KEY
)

log() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG_DIR/watch.log"
}

process_stage() {
    local stage="$1"
    local service="agent-$stage"
    local model="${LLM_MODEL[$stage]}"
    local key_var="${LLM_KEY_VAR[$stage]}"

    local ids
    ids=$(beans list --tag "stage:$stage" --status todo -q || true)
    [ -z "$ids" ] && return 0

    while IFS= read -r id; do
        [ -z "$id" ] && continue
        log "Claiming $id for stage:$stage"
        beans update "$id" -s in-progress

        local run_log="$LOG_DIR/${id}-${stage}-$(date +%s).log"
        log "Running $service (model=$model) for $id, logging to $run_log"

        if docker compose exec -T -e BEAN_ID="$id" "$service" bash -c "
            export LLM_MODEL='$model'
            export LLM_API_KEY=\"\$$key_var\"
            openhands --headless --override-with-envs -f 'pipeline/roles/$stage.md'
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
