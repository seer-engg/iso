#!/usr/bin/env bash
set -euo pipefail

# One-time setup for ISO systemd user services

echo "Enabling lingering for user $(whoami)..."
loginctl enable-linger "$(whoami)"

echo "Reloading systemd user daemon..."
systemctl --user daemon-reload

echo ""
echo "Installed unit templates:"
systemctl --user list-unit-files 'iso-*' 2>/dev/null || echo "  (templates show up when instantiated)"
echo ""
echo "Setup complete. ISO threads will now use systemd for process management."
echo "Linger: $(loginctl show-user "$(whoami)" -p Linger --value)"
