#!/usr/bin/env bash
set -euo pipefail

# Initialize a new seer thread with isolated environment

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
    echo "Usage: thread-init.sh <feature-name> [base-branch]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  thread-init.sh \"add-auth-feature\" dev" >&2
    echo "  thread-init.sh \"fix-workflow-bug\" main" >&2
    exit 1
fi

FEATURE_NAME="$1"
BASE_BRANCH="${2:-dev}"

# Change to seer repo
cd "$SEER_REPO_PATH"

# Verify base branch exists
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist" >&2
    exit 1
fi

# Sanitize feature name (replace spaces/special chars with dashes)
FEATURE_SLUG=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

echo "Initializing thread for feature: $FEATURE_NAME"
echo "Base branch: $BASE_BRANCH"
echo ""

# Allocate thread ID and ports
echo "Allocating thread resources..."
ALLOCATION=$("$SCRIPT_DIR/port-allocator.sh" allocate "$FEATURE_NAME" "thread-X-$FEATURE_SLUG")

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to allocate thread" >&2
    exit 1
fi

# Parse allocation result
IFS='|' read -r THREAD_ID PG_PORT REDIS_PORT API_PORT WORKER_PORT WORKTREE_PATH <<< "$ALLOCATION"

BRANCH_NAME="thread-$THREAD_ID-$FEATURE_SLUG"
THREAD_DIR="$SEER_REPO_PATH/.worktrees/thread-$THREAD_ID"

echo "✓ Thread $THREAD_ID allocated"
echo "  Postgres: localhost:$PG_PORT"
echo "  Redis: localhost:$REDIS_PORT"
echo "  API: localhost:$API_PORT"
echo ""

# Create git worktree
echo "Creating git worktree..."
if ! git worktree add "$THREAD_DIR" -b "$BRANCH_NAME" "$BASE_BRANCH" 2>&1; then
    echo "Error: Failed to create worktree" >&2
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    exit 1
fi

echo "✓ Worktree created at $THREAD_DIR"
echo "✓ Branch: $BRANCH_NAME"
echo ""

# Generate docker-compose.yml from template
echo "Generating docker-compose.yml..."
TEMPLATE_FILE="$REPO_ROOT/templates/docker-compose.thread.template.yml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "Error: Template file not found: $TEMPLATE_FILE" >&2
    git worktree remove --force "$THREAD_DIR"
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    exit 1
fi

# Substitute template variables
sed -e "s|{{THREAD_ID}}|$THREAD_ID|g" \
    -e "s|{{PG_PORT}}|$PG_PORT|g" \
    -e "s|{{REDIS_PORT}}|$REDIS_PORT|g" \
    -e "s|{{API_PORT}}|$API_PORT|g" \
    -e "s|{{WORKER_PORT}}|$WORKER_PORT|g" \
    -e "s|{{THREAD_DIR}}|$THREAD_DIR|g" \
    "$TEMPLATE_FILE" > "$THREAD_DIR/docker-compose.thread.yml"

echo "✓ docker-compose.thread.yml generated"
echo ""

# Create .env.thread
echo "Creating .env.thread..."
cat > "$THREAD_DIR/.env.thread" <<EOF
# Thread $THREAD_ID environment configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

THREAD_ID=$THREAD_ID
THREAD_BRANCH=$BRANCH_NAME
DATABASE_URL=postgresql://postgres:postgres@localhost:$PG_PORT/seer
REDIS_URL=redis://localhost:$REDIS_PORT/0
API_PORT=$API_PORT
WORKER_DEBUG_PORT=$WORKER_PORT
EOF

# Copy secrets from main .env if it exists
if [[ -f "$SEER_REPO_PATH/.env" ]]; then
    echo "" >> "$THREAD_DIR/.env.thread"
    echo "# Inherited from main .env" >> "$THREAD_DIR/.env.thread"
    grep -E '^(OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|SENTRY_DSN)=' "$SEER_REPO_PATH/.env" >> "$THREAD_DIR/.env.thread" 2>/dev/null || true
fi

echo "✓ .env.thread created"
echo ""

