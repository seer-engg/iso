export default {
  preset: 'ts-jest/presets/default-esm',
  testEnvironment: 'node',
  extensionsToTreatAsEsm: ['.ts'],
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
  transform: {
    '^.+\\.ts$': ['ts-jest', {
      useESM: true,
    }],
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.test.ts',
    '!src/**/__tests__/**',
  ],
  // Coverage thresholds disabled for MCP server (thin wrapper around shell scripts)
  // Testing strategy focuses on:
  // 1. Schema validation (input contracts)
  // 2. Type safety (output contracts)
  // 3. Integration testing via shell scripts themselves
  coverageThreshold: {},
  testMatch: ['**/__tests__/**/*.test.ts'],
};
