#!/usr/bin/env bash
set -euo pipefail

# Initialize a new seer thread with local process isolation
# Creates unified worktree structure with backend + frontend as local processes

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

# Validate base branch exists in backend repo
cd "$SEER_REPO_PATH"
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist in backend repo" >&2
    exit 1
fi

# Validate frontend repo and base branch
if [[ -z "${SEER_FRONTEND_PATH:-}" ]] || [[ ! -d "$SEER_FRONTEND_PATH" ]]; then
    echo "Error: SEER_FRONTEND_PATH not set or does not exist: ${SEER_FRONTEND_PATH:-}" >&2
    echo "ISO requires both backend and frontend repos" >&2
    exit 1
fi

cd "$SEER_FRONTEND_PATH"
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist in frontend repo" >&2
    exit 1
fi

# Validate sales-cx repo and base branch (optional)
if [[ -n "${SALES_CX_REPO_PATH:-}" ]] && [[ -d "$SALES_CX_REPO_PATH" ]]; then
    cd "$SALES_CX_REPO_PATH"
    if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
        echo "Error: Base branch '$BASE_BRANCH' does not exist in sales-cx repo" >&2
        exit 1
    fi
fi

# Validate seer-website repo and base branch (optional)
if [[ -n "${SEER_WEBSITE_PATH:-}" ]] && [[ -d "$SEER_WEBSITE_PATH" ]]; then
    cd "$SEER_WEBSITE_PATH"
    if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
        echo "Error: Base branch '$BASE_BRANCH' does not exist in seer-website repo" >&2
        exit 1
    fi
fi

# Sanitize feature name
FEATURE_SLUG=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

echo "Initializing thread for feature: $FEATURE_NAME"
echo "Base branch: $BASE_BRANCH"
echo ""

# Allocate thread ID and ports
echo "Allocating thread resources..."
ALLOCATION=$("$SCRIPT_DIR/port-allocator.sh" allocate "$FEATURE_NAME" "placeholder")

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to allocate thread" >&2
    exit 1
fi

# Parse allocation result
IFS='|' read -r THREAD_ID BACKEND_PORT FRONTEND_PORT OLD_WORKTREE_PATH <<< "$ALLOCATION"

BRANCH_NAME="thread-$THREAD_ID-$FEATURE_SLUG"
THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
BACKEND_WORKTREE="$THREAD_PARENT_DIR/backend"
FRONTEND_WORKTREE="$THREAD_PARENT_DIR/frontend"

# Fix the branch name in registry (allocator didn't know the thread ID yet)
REGISTRY_FILE="$REPO_ROOT/worktrees/.thread-registry"
sed -i "s|^${THREAD_ID}|placeholder|${THREAD_ID}|${BRANCH_NAME}|" "$REGISTRY_FILE" 2>/dev/null || true

echo "✓ Thread $THREAD_ID allocated"
echo "  Backend:  localhost:$BACKEND_PORT"
echo "  Frontend: localhost:$FRONTEND_PORT"
echo ""

# Create parent directory
mkdir -p "$THREAD_PARENT_DIR"

# Create backend git worktree
echo "Creating backend worktree..."
cd "$SEER_REPO_PATH"
if ! git worktree add "$BACKEND_WORKTREE" -b "$BRANCH_NAME" "$BASE_BRANCH" 2>&1; then
    echo "Error: Failed to create backend worktree" >&2
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    rm -rf "$THREAD_PARENT_DIR"
    exit 1
fi
echo "✓ Backend worktree: $BACKEND_WORKTREE"
echo "✓ Branch: $BRANCH_NAME"
echo ""

# Create frontend git worktree
echo "Creating frontend worktree..."
cd "$SEER_FRONTEND_PATH"
if ! git worktree add "$FRONTEND_WORKTREE" -b "$BRANCH_NAME" "$BASE_BRANCH" 2>&1; then
    echo "Error: Failed to create frontend worktree" >&2
    cd "$SEER_REPO_PATH"
    git worktree remove --force "$BACKEND_WORKTREE"
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    rm -rf "$THREAD_PARENT_DIR"
    exit 1
fi
echo "✓ Frontend worktree: $FRONTEND_WORKTREE"
echo "✓ Branch: $BRANCH_NAME"
echo ""

# Create sales-cx git worktree (optional)
if [[ -n "${SALES_CX_REPO_PATH:-}" ]] && [[ -d "$SALES_CX_REPO_PATH" ]]; then
    SALES_CX_WORKTREE="$THREAD_PARENT_DIR/sales-cx"
    echo "Creating sales-cx worktree..."
    cd "$SALES_CX_REPO_PATH"
    if ! git worktree add "$SALES_CX_WORKTREE" -b "$BRANCH_NAME" "$BASE_BRANCH" 2>&1; then
        echo "Error: Failed to create sales-cx worktree" >&2
        cd "$SEER_REPO_PATH"
        git worktree remove --force "$BACKEND_WORKTREE"
        cd "$SEER_FRONTEND_PATH"
        git worktree remove --force "$FRONTEND_WORKTREE"
        "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
        rm -rf "$THREAD_PARENT_DIR"
        exit 1
    fi
    echo "✓ Sales-CX worktree: $SALES_CX_WORKTREE"
    echo "✓ Branch: $BRANCH_NAME"
    echo ""
fi

