#!/usr/bin/env bash
# ISO Thread Init - creates isolated worktrees with allocated ports
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_DIR="$(dirname "$SCRIPT_DIR")"
source "$ISO_DIR/config" 2>/dev/null || { echo "Run setup.sh first" >&2; exit 1; }

FEATURE_NAME="${1:?Usage: thread-init.sh <feature-name> [base-branch]}"
BASE_BRANCH="${2:-dev}"

WORKTREES_DIR="$ISO_DIR/worktrees"
PORTS_DIR="$ISO_DIR/ports"
LOGS_DIR="$WORKTREES_DIR/logs"
mkdir -p "$WORKTREES_DIR" "$PORTS_DIR" "$LOGS_DIR"

# Allocate thread ID (next available)
THREAD_ID=1
while [ -d "$WORKTREES_DIR/thread-$THREAD_ID" ] || [ -f "$PORTS_DIR/thread-$THREAD_ID" ]; do
  THREAD_ID=$((THREAD_ID + 1))
done

# Allocate ports
# port-allocator.sh is a CLI tool, not a sourceable library — skip it
# Ports are computed inline below
BACKEND_PORT=$((3000 + THREAD_ID))
FRONTEND_PORT=$((4000 + THREAD_ID))

# Save port allocation
echo "BACKEND_PORT=$BACKEND_PORT" > "$PORTS_DIR/thread-$THREAD_ID"
echo "FRONTEND_PORT=$FRONTEND_PORT" >> "$PORTS_DIR/thread-$THREAD_ID"

THREAD_DIR="$WORKTREES_DIR/thread-$THREAD_ID"
BRANCH_NAME="thread-${THREAD_ID}/${FEATURE_NAME}"

# Create backend worktree
echo "Creating backend worktree..."
cd "$SEER_REPO_PATH"
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
git worktree add "$THREAD_DIR/backend" -b "$BRANCH_NAME" "origin/$BASE_BRANCH"

# Install post-commit hook for backend (auto-push on commit)
BACKEND_GITDIR=$(git -C "$THREAD_DIR/backend" rev-parse --git-dir)
mkdir -p "$BACKEND_GITDIR/hooks"
cat > "$BACKEND_GITDIR/hooks/post-commit" << 'HOOK'
#!/usr/bin/env bash
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
[[ -n "$branch" ]] && git push origin "$branch" 2>/dev/null &
HOOK
chmod +x "$BACKEND_GITDIR/hooks/post-commit"

# Push initial branch to origin so tracking exists
cd "$THREAD_DIR/backend" && git push -u origin "$BRANCH_NAME" 2>/dev/null || true

# Create frontend worktree
echo "Creating frontend worktree..."
cd "$SEER_FRONTEND_PATH"
git worktree add "$THREAD_DIR/frontend" -b "$BRANCH_NAME" "origin/$BASE_BRANCH"

# Install post-commit hook for frontend (auto-push on commit)
FRONTEND_GITDIR=$(git -C "$THREAD_DIR/frontend" rev-parse --git-dir)
mkdir -p "$FRONTEND_GITDIR/hooks"
cat > "$FRONTEND_GITDIR/hooks/post-commit" << 'HOOK'
#!/usr/bin/env bash
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
[[ -n "$branch" ]] && git push origin "$branch" 2>/dev/null &
HOOK
chmod +x "$FRONTEND_GITDIR/hooks/post-commit"

# Push initial branch to origin so tracking exists
cd "$THREAD_DIR/frontend" && git push -u origin "$BRANCH_NAME" 2>/dev/null || true

# Install backend deps
echo "Installing backend dependencies..."
cd "$THREAD_DIR/backend"
uv sync 2>&1 | tail -1 || true

# Install frontend deps
echo "Installing frontend dependencies..."
cd "$THREAD_DIR/frontend"
npm install 2>&1 | tail -1 || true

# Start backend
echo "Starting backend on port $BACKEND_PORT..."
cd "$THREAD_DIR/backend"
PORT=$BACKEND_PORT nohup uv run uvicorn src.seer.api.main:app --host 0.0.0.0 --port $BACKEND_PORT > "$LOGS_DIR/thread-${THREAD_ID}-backend.log" 2>&1 &
echo $! > "$PORTS_DIR/thread-${THREAD_ID}-backend.pid"

# Start frontend
echo "Starting frontend on port $FRONTEND_PORT..."
cd "$THREAD_DIR/frontend"
PORT=$FRONTEND_PORT nohup npm run dev -- --port $FRONTEND_PORT > "$LOGS_DIR/thread-${THREAD_ID}-frontend.log" 2>&1 &
echo $! > "$PORTS_DIR/thread-${THREAD_ID}-frontend.pid"

echo ""
echo "✓ Thread $THREAD_ID allocated"
echo "  Branch:   $BRANCH_NAME"
echo "  Worktree: $THREAD_DIR"
echo "  Backend:  localhost:$BACKEND_PORT"
echo "  Frontend: localhost:$FRONTEND_PORT"
echo "  Logs:     $LOGS_DIR/thread-${THREAD_ID}-*.log"
