# Testing Strategy

## Overview

The ISO MCP server is a thin wrapper around existing shell scripts. The testing strategy reflects this architecture:

## Test Coverage

### 1. Schema Validation Tests (`schemas.test.ts`)
- **Purpose**: Verify input validation using Zod schemas
- **Coverage**: All input schemas (initThread, cleanupThread, getThreadInfo)
- **Ensures**: Type safety and correct default values

### 2. Type Contract Tests (`types.test.ts`)
- **Purpose**: Document and verify output type shapes
- **Coverage**: All result types (InitThreadResult, CleanupThreadResult, etc.)
- **Ensures**: API contract stability

### 3. Integration Tests (`index.test.ts`)
- **Purpose**: Smoke tests for module loading
- **Coverage**: Server initialization and tool registration

## Why Low Line Coverage?

The MCP server functions (`initThread`, `listThreads`, etc.) are wrappers that:
1. Call shell scripts via `spawn`
2. Parse script output
3. Return structured data

**Testing Philosophy**:
- Shell script logic is tested separately (in the `scripts/` directory)
- MCP server tests focus on the wrapper contracts (inputs/outputs)
- Integration testing happens through actual shell script execution

## Running Tests

```bash
# Run all tests
npm test

# Run with coverage report
npm run test:coverage

# Run in watch mode
npm run dev & npm test -- --watch
```

## Adding New Tests

When adding new MCP tools:
1. Add schema validation tests in `schemas.test.ts`
2. Add type contract tests in `types.test.ts`
3. Ensure shell scripts have their own test coverage

## Linting

```bash
# Check code style
npm run lint

# Fix auto-fixable issues
npm run lint:fix

# Format code
npm run format
```
