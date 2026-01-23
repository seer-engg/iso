# ISO MCP Server

Model Context Protocol server for ISO (Isolated Thread Manager).

## Overview

The ISO MCP server exposes ISO's thread management capabilities through the MCP protocol, allowing AI tools like Claude Desktop and Cursor to interact with ISO threads programmatically.

## Features

- **iso_init_thread**: Create new isolated development threads
- **iso_list_threads**: List all threads with status and container info
- **iso_get_thread_info**: Get detailed info about a specific thread
- **iso_cleanup_thread**: Clean up thread resources

## Installation

From the ISO root directory:

```bash
./install-mcp.sh
```

For global installation (optional):

```bash
cd mcp-server
npm link
```

## Configuration

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "iso": {
      "command": "node",
      "args": ["/absolute/path/to/iso/mcp-server/dist/index.js"]
    }
  }
}
```

Or if installed globally:

```json
{
  "mcpServers": {
    "iso": {
      "command": "iso-mcp"
    }
  }
}
```

### Claude Code CLI

Add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "iso": {
      "type": "stdio",
      "command": "node",
      "args": ["/absolute/path/to/iso/mcp-server/dist/index.js"]
    }
  }
}
```

**Using with existing MCPs:**
```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    },
    "shadcn": {
      "type": "stdio",
      "command": "npx",
      "args": ["shadcn@latest", "mcp"]
    },
    "iso": {
      "type": "stdio",
      "command": "node",
      "args": ["/Users/pika/Projects/iso/mcp-server/dist/index.js"]
    }
  }
}
```

**Verification:**
1. Restart Claude Code or start a new session
2. The ISO MCP tools should appear in the available tools
3. Test with: "List all ISO threads"

### Cursor

Add to Cursor settings (MCP section):

```json
{
  "iso": {
    "command": "node",
    "args": ["/absolute/path/to/iso/mcp-server/dist/index.js"]
  }
}
```

## Available Tools

### iso_init_thread

Initialize a new ISO thread with isolated backend and frontend environments.

**Input:**
```json
{
  "featureName": "add-user-auth",
  "baseBranch": "dev"
}
```

**Output:**
```json
{
  "threadId": 1,
  "backendPort": 3001,
  "frontendPort": 4001,
  "branch": "thread-1-add-user-auth",
  "worktreePath": "/path/to/seer/.worktrees/thread-1",
  "output": "..."
}
```

### iso_list_threads

List all active threads with their status and container information.

**Output:**
```json
[
  {
    "threadId": 1,
    "branch": "thread-1-add-user-auth",
    "backendPort": 3001,
    "frontendPort": 4001,
    "worktreePath": "/path/to/seer/.worktrees/thread-1",
    "created": "2024-01-15T10:30:00Z",
    "status": "active",
    "containers": {
      "total": 4,
      "running": 4
    }
  }
]
```

### iso_get_thread_info

Get detailed information about a specific thread.

**Input:**
```json
{
  "threadId": 1
}
```

**Output:**
```json
{
  "threadId": 1,
  "branch": "thread-1-add-user-auth",
  "backendPort": 3001,
  "frontendPort": 4001,
  "worktreePath": "/path/to/seer/.worktrees/thread-1",
  "created": "2024-01-15T10:30:00Z",
  "status": "active",
  "dockerContainers": [
    {
      "name": "seer-thread-1-postgres",
      "status": "Up",
      "health": "healthy"
    }
  ]
}
```

### iso_cleanup_thread

Clean up a thread's resources (stops containers, removes worktrees, deallocates ports).

**Input:**
```json
{
  "threadId": 1
}
```

**Output:**
```json
{
  "success": true,
  "message": "Thread 1 cleaned up successfully"
}
```

## Development

Build:
```bash
npm run build
```

Watch mode:
```bash
npm run dev
```

## Port Scheme

ISO uses a simplified port allocation scheme:

- **Backend API**: 3000 + thread_id (3001, 3002, 3003...)
- **Frontend**: 4000 + thread_id (4001, 4002, 4003...)
- **Postgres/Redis**: Internal Docker network only (no host mapping)

## Troubleshooting

### Server not appearing in Claude Desktop

1. Check config file location and syntax
2. Restart Claude Desktop completely
3. Check MCP server logs in Claude Desktop developer console

### Path issues

Ensure ISO config file exists:
```bash
cp /path/to/iso/config.example /path/to/iso/config
```

Edit `config` to set `SEER_REPO_PATH`.

### Permission errors

Ensure the MCP server has execute permissions:
```bash
chmod +x /path/to/iso/mcp-server/dist/index.js
```
