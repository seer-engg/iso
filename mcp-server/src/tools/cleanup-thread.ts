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

  return new Promise((resolve, reject) => {
    // 60 second timeout for cleanup operations
    const timeout = setTimeout(() => {
      proc.kill('SIGTERM');
      setTimeout(() => proc.kill('SIGKILL'), 5000);
      reject(new Error('Cleanup timed out after 60 seconds'));
    }, 60000);

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

    proc.on('error', (error) => {
      clearTimeout(timeout);
      resolve({
        success: false,
        message: `Cleanup script error: ${error.message}`,
      });
    });

    proc.on('close', (code) => {
      clearTimeout(timeout);
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
