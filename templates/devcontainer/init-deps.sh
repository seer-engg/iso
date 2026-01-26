#!/bin/bash
set -euo pipefail

echo "=== Installing Backend Dependencies ==="
cd /workspace/backend
uv sync

echo "=== Running Database Migrations ==="
uv run aerich upgrade

echo "=== Installing Frontend Dependencies ==="
cd /workspace/frontend
bun install

echo ""
echo "✓ All dependencies installed!"
echo "  Backend: /workspace/backend/.venv"
echo "  Frontend: /workspace/frontend/node_modules"
echo ""
