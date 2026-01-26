#!/usr/bin/env bash
set -euo pipefail

# Generate .devcontainer/ in thread worktree from templates
# Substitutes template variables: {{THREAD_ID}}, {{BACKEND_PORT}}, {{FRONTEND_PORT}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Usage
if [[ $# -lt 4 ]]; then
    echo "Usage: devcontainer-init.sh <worktree-dir> <thread-id> <backend-port> <frontend-port>" >&2
    exit 1
fi

WORKTREE_DIR="$1"
THREAD_ID="$2"
BACKEND_PORT="$3"
FRONTEND_PORT="$4"

# Validate inputs
if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo "Error: Worktree directory does not exist: $WORKTREE_DIR" >&2
    exit 1
fi

if ! [[ "$THREAD_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid thread ID: $THREAD_ID" >&2
    exit 1
fi

# Template directory
TEMPLATE_DIR="$REPO_ROOT/templates/devcontainer"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: Template directory not found: $TEMPLATE_DIR" >&2
    exit 1
fi

# Create .devcontainer directory
DEVCONTAINER_DIR="$WORKTREE_DIR/.devcontainer"
mkdir -p "$DEVCONTAINER_DIR"

echo "Generating devcontainer configuration..."

# Process each template file
for template_file in "$TEMPLATE_DIR"/*; do
    filename=$(basename "$template_file")
    output_file="$DEVCONTAINER_DIR/$filename"

    # Substitute template variables
    sed -e "s|{{THREAD_ID}}|$THREAD_ID|g" \
        -e "s|{{BACKEND_PORT}}|$BACKEND_PORT|g" \
        -e "s|{{FRONTEND_PORT}}|$FRONTEND_PORT|g" \
        "$template_file" > "$output_file"

    # Make shell scripts executable
    if [[ "$filename" == *.sh ]]; then
        chmod +x "$output_file"
    fi

    echo "✓ Generated: $filename"
done

echo ""
echo "Devcontainer configuration created at: $DEVCONTAINER_DIR"
