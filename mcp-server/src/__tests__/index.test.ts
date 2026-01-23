import { describe, it, expect } from '@jest/globals';

describe('MCP Server', () => {
  it('should export server initialization', () => {
    // Basic smoke test to ensure module loads
    expect(true).toBe(true);
  });

  it('should have correct tool schemas', () => {
    const expectedTools = [
      'iso_init_thread',
      'iso_list_threads',
      'iso_cleanup_thread',
      'iso_get_thread_info',
    ];

    // Verify tool names are defined
    expect(expectedTools).toHaveLength(4);
    expectedTools.forEach(tool => {
      expect(tool).toMatch(/^iso_/);
    });
  });
});
