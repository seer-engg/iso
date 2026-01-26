# iso - Isolated Thread Manager

VS Code devcontainer-based parallel development for running multiple isolated Claude Code threads simultaneously with full-stack context.

## Problem

Running multiple Claude Code threads on the same repository causes conflicts:
- File changes overwrite each other
- Docker port collisions (5432, 6379, 8000)
- Shared database volumes corrupt state
- No independent verification
- Frontend and backend in separate contexts

## Solution

Each thread gets isolated with unified full-stack context:
- **Unified devcontainer** - Backend + frontend in single VS Code workspace
- **Git worktrees** - Separate working directories for both repos
- **Docker isolation** - Unique Postgres, Redis, network per thread
- **Auto-install dependencies** - `uv sync`, `aerich upgrade`, `bun install` run automatically
- **Claude Code full-stack context** - Edit backend API while viewing frontend components
- **Claude Code pre-installed** - CLI and VS Code extension included

## Quick Start

### One-Time Setup

```bash
# 1. Configure repo paths (both required for devcontainer approach)
cp config.example config
nano config
# Set: SEER_REPO_PATH=/Users/pika/Projects/seer
# Set: SEER_FRONTEND_PATH=/Users/pika/Projects/seer-frontend

# 2. Install VS Code Dev Containers extension
code --install-extension ms-vscode-remote.remote-containers

# 3. Add to PATH
echo 'export PATH="/Users/pika/Projects/iso:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Daily Workflow

```bash
# Start new thread
iso init "add-auth-feature" dev

# Open in VS Code
code /Users/pika/Projects/iso/worktrees/thread-1

# Click "Reopen in Container" when prompted
# Wait for devcontainer to build + auto-install dependencies (first time ~3-5 min)

# Dependencies are pre-installed - start services immediately:
cd /workspace/backend
uv run uvicorn seer.api.main:app --host 0.0.0.0 --port 8000 --reload

# In another terminal:
cd /workspace/frontend
bun dev --port 5173

# Claude Code now sees both backend/ and frontend/ in same session

# When done, cleanup
iso cleanup 1
```

## Commands

### iso init

Initialize a new isolated thread with unified devcontainer.

```bash
iso init <feature-name> [base-branch]

# Examples:
iso init "add-authentication" dev
iso init "fix-workflow-bug" main
```

**What it does:**
1. Allocates thread ID and ports
2. Creates unified parent directory: `worktrees/thread-N/`
3. Creates backend git worktree: `thread-N/backend/`
4. Creates frontend git worktree: `thread-N/frontend/`
5. Generates `.devcontainer/` with docker-compose.yml, Dockerfile
6. Creates .env files with thread-specific config
7. Prints `code` command to open in VS Code

**Does NOT start Docker** - VS Code handles container lifecycle when you "Reopen in Container"

### iso list

Display all active threads.

```bash
iso list

# Output:
# THREAD  BRANCH                 STATUS   BACKEND  FRONTEND
# 1       thread-1-add-auth      ready    3001     4001
# 2       thread-2-fix-bug       ready    3002     4002
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
1. Stops devcontainer
2. Removes Docker volumes and network
3. Removes backend and frontend worktrees
4. Removes parent directory
5. Updates registry
6. Preserves branch for PR history

**Aliases:** `iso clean`, `iso rm`

## Port Allocation

Simplified sequential port scheme:
- **Backend API**: 3000 + thread_id (Thread 1 = 3001, Thread 2 = 3002)
- **Frontend**: 4000 + thread_id (Thread 1 = 4001, Thread 2 = 4002)
- **Postgres/Redis**: Internal Docker network only (postgres:5432, redis:6379)

Main repo continues using default ports.

## Directory Structure

