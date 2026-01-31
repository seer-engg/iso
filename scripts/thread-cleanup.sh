#!/usr/bin/env bash
set -euo pipefail

# Clean up thread resources (devcontainer, volumes, worktrees)
# Handles unified worktree structure with backend + frontend

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
    echo "Usage: thread-cleanup.sh <thread-id> [--force]" >&2
    echo "" >&2
    echo "Example: thread-cleanup.sh 1" >&2
    echo "  --force: Skip confirmation prompt" >&2
    exit 1
fi

THREAD_ID="$1"
FORCE_CLEANUP=false

# Check for --force flag
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE_CLEANUP=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

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
IFS='|' read -r tid branch backend_port frontend_port wt_path created status <<< "$THREAD_INFO"

# Determine actual worktree path (new unified structure)
THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
BACKEND_WORKTREE="$THREAD_PARENT_DIR/backend"
FRONTEND_WORKTREE="$THREAD_PARENT_DIR/frontend"
SALES_CX_WORKTREE="$THREAD_PARENT_DIR/sales-cx"
WEBSITE_WORKTREE="$THREAD_PARENT_DIR/website"

# Display thread info
echo "Thread $THREAD_ID details:"
echo "  Branch: $branch"
echo "  Workspace: $THREAD_PARENT_DIR"
echo "  Backend: localhost:$backend_port"
echo "  Frontend: localhost:$frontend_port"
echo "  Status: $status"
echo "  Created: $created"
echo ""

# Confirm cleanup
if [[ "$FORCE_CLEANUP" != "true" ]]; then
    read -p "Are you sure you want to cleanup thread $THREAD_ID? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled"
        exit 0
    fi
fi

echo ""
echo "Cleaning up thread $THREAD_ID..."
echo ""

# Stop devcontainer if running
DEVCONTAINER_COMPOSE="$THREAD_PARENT_DIR/.devcontainer/docker-compose.yml"
if [[ -f "$DEVCONTAINER_COMPOSE" ]]; then
    echo "Stopping devcontainer..."
    cd "$THREAD_PARENT_DIR/.devcontainer"
    if docker compose down -v 2>&1; then
        echo "✓ Devcontainer stopped and removed"
    else
        echo "Warning: Failed to stop devcontainer, it may not be running" >&2
    fi
    cd "$REPO_ROOT"
else
    echo "Warning: Devcontainer compose file not found, skipping container cleanup" >&2
fi

echo ""

# Remove Docker volumes
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

# Remove Docker network
NETWORK="seer-thread-${THREAD_ID}-network"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    if docker network rm "$NETWORK" 2>&1; then
        echo "✓ Removed network: $NETWORK"
    else
        echo "Warning: Failed to remove network: $NETWORK" >&2
    fi
fi

echo ""

# Remove backend worktree
if [[ -d "$BACKEND_WORKTREE" ]]; then
    echo "Removing backend worktree..."
    cd "$SEER_REPO_PATH"
    if git worktree remove "$BACKEND_WORKTREE" 2>&1; then
        echo "✓ Backend worktree removed"
    else
        echo "Warning: Failed to remove backend worktree normally, trying force..." >&2
        if git worktree remove --force "$BACKEND_WORKTREE" 2>&1; then
            echo "✓ Backend worktree force removed"
        else
            echo "Warning: Failed to remove backend worktree: $BACKEND_WORKTREE" >&2
        fi
    fi
    git worktree prune 2>/dev/null || true
fi

echo ""

# Remove frontend worktree
if [[ -n "${SEER_FRONTEND_PATH:-}" ]] && [[ -d "$SEER_FRONTEND_PATH" ]] && [[ -d "$FRONTEND_WORKTREE" ]]; then
    echo "Removing frontend worktree..."
    cd "$SEER_FRONTEND_PATH"
    if git worktree remove "$FRONTEND_WORKTREE" 2>&1; then
        echo "✓ Frontend worktree removed"
    else
        echo "Warning: Failed to remove frontend worktree normally, trying force..." >&2
        if git worktree remove --force "$FRONTEND_WORKTREE" 2>&1; then
            echo "✓ Frontend worktree force removed"
        else
            echo "Warning: Failed to remove frontend worktree: $FRONTEND_WORKTREE" >&2
        fi
    fi
    git worktree prune 2>/dev/null || true
    cd "$REPO_ROOT"
fi

echo ""

# Remove sales-cx worktree (optional)
if [[ -n "${SALES_CX_REPO_PATH:-}" ]] && [[ -d "$SALES_CX_REPO_PATH" ]] && [[ -d "$SALES_CX_WORKTREE" ]]; then
    echo "Removing sales-cx worktree..."
    cd "$SALES_CX_REPO_PATH"
    if git worktree remove "$SALES_CX_WORKTREE" 2>&1; then
        echo "✓ Sales-CX worktree removed"
    else
        echo "Warning: Failed to remove sales-cx worktree normally, trying force..." >&2
        if git worktree remove --force "$SALES_CX_WORKTREE" 2>&1; then
            echo "✓ Sales-CX worktree force removed"
        else
            echo "Warning: Failed to remove sales-cx worktree: $SALES_CX_WORKTREE" >&2
        fi
    fi
    git worktree prune 2>/dev/null || true
    cd "$REPO_ROOT"
fi

echo ""

# Remove seer-website worktree (optional)
if [[ -n "${SEER_WEBSITE_PATH:-}" ]] && [[ -d "$SEER_WEBSITE_PATH" ]] && [[ -d "$WEBSITE_WORKTREE" ]]; then
    echo "Removing seer-website worktree..."
    cd "$SEER_WEBSITE_PATH"
    if git worktree remove "$WEBSITE_WORKTREE" 2>&1; then
        echo "✓ Seer-website worktree removed"
    else
        echo "Warning: Failed to remove seer-website worktree normally, trying force..." >&2
        if git worktree remove --force "$WEBSITE_WORKTREE" 2>&1; then
            echo "✓ Seer-website worktree force removed"
        else
            echo "Warning: Failed to remove seer-website worktree: $WEBSITE_WORKTREE" >&2
        fi
    fi
    git worktree prune 2>/dev/null || true
    cd "$REPO_ROOT"
fi

echo ""

# Remove parent directory (includes .devcontainer and any remaining files)
if [[ -d "$THREAD_PARENT_DIR" ]]; then
    echo "Removing thread parent directory..."
    rm -rf "$THREAD_PARENT_DIR"
    echo "✓ Thread directory removed: $THREAD_PARENT_DIR"
fi

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
echo "Branch '$branch' has been preserved in both repos."
echo "You can still create a PR from this branch if needed:"
echo "  git push origin $branch"
echo "  gh pr create --base dev"
echo ""
echo "To delete the branch from all repos:"
echo "  cd $SEER_REPO_PATH && git branch -D $branch"
echo "  cd $SEER_FRONTEND_PATH && git branch -D $branch"
if [[ -n "${SALES_CX_REPO_PATH:-}" ]] && [[ -d "$SALES_CX_REPO_PATH" ]]; then
    echo "  cd $SALES_CX_REPO_PATH && git branch -D $branch"
fi
if [[ -n "${SEER_WEBSITE_PATH:-}" ]] && [[ -d "$SEER_WEBSITE_PATH" ]]; then
    echo "  cd $SEER_WEBSITE_PATH && git branch -D $branch"
fi
echo "  git push origin --delete $branch"
echo "=========================================="
