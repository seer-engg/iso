#!/usr/bin/env bash
set -euo pipefail

# List all active threads with status

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

REGISTRY_FILE="$SEER_REPO_PATH/.worktrees/.thread-registry"

# Check if registry exists and has threads
if [[ ! -f "$REGISTRY_FILE" ]] || [[ ! -s "$REGISTRY_FILE" ]]; then
    echo "No active threads found."
    echo ""
    echo "To create a thread:"
    echo "  iso init <feature-name> [base-branch]"
    exit 0
fi

# Header
echo ""
echo "Repository: $SEER_REPO_PATH"
echo ""
printf "%-8s %-30s %-12s %-22s %-13s %-20s\n" "THREAD" "BRANCH" "STATUS" "PORTS(PG/RD/API)" "CONTAINERS" "WORKTREE"
echo "--------------------------------------------------------------------------------------------------------"

# Read and display threads
while IFS='|' read -r thread_id branch pg_port redis_port api_port worker_port wt_path created status; do
    # Skip empty lines
    if [[ -z "$thread_id" ]]; then
        continue
    fi

    # Check Docker container status
    container_count=0
    running_count=0

    for service in postgres redis worker; do
        container_name="seer-thread-${thread_id}-${service}"
        if docker ps -q -f name="$container_name" >/dev/null 2>&1; then
            if docker ps -q -f name="$container_name" -f status=running >/dev/null 2>&1; then
                ((running_count++)) || true
            fi
            ((container_count++)) || true
        fi
    done

    # Format container status
    if [[ $container_count -eq 0 ]]; then
        container_status="none"
    else
        container_status="$running_count running"
    fi

    # Format ports
    ports="$pg_port/$redis_port/$api_port"

    # Truncate branch name if too long
    if [[ ${#branch} -gt 30 ]]; then
        branch="${branch:0:27}..."
    fi

    # Format worktree path (relative to repo)
    wt_relative=$(echo "$wt_path" | sed "s|$SEER_REPO_PATH/||")

    # Print row
    printf "%-8s %-30s %-12s %-22s %-13s %-20s\n" \
        "$thread_id" \
        "$branch" \
        "$status" \
        "$ports" \
        "$container_status" \
        "$wt_relative"

done < "$REGISTRY_FILE"

echo ""
echo "Commands:"
echo "  iso init <feature> [base]    Create new thread"
echo "  iso cleanup <id>             Cleanup thread resources"
echo ""
