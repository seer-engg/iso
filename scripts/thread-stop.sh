#!/usr/bin/env bash
set -euo pipefail

# Stop backend stack (docker compose) + frontend (systemd) for an ISO thread
# Safe: no process killing, no pattern matching, no PID files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/config"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-stop.sh <thread-id>" >&2
    exit 1
fi

THREAD_ID="$1"
THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
BACKEND_WORKTREE="$THREAD_PARENT_DIR/backend"

# Stop backend stack via docker compose
if [[ -f "$BACKEND_WORKTREE/.env.thread" ]]; then
    cd "$BACKEND_WORKTREE"
    docker compose --env-file .env --env-file .env.thread stop 2>/dev/null && echo "✓ Backend stack stopped" || echo "  Backend stack was not running"
else
    echo "  No .env.thread found, skipping docker compose stop"
fi

# Stop frontend via systemd
systemctl --user stop "iso-frontend@${THREAD_ID}" 2>/dev/null && echo "✓ Frontend stopped" || echo "  Frontend was not running"

# Clean up legacy PID file if present
rm -f "$THREAD_PARENT_DIR/.pids"

# Update status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "stopped" 2>/dev/null || true

echo "✓ Thread $THREAD_ID stopped"
