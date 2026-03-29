#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGF="$SCRIPT_DIR/install_yt6801.log"

echo "=== $(date): Starting YT6801 driver installation if needed ===" >> "$LOGF"

# Check if the module is already loaded
if lsmod | grep -q yt6801; then
    echo "$(date): Module already loaded; nothing to do." >> "$LOGF"
    exit 0
fi

echo "$(date): Module not loaded; proceeding with installation." >> "$LOGF"

# Auto-detect the most recent .deb package in deb/
DEB_PKG="$(find "$SCRIPT_DIR/deb" -maxdepth 1 -name '*.deb' -type f | sort -V | tail -n 1)"

if [[ -z "$DEB_PKG" || ! -f "$DEB_PKG" ]]; then
    echo "$(date): ERROR: No .deb package found in $SCRIPT_DIR/deb/" >> "$LOGF"
    exit 1
fi

echo "$(date): Using package: $DEB_PKG" >> "$LOGF"

# Install the package
{
    echo "$(date): Installing .deb package..."
    sudo dpkg -i "$DEB_PKG" 2>&1 || echo "$(date): dpkg -i failed, continuing..."

    # Regenerate module dependencies
    echo "$(date): Running depmod..."
    sudo depmod 2>&1

    # Verify module
    echo "$(date): Checking lsmod..."
    lsmod | grep yt6801 || true
} >> "$LOGF"

# Add module to /etc/modules if not present
if ! grep -qxF 'yt6801' /etc/modules; then
    echo "$(date): Adding 'yt6801' to /etc/modules" >> "$LOGF"
    echo 'yt6801' | sudo tee -a /etc/modules >> /dev/null
else
    echo "$(date): 'yt6801' already present in /etc/modules" >> "$LOGF"
fi

# Second call to depmod just in case
{
    echo "$(date): Second depmod call..."
    sudo depmod 2>&1
} >> "$LOGF"

echo "$(date): Installation completed." >> "$LOGF"
exit 0
