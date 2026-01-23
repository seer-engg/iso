#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { initThread, initThreadSchema } from './tools/init-thread.js';
import { listThreads } from './tools/list-threads.js';
import { cleanupThread, cleanupThreadSchema } from './tools/cleanup-thread.js';
import { getThreadInfo, getThreadInfoSchema } from './tools/get-thread-info.js';

const server = new Server(
  {
    name: 'iso-mcp-server',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'iso_init_thread',
        description: 'Initialize a new ISO thread with isolated backend and frontend environments',
        inputSchema: {
          type: 'object',
          properties: {
            featureName: {
              type: 'string',
              description: 'Feature name for the new thread',
            },
            baseBranch: {
              type: 'string',
              description: 'Base branch to branch from (default: dev)',
              default: 'dev',
            },
          },
          required: ['featureName'],
        },
      },
      {
        name: 'iso_list_threads',
        description: 'List all ISO threads with their status, ports, and container information',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
      {
        name: 'iso_cleanup_thread',
        description:
          'Cleanup an ISO thread (stops containers, removes worktrees, deallocates ports)',
        inputSchema: {
          type: 'object',
          properties: {
            threadId: {
              type: 'number',
              description: 'Thread ID to cleanup',
            },
          },
          required: ['threadId'],
        },
      },
      {
        name: 'iso_get_thread_info',
        description:
          'Get detailed information about a specific ISO thread including Docker container status',
        inputSchema: {
          type: 'object',
          properties: {
            threadId: {
              type: 'number',
              description: 'Thread ID to get info for',
            },
          },
          required: ['threadId'],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    switch (request.params.name) {
      case 'iso_init_thread': {
        const input = initThreadSchema.parse(request.params.arguments);
        const result = await initThread(input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      case 'iso_list_threads': {
        const threads = await listThreads();
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(threads, null, 2),
            },
          ],
        };
      }

      case 'iso_cleanup_thread': {
        const input = cleanupThreadSchema.parse(request.params.arguments);
        const result = await cleanupThread(input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      case 'iso_get_thread_info': {
        const input = getThreadInfoSchema.parse(request.params.arguments);
        const result = await getThreadInfo(input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${request.params.name}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({ error: errorMessage }, null, 2),
        },
      ],
      isError: true,
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('ISO MCP server running on stdio');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
