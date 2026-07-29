#!/bin/bash
# One-time setup, run once when the container is first created
# (devcontainer.json: postCreateCommand). Not re-run on every start —
# that's what postStartCommand/init-firewall.sh is for.
set -euo pipefail

cd /workspace

echo "== Beans =="
if [ ! -f .beans.yml ]; then
    echo "No .beans.yml found, running 'beans init'..."
    beans init
    # `beans init` defaults the bean-ID prefix to the current directory's
    # basename — which inside this container is always "workspace" (the
    # fixed mount point), regardless of the actual repo name. Repoint it at
    # the git remote's repo name instead, so bean IDs (and the branches
    # named after them) read as e.g. "ai-factory-1234", not "workspace-1234".
    repo_name=$(basename -s .git "$(git config --get remote.origin.url 2>/dev/null || true)" 2>/dev/null || true)
    if [ -n "$repo_name" ]; then
        sed -i -E "s/^([[:space:]]*prefix:[[:space:]]*).*/\1${repo_name}-/" .beans.yml
        echo "Set bean ID prefix to '${repo_name}-' (from git remote origin)."
    fi
else
    echo ".beans.yml already present, skipping 'beans init'."
fi

echo
echo "== Agent instructions =="
if [ ! -f AGENTS.md ]; then
    echo "No AGENTS.md found in the target repo, copying template..."
    cp /usr/local/share/ai-factory/AGENTS.md.template AGENTS.md
else
    echo "AGENTS.md already present, leaving it as-is."
fi

echo
echo "== GitHub CLI =="
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token
    if [ -n "${GITHUB_USERNAME:-}" ]; then
        git config --global user.name "$GITHUB_USERNAME"
    fi
    gh auth status || true
else
    echo "GITHUB_TOKEN is not set — 'gh' will not be authenticated."
    echo "See docs/GITHUB_TOKEN.md to create one, then add it to .env and rebuild."
fi

echo
echo "== Playwright browsers =="
# No --with-deps: the base image (mcr.microsoft.com/playwright/python)
# already bakes in every OS-level dependency the browsers need, and
# --with-deps would try to `apt install` them itself, which needs root the
# agent user deliberately doesn't have (see .devcontainer/Dockerfile). This
# just verifies/completes the browser binaries themselves, no root required.
python3 -m playwright install chromium

echo
echo "Setup complete."
