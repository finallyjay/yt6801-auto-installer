#!/bin/bash
set -euo pipefail

# Require root up front instead of prompting for `sudo` command-by-command:
# a mid-script sudo prompt the user cancels (or a stale credential cache
# timing out) would leave the uninstall half-applied.
# YT6801_SKIP_ROOT_CHECK is set only by the bats test suite (test/smoke.bats)
# to exercise this script's logic without requiring the test runner to be root.
if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
    echo "This script must be run as root (use: sudo ./uninstall.sh)." >&2
    exit 1
fi

INSTALL_DIR="/opt/yt6801-auto-installer"
SERVICE_NAME="yt6801-reinstall.service"

echo "==> Uninstalling YT6801 auto-installer..."

# Stop and disable systemd service
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "==> Stopping service..."
    systemctl stop "$SERVICE_NAME"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "==> Disabling service..."
    systemctl disable "$SERVICE_NAME"
fi

# Remove service file
if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    echo "==> Removing service file..."
    rm -f "/etc/systemd/system/$SERVICE_NAME"
fi

# Reload systemd and clear any failed-state entry left behind by the unit
systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Removing $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

echo "==> Uninstallation complete."
echo "    Note: The yt6801 kernel module and /etc/modules entry were NOT removed."
echo "    To remove the module entry: sudo sed -i '/^yt6801$/d' /etc/modules"
