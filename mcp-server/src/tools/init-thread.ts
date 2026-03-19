import { spawn } from 'child_process';
import { z } from 'zod';
import { getIsoPaths } from '../utils/iso-paths.js';
import { join } from 'path';

export const initThreadSchema = z.object({
  featureName: z.string().describe('Feature name for the new thread'),
  baseBranch: z.string().optional().default('dev').describe('Base branch to branch from'),
});

export type InitThreadInput = z.infer<typeof initThreadSchema>;

export interface InitThreadResult {
  threadId: number;
  backendPort: number;
  frontendPort: number;
  branch: string;
  worktreePath: string;
  output: string;
}

export async function initThread(input: InitThreadInput): Promise<InitThreadResult> {
  const paths = getIsoPaths();
  const scriptPath = join(paths.scriptsDir, 'thread-init.sh');

  return new Promise((resolve, reject) => {
    const args = [input.featureName];
    if (input.baseBranch) {
      args.push(input.baseBranch);
    }

    const proc = spawn(scriptPath, args, {
      cwd: paths.repoRoot,
      env: { ...process.env },
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`Thread initialization failed: ${stderr || stdout}`));
        return;
      }

      // Parse output to extract thread info
      const threadIdMatch = stdout.match(/✓?\s*Thread (\d+) allocated/);
      const backendMatch = stdout.match(/Backend:\s+localhost:(\d+)/);
      const frontendMatch = stdout.match(/Frontend:\s+localhost:(\d+)/);
      const branchMatch = stdout.match(/Branch:\s+(\S+)/);
      const worktreeMatch = stdout.match(/Work(?:tree|space):\s+(\S+)/);

      if (!threadIdMatch || !backendMatch || !frontendMatch || !branchMatch || !worktreeMatch) {
        const missing = [
          !threadIdMatch && 'threadId',
          !backendMatch && 'backend',
          !frontendMatch && 'frontend',
          !branchMatch && 'branch',
          !worktreeMatch && 'worktree',
        ].filter(Boolean);
        reject(new Error(`Failed to parse thread initialization output. Missing: ${missing.join(', ')}. Output:\n${stdout}`));
        return;
      }

      resolve({
        threadId: parseInt(threadIdMatch[1]),
        backendPort: parseInt(backendMatch[1]),
        frontendPort: parseInt(frontendMatch[1]),
        branch: branchMatch[1],
        worktreePath: worktreeMatch[1],
        output: stdout,
      });
    });
  });
}
