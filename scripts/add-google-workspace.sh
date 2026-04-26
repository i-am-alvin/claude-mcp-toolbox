#!/usr/bin/env bash
# Install a launchd-managed `workspace-mcp` HTTP daemon for one Google account
# and register it in Claude Code.
#
# Usage: ./scripts/add-google-workspace.sh <workspace> <client_id> <client_secret> <port>
#
# What this does:
#   1. Renders ~/Library/LaunchAgents/com.claude-mcp-toolbox.gws-<workspace>.plist
#      from packaging/gws-daemon.plist.tpl
#   2. Bootstraps the LaunchAgent (starts the daemon, persists across reboots)
#   3. Registers the daemon with Claude Code via HTTP transport
#
# Prerequisites (see servers/google-workspace.md for details):
#   1. A GCP project with Gmail/Calendar/Drive/etc APIs enabled
#   2. An OAuth consent screen (brand) configured — Internal for Workspace, External for gmail.com
#   3. A DESKTOP-type OAuth client (must be created via console.cloud.google.com UI;
#      gcloud's iap oauth-clients produces clients that reject loopback redirects)
#   4. uv installed: brew install uv

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <workspace> <client_id> <client_secret> <port>" >&2
  echo "  workspace:     short name (e.g. 'personal', 'acme')" >&2
  echo "  client_id:     Desktop OAuth client ID ending with .apps.googleusercontent.com" >&2
  echo "  client_secret: Desktop OAuth client secret starting with GOCSPX-" >&2
  echo "  port:          unique local port for the daemon (e.g. 8765)" >&2
  echo "                 Each Google account needs a distinct port; avoid 8000 (default, conflicts easily)" >&2
  exit 1
fi

workspace=$1
client_id=$2
client_secret=$3
port=$4
name="gws-${workspace}"
label="com.claude-mcp-toolbox.${name}"
creds_dir="${HOME}/.gws-auth/${workspace}"
log_dir="${HOME}/Library/Logs/${name}"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_path="${script_dir}/packaging/gws-daemon.plist.tpl"
uid_n="$(id -u)"

if [[ ! -f "${template_path}" ]]; then
  echo "Error: plist template not found at ${template_path}" >&2
  exit 1
fi

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

uvx_bin="$(command -v uvx)"

mkdir -p "${creds_dir}" "${log_dir}" "${HOME}/Library/LaunchAgents"

# Render the plist template
sed \
  -e "s|__LABEL__|${label}|g" \
  -e "s|__UVX_BIN__|${uvx_bin}|g" \
  -e "s|__HOME__|${HOME}|g" \
  -e "s|__CLIENT_ID__|${client_id}|g" \
  -e "s|__CLIENT_SECRET__|${client_secret}|g" \
  -e "s|__CREDS_DIR__|${creds_dir}|g" \
  -e "s|__PORT__|${port}|g" \
  -e "s|__LOG_DIR__|${log_dir}|g" \
  "${template_path}" > "${plist_path}"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "${plist_path}" >/dev/null
fi

# (Re-)bootstrap the agent. bootout is idempotent-safe with `|| true`.
launchctl bootout "gui/${uid_n}/${label}" 2>/dev/null || true
launchctl bootstrap "gui/${uid_n}" "${plist_path}"

# Wait for the daemon to bind the port. uvx may take a few seconds to extract
# the workspace-mcp wheel into ~/.cache/uv/ on first run.
echo "==> Waiting for daemon on port ${port} (up to 30s)..."
ready=0
for _ in $(seq 1 30); do
  if curl -sfo /dev/null "http://127.0.0.1:${port}/"; then
    ready=1
    break
  fi
  sleep 1
done

if (( ready != 1 )); then
  echo "Error: daemon did not start listening on port ${port} within 30 seconds." >&2
  echo "       Check logs at ${log_dir}/stderr.log" >&2
  exit 1
fi

# Replace any existing Claude Code entry (stdio or HTTP) with the new HTTP one.
if claude mcp get "${name}" >/dev/null 2>&1; then
  claude mcp remove "${name}" -s user >/dev/null
fi
claude mcp add --transport http "${name}" -s user "http://127.0.0.1:${port}/mcp"

cat <<EOF

Registered ${name} as a launchd-managed HTTP MCP daemon.

  Plist:        ${plist_path}
  Logs:         ${log_dir}/{stdout,stderr}.log
  Credentials:  ${creds_dir}/<email>.json
  Endpoint:     http://127.0.0.1:${port}/mcp

Next steps:
  1. Restart Claude Code (/exit, then reopen) — the current session's MCP tool list is frozen.
  2. In the new session, trigger OAuth (only needed first time, or after a refresh-token failure):

       Call mcp__${name}__start_google_auth with
         service_name:     "gmail"
         user_google_email: "<your Google account email>"

  3. Open the returned URL in a browser, authorize.
  4. Token lands at ${creds_dir}/<email>.json
  5. Smoke-test: ask Claude to call mcp__${name}__list_gmail_labels

To stop / uninstall:
  launchctl bootout gui/${uid_n}/${label}
  rm "${plist_path}"
  claude mcp remove "${name}" -s user
  # Token files at ${creds_dir} are NOT removed; rm -rf manually if you want a clean slate.
EOF
