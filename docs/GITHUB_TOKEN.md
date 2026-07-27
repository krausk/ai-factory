# GitHub Token Setup

The agent needs GitHub access to clone/push/open PRs. Since it runs
unsupervised, prefer the most narrowly-scoped, shortest-lived credential that
still gets the job done.

## Recommended: fine-grained personal access token

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Repository access**: select only the repo(s) this agent will touch —
   never "All repositories" for an unsupervised agent.
3. **Permissions** (Repository permissions):
   - Contents: Read and write
   - Pull requests: Read and write
   - Metadata: Read-only (required, auto-selected)
   - Add Issues: Read and write if the agent should also file/update issues.
4. Set an **expiration** (90 days or less; shorter for anything higher-risk).
   Rotate it before it expires — the container will simply fail `gh auth`
   checks until you do, which is the point (a token that silently never
   expires is a bigger liability for something running unattended).
5. Generate, copy the token (`github_pat_...`), and put it in `.env`:
   ```
   GITHUB_TOKEN=github_pat_...
   GITHUB_USERNAME=your-username
   ```

`post-create.sh` runs `gh auth login --with-token` using this value on
container creation, and sets `git config user.name` from `GITHUB_USERNAME`.

## Advanced / team scale: GitHub App installation tokens

If you're running many agents against many repos, consider registering a
dedicated **GitHub App** instead of managing PATs per agent:

- The App gets its own identity (commits/PRs are attributed to the App/bot,
  not a human account).
- Installation access tokens are minted on demand and expire after **1
  hour**, scoped to exactly the repos the App is installed on.
- Flow: sign a JWT with the App's private key → exchange it for an
  installation access token → use that token wherever a PAT would go (`gh
  auth login --with-token`, git remote URLs, REST/GraphQL calls).
- This needs a small amount of supporting automation (something has to mint
  and refresh the hourly token and drop it into each container's `.env` or
  inject it directly) — worth the extra setup once you have several agents
  running continuously, overkill for a single one.

See GitHub's docs on
[registering a GitHub App](https://docs.github.com/en/apps/creating-github-apps)
and
[generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
if you want to go this route.

## Avoid

- Classic PATs — no per-repo scoping, broad blast radius if a container is
  compromised or a prompt-injection payload the agent encounters tries to
  exfiltrate it.
- Committing `.env` — it's gitignored by default; double-check
  `git status` never shows it as staged.
