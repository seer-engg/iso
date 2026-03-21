#!/usr/bin/env bash
set -euo pipefail

# Stop backend + frontend processes for an ISO thread without cleanup

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

# Kill a process and all its children via process group
kill_tree() {
    local pid="$1"
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    # Try process group kill first
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ') || true
    if [[ -n "$pgid" ]] && [[ "$pgid" != "0" ]]; then
        kill -- -"$pgid" 2>/dev/null || true
    fi
    # Fallback: kill children then parent
    pkill -P "$pid" 2>/dev/null || true
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
        kill_tree "$pid"
        echo "✓ Killed process tree for PID $pid"
    done

    rm -f "$PID_FILE"
else
    echo "No PID file found, will clean up by port..."
fi

# Always verify ports are clear (catches orphans the PID kill missed)
for port in $BACKEND_PORT $FRONTEND_PORT; do
    if [[ -z "$port" ]]; then continue; fi
    remaining=$(lsof -ti :"$port" 2>/dev/null || true)
    if [[ -n "$remaining" ]]; then
        echo "⚠ Rogue process on port $port (PIDs: $remaining) — force killing"
        echo "$remaining" | xargs kill -9 2>/dev/null || true
        sleep 0.5
        # Final check
        still_there=$(lsof -ti :"$port" 2>/dev/null || true)
        if [[ -n "$still_there" ]]; then
            echo "✗ Failed to free port $port (PIDs: $still_there)" >&2
        else
            echo "✓ Port $port cleared"
        fi
    fi
done

# Update status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "stopped" 2>/dev/null || true

echo "✓ Thread $THREAD_ID stopped"
