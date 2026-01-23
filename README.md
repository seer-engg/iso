# iso - Isolated Thread Manager

Git worktree-based parallel development for running multiple isolated Claude Code threads simultaneously.

## Problem

Running multiple Claude Code threads on the same repository causes conflicts:
- File changes overwrite each other
- Docker port collisions (5432, 6379, 8000)
- Shared database volumes corrupt state
- No independent verification

## Solution

Each thread gets isolated:
- **Git worktree** - Separate working directory
- **Docker environment** - Unique Postgres, Redis, API ports
- **Thread registry** - Track all active threads

## Quick Start

### One-Time Setup

```bash
# 1. Configure repo path
cp config.example config
nano config
# Set: SEER_REPO_PATH=/Users/pika/Projects/seer

# 2. (Optional) Configure frontend integration
# Add to config: SEER_FRONTEND_PATH=/Users/pika/Projects/seer-frontend
# This creates frontend worktrees automatically

# 3. Add to PATH
echo 'export PATH="/Users/pika/Projects/iso:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 4. (Optional) Install MCP server for Claude Desktop/Cursor
./install-mcp.sh
```

### Daily Workflow

```bash
# Start new thread
iso init "add-auth-feature" dev
cd /Users/pika/Projects/seer/.worktrees/thread-1
# Open Claude Code here

# Check active threads
iso list

# When done, create PR
git push origin thread-1-add-auth-feature
gh pr create --base dev

# Cleanup resources
iso cleanup 1
```

## Commands

### iso init

Initialize a new isolated thread.

```bash
iso init <feature-name> [base-branch]

# Examples:
iso init "add-authentication" dev
iso init "fix-workflow-bug" main
```

**What it does:**
1. Allocates thread ID and ports
2. Creates git worktree with new branch
3. Generates thread-specific docker-compose.yml
4. Creates .env.thread with unique DATABASE_URL, REDIS_URL
5. Starts Docker containers (postgres, redis, worker)
6. Runs database migrations
7. Shows connection details

### iso list

Display all active threads.

```bash
iso list

# Output:
# THREAD  BRANCH                 STATUS   BACKEND  FRONTEND  CONTAINERS
# 1       thread-1-add-auth      active   3001     4001      3 running
# 2       thread-2-fix-bug       active   3002     4002      3 running
```

**Aliases:** `iso ls`

### iso cleanup

Clean up thread resources.

```bash
iso cleanup <thread-id>

# Example:
iso cleanup 1
```

**What it does:**
1. Stops Docker containers
2. Removes volumes
3. Removes worktree
4. Updates registry
5. Preserves branch for PR history

**Aliases:** `iso clean`, `iso rm`

## Port Allocation

Simplified sequential port scheme:
- **Backend API**: 3000 + thread_id (Thread 1 = 3001, Thread 2 = 3002, ...)
- **Frontend**: 4000 + thread_id (Thread 1 = 4001, Thread 2 = 4002, ...)
- **Postgres/Redis**: Internal Docker network only (postgres:5432, redis:6379)

Main repo continues using default ports (5432, 6379, 8000).

## Directory Structure

```
/Users/pika/Projects/
├── seer/                           # Main repo (unchanged)
│   ├── src/, tests/, etc.          # Source code
│   └── .worktrees/                 # Created by iso (gitignored)
│       ├── thread-1/               # Isolated worktree for thread 1
│       │   ├── docker-compose.thread.yml
│       │   ├── .env.thread
│       │   └── [full repo files]
│       ├── thread-2/
│       └── .thread-registry        # Active threads tracking
└── iso/                            # This repo
    ├── iso                         # Main CLI (add to PATH)
    ├── scripts/
    │   ├── thread-init.sh
    │   ├── thread-cleanup.sh
    │   ├── thread-list.sh
    │   └── port-allocator.sh
    ├── templates/
    │   └── docker-compose.thread.template.yml
    ├── mcp-server/                 # MCP server for Claude Desktop
    │   ├── src/
    │   ├── dist/
    │   └── package.json
    ├── worktrees/                  # Frontend worktrees
    │   └── frontend/
    │       ├── thread-1/
    │       └── thread-2/
    ├── config                      # Your config (gitignored)
    └── config.example
```

## Working in a Thread

```bash
# Navigate to thread
cd /Users/pika/Projects/seer/.worktrees/thread-1

# View logs
docker compose -f docker-compose.thread.yml logs -f api

# Run tests
uv run pytest -m unit           # SQLite (fast)
uv run pytest -m integration    # Thread's Postgres (isolated)

# Test API (use your thread's backend port)
curl http://localhost:3001/health

# Commit and push
git add .
git commit -m "feat: add authentication"
git push origin thread-1-add-auth-feature
```

## Frontend Integration

