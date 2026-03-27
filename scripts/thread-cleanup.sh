#!/usr/bin/env bash
set -euo pipefail

# ISO Thread Cleanup — safe cleanup with commit protection
# Refuses to delete worktrees with unpushed commits unless they can be pushed/bundled.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$(dirname "$SCRIPT_DIR")"

source "$ISO_DIR/config"
source "$SCRIPT_DIR/commit-guard.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-cleanup.sh <thread-id> [--force]" >&2
    exit 1
fi

THREAD_ID="$1"
FORCE="${2:-}"
THREAD_DIR="$ISO_DIR/worktrees/thread-$THREAD_ID"
PORTS_FILE="$ISO_DIR/ports/thread-$THREAD_ID"

if [[ ! -d "$THREAD_DIR" ]]; then
    echo "Error: Thread $THREAD_ID not found at $THREAD_DIR" >&2
    exit 1
fi

# Read branch name from worktree
BRANCH_NAME=""
for repo in backend frontend; do
    if [[ -d "$THREAD_DIR/$repo" ]]; then
        BRANCH_NAME=$(git -C "$THREAD_DIR/$repo" symbolic-ref --short HEAD 2>/dev/null || true)
        [[ -n "$BRANCH_NAME" ]] && break
    fi
done

BASE_BRANCH="dev"
BLOCKED=false

echo "=== Cleanup thread $THREAD_ID (branch: ${BRANCH_NAME:-unknown}) ==="

# Safety checks for each worktree
for repo in backend frontend; do
    worktree="$THREAD_DIR/$repo"
    [[ -d "$worktree" ]] || continue

    echo "Checking $repo..."
    unpushed=$(check_unpushed_commits "$worktree" "$BRANCH_NAME")

    if [[ "$unpushed" -gt 0 ]]; then
        echo "  $unpushed unpushed commit(s) in $repo"
        if ! push_or_backup "$worktree" "$BRANCH_NAME"; then
            BLOCKED=true
            echo "  BLOCKED: Cannot push $repo commits" >&2
        fi
    else
        echo "  All commits pushed"
    fi

    # Always create bundle as cheap insurance (may fail on empty diff — that's fine)
    create_bundle "$worktree" "$BRANCH_NAME" "$BASE_BRANCH" "$THREAD_ID" || true
done

if [[ "$BLOCKED" == true ]]; then
    echo ""
    echo "ABORT: Unpushed commits could not be pushed. Fix network/auth and retry." >&2
    echo "Bundles were saved to $BACKUP_DIR/ as partial backup." >&2
    exit 1
fi

# Stop services
echo "Stopping services..."
"$SCRIPT_DIR/thread-stop.sh" "$THREAD_ID" 2>/dev/null || true

# Remove worktrees
for repo in backend frontend; do
    worktree="$THREAD_DIR/$repo"
    [[ -d "$worktree" ]] || continue

    PARENT_REPO="$SEER_REPO_PATH"
    [[ "$repo" == "frontend" ]] && PARENT_REPO="$SEER_FRONTEND_PATH"

    git -C "$PARENT_REPO" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    echo "  Removed $repo worktree"

    # Delete local branch only (NOT remote)
    if [[ -n "$BRANCH_NAME" ]]; then
        git -C "$PARENT_REPO" branch -D "$BRANCH_NAME" 2>/dev/null || true
    fi
done

# Cleanup thread directory and port allocation
rm -rf "$THREAD_DIR"
rm -f "$PORTS_FILE"
rm -f "$ISO_DIR/ports/thread-${THREAD_ID}-backend.pid"
rm -f "$ISO_DIR/ports/thread-${THREAD_ID}-frontend.pid"

# Stop systemd service if exists
systemctl --user stop "iso-frontend@${THREAD_ID}" 2>/dev/null || true

echo ""
echo "✓ Thread $THREAD_ID cleaned up"
echo "  Remote branch '$BRANCH_NAME' preserved (use thread-archive.sh to delete)"
echo "  Bundles saved in $BACKUP_DIR/"
