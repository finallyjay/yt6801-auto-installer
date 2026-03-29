#!/bin/bash
set -e

INSTALL_DIR="/opt/yt6801-auto-installer"
SERVICE_NAME="yt6801-reinstall.service"

echo "==> Uninstalling YT6801 auto-installer..."

# Stop and disable systemd service
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "==> Stopping service..."
    sudo systemctl stop "$SERVICE_NAME"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "==> Disabling service..."
    sudo systemctl disable "$SERVICE_NAME"
fi

# Remove service file
if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    echo "==> Removing service file..."
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
    sudo systemctl daemon-reload
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Removing $INSTALL_DIR..."
    sudo rm -rf "$INSTALL_DIR"
fi

echo "==> Uninstallation complete."
echo "    Note: The yt6801 kernel module and /etc/modules entry were NOT removed."
echo "    To remove the module entry: sudo sed -i '/^yt6801$/d' /etc/modules"
