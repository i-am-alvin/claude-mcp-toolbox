# claude-mcp-toolbox

Opinionated, tested patterns for managing **multiple workspaces** of the same MCP server (Notion / Slack / Google Workspace) in [Claude Code](https://claude.com/claude-code) — with per-workspace secret isolation, one-command setup, and documented workarounds for the quirks you hit along the way.

## Why this exists

Claude Code's built-in connectors bind to **one workspace per service**. If you have a personal Notion + a work Notion, or a personal Gmail + two work Google accounts, the built-in connectors can't handle it — you need separate MCP entries with isolated credentials.

This repo captures the patterns that actually work, end-to-end, including:

- Routing around broken OAuth redirect chains in built-in connectors
- Per-workspace token isolation (so workspace A's token doesn't overwrite workspace B's)
- Picking the right community server when the official one has policy restrictions
- Escaping programmatic-only failures by knowing which UI steps are genuinely unavoidable
- Port collision gotchas for servers that bind local HTTP for OAuth callback

## Supported servers

| Server | Why | Auth pattern |
|---|---|---|
| [Notion](servers/notion.md) | Built-in connector's OAuth callback is broken; one connector = one workspace | [`mcp-remote`](https://github.com/geelen/mcp-remote) + DCR, per-workspace `MCP_REMOTE_CONFIG_DIR` |
| [Slack](servers/slack.md) | Official `mcp.slack.com` forbids unlisted apps and doesn't support DCR | [`korotovsky/slack-mcp-server`](https://github.com/korotovsky/slack-mcp-server) + `xoxp-` user token |
| [Google Workspace](servers/google-workspace.md) | Covers Gmail + Calendar + Drive + Docs + Sheets in one server, with direct-to-Google OAuth | [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) + self-owned Desktop OAuth client |

## Quickstart

1. **Pick a server** from the table and open its playbook
2. **Follow the per-workspace setup** (prepare credentials, run the `add-*.sh` script)
3. **Restart Claude Code** — new MCP entries only take effect in fresh sessions
4. **Trigger auth** from the new session (for OAuth-based servers)

## Core pattern: `claude mcp add -s user`

All playbooks use this shape:

```bash
claude mcp add <server>-<workspace> -s user \
  -e <CONFIG_DIR_OR_TOKEN_ENV>=<per-workspace value> \
  -e <other env> \
  -- <binary> <args>
```

- **`-s user`**: persists to `~/.claude.json` (not per-project `.mcp.json`), so it's visible across every Claude Code session regardless of which directory you're in.
- **`<server>-<workspace>` naming**: `notion-personal`, `notion-work`, `slack-acme`, etc. The prefix + suffix scheme makes tool names predictable (`mcp__notion-work__search`) and lets you grep `claude mcp list` by workspace.
- **Per-workspace env**: token / credentials directory / port are all env vars — isolation comes from giving different values per MCP entry.

## File layout

```
claude-mcp-toolbox/
├── README.md                       # this file
├── servers/
│   ├── notion.md                   # Notion playbook
│   ├── slack.md                    # Slack playbook
│   └── google-workspace.md         # Google Workspace playbook
└── scripts/
    ├── add-notion.sh               # wrapper around `claude mcp add` for Notion
    ├── add-slack.sh                # ... for Slack
    └── add-google-workspace.sh     # ... for Google Workspace
```

Each script is thin — it lays out the flags correctly and points you at the next manual step. Read the corresponding playbook for the full context.

## Security notes

- Tokens and client secrets are written to `~/.claude.json` via `-e` flags. Treat this file like `~/.npmrc` — local-only, not in any dotfile repo.
- OAuth flows drop tokens to per-workspace directories under `~/.mcp-auth/`, `~/.gws-auth/`, `~/.cache/slack-mcp/`. These are `chmod 600` by default; don't chown/rsync them around casually.
- This repo contains **no secrets**. Every example uses `<workspace>` / `<token>` / `<client_id>` placeholders.

## Prerequisites

- Claude Code ≥ current stable
- [`mcp-remote`](https://github.com/geelen/mcp-remote) (Notion): `npm install -g mcp-remote`
- [`slack-mcp-server`](https://github.com/korotovsky/slack-mcp-server) (Slack): auto-fetched via `npx -y`
- [`uv`](https://github.com/astral-sh/uv) (Google Workspace): `brew install uv`
- [`gcloud`](https://cloud.google.com/sdk/docs/install) (Google Workspace): for GCP project/API/consent-screen setup
- [`gh`](https://cli.github.com/) (optional): only for cloning/forking this repo

## License

MIT
