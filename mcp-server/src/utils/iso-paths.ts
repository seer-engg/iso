import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export interface IsoPaths {
  repoRoot: string;
  scriptsDir: string;
  configPath: string;
  seerRepoPath: string;
}

export function getIsoPaths(): IsoPaths {
  // MCP server is in iso/mcp-server/dist/utils/iso-paths.js
  // Need to go up to iso root
  const repoRoot = join(__dirname, '..', '..', '..');
  const scriptsDir = join(repoRoot, 'scripts');
  const configPath = join(repoRoot, 'config');

  if (!existsSync(configPath)) {
    throw new Error(`ISO config file not found at ${configPath}. Run: cp config.example config`);
  }

  // Parse config to get SEER_REPO_PATH
  const configContent = readFileSync(configPath, 'utf-8');
  const seerRepoMatch = configContent.match(/^SEER_REPO_PATH="([^"]+)"/m);

  if (!seerRepoMatch) {
    throw new Error('SEER_REPO_PATH not found in config file');
  }

  const seerRepoPath = seerRepoMatch[1];

  if (!existsSync(seerRepoPath)) {
    throw new Error(`SEER_REPO_PATH does not exist: ${seerRepoPath}`);
  }

  return {
    repoRoot,
    scriptsDir,
    configPath,
    seerRepoPath,
  };
}
