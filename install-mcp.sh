#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building ISO MCP server..."
cd "$SCRIPT_DIR/mcp-server"

if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Please install Node.js and npm first." >&2
    exit 1
fi

npm install
npm run build

echo ""
echo "✓ MCP server built successfully"
echo ""
echo "To install globally:"
echo "  cd mcp-server && npm link"
echo ""
echo "To use with Claude Desktop, add to your config:"
echo ""
echo '{
  "mcpServers": {
    "iso": {
      "command": "node",
      "args": ["'$SCRIPT_DIR'/mcp-server/dist/index.js"]
    }
  }
}'
echo ""
echo "Claude Desktop config location:"
echo "  macOS: ~/Library/Application Support/Claude/claude_desktop_config.json"
echo "  Linux: ~/.config/Claude/claude_desktop_config.json"
echo ""
echo "For Claude Code CLI, add to your project's .mcp.json:"
echo ""
echo '{
  "mcpServers": {
    "iso": {
      "type": "stdio",
      "command": "node",
      "args": ["'$SCRIPT_DIR'/mcp-server/dist/index.js"]
    }
  }
}'
echo ""
