import { spawn } from 'child_process';
import { z } from 'zod';
import { getIsoPaths } from '../utils/iso-paths.js';
import { join } from 'path';

export const cleanupThreadSchema = z.object({
  threadId: z.number().describe('Thread ID to cleanup'),
});

export type CleanupThreadInput = z.infer<typeof cleanupThreadSchema>;

export interface CleanupThreadResult {
  success: boolean;
  message: string;
}

export async function cleanupThread(input: CleanupThreadInput): Promise<CleanupThreadResult> {
  const paths = getIsoPaths();
  const scriptPath = join(paths.scriptsDir, 'thread-cleanup.sh');

  return new Promise((resolve) => {
    const proc = spawn(scriptPath, [input.threadId.toString(), '--force'], {
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
        resolve({
          success: false,
          message: `Cleanup failed: ${stderr || stdout}`,
        });
        return;
      }

      resolve({
        success: true,
        message: stdout,
      });
    });
  });
}
