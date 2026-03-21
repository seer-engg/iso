#!/usr/bin/env bash
set -euo pipefail

# Start backend + frontend processes for an ISO thread

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/config"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-start.sh <thread-id>" >&2
    exit 1
fi

THREAD_ID="$1"

# Get thread info from registry
THREAD_INFO=$("$SCRIPT_DIR/port-allocator.sh" get-info "$THREAD_ID" 2>/dev/null || echo "")
if [[ -z "$THREAD_INFO" ]]; then
    echo "Error: Thread $THREAD_ID not found in registry" >&2
    exit 1
fi

IFS='|' read -r tid branch backend_port frontend_port wt_path created status <<< "$THREAD_INFO"

THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
BACKEND_WORKTREE="$THREAD_PARENT_DIR/backend"
FRONTEND_WORKTREE="$THREAD_PARENT_DIR/frontend"
LOG_DIR="$REPO_ROOT/worktrees/logs"
PID_FILE="$THREAD_PARENT_DIR/.pids"

mkdir -p "$LOG_DIR"

# Check worktrees exist
if [[ ! -d "$BACKEND_WORKTREE" ]]; then
    echo "Error: Backend worktree not found: $BACKEND_WORKTREE" >&2
    exit 1
fi
if [[ ! -d "$FRONTEND_WORKTREE" ]]; then
    echo "Error: Frontend worktree not found: $FRONTEND_WORKTREE" >&2
    exit 1
fi

# Install backend deps
echo "Installing backend dependencies..."
cd "$BACKEND_WORKTREE"
uv sync 2>&1 | tail -1
echo "✓ Backend dependencies installed"

# Install frontend deps
echo "Installing frontend dependencies..."
cd "$FRONTEND_WORKTREE"
npm install 2>&1 | tail -1
echo "✓ Frontend dependencies installed"

# Start backend
echo "Starting backend on port $backend_port..."
cd "$BACKEND_WORKTREE"
setsid nohup uv run uvicorn seer.api.main:app --host 0.0.0.0 --port "$backend_port" --reload \
    > "$LOG_DIR/thread-${THREAD_ID}-backend.log" 2>&1 &
BACKEND_PID=$!
echo "✓ Backend started (PID: $BACKEND_PID)"

# Start frontend
echo "Starting frontend on port $frontend_port..."
cd "$FRONTEND_WORKTREE"
setsid nohup npx vite --host 0.0.0.0 --port "$frontend_port" \
    > "$LOG_DIR/thread-${THREAD_ID}-frontend.log" 2>&1 &
FRONTEND_PID=$!
echo "✓ Frontend started (PID: $FRONTEND_PID)"

# Write PIDs
echo "${BACKEND_PID}|${FRONTEND_PID}" > "$PID_FILE"

# Update status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "running"

echo ""
echo "Services running:"
echo "  Backend API:  http://localhost:$backend_port"
echo "  Frontend Dev: http://localhost:$frontend_port"
echo "  Logs: $LOG_DIR/thread-${THREAD_ID}-{backend,frontend}.log"
