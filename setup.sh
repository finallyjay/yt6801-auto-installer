#!/bin/bash
set -euo pipefail

# Require root up front instead of prompting for `sudo` command-by-command:
# a mid-script sudo prompt the user cancels (or a stale credential cache
# timing out) would leave the install half-applied.
# YT6801_SKIP_ROOT_CHECK is set only by the bats test suite (test/smoke.bats)
# to exercise this script's logic without requiring the test runner to be root.
if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
    echo "This script must be run as root (use: sudo ./setup.sh)." >&2
    exit 1
fi

INSTALL_DIR="/opt/yt6801-auto-installer"
SERVICE_NAME="yt6801-reinstall.service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing YT6801 auto-installer to $INSTALL_DIR..."

# Copy files to installation directory
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR/deb" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/install_yt6801_if_needed.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/check_yt6801_and_reboot.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/yt6801-reinstall.service" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/install_yt6801_if_needed.sh"
chmod +x "$INSTALL_DIR/check_yt6801_and_reboot.sh"

# Install and enable systemd service
echo "==> Installing systemd service..."
cp "$INSTALL_DIR/$SERVICE_NAME" /etc/systemd/system/
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

echo "==> Installation complete."
echo "    The service will run automatically on next boot."
echo "    To start it now:  sudo systemctl start $SERVICE_NAME"
echo "    To check logs:    journalctl -u $SERVICE_NAME"
