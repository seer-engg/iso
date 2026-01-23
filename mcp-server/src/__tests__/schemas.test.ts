import { describe, it, expect } from '@jest/globals';
import { initThreadSchema } from '../tools/init-thread.js';
import { cleanupThreadSchema } from '../tools/cleanup-thread.js';
import { getThreadInfoSchema } from '../tools/get-thread-info.js';

describe('Schema Validation', () => {
  describe('initThreadSchema', () => {
    it('should validate correct input', () => {
      const valid = { featureName: 'test-feature', baseBranch: 'dev' };
      expect(() => initThreadSchema.parse(valid)).not.toThrow();
    });

    it('should use default baseBranch', () => {
      const input = { featureName: 'test-feature' };
      const result = initThreadSchema.parse(input);
      expect(result.baseBranch).toBe('dev');
    });

    it('should reject missing featureName', () => {
      expect(() => initThreadSchema.parse({})).toThrow();
    });

    it('should reject invalid types', () => {
      expect(() => initThreadSchema.parse({ featureName: 123 })).toThrow();
    });
  });

  describe('cleanupThreadSchema', () => {
    it('should validate correct input', () => {
      const valid = { threadId: 1 };
      expect(() => cleanupThreadSchema.parse(valid)).not.toThrow();
    });

    it('should reject missing threadId', () => {
      expect(() => cleanupThreadSchema.parse({})).toThrow();
    });

    it('should reject non-number threadId', () => {
      expect(() => cleanupThreadSchema.parse({ threadId: '1' })).toThrow();
    });
  });

  describe('getThreadInfoSchema', () => {
    it('should validate correct input', () => {
      const valid = { threadId: 1 };
      expect(() => getThreadInfoSchema.parse(valid)).not.toThrow();
    });

    it('should reject missing threadId', () => {
      expect(() => getThreadInfoSchema.parse({})).toThrow();
    });

    it('should accept valid thread IDs', () => {
      [1, 2, 10, 100].forEach(id => {
        expect(() => getThreadInfoSchema.parse({ threadId: id })).not.toThrow();
      });
    });
  });
});
