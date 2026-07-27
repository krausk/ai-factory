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
else
    echo ".beans.yml already present, skipping 'beans init'."
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
