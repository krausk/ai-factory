# Firewall

The agent container runs with a **default-deny outbound firewall**: unless a
domain is explicitly allowed, the agent can't reach it. This is what makes
"unsupervised" safe enough to actually run — an agent that goes off-script
(or is fed a prompt-injection payload while browsing) can't exfiltrate data
or pull in arbitrary code from the open internet.

## How it works

`.devcontainer/init-firewall.sh` runs as root (via a narrowly-scoped sudoers
entry — the agent user can run *only* this exact script as root, nothing
else) every time the container starts (`devcontainer.json`'s
`postStartCommand`, gated by `waitFor` so the container isn't considered
ready until the firewall is confirmed working). It:

1. Flushes the `filter` table's iptables rules and rebuilds an `ipset`
   allowlist called `allowed-domains`. (It deliberately leaves the `nat`
   table alone — Docker's own embedded-DNS rules live there, and an earlier
   version of this script that tried to flush/restore them had a quoting
   bug that silently broke DNS for the whole container.)
2. Adds GitHub's published IP ranges (fetched fresh from
   `https://api.github.com/meta`).
3. Resolves and adds every domain listed in
   `.devcontainer/allowed-domains.txt`.
4. Sets the default policy on `INPUT`/`FORWARD`/`OUTPUT` to `DROP`, then
   allows only: loopback, DNS, established/related connections, and traffic
   to the `allowed-domains` ipset. Everything else gets an explicit
   `REJECT` (fast, clear failure — not a silent hang).
5. **Locks down IPv6 separately**: nothing is allowlisted over IPv6 (all
   the resolving above is IPv4-only), so IPv6 is simply denied outright
   (loopback excepted) rather than left at its default-open policy — a
   host/network that happens to route IPv6 for the container would
   otherwise be a silent, total bypass of everything above.
6. **Self-tests itself**: confirms `https://example.com` is blocked and
   `https://api.github.com/zen` succeeds. If either check fails, the script
   exits non-zero and the container fails to start — a broken firewall
   fails loudly instead of silently running unprotected.

## Adding a domain

Edit `.devcontainer/allowed-domains.txt` (one domain per line, `#` for
comments) — it's a live, bind-mounted file, not baked into the image, so no
rebuild is needed. Then either:

- Restart the container, or
- Run `sudo /usr/local/bin/init-firewall.sh` again from inside it.

The script re-resolves every domain in the file each time it runs.

## Why the script itself can't just be edited the same way

`init-firewall.sh` is copied into the image at build time, owned by root,
and not writable by the `agent` user (`chmod 750`). This is deliberate: the
agent's sudo grant is `NOPASSWD: /usr/local/bin/init-firewall.sh` with no
wildcard, so if the script itself were live-editable, that sudo grant would
amount to unrestricted root access. The domain list is treated as pure data
(hostnames to resolve), so it's safe to let it be edited live — worst case
of a compromised edit is the agent narrowing or widening its *own* sandbox,
not arbitrary code execution as root.

## Known limitation

The allowlist works at the **IP layer** (`ipset`), resolved once per
container start. Two consequences:

- If an allowed and a disallowed hostname happen to share IP infrastructure
  (common behind large CDNs), the disallowed one may incidentally work too.
  For anything security-critical, prefer domains with dedicated
  infrastructure, or add a SNI-aware proxy (e.g. mitmproxy/Squid with an SNI
  ACL) in front if that risk matters for your use case.
- Domains behind IPs that rotate frequently may need a restart to pick up a
  new address, or a wider CIDR allow instead of an exact-IP one.
