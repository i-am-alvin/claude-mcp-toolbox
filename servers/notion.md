# Notion

## Why not the built-in connector

Claude Code ships with a managed Notion connector (`mcp.notion.com/mcp`) that's **broken for us** in two ways:

1. **OAuth callback goes through `mcp.notion.com/callback`** which returns 500 Internal Server Error. Result: you click "Authorize" and land on an error page, no token written.
2. **Token refresh bug** — when the metadata discovery endpoint fails, the internal `_doRefresh` function doesn't fall back to cached metadata. Tokens die after their lifetime expires.
3. **One connector = one workspace** — you can't add two Notion workspaces via the built-in connector, even if both OAuth's complete successfully.

Related issues: [`makenotion/notion-mcp-server#167`](https://github.com/makenotion/notion-mcp-server/issues/167), [`anthropics/claude-code#44416`](https://github.com/anthropics/claude-code/issues/44416).

## Solution: `mcp-remote` + per-workspace config dir

[`mcp-remote`](https://github.com/geelen/mcp-remote) is a local OAuth proxy that forwards MCP traffic to a remote stdio-less server. It supports the `MCP_REMOTE_CONFIG_DIR` env var for isolating token storage per workspace.

**Do not use `mcp-stdio`** — it only has a `$HOME` hack for isolation and no first-class multi-workspace support.

## Setup

### 1. Install `mcp-remote`

```bash
npm install -g mcp-remote
```

### 2. Add the MCP entry (once per workspace)

```bash
./scripts/add-notion.sh <workspace>
```

Or manually:

```bash
claude mcp add notion-<workspace> -s user \
  -e MCP_REMOTE_CONFIG_DIR=$HOME/.mcp-auth/notion-<workspace> \
  -- mcp-remote https://mcp.notion.com/mcp
```

### 3. Do the OAuth handshake (once per workspace)

Critical: **do not run `claude mcp list` before the handshake completes.** That command's health check spawns a zombie `mcp-remote` process which races with the manual OAuth.

In a regular terminal (not Claude Code):

```bash
# Make sure the browser is logged in to the intended Notion workspace, or use an incognito window
MCP_REMOTE_CONFIG_DIR=$HOME/.mcp-auth/notion-<workspace> mcp-remote https://mcp.notion.com/mcp
```

1. Browser auto-opens Notion authorization page
2. Verify the workspace → Grant
3. Browser shows "Authorization successful"
4. **Wait ~5 seconds** for token write (Ctrl+C too early leaves half-state with `client_info.json` but no `tokens.json`)
5. Ctrl+C to stop `mcp-remote`

### 4. Verify

```bash
ls ~/.mcp-auth/notion-<workspace>/mcp-remote-*/
# Should list: <hash>_client_info.json, <hash>_tokens.json
```

Then `claude mcp list` should show `notion-<workspace>: ... - ✓ Connected`.

## How it works

- The built-in connector's OAuth `redirect_uri` routes through `mcp.notion.com/callback` (broken). `mcp-remote` instead uses `http://localhost:<auto-port>/oauth/callback`, cutting out the middleman.
- Token is stored at `~/.mcp-auth/<config-dir-name>/mcp-remote-<version>/<url-hash>_tokens.json` and auto-refreshed on demand.
- The URL hash is derived from the server URL, so using a different `MCP_REMOTE_CONFIG_DIR` per workspace is what keeps tokens isolated — without it, the second workspace's auth overwrites the first.

## Gotchas

- **Env var broken across lines**: `ZSH_VAR=xxx\ncommand` (two lines) doesn't set the env var correctly; use `\` line continuation or one long line.
- **Killing `mcp-remote` during token write**: if you Ctrl+C or `pkill` while OAuth is finalizing, the dir ends up with `client_info.json` + `code_verifier.txt` but no `tokens.json`. Recovery: `rm -rf ~/.mcp-auth/notion-<workspace>` and redo OAuth.
- **`claude mcp list` spawns zombies**: each call spins up a fresh `mcp-remote` process for health check. These can fight for the OAuth callback port. Don't call `claude mcp list` while doing manual OAuth.
- **Version upgrade = config dir renamed**: `mcp-remote` stores tokens under a version-scoped subdirectory (`mcp-remote-0.1.37/`, then `mcp-remote-0.1.38/` after upgrade). Tokens don't auto-migrate — the first call after upgrade re-authenticates.
- **Multiple workspaces sharing `MCP_REMOTE_CONFIG_DIR`**: both get hashed under the same URL, second overwrites first. Always use distinct dirs.
