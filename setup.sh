#!/bin/bash
set -e

INSTALL_DIR="/opt/yt6801-auto-installer"
SERVICE_NAME="yt6801-reinstall.service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing YT6801 auto-installer to $INSTALL_DIR..."

# Copy files to installation directory
sudo mkdir -p "$INSTALL_DIR"
sudo cp -r "$SCRIPT_DIR/deb" "$INSTALL_DIR/"
sudo cp "$SCRIPT_DIR/install_yt6801_if_needed.sh" "$INSTALL_DIR/"
sudo cp "$SCRIPT_DIR/check_yt6801_and_reboot.sh" "$INSTALL_DIR/"
sudo cp "$SCRIPT_DIR/yt6801-reinstall.service" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/install_yt6801_if_needed.sh"
sudo chmod +x "$INSTALL_DIR/check_yt6801_and_reboot.sh"

# Install and enable systemd service
echo "==> Installing systemd service..."
sudo cp "$INSTALL_DIR/$SERVICE_NAME" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

echo "==> Installation complete."
echo "    The service will run automatically on next boot."
echo "    To start it now:  sudo systemctl start $SERVICE_NAME"
echo "    To check logs:    cat $INSTALL_DIR/install_yt6801.log"
