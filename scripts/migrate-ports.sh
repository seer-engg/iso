#!/usr/bin/env bash
set -euo pipefail

# Migrate from old 5-port scheme to new 2-port scheme

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

REGISTRY_FILE="$REPO_ROOT/worktrees/.thread-registry"
BACKUP_FILE="$REGISTRY_FILE.backup-$(date +%Y%m%d-%H%M%S)"

# Check if registry exists
if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "No registry file found. Nothing to migrate."
    exit 0
fi

# Detect registry format by counting fields
first_line=$(head -n 1 "$REGISTRY_FILE")
field_count=$(echo "$first_line" | awk -F'|' '{print NF}')

if [[ $field_count -eq 7 ]]; then
    echo "Registry already using new format (7 fields). Nothing to migrate."
    exit 0
fi

if [[ $field_count -ne 10 ]]; then
    echo "Error: Unknown registry format (expected 10 or 7 fields, got $field_count)" >&2
    exit 1
fi

echo "Old format detected (10 fields). Migrating to new format..."
echo ""

# Backup registry
cp "$REGISTRY_FILE" "$BACKUP_FILE"
echo "✓ Backup created: $BACKUP_FILE"
echo ""

# Read all threads
declare -a threads
while IFS='|' read -r tid branch pg_port redis_port api_port worker_port frontend_port wt_path created status; do
    if [[ -z "$tid" ]]; then
        continue
    fi
    threads+=("$tid|$branch|$pg_port|$redis_port|$api_port|$worker_port|$frontend_port|$wt_path|$created|$status")
done < "$REGISTRY_FILE"

if [[ ${#threads[@]} -eq 0 ]]; then
    echo "No threads to migrate."
    exit 0
fi

echo "Found ${#threads[@]} thread(s) to migrate:"
echo ""

# Process each thread
temp_registry="$REGISTRY_FILE.tmp"
> "$temp_registry"

for thread_data in "${threads[@]}"; do
    IFS='|' read -r tid branch pg_port redis_port api_port worker_port frontend_port wt_path created status <<< "$thread_data"

    echo "Thread $tid:"
    echo "  Old ports: PG=$pg_port, Redis=$redis_port, API=$api_port, Worker=$worker_port, Frontend=$frontend_port"

    # Calculate new ports
    new_backend_port=$((3000 + tid))
    new_frontend_port=$((4000 + tid))

    echo "  New ports: Backend=$new_backend_port, Frontend=$new_frontend_port"

    # Stop containers if running
    echo "  Stopping containers..."
    cd "$wt_path" 2>/dev/null || {
        echo "  Warning: Worktree not found at $wt_path, skipping container operations" >&2
        echo "$tid|$branch|$new_backend_port|$new_frontend_port|$wt_path|$created|$status" >> "$temp_registry"
        echo ""
        continue
    }

    if [[ -f "docker-compose.thread.yml" ]]; then
        docker compose -f docker-compose.thread.yml down -v 2>/dev/null || true
    fi

    # Regenerate docker-compose.thread.yml with new template
    echo "  Regenerating docker-compose.thread.yml..."
    TEMPLATE_FILE="$REPO_ROOT/templates/docker-compose.thread.template.yml"

    if [[ -f "$TEMPLATE_FILE" ]]; then
        sed -e "s|{{THREAD_ID}}|$tid|g" \
            -e "s|{{BACKEND_PORT}}|$new_backend_port|g" \
            -e "s|{{THREAD_DIR}}|$wt_path|g" \
            "$TEMPLATE_FILE" > "$wt_path/docker-compose.thread.yml"
    fi

    # Update .env.thread
    echo "  Updating .env.thread..."
    if [[ -f "$wt_path/.env.thread" ]]; then
        # Replace old URLs with new ones (internal Docker network)
        sed -i.bak \
            -e "s|DATABASE_URL=.*|DATABASE_URL=postgresql://postgres:postgres@postgres:5432/seer|g" \
            -e "s|REDIS_URL=.*|REDIS_URL=redis://redis:6379/0|g" \
            -e "s|API_PORT=.*|BACKEND_PORT=$new_backend_port|g" \
            -e "/WORKER_DEBUG_PORT=/d" \
            "$wt_path/.env.thread"
        rm -f "$wt_path/.env.thread.bak"
    fi

    # Update frontend worktree if exists
    if [[ -n "${SEER_FRONTEND_PATH:-}" ]]; then
        FRONTEND_WORKTREE_ROOT="$REPO_ROOT/worktrees/frontend"
        FRONTEND_WORKTREE_DIR="$FRONTEND_WORKTREE_ROOT/thread-$tid"

        if [[ -f "$FRONTEND_WORKTREE_DIR/.env" ]]; then
            echo "  Updating frontend .env..."
            sed -i.bak \
                -e "s|VITE_DEV_PORT=.*|VITE_DEV_PORT=$new_frontend_port|g" \
                -e "s|VITE_BACKEND_API_URL=.*|VITE_BACKEND_API_URL=http://localhost:$new_backend_port|g" \
                "$FRONTEND_WORKTREE_DIR/.env"
            rm -f "$FRONTEND_WORKTREE_DIR/.env.bak"
        fi
    fi

    # Restart containers
    echo "  Starting containers with new ports..."
    if [[ -f "$wt_path/docker-compose.thread.yml" ]]; then
        docker compose -f "$wt_path/docker-compose.thread.yml" up -d 2>&1 | grep -v "^$" || true
    fi

    # Write to new registry
    echo "$tid|$branch|$new_backend_port|$new_frontend_port|$wt_path|$created|$status" >> "$temp_registry"

    echo "  ✓ Migration complete"
    echo ""
done

# Replace registry with new format
mv "$temp_registry" "$REGISTRY_FILE"

echo "=========================================="
echo "Migration complete!"
echo "=========================================="
echo ""
echo "Backup saved to: $BACKUP_FILE"
echo ""
echo "Summary:"
echo "- Migrated ${#threads[@]} thread(s)"
echo "- Updated registry format (10 fields → 7 fields)"
echo "- Regenerated docker-compose files"
echo "- Updated environment files"
echo "- Restarted containers with new ports"
echo ""
echo "New port scheme:"
echo "  Backend: 3000 + thread_id"
echo "  Frontend: 4000 + thread_id"
echo "  Postgres/Redis: Internal Docker network only"
echo ""
echo "Verify threads:"
echo "  iso list"
echo ""
