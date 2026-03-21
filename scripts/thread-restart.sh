#!/usr/bin/env bash
set -euo pipefail

# Restart backend + frontend processes for an ISO thread

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-restart.sh <thread-id>" >&2
    exit 1
fi

THREAD_ID="$1"

echo "Restarting thread $THREAD_ID..."
"$SCRIPT_DIR/thread-stop.sh" "$THREAD_ID"
echo ""
"$SCRIPT_DIR/thread-start.sh" "$THREAD_ID"
