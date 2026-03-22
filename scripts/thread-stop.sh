#!/usr/bin/env bash
set -euo pipefail

# Stop backend + frontend processes for an ISO thread without cleanup
# Safe: kills only specific PIDs and their children, never process groups

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/config"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-stop.sh <thread-id>" >&2
    exit 1
fi

THREAD_ID="$1"
THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
PID_FILE="$THREAD_PARENT_DIR/.pids"

# Kill a process and its children recursively (SIGTERM, no group kills)
kill_tree() {
    local pid="$1"
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    # Kill children first
    local children
    children=$(pgrep -P "$pid" 2>/dev/null) || true
    for child in $children; do
        kill_tree "$child"
    done
    # Then kill the parent
    kill "$pid" 2>/dev/null || true
}

# Get ports from registry
THREAD_INFO=$("$SCRIPT_DIR/port-allocator.sh" get-info "$THREAD_ID" 2>/dev/null || echo "")
BACKEND_PORT=""
FRONTEND_PORT=""
if [[ -n "$THREAD_INFO" ]]; then
    IFS='|' read -r tid branch BACKEND_PORT FRONTEND_PORT wt_path created status <<< "$THREAD_INFO"
fi

# Kill by PID file
if [[ -f "$PID_FILE" ]]; then
    IFS='|' read -r backend_pid frontend_pid < "$PID_FILE"

    for pid in $backend_pid $frontend_pid; do
        if [[ -n "$pid" ]]; then
            kill_tree "$pid"
            echo "✓ Killed process tree for PID $pid"
        fi
    done

    rm -f "$PID_FILE"
else
    echo "No PID file found, will clean up by command match..."
fi

# Verify ports are clear — match on command string, NOT lsof (which catches VSCode proxies)
if [[ -n "$BACKEND_PORT" ]]; then
    remaining=$(pgrep -f "uvicorn.*port.*$BACKEND_PORT" 2>/dev/null || true)
    if [[ -n "$remaining" ]]; then
        echo "⚠ Rogue uvicorn on port $BACKEND_PORT (PIDs: $remaining) — killing"
        echo "$remaining" | xargs kill 2>/dev/null || true
        sleep 1
        still_there=$(pgrep -f "uvicorn.*port.*$BACKEND_PORT" 2>/dev/null || true)
        if [[ -n "$still_there" ]]; then
            echo "$still_there" | xargs kill -9 2>/dev/null || true
        fi
        echo "✓ Port $BACKEND_PORT cleared"
    fi
fi

if [[ -n "$FRONTEND_PORT" ]]; then
    remaining=$(pgrep -f "vite.*port.*$FRONTEND_PORT" 2>/dev/null || true)
    if [[ -n "$remaining" ]]; then
        echo "⚠ Rogue vite on port $FRONTEND_PORT (PIDs: $remaining) — killing"
        echo "$remaining" | xargs kill 2>/dev/null || true
        sleep 1
        still_there=$(pgrep -f "vite.*port.*$FRONTEND_PORT" 2>/dev/null || true)
        if [[ -n "$still_there" ]]; then
            echo "$still_there" | xargs kill -9 2>/dev/null || true
        fi
        echo "✓ Port $FRONTEND_PORT cleared"
    fi
fi

# Update status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "stopped" 2>/dev/null || true

echo "✓ Thread $THREAD_ID stopped"
