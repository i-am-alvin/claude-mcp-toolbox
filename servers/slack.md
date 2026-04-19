# Slack

## Why not the official `mcp.slack.com`

Slack launched an official MCP server in early 2026, but it's **unusable for personal/individual use**:

- **Does not support Dynamic Client Registration** — the `/.well-known/oauth-authorization-server` metadata does not advertise `registration_endpoint`. You must pre-register a Slack App's `client_id` and `client_secret`.
- **Unlisted apps are prohibited**. Per [Slack's policy](https://docs.slack.dev/ai/slack-mcp-server/): *"Only directory-published apps or internal apps may use MCP."* That means:
  - **Directory-published**: submit to the Slack App Directory, go through review — overkill for personal use.
  - **Internal / org-owned**: Enterprise Grid only. Pro/Plus/Business+ plans have no equivalent.

If your workspace is not on Enterprise Grid, you **cannot** use `mcp.slack.com`. Don't waste time building a Slack App for it.

## Solution: `korotovsky/slack-mcp-server` + user token

[`korotovsky/slack-mcp-server`](https://github.com/korotovsky/slack-mcp-server) (npm: `slack-mcp-server`) is a mature community Slack MCP that:

- Uses the Slack Web API directly (bypasses `mcp.slack.com` and its policy gate)
- Supports user tokens (`xoxp-`) — actions execute **as you**, not as a bot
- Is stdio-only — no OAuth proxy needed, just pass the token as an env var

**Critical distinction**: with a user token and `chat:write` on the **User Token Scopes** side (not Bot Token Scopes), messages you send appear with your name and avatar. Slack's audit log records them as your actions. If you want bot identity instead, use `SLACK_MCP_XOXB_TOKEN` with bot-scope `chat:write`.

## Setup

### 1. Create an unlisted Slack App (once per workspace)

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**
2. Name it `Claude MCP (<workspace>)`, pick the target workspace
3. Left sidebar: **OAuth & Permissions** → **User Token Scopes** (⚠️ *User*, not Bot):
   ```
   chat:write
   channels:history   groups:history   im:history   mpim:history
   channels:read      groups:read      im:read      mpim:read
   search:read.public search:read.private search:read.im search:read.mpim
   search:read.files  search:read.users
   users:read
   ```
4. Scroll up → **Install to Workspace** → Allow → copy the `User OAuth Token` (starts with `xoxp-`)

### 2. Add the MCP entry

```bash
./scripts/add-slack.sh <workspace> <xoxp-token>
```

Or manually:

```bash
mkdir -p ~/.cache/slack-mcp/<workspace>
claude mcp add slack-<workspace> -s user \
  -e SLACK_MCP_XOXP_TOKEN=<xoxp-...> \
  -e SLACK_MCP_USERS_CACHE=$HOME/.cache/slack-mcp/<workspace>/users.json \
  -e SLACK_MCP_CHANNELS_CACHE=$HOME/.cache/slack-mcp/<workspace>/channels.json \
  -e SLACK_MCP_ADD_MESSAGE_TOOL=true \
  -- npx -y slack-mcp-server --transport stdio
```

> Without `SLACK_MCP_ADD_MESSAGE_TOOL`, the server won't expose the `conversations_add_message` tool (write operations are opt-in by default for safety). Valid values: `true` (allow all channels), comma-separated channel IDs (allowlist), or `!C123,C456` (blocklist). A similar flag `SLACK_MCP_MARK_TOOL` gates the mark-as-read capability.

### 3. Verify

```bash
claude mcp list | grep slack-<workspace>
# slack-<workspace>: npx -y slack-mcp-server --transport stdio - ✓ Connected
```

Then restart Claude Code and call `mcp__slack-<workspace>__channels_list` to smoke-test.

## Gotchas

- **User Token Scopes vs Bot Token Scopes**: same scope name, different behavior depending on which column you put it in. User column + `xoxp-` = you. Bot column + `xoxb-` = the app. Mixing ends in confusion.
- **Cache path collision**: `slack-mcp-server`'s default users/channels cache goes to `~/.cache/slack-mcp/...` — multiple workspaces sharing this path clobber each other. Always set `SLACK_MCP_USERS_CACHE` and `SLACK_MCP_CHANNELS_CACHE` per workspace.
- **Token in `~/.claude.json`**: the `-e SLACK_MCP_XOXP_TOKEN=...` flag writes the token to that file. Treat it like `.npmrc` auth — local-only, don't commit, don't sync.
- **Token is bearer of your identity**: anyone with the `xoxp-` can act as you in Slack (send messages, read DMs, search private channels). Rotate via **OAuth & Permissions → Revoke Tokens** → **Reinstall to Workspace** if it leaks.
