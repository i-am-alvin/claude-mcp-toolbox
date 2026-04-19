#!/usr/bin/env bash
# Add a Slack workspace as a Claude Code MCP server using a user OAuth token.
#
# Usage: ./scripts/add-slack.sh <workspace> <xoxp-token>
#
# Prerequisite: create an unlisted Slack App with User Token Scopes and
# install it to the target workspace. See servers/slack.md for the full scope list.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <workspace> <xoxp-token>" >&2
  echo "  workspace:  short name for this Slack workspace (e.g. 'personal', 'acme')" >&2
  echo "  xoxp-token: User OAuth Token from api.slack.com/apps → OAuth & Permissions" >&2
  exit 1
fi

workspace=$1
token=$2
name="slack-${workspace}"
cache_dir="${HOME}/.cache/slack-mcp/${workspace}"

if [[ ${token} != xoxp-* ]]; then
  echo "Error: expected a user OAuth token (xoxp-...), got: ${token:0:6}..." >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude (Claude Code CLI) is not installed." >&2
  exit 1
fi

mkdir -p "${cache_dir}"

claude mcp add "${name}" -s user \
  -e "SLACK_MCP_XOXP_TOKEN=${token}" \
  -e "SLACK_MCP_USERS_CACHE=${cache_dir}/users.json" \
  -e "SLACK_MCP_CHANNELS_CACHE=${cache_dir}/channels.json" \
  -- npx -y slack-mcp-server --transport stdio

cat <<EOF

Registered ${name} in Claude Code.

Verify:
  claude mcp list | grep ${name}

The server is ready immediately (no OAuth handshake needed — the user token is the credential).
Restart Claude Code, then call mcp__${name}__channels_list to smoke-test.
EOF
