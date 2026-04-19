# Google Workspace

Covers Gmail, Calendar, Drive, Docs, Sheets, Slides, Tasks, Forms, Chat, and Contacts through a single MCP entry per account.

## Why not the built-in `*.mcp.claude.com` connectors

Claude Code's managed Gmail/Calendar/Drive connectors route data through Anthropic servers. If you'd rather have traffic go directly between your machine and Google, or you want more than one of the same product (personal Gmail + work Gmail + another work Gmail), you need to own the OAuth client.

## Solution: `taylorwilsdon/google_workspace_mcp` (composite)

[`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) (PyPI: `workspace-mcp`) bundles all major Google Workspace products into one MCP server. Three accounts = three MCP entries (not nine per-product).

**Composite vs. per-product trade-off**:
- ✅ 3 entries instead of 9, one OAuth authorization per account covers every product, single codebase to follow for CVEs/updates
- ⚠️ Larger exposed tool surface — cap it with `--tool-tier core` or `--tools gmail drive calendar`
- ⚠️ If the server crashes, you lose every product for that account at once (but it's stable in practice)

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
- **Publish to Production** (UI only). Unverified is fine, but Test-mode refresh tokens expire in 7 days — Production refresh tokens don't.

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

### 4. Add the MCP entry

```bash
./scripts/add-google-workspace.sh <workspace> <client_id> <client_secret> <port>
```

Or manually:

```bash
mkdir -p ~/.gws-auth/<workspace>
claude mcp add gws-<workspace> -s user \
  -e GOOGLE_OAUTH_CLIENT_ID=<client_id> \
  -e GOOGLE_OAUTH_CLIENT_SECRET=<client_secret> \
  -e GOOGLE_MCP_CREDENTIALS_DIR=$HOME/.gws-auth/<workspace> \
  -e WORKSPACE_MCP_PORT=<unique_port> \
  -e OAUTHLIB_INSECURE_TRANSPORT=1 \
  -- uvx workspace-mcp --single-user --tool-tier complete
```

### 5. Restart Claude Code, then trigger OAuth

MCP servers added mid-session don't register their tools until you restart Claude Code.

In the new session, call:

```
mcp__gws-<workspace>__start_google_auth
  service_name: "gmail"
  user_google_email: "you@your-domain.com"
```

The tool returns an auth URL. Open it in the browser, authorize, and the OAuth callback hits `localhost:<port>/oauth2callback` where `workspace-mcp` is listening. The token lands in `~/.gws-auth/<workspace>/<email>.json`.

### 6. Verify

Ask Claude to run `mcp__gws-<workspace>__list_gmail_labels` with `user_google_email` set to your address. You should see your Gmail labels.

## Why `WORKSPACE_MCP_PORT` is mandatory

The `workspace-mcp` default port is 8000, which:

- Frequently conflicts with local dev servers / proxies. When the port is taken, `workspace-mcp` silently fails to bind, and the OAuth callback hits whatever process grabbed 8000 instead — you get a cryptic 404 or `redirect_uri_mismatch`.
- Means every Google account's `workspace-mcp` process would try to bind the same port. They can't coexist at 8000.

Use a unique port per workspace: 8765, 8766, 8767, ... The port is embedded in the OAuth redirect URI that the server generates on the fly, so changing `WORKSPACE_MCP_PORT` automatically updates the redirect.

## Why `--single-user`

Per-account MCP entry + per-account credentials dir = inherently single-user. The flag tells `workspace-mcp` to skip its session-mapping code (which exists for shared/multi-tenant deployments) and just use any credentials it finds in the dir. Simpler, less overhead, fewer moving parts.

## Gotchas

- **Session refresh required**: `claude mcp add` appends to `~/.claude.json` but the currently-running Claude Code session has its MCP tool list frozen at startup. New servers need `/exit` + reopen to become callable.
- **Scope list is long**: with `--tool-tier complete` the server requests 40+ scopes. You have to select all of them on the consent screen, or authorization fails with "invalid_scope" for any unselected one. The `start_google_auth` tool will show you exactly which scopes the auth URL needs.
- **`OAUTHLIB_INSECURE_TRANSPORT=1` is mandatory for local dev**: the OAuth library rejects `http://` redirect URIs without it. It only affects the localhost callback, not production traffic.
- **Token stored per email**: the file is `<email>.json` in the credentials dir. If you authorize with the wrong Google account, the file gets that account's name — delete and redo.
- **IAP OAuth client rejection**: if you try `gcloud alpha iap oauth-clients create`, you get a client_id/secret back that **looks** like it should work but Google 400s on the loopback redirect. Don't fall for it — only UI-created Desktop clients accept loopback.
