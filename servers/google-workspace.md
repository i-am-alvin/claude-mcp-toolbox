# Google Workspace

Covers Gmail, Calendar, Drive, Docs, Sheets, Slides, Tasks, Forms, Chat, and Contacts through a single MCP entry per account.

## Why not the built-in `*.mcp.claude.com` connectors

Claude Code's managed Gmail/Calendar/Drive connectors route data through Anthropic servers. If you'd rather have traffic go directly between your machine and Google, or you want more than one of the same product (personal Gmail + work Gmail + another work Gmail), you need to own the OAuth client.

## Pick your approach

Like the Notion playbook, there are two grades:

| Approach | When to use | Trade-off |
|---|---|---|
| **stdio** (legacy) | One Claude Code session at a time, never re-authorize OAuth | Simple but **breaks under multi-session and any time the OAuth callback is needed** — see [Why stdio breaks](#why-stdio-breaks) below |
| **HTTP daemon** (recommended) | Default for everyone | A `launchd`-managed `workspace-mcp --transport streamable-http` daemon, one per Google account, shared by all Claude Code sessions; ~3 minutes to install via the script |

If you're starting fresh, use the HTTP daemon path. If you're moving an existing setup, jump to [Migrating from stdio](#migrating-from-stdio).

## Solution: `taylorwilsdon/google_workspace_mcp` as a daemon

[`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) (PyPI: `workspace-mcp`) bundles all major Google Workspace products into one MCP server. Three accounts = three MCP entries (not nine per-product).

It supports `--transport streamable-http`, which makes the same process serve both `/mcp` (MCP traffic) and `/oauth2callback` (OAuth) on a single port. We run that as a `launchd` LaunchAgent per account, and Claude Code talks to it over HTTP:

```
Claude Code × N  ──>  gws-<workspace> daemon (launchd)  ──>  Google APIs
                      (single OAuth callback owner,
                       single token-file owner)
```

**Composite vs. per-product trade-off**:
- ✅ 3 entries instead of 9, one OAuth authorization per account covers every product, single codebase to follow for CVEs/updates
- ⚠️ Larger exposed tool surface — cap with `--tool-tier core` or `--tools gmail drive calendar`
- ⚠️ If the daemon crashes you lose every product for that account at once (but `KeepAlive` respawns within seconds)

## Setup

### 1. GCP project + APIs + consent screen (gcloud-automatable)

```bash
gcloud auth login  # use the target Google account
gcloud projects create claude-mcp-<workspace> --organization=<ORG_ID>  # or use an existing project
gcloud config set project claude-mcp-<workspace>

gcloud services enable \
  gmail.googleapis.com calendar-json.googleapis.com drive.googleapis.com \
  docs.googleapis.com sheets.googleapis.com slides.googleapis.com \
  tasks.googleapis.com people.googleapis.com forms.googleapis.com \
  chat.googleapis.com script.googleapis.com iap.googleapis.com
```

Then create the consent screen (brand):

**For Google Workspace accounts** (e.g. `you@your-org.com`) — Internal, no admin required:

```bash
gcloud alpha iap oauth-brands create \
  --application_title="Claude MCP <workspace>" \
  --support_email=you@your-org.com
```

You just need to be *inside* the Google Workspace org. Internal consent screens bypass the "unverified app" warning and don't require Google's review.

**For personal gmail.com accounts** — Internal is not available; use External + self-add as Test User. Do this in the UI because the gcloud CLI cannot mark the brand External. After creating:
- Add yourself as a Test User
- **Publish to Production** (UI only)

⚠️ Personal gmail.com + sensitive scopes (Gmail/Drive/Calendar) still has refresh-token expiry quirks even on Production — see [Personal gmail.com refresh tokens fail intermittently](#personal-gmailcom-refresh-tokens-fail-intermittently) below.

### 2. Desktop OAuth Client (UI only — gcloud cannot do this)

**`gcloud alpha iap oauth-clients create` builds IAP-scoped OAuth clients that reject loopback redirect URIs** (`http://localhost:<port>/oauth2callback`). Google will 400 with `redirect_uri_mismatch`. There is no public gcloud/API path to create a Desktop OAuth client — this step is UI-only.

1. [console.cloud.google.com](https://console.cloud.google.com) → **APIs & Services → Credentials**
2. **+ CREATE CREDENTIALS → OAuth client ID**
3. Application type: **Desktop app**
4. Name: `workspace-mcp`
5. CREATE → copy the **Client ID** + **Client Secret**

### 3. Install `uv` (once)

```bash
brew install uv
```

### 4. Install the daemon + register MCP entry

```bash
./scripts/add-google-workspace.sh <workspace> <client_id> <client_secret> <port>
```

Pick a unique port per account: `8765`, `8766`, `8767`, ... (avoid `8000`, `workspace-mcp`'s default — conflicts often).

The script:
1. Renders `~/Library/LaunchAgents/com.claude-mcp-toolbox.gws-<workspace>.plist` from [`packaging/gws-daemon.plist.tpl`](../packaging/gws-daemon.plist.tpl)
2. Bootstraps the LaunchAgent (starts the daemon, marks it for boot-time autostart)
3. Polls `http://127.0.0.1:<port>/` until the daemon is ready (uvx extracts the wheel into `~/.cache/uv/` on first run, ~3–5 s)
4. Removes any existing `claude mcp` entry of the same name and registers the new HTTP one

### 5. Restart Claude Code, then trigger OAuth

MCP servers added mid-session don't register their tools until you restart Claude Code.

In the new session, call:

```
mcp__gws-<workspace>__start_google_auth
  service_name: "gmail"
  user_google_email: "you@your-domain.com"
```

The tool returns an auth URL. Open it in the browser, authorize. The OAuth callback hits `localhost:<port>/oauth2callback` on the daemon (the only thing listening on that port — no zombie collision possible). Token lands in `~/.gws-auth/<workspace>/<email>.json`.

### 6. Verify

Ask Claude to run `mcp__gws-<workspace>__list_gmail_labels` with `user_google_email` set to your address. You should see your Gmail labels.

## Migrating from stdio

If you previously ran `claude mcp add gws-<workspace> -s user -- uvx workspace-mcp ...`:

```bash
# 1. Stop & remove the old stdio entry
claude mcp remove gws-<workspace> -s user
pkill -f "uvx workspace-mcp"  # kills all workspace-mcp subprocesses; the new daemon will be (re)spawned by launchd

# 2. Run the new add script with the SAME client_id / client_secret / port as before
./scripts/add-google-workspace.sh <workspace> <client_id> <client_secret> <port>
```

Existing token files at `~/.gws-auth/<workspace>/<email>.json` are reused — the daemon picks them up on first request, no re-OAuth needed (assuming the refresh token is still valid).

## Why stdio breaks

`workspace-mcp` is more than just an MCP server: it also runs an HTTP server internally to receive the OAuth callback at `localhost:<WORKSPACE_MCP_PORT>/oauth2callback`. The stdio transport, by contrast, is **process-per-client** — every Claude Code session, worktree, and `claude mcp list` health check spawns its own `workspace-mcp` subprocess.

When N stdio subprocesses run concurrently:

1. **Only the first one binds `WORKSPACE_MCP_PORT`** (silently — no error). The rest can serve MCP traffic over their own stdin/stdout but can't receive the OAuth callback.
2. **OAuth state is stored in the in-memory cache of whichever process generated it** (the one that handled `start_google_auth` for *this* session). Yes, `oauth_states.json` exists on disk too, but the callback handler validates against in-memory cache first.
3. **The callback hits the port-bound process — usually not the same one that generated the state.** Result: `Invalid or expired OAuth state parameter`, even on a freshly-issued state.

Killing zombies (`pkill -f workspace-mcp`) only reduces process count; it doesn't fix the in-memory state mismatch — every new session generates new in-memory state.

The HTTP daemon eliminates both halves: one process, one in-memory state, one callback owner.

## Why `WORKSPACE_MCP_PORT` is mandatory

- The default 8000 frequently conflicts with local dev servers / proxies. When the port is taken, `workspace-mcp` silently fails to bind, and the OAuth callback hits whatever process grabbed 8000 instead — you get a cryptic 404 or `redirect_uri_mismatch`.
- Every Google account's daemon needs its own port; they can't coexist on the same one.

Use a unique port per account: 8765, 8766, 8767, ...

## Why `--single-user`

Per-account daemon + per-account credentials dir = inherently single-user. The flag tells `workspace-mcp` to skip its session-mapping code (which exists for shared/multi-tenant deployments) and just use any credentials it finds in the dir. Simpler, less overhead, fewer moving parts.

## Operations

```bash
# Status
launchctl list | grep gws-

# Logs
tail -f ~/Library/Logs/gws-<workspace>/{stdout,stderr}.log

# Manual stop / start
launchctl bootout    gui/$(id -u) com.claude-mcp-toolbox.gws-<workspace>
launchctl bootstrap  gui/$(id -u) ~/Library/LaunchAgents/com.claude-mcp-toolbox.gws-<workspace>.plist

# Restart (daemon respawns automatically via KeepAlive)
kill <pid>

# Uninstall completely
launchctl bootout gui/$(id -u) com.claude-mcp-toolbox.gws-<workspace>
rm ~/Library/LaunchAgents/com.claude-mcp-toolbox.gws-<workspace>.plist
claude mcp remove gws-<workspace> -s user
# Token files at ~/.gws-auth/<workspace>/ remain — rm -rf manually if you want a fully clean slate
```

## Gotchas

- **Session refresh required**: `claude mcp add --transport http` writes to `~/.claude.json` but the currently-running session's MCP tool list is frozen at startup. New servers need `/exit` + reopen to become callable.
- **Scope list is long**: with `--tool-tier complete` the server requests 40+ scopes. You have to select all of them on the consent screen, or authorization fails with "invalid_scope" for any unselected one. The `start_google_auth` tool will show you exactly which scopes the auth URL needs.
- **`OAUTHLIB_INSECURE_TRANSPORT=1` is mandatory for local dev**: the OAuth library rejects `http://` redirect URIs without it. It only affects the localhost callback, not production traffic.
- **Token stored per email**: the file is `<email>.json` in the credentials dir. If you authorize with the wrong Google account, the file gets that account's name — delete and redo.
- **IAP OAuth client rejection**: if you try `gcloud alpha iap oauth-clients create`, you get a client_id/secret back that **looks** like it should work but Google 400s on the loopback redirect. Don't fall for it — only UI-created Desktop clients accept loopback.

## Personal gmail.com refresh tokens fail intermittently

**Symptom**: a Google account that's been working for days suddenly returns `invalid_grant` from the token endpoint. Re-running OAuth fixes it for another stretch.

**Common myth**: "Test-mode refresh tokens expire in 7 days, so just publish to Production." Half true — Production *does* solve the strict 7-day cutoff documented for Test mode. But personal gmail.com + sensitive scopes (Gmail/Drive/Calendar) on an **unverified** app still has Google's safety policies kicking in periodically and revoking refresh tokens, with no fixed schedule.

**Workarounds, in order of practicality**:
- **Just redo OAuth when it fails** (~30 seconds with the daemon architecture; the URL from `start_google_auth` works on the first try because there's no zombie collision)
- **Submit your app for Google verification** (4–6 weeks; requires homepage + privacy policy + domain ownership) — only worth it if you're shipping the app to others
- **Switch to a Google Workspace account** if you have one — Internal consent screens don't trigger the unverified-app policy

Workspace accounts (Internal consent) don't experience this — their refresh tokens are stable indefinitely.

## See also

- [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) — upstream
- [`packaging/gws-daemon.plist.tpl`](../packaging/gws-daemon.plist.tpl) — launchd template used by the install script
- [`servers/notion.md`](notion.md) — same multi-session-vs-stdio trade-off in the Notion world
