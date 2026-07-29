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
    # `gh` already authenticates every call with GITHUB_TOKEN/GH_TOKEN from
    # the environment automatically (no `gh auth login` needed) — and while
    # that env var is set, `gh auth login --with-token` actively refuses to
    # run ("the value of the GITHUB_TOKEN environment variable is being
    # used for authentication..."), which under `set -e` used to abort this
    # whole script. Just report status instead of trying to log in.
    if [ -n "${GITHUB_USERNAME:-}" ]; then
        git config --global user.name "$GITHUB_USERNAME"
        # GitHub's own noreply address for this user — commits need *some*
        # user.email or they fail outright, and this keeps a real address
        # out of the target repo's history.
        git config --global user.email "${GITHUB_USERNAME}@users.noreply.github.com"
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
