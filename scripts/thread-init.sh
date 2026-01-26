#!/usr/bin/env bash
set -euo pipefail

# Initialize a new seer thread with devcontainer isolation
# Creates unified worktree structure with backend + frontend in single devcontainer

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
    echo "Devcontainer approach requires both backend and frontend repos" >&2
    exit 1
fi

cd "$SEER_FRONTEND_PATH"
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist in frontend repo" >&2
    exit 1
fi

# Sanitize feature name
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
IFS='|' read -r THREAD_ID BACKEND_PORT FRONTEND_PORT OLD_WORKTREE_PATH <<< "$ALLOCATION"

BRANCH_NAME="thread-$THREAD_ID-$FEATURE_SLUG"
THREAD_PARENT_DIR="$REPO_ROOT/worktrees/thread-$THREAD_ID"
BACKEND_WORKTREE="$THREAD_PARENT_DIR/backend"
FRONTEND_WORKTREE="$THREAD_PARENT_DIR/frontend"

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

# Create backend .env.thread
echo "Creating backend .env.thread..."
cat > "$BACKEND_WORKTREE/.env.thread" <<EOF
# Thread $THREAD_ID backend environment configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

THREAD_ID=$THREAD_ID
THREAD_BRANCH=$BRANCH_NAME
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/seer
REDIS_URL=redis://redis:6379/0
BACKEND_PORT=$BACKEND_PORT
EOF

# Copy secrets from main backend .env if it exists
if [[ -f "$SEER_REPO_PATH/.env" ]]; then
    echo "" >> "$BACKEND_WORKTREE/.env.thread"
    echo "# Inherited from main .env" >> "$BACKEND_WORKTREE/.env.thread"
    grep -E '^(OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|SENTRY_DSN)=' "$SEER_REPO_PATH/.env" >> "$BACKEND_WORKTREE/.env.thread" 2>/dev/null || true
fi
echo "✓ Backend .env.thread created"
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

# Generate devcontainer configuration
echo "Generating devcontainer configuration..."
if ! "$SCRIPT_DIR/devcontainer-init.sh" "$THREAD_PARENT_DIR" "$THREAD_ID" "$BACKEND_PORT" "$FRONTEND_PORT"; then
    echo "Error: Failed to generate devcontainer configuration" >&2
    cd "$SEER_REPO_PATH"
    git worktree remove --force "$BACKEND_WORKTREE"
    cd "$SEER_FRONTEND_PATH"
    git worktree remove --force "$FRONTEND_WORKTREE"
    "$SCRIPT_DIR/port-allocator.sh" remove "$THREAD_ID"
    rm -rf "$THREAD_PARENT_DIR"
    exit 1
fi
echo ""

# Update thread status
"$SCRIPT_DIR/port-allocator.sh" update-status "$THREAD_ID" "ready"

# Output success message
echo "=========================================="
echo "Thread $THREAD_ID initialized successfully!"
echo "=========================================="
echo ""
echo "Branch: $BRANCH_NAME"
echo "Workspace: $THREAD_PARENT_DIR"
echo ""
echo "Structure:"
echo "  $THREAD_PARENT_DIR/"
echo "    ├── .devcontainer/    # Devcontainer config"
echo "    ├── backend/          # Backend git worktree"
echo "    └── frontend/         # Frontend git worktree"
echo ""
echo "Services (after opening in VS Code):"
echo "  Backend API:  http://localhost:$BACKEND_PORT"
echo "  Frontend Dev: http://localhost:$FRONTEND_PORT"
echo "  Postgres:     postgres:5432 (internal only)"
echo "  Redis:        redis:6379 (internal only)"
echo ""
echo "Next steps:"
echo "  1. Open in VS Code:"
echo "     code $THREAD_PARENT_DIR"
echo ""
echo "  2. Click 'Reopen in Container' when prompted"
echo ""
echo "  3. Inside devcontainer, start services:"
echo "     cd /workspace/backend && uv run uvicorn seer.api.main:app --host 0.0.0.0 --port 8000 --reload"
echo "     cd /workspace/frontend && bun dev --port 5173"
echo ""
echo "  4. Claude Code will have full-stack context (backend + frontend)"
echo ""
echo "When done:"
echo "  git push origin $BRANCH_NAME"
echo "  thread-cleanup.sh $THREAD_ID"
echo "=========================================="
