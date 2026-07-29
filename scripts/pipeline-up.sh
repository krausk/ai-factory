#!/bin/bash
# Brings up the four pipeline containers and runs the setup that VS Code's
# Dev Containers tooling would normally do automatically (postCreateCommand /
# postStartCommand) — plain `docker compose up` doesn't run those, they only
# fire through the devcontainer CLI/extension, so headless/background use
# needs this explicit step. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICES=(agent-conception agent-refinement agent-development agent-review)

echo "Starting pipeline containers..."
docker compose up -d "${SERVICES[@]}"

for svc in "${SERVICES[@]}"; do
    echo
    echo "=== $svc: firewall ==="
    docker compose exec -T --user root "$svc" /usr/local/bin/init-firewall.sh

    echo "=== $svc: post-create (beans init check, gh auth, playwright browsers) ==="
    docker compose exec -T "$svc" bash /usr/local/share/ai-factory/post-create.sh
done

echo
echo "Pipeline containers are up. Start scripts/pipeline-watch.sh to begin processing beans."