# Create seer-website git worktree (optional)
if [[ -n "${SEER_WEBSITE_PATH:-}" ]] && [[ -d "$SEER_WEBSITE_PATH" ]]; then
    WEBSITE_WORKTREE="$THREAD_PARENT_DIR/website"
    echo "Creating seer-website worktree..."
    cd "$SEER_WEBSITE_PATH"
    if ! git worktree add "$WEBSITE_WORKTREE" -b "$BRANCH_NAME" "$BASE_BRANCH" 2>&1; then
        echo "Error: Failed to create seer-website worktree" >&2
        cd "$SEER_REPO_PATH"
        git worktree remove --force "$BACKEND_WORKTREE"
        cd "$SEER_FRONTEND_PATH"
        git worktree remove --force "$FRONTEND_WORKTREE"
        if [[ -n "${SALES_CX_REPO_PATH:-}" ]] && [[ -d "$SALES_CX_REPO_PATH" ]] && [[ -d "$SALES_CX_WORKTREE" ]]; then
            cd "$SALES_CX_REPO_PATH"
            git worktree remove --force "$SALES_CX_WORKTREE"
        fi
        "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
        rm -rf "$THREAD_PARENT_DIR"
        exit 1
    fi
    echo "✓ Seer-website worktree: $WEBSITE_WORKTREE"
    echo "✓ Branch: $BRANCH_NAME"
    echo ""
fi

# Create backend .env
echo "Creating backend .env..."

# Start with main .env if it exists
if [[ -f "$SEER_REPO_PATH/.env" ]]; then
    cp "$SEER_REPO_PATH/.env" "$BACKEND_WORKTREE/.env"
else
    touch "$BACKEND_WORKTREE/.env"
fi

# Append thread-specific overrides
# DATABASE_URL and REDIS_URL use container service names (resolved by docker compose networking)
cat >> "$BACKEND_WORKTREE/.env" <<EOF

# Thread $THREAD_ID backend overrides
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
THREAD_ID=$THREAD_ID
THREAD_BRANCH=$BRANCH_NAME
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/seer
REDIS_URL=redis://valkey:6379/0
BACKEND_PORT=$BACKEND_PORT
DISABLE_USAGE_LIMITS=true
FRONTEND_URL=http://localhost:$FRONTEND_PORT
WEBHOOK_BASE_URL=http://localhost:$BACKEND_PORT
EOF

# Create .env.thread for docker compose port overrides + project isolation
cat > "$BACKEND_WORKTREE/.env.thread" <<EOF
COMPOSE_PROJECT_NAME=seer-thread-$THREAD_ID
POSTGRES_PORT=$((5432 + THREAD_ID))
REDIS_PORT=$((6379 + THREAD_ID))
API_PORT=$BACKEND_PORT
EOF

echo "✓ Backend .env + .env.thread created"
echo ""

# Create frontend .env
echo "Creating frontend .env..."
# Copy from main frontend .env if it exists
if [[ -f "$SEER_FRONTEND_PATH/.env" ]]; then
    cp "$SEER_FRONTEND_PATH/.env" "$FRONTEND_WORKTREE/.env"
else
    touch "$FRONTEND_WORKTREE/.env"
fi

# Append thread-specific overrides
cat >> "$FRONTEND_WORKTREE/.env" <<ENVEOF

# Thread $THREAD_ID frontend overrides
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
THREAD_ID=$THREAD_ID
VITE_DEV_PORT=$FRONTEND_PORT
VITE_BACKEND_API_URL=http://localhost:$BACKEND_PORT
ENVEOF

echo "✓ Frontend .env created"
echo ""

# Create seer-website .env (optional)
if [[ -n "${SEER_WEBSITE_PATH:-}" ]] && [[ -d "$SEER_WEBSITE_PATH" ]] && [[ -d "$WEBSITE_WORKTREE" ]]; then
    echo "Creating seer-website .env..."

    # Copy from main website .env if it exists
    if [[ -f "$SEER_WEBSITE_PATH/.env" ]]; then
        cp "$SEER_WEBSITE_PATH/.env" "$WEBSITE_WORKTREE/.env"
    elif [[ -f "$SEER_WEBSITE_PATH/env.example" ]]; then
        cp "$SEER_WEBSITE_PATH/env.example" "$WEBSITE_WORKTREE/.env"
    else
        touch "$WEBSITE_WORKTREE/.env"
    fi

    # Append thread-specific overrides
    cat >> "$WEBSITE_WORKTREE/.env" <<ENVEOF

# Thread $THREAD_ID website overrides
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
THREAD_ID=$THREAD_ID
ENVEOF

    echo "✓ Seer-website .env created"
    echo ""
fi

# Start backend + frontend processes
echo "Starting services..."
if ! "$SCRIPT_DIR/thread-start.sh" "$THREAD_ID"; then
    echo "Error: Failed to start services" >&2
    echo "Worktrees are ready but services need manual start" >&2
    "$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "ready"
fi

# Output success message
echo ""
echo "=========================================="
echo "Thread $THREAD_ID initialized successfully!"
echo "=========================================="
echo ""
echo "Branch: $BRANCH_NAME"
echo "Workspace: $THREAD_PARENT_DIR"
echo ""
echo "Services:"
echo "  Backend API:  http://localhost:$BACKEND_PORT"
echo "  Frontend Dev: http://localhost:$FRONTEND_PORT"
echo ""
echo "When done:"
echo "  git push origin $BRANCH_NAME"
echo "  thread-cleanup.sh $THREAD_ID"
echo "=========================================="
