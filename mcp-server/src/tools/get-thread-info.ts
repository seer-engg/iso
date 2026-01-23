import { spawn } from 'child_process';
import { z } from 'zod';
import { getIsoPaths } from '../utils/iso-paths.js';
import { join } from 'path';

export const getThreadInfoSchema = z.object({
  threadId: z.number().describe('Thread ID to get info for'),
});

export type GetThreadInfoInput = z.infer<typeof getThreadInfoSchema>;

export interface GetThreadInfoResult {
  threadId: number;
  branch: string;
  backendPort: number;
  frontendPort: number;
  worktreePath: string;
  created: string;
  status: string;
  dockerContainers?: Array<{
    name: string;
    status: string;
    health: string;
  }>;
}

export async function getThreadInfo(input: GetThreadInfoInput): Promise<GetThreadInfoResult> {
  const paths = getIsoPaths();
  const scriptPath = join(paths.scriptsDir, 'port-allocator.sh');

  return new Promise((resolve, reject) => {
    const proc = spawn(scriptPath, ['get-info', input.threadId.toString()], {
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

    proc.on('close', async (code) => {
      if (code !== 0) {
        reject(new Error(`Failed to get thread info: ${stderr || stdout}`));
        return;
      }

      const parts = stdout.trim().split('|');
      if (parts.length < 7) {
        reject(new Error('Invalid thread info format'));
        return;
      }

      const [threadId, branch, backendPort, frontendPort, worktreePath, created, status] = parts;

      const result: GetThreadInfoResult = {
        threadId: parseInt(threadId),
        branch,
        backendPort: parseInt(backendPort),
        frontendPort: parseInt(frontendPort),
        worktreePath,
        created,
        status,
      };

      // Enhance with Docker inspect data
      const containers = await getDockerContainers(parseInt(threadId));
      if (containers.length > 0) {
        result.dockerContainers = containers;
      }

      resolve(result);
    });
  });
}

async function getDockerContainers(
  threadId: number
): Promise<Array<{ name: string; status: string; health: string }>> {
  return new Promise((resolve) => {
    const proc = spawn('docker', [
      'ps',
      '-a',
      '--filter',
      `name=seer-thread-${threadId}-`,
      '--format',
      '{{.Names}}|{{.Status}}',
    ]);

    let stdout = '';
    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.on('close', () => {
      const containers = stdout
        .split('\n')
        .filter((l) => l.trim())
        .map((line) => {
          const [name, status] = line.split('|');
          const healthMatch = status.match(/\(([^)]+)\)/);
          return {
            name,
            status: status.split(' ')[0],
            health: healthMatch ? healthMatch[1] : 'unknown',
          };
        });
      resolve(containers);
    });
  });
}
