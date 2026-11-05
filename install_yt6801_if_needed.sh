#!/bin/bash
set -euo pipefail

# Boot-time step of yt6801-reinstall.service (as root): installs or
# reinstalls the TUXEDO driver when the yt6801 module is not loaded, e.g.
# after a kernel update. It does nothing when the driver is not needed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=yt6801-common.sh
. "$SCRIPT_DIR/yt6801-common.sh"
yt6801_require_root install_yt6801_if_needed.sh

echo "=== $(date): Starting YT6801 driver installation if needed ==="

# No controller (e.g. the disk moved to other hardware), or a kernel with its
# own driver (Linux 7.0+): installing the package would only waste a DKMS
# build, or fight the in-kernel driver at every boot.
if reason="$(yt6801_tuxedo_unneeded)"; then
    echo "$(date): $reason. Nothing to do."
    exit 0
fi

# The newest package in deb/ is needed both to install and, when the module
# is already loaded, to tell whether a newer version was dropped in.
yt6801_newest_deb "$SCRIPT_DIR/deb" || true

if yt6801_tuxedo_loaded; then
    if [ -z "$DEB_PKG" ]; then
        echo "$(date): Module already loaded and no .deb package found in $SCRIPT_DIR/deb/; nothing to do."
        exit 0
    fi
    INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null)" || INSTALLED_VERSION=""
    if [ -n "$INSTALLED_VERSION" ] && ! dpkg --compare-versions "$DEB_VERSION" gt "$INSTALLED_VERSION"; then
        echo "$(date): Module already loaded and installed version ($INSTALLED_VERSION) is up to date with available package ($DEB_VERSION); nothing to do."
        exit 0
    fi
    echo "$(date): Module loaded but a newer package is available (available: $DEB_VERSION, installed: ${INSTALLED_VERSION:-none}); proceeding with update."
else
    echo "$(date): Module not loaded; proceeding with installation."
fi

if [ -z "$DEB_PKG" ]; then
    echo "$(date): ERROR: No .deb package found in $SCRIPT_DIR/deb/"
    exit 1
fi

echo "$(date): Installing $DEB_PKG..."
if ! dpkg -i "$DEB_PKG" 2>&1; then
    echo "$(date): ERROR: dpkg -i failed to install $DEB_PKG"
    exit 1
fi
depmod 2>&1

# Load the module at every boot.
if ! grep -qxF "$YT6801_TUXEDO_MODULE" "$ETC_MODULES" 2>/dev/null; then
    echo "$(date): Adding '$YT6801_TUXEDO_MODULE' to $ETC_MODULES"
    echo "$YT6801_TUXEDO_MODULE" >>"$ETC_MODULES"
fi

# Verify the module can actually be loaded before declaring success.
if ! modprobe "$YT6801_TUXEDO_MODULE" 2>&1; then
    echo "$(date): ERROR: modprobe $YT6801_TUXEDO_MODULE failed; installation did not succeed."
    exit 1
fi

echo "$(date): Installation completed."
