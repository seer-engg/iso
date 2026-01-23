#!/usr/bin/env bash
set -euo pipefail

# Clean up thread resources (containers, volumes, worktree)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [[ ! -f "$REPO_ROOT/config" ]]; then
    echo "Error: Config file not found. Run: cp config.example config" >&2
    exit 1
fi

source "$REPO_ROOT/config"

if [[ -z "${SEER_REPO_PATH:-}" ]]; then
    echo "Error: SEER_REPO_PATH not set in config" >&2
    exit 1
fi

if [[ ! -d "$SEER_REPO_PATH" ]]; then
    echo "Error: SEER_REPO_PATH does not exist: $SEER_REPO_PATH" >&2
    exit 1
fi

# Usage
if [[ $# -lt 1 ]]; then
    echo "Usage: thread-cleanup.sh <thread-id>" >&2
    echo "" >&2
    echo "Example: thread-cleanup.sh 1" >&2
    exit 1
fi

THREAD_ID="$1"

# Validate thread ID
if ! [[ "$THREAD_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid thread ID: $THREAD_ID" >&2
    exit 1
fi

# Get thread info
THREAD_INFO=$("$SCRIPT_DIR/port-allocator.sh" get-info "$THREAD_ID" 2>/dev/null || echo "")

if [[ -z "$THREAD_INFO" ]]; then
    echo "Error: Thread $THREAD_ID not found in registry" >&2
    exit 1
fi

# Parse thread info
IFS='|' read -r tid branch pg_port redis_port api_port worker_port wt_path created status <<< "$THREAD_INFO"

# Display thread info
echo "Thread $THREAD_ID details:"
echo "  Branch: $branch"
echo "  Worktree: $wt_path"
echo "  Postgres: localhost:$pg_port"
echo "  API: localhost:$api_port"
echo "  Status: $status"
echo "  Created: $created"
echo ""

# Confirm cleanup
read -p "Are you sure you want to cleanup thread $THREAD_ID? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "Cleaning up thread $THREAD_ID..."
echo ""

# Change to seer repo
cd "$SEER_REPO_PATH"

# Stop and remove Docker containers
if [[ -f "$wt_path/docker-compose.thread.yml" ]]; then
    echo "Stopping Docker containers..."
    if docker compose -f "$wt_path/docker-compose.thread.yml" down -v 2>&1; then
        echo "✓ Containers stopped and removed"
    else
        echo "Warning: Failed to stop containers, they may not be running" >&2
    fi
else
    echo "Warning: docker-compose.thread.yml not found, skipping container cleanup" >&2
fi

echo ""

# Remove Docker volumes (belt and suspenders approach)
echo "Removing Docker volumes..."
VOLUMES=(
    "seer-thread-${THREAD_ID}-postgres_data"
    "seer-thread-${THREAD_ID}-redis_data"
)

for volume in "${VOLUMES[@]}"; do
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        if docker volume rm "$volume" 2>&1; then
            echo "✓ Removed volume: $volume"
        else
            echo "Warning: Failed to remove volume: $volume" >&2
        fi
    fi
done

echo ""

# Remove Docker network (if exists)
NETWORK="seer-thread-${THREAD_ID}-network"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    if docker network rm "$NETWORK" 2>&1; then
        echo "✓ Removed network: $NETWORK"
    else
        echo "Warning: Failed to remove network: $NETWORK" >&2
    fi
fi

echo ""

# Restore frontend .env if it was modified
if [[ -n "${SEER_FRONTEND_PATH:-}" ]] && [[ -d "$SEER_FRONTEND_PATH" ]]; then
    if [[ -f "$SEER_FRONTEND_PATH/.env.original" ]]; then
        echo "Restoring frontend configuration..."
        mv "$SEER_FRONTEND_PATH/.env.original" "$SEER_FRONTEND_PATH/.env"
        echo "✓ Frontend .env restored to original"
        echo ""
    fi
fi

# Remove worktree
if [[ -d "$wt_path" ]]; then
    echo "Removing worktree..."
    if git worktree remove "$wt_path" 2>&1; then
        echo "✓ Worktree removed"
    else
        echo "Warning: Failed to remove worktree normally, trying force..." >&2
        if git worktree remove --force "$wt_path" 2>&1; then
            echo "✓ Worktree force removed"
        else
            echo "Error: Failed to remove worktree: $wt_path" >&2
        fi
    fi
else
    echo "Warning: Worktree directory not found: $wt_path" >&2
fi

# Prune worktrees
git worktree prune 2>/dev/null || true

echo ""

# Remove from registry
echo "Updating registry..."
"$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
echo "✓ Thread removed from registry"

echo ""
echo "=========================================="
echo "Thread $THREAD_ID cleanup complete!"
echo "=========================================="
echo ""
echo "Branch '$branch' has been preserved."
echo "You can still create a PR from this branch if needed:"
echo "  git push origin $branch"
echo "  gh pr create --base dev"
echo ""
echo "To delete the branch:"
echo "  git branch -D $branch"
echo "  git push origin --delete $branch"
echo "=========================================="
