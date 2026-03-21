#!/usr/bin/env bash
set -euo pipefail

# Rebase thread branch on latest dev, then push to origin
# Usage: thread-push.sh <thread-id> [repo]
#   repo: "backend", "frontend", or "both" (default: both)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/config"

if [[ $# -lt 1 ]]; then
    echo "Usage: thread-push.sh <thread-id> [backend|frontend|both]" >&2
    exit 1
fi

THREAD_ID="$1"
TARGET="${2:-both}"

THREAD_INFO=$("$SCRIPT_DIR/port-allocator.sh" get-info "$THREAD_ID" 2>/dev/null || echo "")
if [[ -z "$THREAD_INFO" ]]; then
    echo "Error: Thread $THREAD_ID not found" >&2
    exit 1
fi

IFS='|' read -r tid branch backend_port frontend_port wt_path created status <<< "$THREAD_INFO"

THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"

rebase_and_push() {
    local worktree="$1"
    local label="$2"

    if [[ ! -d "$worktree" ]]; then
        echo "⚠ $label worktree not found, skipping"
        return 0
    fi

    echo "=== $label ==="
    cd "$worktree"

    # Check for uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "✗ $label has uncommitted changes — commit or stash first" >&2
        return 1
    fi

    echo "Fetching origin..."
    git fetch origin dev

    echo "Rebasing on origin/dev..."
    if ! git rebase origin/dev; then
        echo "✗ Rebase conflict in $label — resolve manually, then run:" >&2
        echo "  cd $worktree && git rebase --continue && git push -u origin $branch" >&2
        git rebase --abort 2>/dev/null || true
        return 1
    fi

    echo "Pushing to origin..."
    git push -u origin "$branch" --force-with-lease

    echo "✓ $label pushed (rebased on dev)"
    echo ""
}

if [[ "$TARGET" == "backend" ]] || [[ "$TARGET" == "both" ]]; then
    rebase_and_push "$THREAD_PARENT_DIR/backend" "Backend"
fi

if [[ "$TARGET" == "frontend" ]] || [[ "$TARGET" == "both" ]]; then
    rebase_and_push "$THREAD_PARENT_DIR/frontend" "Frontend"
fi

echo "✓ Thread $THREAD_ID pushed to origin/$branch"
