#!/usr/bin/env bash
set -euo pipefail

# Start backend stack (docker compose) + frontend (systemd) for an ISO thread

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

# Check worktrees exist
if [[ ! -d "$BACKEND_WORKTREE" ]]; then
    echo "Error: Backend worktree not found: $BACKEND_WORKTREE" >&2
    exit 1
fi
if [[ ! -d "$FRONTEND_WORKTREE" ]]; then
    echo "Error: Frontend worktree not found: $FRONTEND_WORKTREE" >&2
    exit 1
fi

# Start backend stack via docker compose (postgres, redis, api, worker, migrations)
echo "Starting backend stack on port $backend_port..."
cd "$BACKEND_WORKTREE"

if [[ ! -f ".env.thread" ]]; then
    echo "Error: .env.thread not found. Was this thread initialized with the new ISO?" >&2
    exit 1
fi

docker compose --env-file .env --env-file .env.thread up -d --build
echo "✓ Backend stack started (api, worker, postgres, valkey)"

# Install frontend deps + start via systemd
echo "Installing frontend dependencies..."
cd "$FRONTEND_WORKTREE"
npm install 2>&1 | tail -1
echo "✓ Frontend dependencies installed"

# Write systemd env file
cat > "$THREAD_PARENT_DIR/.env" <<EOF
BACKEND_PORT=$backend_port
FRONTEND_PORT=$frontend_port
EOF

systemctl --user daemon-reload
echo "Starting frontend on port $frontend_port..."
systemctl --user start "iso-frontend@${THREAD_ID}"
echo "✓ Frontend started"

# Update status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "running"

echo ""
echo "Services running:"
echo "  Backend API:  http://localhost:$backend_port"
echo "  Frontend Dev: http://localhost:$frontend_port"
echo "  Containers:   docker ps --filter name=seer-thread-$THREAD_ID"
echo "  Backend logs: docker compose --env-file .env --env-file .env.thread logs -f"
echo "  Frontend log: journalctl --user -u iso-frontend@${THREAD_ID} -f"
