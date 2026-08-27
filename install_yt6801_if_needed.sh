#!/bin/bash
set -e

# This script is normally launched by systemd (as root) or via setup.sh's
# service, but can also be run manually. Either way it needs root to run
# dpkg/depmod/modprobe and to write /etc/modules, so require it up front
# instead of relying on fragile per-command `sudo`.
# YT6801_SKIP_ROOT_CHECK is set only by the bats test suite (test/smoke.bats)
# to exercise this script's logic without requiring the test runner to be root.
if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
    echo "This script must be run as root (use: sudo ./install_yt6801_if_needed.sh)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGF="$SCRIPT_DIR/install_yt6801.log"
PKG_NAME="tuxedo-yt6801"

echo "=== $(date): Starting YT6801 driver installation if needed ===" >>"$LOGF"

# Auto-detect the tuxedo-yt6801 .deb package with the highest Debian version in
# deb/. Needed both to install and, when the module is already loaded, to check
# whether a newer version is available so updates placed in deb/ are not
# silently skipped. Candidates are filtered by their Debian package name (not
# just filename) so an unrelated .deb dropped in deb/ cannot be mistaken for a
# driver update, and compared with dpkg --compare-versions rather than
# `sort -V`, since GNU sort does not follow Debian's version ordering rules
# (epochs, tildes, etc.).
DEB_PKG=""
DEB_VERSION=""
while IFS= read -r candidate; do
    candidate_package="$(dpkg-deb -f "$candidate" Package 2>/dev/null)" || continue
    [[ "$candidate_package" == "$PKG_NAME" ]] || continue

    candidate_version="$(dpkg-deb -f "$candidate" Version 2>/dev/null)" || continue

    if [[ -z "$DEB_VERSION" ]] || dpkg --compare-versions "$candidate_version" gt "$DEB_VERSION"; then
        DEB_PKG="$candidate"
        DEB_VERSION="$candidate_version"
    fi
done < <(find "$SCRIPT_DIR/deb" -maxdepth 1 -name '*.deb' -type f)

# Check if the module is already loaded
if lsmod | grep -q yt6801; then
    if [[ -n "$DEB_PKG" && -f "$DEB_PKG" ]]; then
        INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null)" || INSTALLED_VERSION=""

        if [[ -z "$INSTALLED_VERSION" ]] || dpkg --compare-versions "$DEB_VERSION" gt "$INSTALLED_VERSION"; then
            echo "$(date): Module loaded but a newer package is available (available: $DEB_VERSION, installed: ${INSTALLED_VERSION:-none}); proceeding with update." >>"$LOGF"
        else
            echo "$(date): Module already loaded and installed version ($INSTALLED_VERSION) is up to date with available package ($DEB_VERSION); nothing to do." >>"$LOGF"
            exit 0
        fi
    else
        echo "$(date): Module already loaded and no .deb package found in $SCRIPT_DIR/deb/; nothing to do." >>"$LOGF"
        exit 0
    fi
else
    echo "$(date): Module not loaded; proceeding with installation." >>"$LOGF"
fi

if [[ -z "$DEB_PKG" || ! -f "$DEB_PKG" ]]; then
    echo "$(date): ERROR: No .deb package found in $SCRIPT_DIR/deb/" >>"$LOGF"
    exit 1
fi

echo "$(date): Using package: $DEB_PKG" >>"$LOGF"

# Install the package
{
    echo "$(date): Installing .deb package..."
    if ! dpkg -i "$DEB_PKG" 2>&1; then
        echo "$(date): ERROR: dpkg -i failed to install $DEB_PKG"
        exit 1
    fi

    # Regenerate module dependencies
    echo "$(date): Running depmod..."
    depmod 2>&1

    # Verify module
    echo "$(date): Checking lsmod..."
    lsmod | grep yt6801 || true
} >>"$LOGF"

# Add module to /etc/modules if not present
if ! grep -qxF 'yt6801' /etc/modules; then
    echo "$(date): Adding 'yt6801' to /etc/modules" >>"$LOGF"
    echo 'yt6801' >>/etc/modules
else
    echo "$(date): 'yt6801' already present in /etc/modules" >>"$LOGF"
fi

# Second call to depmod just in case
{
    echo "$(date): Second depmod call..."
    depmod 2>&1
} >>"$LOGF"

# Verify the module can actually be loaded before declaring success
if ! modprobe yt6801 2>>"$LOGF"; then
    echo "$(date): ERROR: modprobe yt6801 failed; installation did not succeed." >>"$LOGF"
    exit 1
fi

echo "$(date): Installation completed." >>"$LOGF"
exit 0
