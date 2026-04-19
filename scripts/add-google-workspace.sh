#!/usr/bin/env bash
# Add a Google Workspace account as a Claude Code MCP server.
#
# Usage: ./scripts/add-google-workspace.sh <workspace> <client_id> <client_secret> <port>
#
# Prerequisites (see servers/google-workspace.md for details):
#   1. A GCP project with Gmail/Calendar/Drive/etc APIs enabled
#   2. An OAuth consent screen (brand) configured — Internal for Workspace, External for gmail.com
#   3. A DESKTOP-type OAuth client (must be created via console.cloud.google.com UI;
#      gcloud's iap oauth-clients produces clients that reject loopback redirects)

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <workspace> <client_id> <client_secret> <port>" >&2
  echo "  workspace:     short name (e.g. 'personal', 'acme')" >&2
  echo "  client_id:     Desktop OAuth client ID ending with .apps.googleusercontent.com" >&2
  echo "  client_secret: Desktop OAuth client secret starting with GOCSPX-" >&2
  echo "  port:          unique local port for OAuth callback (e.g. 8765)" >&2
  echo "                 Each Google account needs a distinct port; avoid 8000 (default, conflicts easily)" >&2
  exit 1
fi

workspace=$1
client_id=$2
client_secret=$3
port=$4
name="gws-${workspace}"
creds_dir="${HOME}/.gws-auth/${workspace}"

if [[ ${client_id} != *.apps.googleusercontent.com ]]; then
  echo "Warning: client_id doesn't look like a Google OAuth client ID (should end in .apps.googleusercontent.com)" >&2
fi

if [[ ${client_secret} != GOCSPX-* ]]; then
  echo "Warning: client_secret doesn't look like a Google Desktop client secret (should start with GOCSPX-)" >&2
fi

if ! [[ ${port} =~ ^[0-9]+$ ]] || (( port < 1024 )) || (( port > 65535 )); then
  echo "Error: port must be a number between 1024 and 65535" >&2
  exit 1
fi

if (( port == 8000 )); then
  echo "Error: port 8000 is the workspace-mcp default and commonly conflicts with other local servers." >&2
  echo "       Pick an unused port like 8765, 8766, 8767, ..." >&2
  exit 1
fi

if ! command -v uvx >/dev/null 2>&1; then
  echo "Error: uvx is not installed. Run: brew install uv" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude (Claude Code CLI) is not installed." >&2
  exit 1
fi

mkdir -p "${creds_dir}"

claude mcp add "${name}" -s user \
  -e "GOOGLE_OAUTH_CLIENT_ID=${client_id}" \
  -e "GOOGLE_OAUTH_CLIENT_SECRET=${client_secret}" \
  -e "GOOGLE_MCP_CREDENTIALS_DIR=${creds_dir}" \
  -e "WORKSPACE_MCP_PORT=${port}" \
  -e "OAUTHLIB_INSECURE_TRANSPORT=1" \
  -- uvx workspace-mcp --single-user --tool-tier complete

cat <<EOF

Registered ${name} in Claude Code.

Next steps:
  1. Restart Claude Code (/exit, then reopen) — the current session's MCP tool list is frozen.
  2. In the new session, trigger OAuth:

       Call mcp__${name}__start_google_auth with
         service_name:     "gmail"
         user_google_email: "<your Google account email>"

  3. Open the returned URL in a browser, authorize.
  4. Token lands at ${creds_dir}/<email>.json
  5. Smoke-test: ask Claude to call mcp__${name}__list_gmail_labels
EOF
