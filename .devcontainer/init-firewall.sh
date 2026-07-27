#!/bin/bash
# Default-deny egress firewall for the agent container.
#
# Adapted from Anthropic's own claude-code reference devcontainer firewall
# (anthropics/claude-code, .devcontainer/init-firewall.sh). Locks outbound
# traffic down to an explicit allowlist (GitHub's published IP ranges, plus
# every domain in .devcontainer/allowed-domains.txt), then self-tests that
# the lockdown actually works before letting the container be considered
# "ready" (devcontainer.json's waitFor: postStartCommand blocks on this).
#
# Must run as root (via sudo, see the scoped sudoers entry in the Dockerfile).

set -euo pipefail

# This script itself is baked into the image (root-owned, not writable by the
# agent user — see the Dockerfile) so the scoped NOPASSWD sudo grant can't be
# abused to run arbitrary code as root. The domain list, by contrast, is read
# from the *live* bind-mounted workspace so it can be edited without a rebuild
# — it's treated purely as data (a list of hostnames to resolve), not code.
ALLOWED_DOMAINS_FILE="/workspace/.devcontainer/allowed-domains.txt"

echo "Starting firewall initialization..."

# --- Flush existing rules ---
# Only the filter table is touched. Docker sets up its own nat-table rules
# inside this container's network namespace (notably the embedded-DNS
# redirect to 127.0.0.11) — flushing/restoring the nat table ourselves is
# unnecessary (our allowlist is enforced entirely via the filter table's
# OUTPUT chain + the allowed-domains ipset) and fragile: an earlier version
# of this script tried to capture and replay those nat rules, and a subtle
# quoting bug in that replay silently broke DNS resolution for the whole
# container. Leaving the nat table alone sidesteps that class of bug
# entirely and isn't dependent on Docker's internal rule format.
iptables -F
iptables -X
ipset destroy allowed-domains 2>/dev/null || true

# --- Bootstrap rules needed before lockdown ---
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT

# SSH (outbound, e.g. git+ssh)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# --- Build the allowlist ipset ---
ipset create allowed-domains hash:net

# GitHub's published IP ranges (git, api, web) — aggregated to minimize entries.
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --max-time 10 https://api.github.com/meta)
if echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
    echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | \
        grep -E '^[0-9a-fA-F.:/]+$' | \
        aggregate -q | \
    while read -r cidr; do
        if [[ "$cidr" =~ ^[0-9./]+$ ]]; then
            ipset add allowed-domains "$cidr" 2>/dev/null || true
        fi
    done
else
    echo "WARNING: could not fetch/parse GitHub IP ranges; github.com will be resolved as a plain domain below instead." >&2
fi

# Domains resolved via DNS (single-IP snapshot at container-start time).
add_domain() {
    local domain="$1"
    local ip
    ip=$(dig +time=5 +tries=2 +short A "$domain" 2>/dev/null | tail -n1)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ipset add allowed-domains "$ip" 2>/dev/null || true
        echo "  allowed: $domain -> $ip"
    else
        echo "  WARNING: could not resolve $domain, skipping" >&2
    fi
}

echo "Resolving allowed domains from $ALLOWED_DOMAINS_FILE..."
if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        domain="$(echo "$line" | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$domain" ] && continue
        add_domain "$domain"
    done < "$ALLOWED_DOMAINS_FILE"
else
    echo "WARNING: $ALLOWED_DOMAINS_FILE not found, no extra domains allowed" >&2
fi

# github.com itself (not just api.github.com) in case the meta-IP fetch above failed.
add_domain "github.com"

# --- Allow the Docker host's subnet (VS Code server / compose networking) ---
HOST_IP=$(ip route | awk '/default/ { print $3 }')
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed -E 's/\.[0-9]+$/.0\/24/')
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
    echo "Allowed host network: $HOST_NETWORK"
fi

# --- Lock down default policy ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Re-allow established/related so responses to already-permitted traffic pass.
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# The core allowlist rule.
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicit reject (not silent drop) for everything else, for fast failure feedback.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# --- IPv6: deny everything except loopback ---
# Nothing in this setup is allowlisted over IPv6 (GitHub ranges and
# allowed-domains are resolved/added as IPv4 only), so rather than maintain
# a parallel ip6tables allowlist, just close IPv6 off entirely. Without
# this, a host/network that happens to route IPv6 for the container would
# have a silent, totally unrestricted bypass of the firewall above.
ip6tables -F
ip6tables -X
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

echo "Firewall rules applied. Running self-test..."

# --- Self-test: deny case must fail, allow case must succeed ---
if curl --max-time 5 -s https://example.com >/dev/null 2>&1; then
    echo "ERROR: firewall self-test FAILED — https://example.com should have been blocked but succeeded." >&2
    exit 1
fi
echo "  OK: blocked https://example.com as expected"

if ! curl --max-time 5 -s https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: firewall self-test FAILED — https://api.github.com/zen should have been reachable but failed." >&2
    exit 1
fi
echo "  OK: reached https://api.github.com/zen as expected"

echo "Firewall initialization complete."
