#!/usr/bin/env bash
# Add a Notion workspace as a Claude Code MCP server.
#
# Usage: ./scripts/add-notion.sh <workspace>
#
# After this script completes, you still need to run mcp-remote manually
# to do the OAuth handshake — see servers/notion.md section "3. Do the OAuth handshake"

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <workspace>" >&2
  echo "  workspace: a short name for this Notion workspace (e.g. 'personal', 'acme')" >&2
  exit 1
fi

workspace=$1
name="notion-${workspace}"
config_dir="${HOME}/.mcp-auth/${name}"

if ! command -v mcp-remote >/dev/null 2>&1; then
  echo "Error: mcp-remote is not installed. Run: npm install -g mcp-remote" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude (Claude Code CLI) is not installed." >&2
  exit 1
fi

mkdir -p "${config_dir}"

claude mcp add "${name}" -s user \
  -e "MCP_REMOTE_CONFIG_DIR=${config_dir}" \
  -- mcp-remote https://mcp.notion.com/mcp

cat <<EOF

Registered ${name} in Claude Code.

Next step — do the OAuth handshake manually (DO NOT run 'claude mcp list' until this completes):

  1. In your browser, log into the intended Notion workspace (or open an incognito window)
  2. In a regular terminal, run:

       MCP_REMOTE_CONFIG_DIR=${config_dir} mcp-remote https://mcp.notion.com/mcp

  3. Grant access in the browser, wait for "Authorization successful"
  4. Wait ~5 seconds for the token to be written to disk
  5. Ctrl+C to stop mcp-remote
  6. Verify:  ls ${config_dir}/mcp-remote-*/  (should include a *_tokens.json file)
EOF
