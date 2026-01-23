import { describe, it, expect } from '@jest/globals';
import type { InitThreadResult } from '../tools/init-thread.js';
import type { CleanupThreadResult } from '../tools/cleanup-thread.js';
import type { GetThreadInfoResult } from '../tools/get-thread-info.js';
import type { ThreadInfo } from '../tools/list-threads.js';

describe('Type Contracts', () => {
  it('InitThreadResult should have correct shape', () => {
    const result: InitThreadResult = {
      threadId: 1,
      backendPort: 3001,
      frontendPort: 4001,
      branch: 'thread-1-test',
      worktreePath: '/test/worktree',
      output: 'test output',
    };

    expect(result).toHaveProperty('threadId');
    expect(result).toHaveProperty('backendPort');
    expect(result).toHaveProperty('frontendPort');
    expect(result).toHaveProperty('branch');
    expect(result).toHaveProperty('worktreePath');
    expect(result).toHaveProperty('output');
    expect(typeof result.threadId).toBe('number');
    expect(typeof result.backendPort).toBe('number');
  });

  it('CleanupThreadResult should have correct shape', () => {
    const result: CleanupThreadResult = {
      success: true,
      message: 'Cleanup successful',
    };

    expect(result).toHaveProperty('success');
    expect(result).toHaveProperty('message');
    expect(typeof result.success).toBe('boolean');
    expect(typeof result.message).toBe('string');
  });

  it('GetThreadInfoResult should have correct shape', () => {
    const result: GetThreadInfoResult = {
      threadId: 1,
      branch: 'thread-1-test',
      backendPort: 3001,
      frontendPort: 4001,
      worktreePath: '/test/worktree',
      created: '2024-01-01T00:00:00Z',
      status: 'active',
      dockerContainers: [
        {
          name: 'container-1',
          status: 'Up',
          health: 'healthy',
        },
      ],
    };

    expect(result).toHaveProperty('threadId');
    expect(result).toHaveProperty('dockerContainers');
    expect(Array.isArray(result.dockerContainers)).toBe(true);
  });

  it('ThreadInfo should have correct shape', () => {
    const info: ThreadInfo = {
      threadId: 1,
      branch: 'thread-1-test',
      backendPort: 3001,
      frontendPort: 4001,
      worktreePath: '/test/worktree',
      created: '2024-01-01T00:00:00Z',
      status: 'active',
      containers: {
        total: 2,
        running: 2,
      },
    };

    expect(info).toHaveProperty('containers');
    expect(info.containers).toHaveProperty('total');
    expect(info.containers).toHaveProperty('running');
  });
});