If `SEER_FRONTEND_PATH` is configured in `config`, ISO automatically:
- Creates frontend worktree in `iso/worktrees/frontend/thread-N/`
- Sets `VITE_BACKEND_API_URL=http://localhost:<backend-port>` in worktree .env
- Sets `VITE_DEV_PORT=<frontend-port>` for isolated frontend dev server
- Removes frontend worktree when thread is cleaned up

**Starting frontend for a thread:**
```bash
cd iso/worktrees/frontend/thread-1
bun dev  # Runs on port 4001
```

**Manual frontend setup** (if not using ISO integration):
```bash
# In seer-frontend/.env
VITE_BACKEND_API_URL=http://localhost:3001  # Use thread's backend port
```

## Isolation Benefits

Each thread is completely isolated:

| Resource | Isolation Method |
|----------|------------------|
| Files | Separate git worktree |
| Database | Unique Postgres instance on unique port |
| Cache | Unique Redis instance on unique port |
| API | Unique port per thread |
| Docker | Thread-specific container names, volumes, networks |

**Result:** No cross-contamination, independent verification, parallel PRs.

## Troubleshooting

## MCP Integration

ISO can be used from Claude Desktop, Cursor, and other MCP-compatible AI tools.

### Installation

```bash
./install-mcp.sh
```

Add to Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "iso": {
      "command": "node",
      "args": ["/Users/pika/Projects/iso/mcp-server/dist/index.js"]
    }
  }
}
```

### Available MCP Tools

- **iso_init_thread**: Create new thread
- **iso_list_threads**: List all threads with status
- **iso_get_thread_info**: Get detailed thread info
- **iso_cleanup_thread**: Clean up thread resources

See [mcp-server/README.md](mcp-server/README.md) for detailed documentation.

## Troubleshooting

### Port conflicts

```bash
# Check what's using a port
lsof -i :3001

# Force cleanup and retry
iso cleanup 1
iso init "feature-name" dev
```

### Docker issues

```bash
# View thread logs
cd .worktrees/thread-1
docker compose -f docker-compose.thread.yml logs

# Rebuild containers
docker compose -f docker-compose.thread.yml up -d --build

# Full reset
docker compose -f docker-compose.thread.yml down -v
docker compose -f docker-compose.thread.yml up -d
```

### Worktree corrupted

```bash
# Remove and recreate
cd /Users/pika/Projects/seer
git worktree remove --force .worktrees/thread-1
git worktree prune
iso init "feature-name" dev
```

### Check thread registry

```bash
# View raw registry
cat /Users/pika/Projects/seer/.worktrees/.thread-registry

# Format: thread_id|branch|backend_port|frontend_port|worktree_path|created_at|status
```

## Resource Requirements

For 5 threads (recommended max):
- **Disk**: ~1.25GB (250MB per thread)
- **Memory**: ~2.5GB (500MB per thread)
- **CPU**: ~1 core per thread during builds/tests

**Recommended specs**: 16GB RAM, 8+ cores, 20GB free disk

## CI/CD Integration

Works seamlessly with existing GitHub Actions:
1. Each thread creates a normal git branch
2. Push branch to origin
3. Create PR from branch
4. CI runs on PR as usual
5. Merge when ready

No changes needed to CI configuration.

## Advanced Usage

### Custom base branch

```bash
# Branch from main instead of dev
iso init "hotfix-auth" main
```

### Multiple seer repos

```bash
# In config file:
SEER_REPO_PATH="/Users/pika/Projects/seer"
SEER_REPO_PATH_2="/Users/pika/Projects/seer-fork"

# Use with environment variable:
SEER_REPO_PATH="/Users/pika/Projects/seer-fork" iso init "test" dev
```

### Check thread health

```bash
# Thread containers running?
docker ps | grep seer-thread-1

# Thread database accessible? (only from within Docker containers)
docker exec seer-thread-1-postgres psql -U postgres -c "SELECT 1"

# Thread API responding?
curl http://localhost:3001/health
```

## FAQ

**Q: Does this change my main seer repo?**
A: No. The main repo at `/Users/pika/Projects/seer` remains untouched. Only `.worktrees/` directory is created (already gitignored).

**Q: Can I use my main repo normally while threads are running?**
A: Yes. Main repo's docker-compose.yml uses default ports (5432, 6379, 8000), which don't conflict with thread ports (3001+, 4001+).

**Q: What happens if I forget to cleanup threads?**
A: No problem. Use `iso list` to see all active threads, cleanup anytime with `iso cleanup N`.

**Q: Do threads share git objects?**
A: Yes. Worktrees share the same `.git` directory, so they're space-efficient (only ~50MB per worktree).

**Q: Can I create PRs from thread branches?**
A: Yes. Each thread is a real git branch. Push and create PRs normally.

**Q: Do pre-commit hooks run in threads?**
A: Yes. Worktrees share `.git/hooks`.

## License

MIT