```
/Users/pika/Projects/
├── seer/                           # Main backend repo (unchanged)
├── seer-frontend/                  # Main frontend repo (unchanged)
└── iso/                            # ISO - manages all isolated threads
    ├── iso                         # Main CLI
    ├── scripts/
    │   ├── thread-init.sh          # Creates unified worktree + devcontainer
    │   ├── thread-cleanup.sh       # Cleans up thread resources
    │   ├── thread-list.sh
    │   ├── port-allocator.sh
    │   └── devcontainer-init.sh    # Generates .devcontainer/ from templates
    ├── templates/
    │   └── devcontainer/           # Devcontainer templates
    │       ├── devcontainer.json
    │       ├── docker-compose.yml
    │       ├── Dockerfile          # Python 3.12 + Node 20 + uv + Bun
    │       └── init-firewall.sh    # Firewall rules
    ├── worktrees/                  # All thread worktrees (unified structure)
    │   ├── .thread-registry
    │   ├── thread-1/               # Unified workspace for thread 1
    │   │   ├── .devcontainer/      # Generated from templates
    │   │   │   ├── devcontainer.json
    │   │   │   ├── docker-compose.yml
    │   │   │   ├── Dockerfile
    │   │   │   └── init-firewall.sh
    │   │   ├── backend/            # Backend git worktree
    │   │   │   ├── .env.thread
    │   │   │   └── [backend files]
    │   │   └── frontend/           # Frontend git worktree
    │   │       ├── .env
    │   │       └── [frontend files]
    │   └── thread-2/
    ├── config                      # Your config (gitignored)
    └── config.example
```

## Working in a Thread

### Opening the Thread

```bash
# After iso init, open in VS Code
code /Users/pika/Projects/iso/worktrees/thread-1

# Click "Reopen in Container"
# First time: Wait ~3-5 min for:
#   - Container build (~2 min)
#   - Dependencies installation via postCreateCommand (~1-2 min)
# Subsequent times: ~10-30 seconds (dependencies cached)
```

### Inside the Devcontainer

The workspace has both repos mounted:
- `/workspace/backend/` - Backend code
- `/workspace/frontend/` - Frontend code

```bash
# Dependencies are pre-installed - start services immediately:

# Start backend API
cd /workspace/backend
uv run uvicorn seer.api.main:app --host 0.0.0.0 --port 8000 --reload

# In another terminal, start frontend
cd /workspace/frontend
bun dev --port 5173

# Run backend tests
cd /workspace/backend
uv run pytest -m unit
uv run pytest -m integration

# Use Claude Code CLI
claude "What files are in /workspace/backend/src?"

# Claude Code sees both codebases
# Ask: "Read backend/src/api/workflows.py and frontend/src/components/WorkflowCanvas.tsx"
```

### Making Changes

```bash
# Commit from backend worktree
cd /workspace/backend
git add .
git commit -m "feat: add authentication endpoint"

# Commit from frontend worktree
cd /workspace/frontend
git add .
git commit -m "feat: add login form"

# Push both (same branch name)
cd /workspace/backend && git push origin thread-1-add-auth-feature
cd /workspace/frontend && git push origin thread-1-add-auth-feature

# Create PR (once, from either repo)
gh pr create --base dev
```

## Isolation & Security

### Thread Isolation

Each thread is completely isolated:

| Resource | Isolation Method |
|----------|------------------|
| Files | Separate git worktrees (backend + frontend) |
| Database | Unique Postgres instance with unique volume |
| Cache | Unique Redis instance with unique volume |
| Network | Thread-specific Docker network |
| Ports | Thread-specific ports (3001, 4001, etc.) |
| Secrets | Thread-specific .env files |
| Dependencies | Auto-installed via postCreateCommand |

**Result:** No cross-contamination, independent verification, parallel PRs, ready to use immediately.

## Claude Code Full-Stack Context

The unified devcontainer gives Claude Code access to both repos in a single session:

**What Claude can see:**
- Backend: `backend/src/`, `backend/tests/`
- Frontend: `frontend/src/`, `frontend/components/`

**Example prompts:**
```
"Read backend/src/api/workflows.py and frontend/src/components/WorkflowCanvas.tsx - what's the API contract?"

"Add a new endpoint POST /api/workflows/execute in backend, then update the frontend WorkflowCanvas to call it"

"The frontend expects {workflow_id, steps[]} but the backend returns {id, actions[]} - fix this mismatch"
```

## Devcontainer Details

### First-Time Build

The first time you open a thread, VS Code builds the devcontainer:
- Base image: Python 3.12 (mcr.microsoft.com/devcontainers/python:3.12-bookworm)
- Installs: Node 20, uv, Bun, git, curl, postgresql-client, redis-tools, Claude Code CLI
- Starts: postgres, redis containers
- Runs postCreateCommand: `uv sync`, `aerich upgrade`, `bun install`

**Build time:** ~3-5 minutes (cached after first build)

### Subsequent Opens

After first build:
- Reuses cached image + installed dependencies
- Starts postgres, redis

**Startup time:** ~10-20 seconds

### Customization

Edit templates before running `iso init`:
- `templates/devcontainer/devcontainer.json` - VS Code extensions, settings
- `templates/devcontainer/Dockerfile` - System packages, tools
- `templates/devcontainer/docker-compose.yml` - Services, ports
- `templates/devcontainer/init-deps.sh` - Dependency installation

