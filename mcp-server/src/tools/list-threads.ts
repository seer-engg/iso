import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { spawn } from 'child_process';
import { getIsoPaths } from '../utils/iso-paths.js';

export interface ThreadInfo {
  threadId: number;
  branch: string;
  backendPort: number;
  frontendPort: number;
  worktreePath: string;
  created: string;
  status: string;
  containers?: {
    total: number;
    running: number;
  };
}

export async function listThreads(): Promise<ThreadInfo[]> {
  const paths = getIsoPaths();
  const registryPath = join(paths.repoRoot, 'worktrees', '.thread-registry');

  if (!existsSync(registryPath)) {
    return [];
  }

  const registryContent = readFileSync(registryPath, 'utf-8');
  const threads: ThreadInfo[] = [];

  for (const line of registryContent.split('\n')) {
    if (!line.trim()) continue;

    const parts = line.split('|');
    if (parts.length < 7) continue;

    const [threadId, branch, backendPort, frontendPort, worktreePath, created, status] = parts;

    threads.push({
      threadId: parseInt(threadId),
      branch,
      backendPort: parseInt(backendPort),
      frontendPort: parseInt(frontendPort),
      worktreePath,
      created,
      status,
    });
  }

  // Enhance with Docker container status
  for (const thread of threads) {
    const containers = await getContainerStatus(thread.threadId);
    thread.containers = containers;
  }

  return threads;
}

async function getContainerStatus(threadId: number): Promise<{ total: number; running: number }> {
  return new Promise((resolve) => {
    const proc = spawn('docker', [
      'ps',
      '-a',
      '--filter',
      `name=seer-thread-${threadId}-`,
      '--format',
      '{{.Status}}',
    ]);

    let stdout = '';
    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.on('close', () => {
      const lines = stdout.split('\n').filter((l) => l.trim());
      const total = lines.length;
      const running = lines.filter((l) => l.startsWith('Up')).length;
      resolve({ total, running });
    });
  });
}