# Update frontend .env if frontend path configured
if [[ -n "${SEER_FRONTEND_PATH:-}" ]] && [[ -d "$SEER_FRONTEND_PATH" ]]; then
    echo "Updating frontend configuration..."

    # Backup original frontend .env if not already backed up
    if [[ -f "$SEER_FRONTEND_PATH/.env" ]] && [[ ! -f "$SEER_FRONTEND_PATH/.env.original" ]]; then
        cp "$SEER_FRONTEND_PATH/.env" "$SEER_FRONTEND_PATH/.env.original"
        echo "✓ Original frontend .env backed up"
    fi

    # Read existing .env and update VITE_BACKEND_API_URL
    if [[ -f "$SEER_FRONTEND_PATH/.env" ]]; then
        sed -i.bak "s|^VITE_BACKEND_API_URL=.*|VITE_BACKEND_API_URL=http://localhost:$API_PORT|" "$SEER_FRONTEND_PATH/.env"
        rm "$SEER_FRONTEND_PATH/.env.bak"
        echo "✓ Frontend .env updated to use port $API_PORT"
    else
        echo "Warning: Frontend .env not found at $SEER_FRONTEND_PATH/.env" >&2
    fi
    echo ""
fi

# Start Docker containers
echo "Starting Docker containers..."
cd "$THREAD_DIR"

if ! docker compose -f docker-compose.thread.yml up -d 2>&1; then
    echo "Error: Failed to start containers" >&2
    cd "$SEER_REPO_PATH"
    git worktree remove --force "$THREAD_DIR"
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    exit 1
fi

echo "✓ Containers started"
echo ""

# Wait for services to be healthy
echo "Waiting for services to be ready..."

# Wait for Postgres
MAX_WAIT=30
for ((i=1; i<=MAX_WAIT; i++)); do
    if docker exec "seer-thread-$THREAD_ID-postgres" pg_isready -U postgres >/dev/null 2>&1; then
        echo "✓ Postgres ready"
        break
    fi
    if [[ $i -eq $MAX_WAIT ]]; then
        echo "Warning: Postgres not ready after ${MAX_WAIT}s, continuing anyway..." >&2
    fi
    sleep 1
done

# Wait for Redis
for ((i=1; i<=MAX_WAIT; i++)); do
    if docker exec "seer-thread-$THREAD_ID-redis" redis-cli ping >/dev/null 2>&1; then
        echo "✓ Redis ready"
        break
    fi
    if [[ $i -eq $MAX_WAIT ]]; then
        echo "Warning: Redis not ready after ${MAX_WAIT}s, continuing anyway..." >&2
    fi
    sleep 1
done

echo ""

# Run database migrations
echo "Running database migrations..."
export DATABASE_URL="postgresql://postgres:postgres@localhost:$PG_PORT/seer"

if command -v uv >/dev/null 2>&1; then
    if uv run aerich upgrade 2>&1; then
        echo "✓ Migrations completed"
    else
        echo "Warning: Migrations failed, you may need to run manually" >&2
    fi
else
    echo "Warning: uv not found, skipping migrations" >&2
fi

echo ""

# Update thread status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "active"

# Output success message
echo "=========================================="
echo "Thread $THREAD_ID initialized successfully!"
echo "=========================================="
echo ""
echo "Branch: $BRANCH_NAME"
echo "Worktree: $THREAD_DIR"
echo ""
echo "Services:"
echo "  API:      http://localhost:$API_PORT"
echo "  Postgres: postgresql://postgres:postgres@localhost:$PG_PORT/seer"
echo "  Redis:    redis://localhost:$REDIS_PORT/0"
echo ""
echo "Frontend Configuration:"
if [[ -n "${SEER_FRONTEND_PATH:-}" ]] && [[ -d "$SEER_FRONTEND_PATH" ]]; then
    echo "  Backend URL: http://localhost:$API_PORT"
    echo "  Frontend .env: Updated automatically"
else
    echo "  ⚠️  Frontend not configured in ISO config"
    echo "  Manually update frontend .env:"
    echo "      VITE_BACKEND_API_URL=http://localhost:$API_PORT"
fi
echo ""
echo "Next steps:"
echo "  cd $THREAD_DIR"
echo "  # Open Claude Code or your editor here"
echo ""
echo "Commands:"
echo "  docker compose -f docker-compose.thread.yml logs -f"
echo "  uv run pytest"
echo "  curl http://localhost:$API_PORT/health"
echo ""
echo "When done:"
echo "  git push origin $BRANCH_NAME"
echo "  thread-cleanup.sh $THREAD_ID"
echo "=========================================="