Changes apply to new threads only. Existing threads keep their generated config.

## Troubleshooting

### Port conflicts

```bash
# Check what's using a port
lsof -i :3001

# Force cleanup and retry
iso cleanup 1
iso init "feature-name" dev
```

### Devcontainer won't start

```bash
# View logs in VS Code terminal or:
cd ~/Projects/iso/worktrees/thread-1/.devcontainer
docker compose logs

# Rebuild devcontainer
# In VS Code: Cmd+Shift+P → "Dev Containers: Rebuild Container"

# Or manually:
docker compose down -v
docker compose up -d --build
```

### Worktree corrupted

```bash
# Remove and recreate
cd /Users/pika/Projects/seer
git worktree remove --force /Users/pika/Projects/iso/worktrees/thread-1/backend
git worktree prune

cd /Users/pika/Projects/seer-frontend
git worktree remove --force /Users/pika/Projects/iso/worktrees/thread-1/frontend
git worktree prune

# Recreate thread
iso init "feature-name" dev
```

### Check thread registry

```bash
# View raw registry
cat ~/Projects/iso/worktrees/.thread-registry

# Format: thread_id|branch|backend_port|frontend_port|worktree_path|created_at|status
```

## Migration from Old ISO

### If you used ISO before devcontainer approach:

**Clean slate (recommended):**

```bash
# 1. Cleanup all existing threads
iso list
iso cleanup 1
iso cleanup 2
# ... cleanup all

# 2. New threads will use devcontainer approach
iso init "my-feature" dev
# Opens: code ~/Projects/iso/worktrees/thread-1
```

**No backward compatibility:** Old threads used `worktrees/backend/thread-N/` with `docker-compose.thread.yml`. New threads use `worktrees/thread-N/` with `.devcontainer/`. They're incompatible.

## Resource Requirements

For 5 threads (recommended max):
- **Disk**: ~10GB (2GB per devcontainer image + worktrees)
- **Memory**: ~8GB (1.5GB per devcontainer)
- **CPU**: ~1 core per thread during builds

**Recommended specs**: 16GB RAM, 8+ cores, 50GB free disk

## CI/CD Integration

Works seamlessly with existing GitHub Actions:
1. Each thread creates normal git branches (backend + frontend)
2. Push branches to origin
3. Create PR from branches
4. CI runs on PR as usual
5. Merge when ready

No changes needed to CI configuration.

## Advanced Usage

### Custom base branch

```bash
# Branch from main instead of dev
iso init "hotfix-auth" main
```

### Manual devcontainer rebuild

```bash
# In VS Code: Cmd+Shift+P → "Dev Containers: Rebuild Container"

# Or from terminal (outside devcontainer):
cd ~/Projects/iso/worktrees/thread-1/.devcontainer
docker compose down -v
docker compose up -d --build
```

### Check thread health

```bash
# Devcontainer running?
docker ps | grep seer-thread-1

# Database accessible?
docker exec seer-thread-1-postgres psql -U postgres -c "SELECT 1"

# API responding?
curl http://localhost:3001/health
```

## FAQ

**Q: Does this change my main seer/seer-frontend repos?**
A: No. Main repos remain completely untouched. All worktrees are in `~/Projects/iso/worktrees/`.

**Q: Can I use my main repos normally while threads are running?**
A: Yes. No port conflicts (main uses 5432/6379/8000, threads use 3001+/4001+).

**Q: What happens if I forget to cleanup threads?**
A: No problem. Use `iso list` to see all threads, cleanup anytime with `iso cleanup N`.

**Q: Do threads share git objects?**
A: Yes. Worktrees share `.git` from main repo, so they're space-efficient.

**Q: Can I create PRs from thread branches?**
A: Yes. Each thread creates real git branches in both repos. Push and PR normally.

**Q: Do pre-commit hooks run in threads?**
A: Yes. Worktrees share `.git/hooks`.

**Q: Does this require VS Code?**
A: Yes. Devcontainer approach is designed for VS Code. Alternatively, use `devcontainer` CLI.

**Q: Can I use Cursor instead of VS Code?**
A: Yes, if Cursor supports Dev Containers extension (check compatibility).

**Q: Why unified devcontainer instead of separate backend/frontend containers?**
A: Claude Code gets full-stack context. Edit backend API while viewing frontend types/components in same session. 90% of features touch both codebases.

## License

MIT
