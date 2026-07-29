# syntax=docker/dockerfile:1

# ---- Stage 1: build the Beans CLI (github.com/hmans/beans) ----
# `go install` is used instead of downloading a release tarball because it
# doesn't require guessing/tracking release-asset filenames across versions.
FROM golang:1.24-bookworm AS beans-builder
RUN go install github.com/hmans/beans@latest

# ---- Stage 2: agent runtime ----
# Official Playwright Python image: ships Chromium/Firefox/WebKit plus every
# OS-level dependency they need, so browser automation works out of the box.
# Pinned deliberately — bump this tag on purpose, don't float on `latest`,
# since browser-binary updates can silently change rendering/behavior.
FROM mcr.microsoft.com/playwright/python:v1.52.0-noble

# The base Ubuntu Noble image already ships a non-root user "ubuntu" at
# uid/gid 1000 — deliberately reused here rather than creating a new user,
# since 1000 is the near-universal default UID for a Linux developer's own
# account, and matching it is what makes the bind-mounted /workspace (owned
# by the host user) actually writable by the container's non-root user.
# Override via --build-arg if your host user's UID/GID isn't 1000.
ARG NODE_MAJOR=20
ARG USERNAME=ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
        iptables \
        ipset \
        iproute2 \
        dnsutils \
        aggregate \
        curl \
        wget \
        git \
        jq \
        sudo \
        ca-certificates \
        gnupg \
        unzip \
        pipx \
    && rm -rf /var/lib/apt/lists/*

# Node.js + npm, for JS/TS tooling and tests the agent may need.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI, used for `gh auth login`, `gh pr create`, etc.
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# The base image ships the Playwright *browser binaries* (/ms-playwright)
# but not the Python package itself — install it system-wide, pinned to
# match the base image's driver version exactly (mismatches between the
# `playwright` package and the pre-downloaded browsers cause launch
# failures). --break-system-packages is safe here: this is a single-purpose
# container image, not a shared host Python.
RUN pip3 install --break-system-packages --no-cache-dir playwright==1.52.0

# Beans CLI, built in stage 1.
COPY --from=beans-builder /go/bin/beans /usr/local/bin/beans

# Firewall script: root-owned and not writable by the non-root agent user,
# so the scoped sudoers NOPASSWD grant below can't be leveraged into
# arbitrary root code execution. See init-firewall.sh's own comments on
# where the (user-editable) domain list is read from instead.
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod 750 /usr/local/bin/init-firewall.sh

# AGENTS.md template: baked into the image (rather than bind-mounted, since
# /workspace is the *target* repo, not this one) so post-create.sh can copy
# it into a target repo that doesn't already have its own AGENTS.md.
COPY .devcontainer/AGENTS.md.template /usr/local/share/ai-factory/AGENTS.md.template

# Sudo scoped to exactly the firewall script — nothing else — for the
# non-root user the agent actually runs as. The base image's "ubuntu" user
# is a member of the "sudo" group by default (full ALL:ALL sudo rights);
# that's currently unexploitable only because the account has no password
# set, which is too fragile a safety margin for something meant to run
# unsupervised — drop the group membership explicitly so the *only* sudo
# access available is the one line below.
RUN deluser "$USERNAME" sudo \
    && echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/"$USERNAME"-firewall \
    && chmod 440 /etc/sudoers.d/"$USERNAME"-firewall \
    && mkdir -p /home/"$USERNAME"/.local/bin \
    && chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
USER $USERNAME
WORKDIR /workspace

# OpenHands — the agent runtime itself. Requires Python 3.12+ (satisfied by
# this base image). Note: the PyPI package was renamed from `openhands-ai`
# to `openhands` — re-verify against https://docs.openhands.dev if this
# ever breaks again, since it's changed once already. Installed as the
# non-root $USERNAME (not root) — pipx installs into the invoking user's
# own home directory, and $USERNAME is the user devcontainer.json actually
# runs commands as (remoteUser), so installing as root here would leave the
# `openhands` command invisible to the user who needs it.
RUN pipx install openhands
