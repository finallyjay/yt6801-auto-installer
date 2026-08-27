#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGF="$SCRIPT_DIR/install_yt6801.log"
PKG_NAME="tuxedo-yt6801"

echo "=== $(date): Starting YT6801 driver installation if needed ===" >> "$LOGF"

# Auto-detect the most recent .deb package in deb/. Needed both to install and,
# when the module is already loaded, to check whether a newer version is
# available so updates placed in deb/ are not silently skipped.
DEB_PKG="$(find "$SCRIPT_DIR/deb" -maxdepth 1 -name '*.deb' -type f | sort -V | tail -n 1)"

# Check if the module is already loaded
if lsmod | grep -q yt6801; then
    if [[ -n "$DEB_PKG" && -f "$DEB_PKG" ]]; then
        if ! DEB_VERSION="$(dpkg-deb -f "$DEB_PKG" Version 2>>"$LOGF")"; then
            echo "$(date): ERROR: Failed to read version from $DEB_PKG" >> "$LOGF"
            exit 1
        fi

        INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null)" || INSTALLED_VERSION=""

        if [[ -z "$INSTALLED_VERSION" ]] || dpkg --compare-versions "$DEB_VERSION" gt "$INSTALLED_VERSION"; then
            echo "$(date): Module loaded but a newer package is available (available: $DEB_VERSION, installed: ${INSTALLED_VERSION:-none}); proceeding with update." >> "$LOGF"
        else
            echo "$(date): Module already loaded and installed version ($INSTALLED_VERSION) is up to date with available package ($DEB_VERSION); nothing to do." >> "$LOGF"
            exit 0
        fi
    else
        echo "$(date): Module already loaded and no .deb package found in $SCRIPT_DIR/deb/; nothing to do." >> "$LOGF"
        exit 0
    fi
else
    echo "$(date): Module not loaded; proceeding with installation." >> "$LOGF"
fi

if [[ -z "$DEB_PKG" || ! -f "$DEB_PKG" ]]; then
    echo "$(date): ERROR: No .deb package found in $SCRIPT_DIR/deb/" >> "$LOGF"
    exit 1
fi

echo "$(date): Using package: $DEB_PKG" >> "$LOGF"

# Install the package
{
    echo "$(date): Installing .deb package..."
    if ! sudo dpkg -i "$DEB_PKG" 2>&1; then
        echo "$(date): ERROR: dpkg -i failed to install $DEB_PKG"
        exit 1
    fi

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

# Verify the module can actually be loaded before declaring success
if ! sudo modprobe yt6801 2>>"$LOGF"; then
    echo "$(date): ERROR: modprobe yt6801 failed; installation did not succeed." >> "$LOGF"
    exit 1
fi

echo "$(date): Installation completed." >> "$LOGF"
exit 0
