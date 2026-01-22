#!/usr/bin/env bash
set -euo pipefail

# Port allocator for seer threads
# Finds next available thread ID, allocates ports, updates registry

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

# Configuration
THREAD_PORT_BASE="${THREAD_PORT_BASE:-10000}"
MAX_THREADS="${MAX_THREADS:-10}"
WORKTREE_DIR="$SEER_REPO_PATH/.worktrees"
REGISTRY_FILE="$WORKTREE_DIR/.thread-registry"
LOCKFILE="$WORKTREE_DIR/.thread-registry.lock"

# Ensure worktree directory exists
mkdir -p "$WORKTREE_DIR"

# Initialize registry if it doesn't exist
if [[ ! -f "$REGISTRY_FILE" ]]; then
    touch "$REGISTRY_FILE"
fi

# Check if a port is available
check_port_available() {
    local port=$1
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Atomic registry operations using flock
allocate_thread() {
    local feature_name=$1
    local branch_name=$2

    (
        # Acquire exclusive lock
        flock -x 200

        # Read existing threads
        local used_ids=()
        while IFS='|' read -r thread_id rest; do
            if [[ -n "$thread_id" && "$thread_id" =~ ^[0-9]+$ ]]; then
                used_ids+=("$thread_id")
            fi
        done < "$REGISTRY_FILE"

        # Find next available ID
        local next_id=0
        for ((i=1; i<=MAX_THREADS; i++)); do
            local found=0
            for used in "${used_ids[@]:-}"; do
                if [[ "$used" == "$i" ]]; then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                next_id=$i
                break
            fi
        done

        if [[ $next_id -eq 0 ]]; then
            echo "Error: No available thread slots (max $MAX_THREADS)" >&2
            return 1
        fi

        # Calculate ports
        local base_port=$((THREAD_PORT_BASE + (next_id * 100)))
        local pg_port=$base_port
        local redis_port=$((base_port + 1))
        local api_port=$((base_port + 2))
        local worker_port=$((base_port + 3))

        # Verify all ports are available
        local ports=($pg_port $redis_port $api_port $worker_port)
        for port in "${ports[@]}"; do
            if ! check_port_available "$port"; then
                echo "Error: Port $port already in use" >&2
                return 1
            fi
        done

        # Calculate worktree path
        local worktree_path="$WORKTREE_DIR/thread-$next_id"

        # Add to registry
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "$next_id|$branch_name|$pg_port|$redis_port|$api_port|$worker_port|$worktree_path|$timestamp|initializing" >> "$REGISTRY_FILE"

        # Output result (for parent script to capture)
        echo "$next_id|$pg_port|$redis_port|$api_port|$worker_port|$worktree_path"

    ) 200>"$LOCKFILE"
}

# Update thread status
update_thread_status() {
    local thread_id=$1
    local new_status=$2

    (
        flock -x 200

        # Create temp file
        local temp_file="$REGISTRY_FILE.tmp"

        # Update status
        while IFS='|' read -r tid branch pg_port redis_port api_port worker_port wt_path created status; do
            if [[ "$tid" == "$thread_id" ]]; then
                echo "$tid|$branch|$pg_port|$redis_port|$api_port|$worker_port|$wt_path|$created|$new_status"
            else
                echo "$tid|$branch|$pg_port|$redis_port|$api_port|$worker_port|$wt_path|$created|$status"
            fi
        done < "$REGISTRY_FILE" > "$temp_file"

        mv "$temp_file" "$REGISTRY_FILE"

    ) 200>"$LOCKFILE"
}

# Remove thread from registry
remove_thread() {
    local thread_id=$1

    (
        flock -x 200

        # Create temp file
        local temp_file="$REGISTRY_FILE.tmp"

        # Remove thread
        while IFS='|' read -r tid rest; do
            if [[ "$tid" != "$thread_id" ]]; then
                echo "$tid|$rest"
            fi
        done < "$REGISTRY_FILE" > "$temp_file"

        mv "$temp_file" "$REGISTRY_FILE"

    ) 200>"$LOCKFILE"
}

# Get thread info
get_thread_info() {
    local thread_id=$1

    while IFS='|' read -r tid branch pg_port redis_port api_port worker_port wt_path created status; do
        if [[ "$tid" == "$thread_id" ]]; then
            echo "$tid|$branch|$pg_port|$redis_port|$api_port|$worker_port|$wt_path|$created|$status"
            return 0
        fi
    done < "$REGISTRY_FILE"

    return 1
}

# Main command dispatcher
case "${1:-}" in
    allocate)
        if [[ $# -lt 3 ]]; then
            echo "Usage: port-allocator.sh allocate <feature-name> <branch-name>" >&2
            exit 1
        fi
        allocate_thread "$2" "$3"
        ;;
    update-status)
        if [[ $# -lt 3 ]]; then
            echo "Usage: port-allocator.sh update-status <thread-id> <status>" >&2
            exit 1
        fi
        update_thread_status "$2" "$3"
        ;;
    remove)
        if [[ $# -lt 2 ]]; then
            echo "Usage: port-allocator.sh remove <thread-id>" >&2
            exit 1
        fi
        remove_thread "$2"
        ;;
    get-info)
        if [[ $# -lt 2 ]]; then
            echo "Usage: port-allocator.sh get-info <thread-id>" >&2
            exit 1
        fi
        get_thread_info "$2"
        ;;
    *)
        echo "Usage: port-allocator.sh {allocate|update-status|remove|get-info} [args]" >&2
        exit 1
        ;;
esac
