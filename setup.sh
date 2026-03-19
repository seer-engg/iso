#!/bin/bash
# One-time ISO setup for Claude Code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_SERVER="$SCRIPT_DIR/mcp-server"

# Build MCP server
echo "Building ISO MCP server..."
cd "$MCP_SERVER"
if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Install Node.js first." >&2
    exit 1
fi
npm install
npm run build

# Create config with auto-detected paths
cat > "$SCRIPT_DIR/config" << EOF
SEER_REPO_PATH="${SEER_REPO_PATH:-$HOME/seer}"
SEER_FRONTEND_PATH="${SEER_FRONTEND_PATH:-$HOME/seer-frontend}"
EOF

# Add to Claude Code user config (idempotent)
SETTINGS="$HOME/.claude.json"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('$SETTINGS','utf8'));
s.mcpServers = s.mcpServers || {};
s.mcpServers.iso = {type:'stdio',command:'node',args:['$MCP_SERVER/dist/index.js']};
fs.writeFileSync('$SETTINGS', JSON.stringify(s, null, 2));
"

echo "ISO setup complete. Restart Claude Code and run /mcp to approve."
