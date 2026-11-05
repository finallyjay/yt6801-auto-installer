#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sudo ./uninstall.sh [--keep-driver] [--force]

Removes the YT6801 auto-installer: the boot service, its files in
/opt/yt6801-auto-installer and, by default, the TUXEDO driver itself
(the tuxedo-yt6801 package, its DKMS module and the /etc/modules entry).

Options:
  --keep-driver  Only remove the auto-installer; keep the TUXEDO driver.
  --force        Remove the driver even if the ethernet port depends on it
                 (it stops working immediately and after every reboot).
  -h, --help     Show this help.
EOF
}

KEEP_DRIVER=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
    --keep-driver) KEEP_DRIVER=1 ;;
    --force) FORCE=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $arg" >&2
        usage >&2
        exit 2
        ;;
    esac
done

# Require root up front instead of prompting for `sudo` command-by-command:
# a mid-script sudo prompt the user cancels (or a stale credential cache
# timing out) would leave the uninstall half-applied.
# YT6801_SKIP_ROOT_CHECK is set only by the bats test suite (test/smoke.bats)
# to exercise this script's logic without requiring the test runner to be root.
if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
    echo "This script must be run as root (use: sudo ./uninstall.sh)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=yt6801-common.sh
. "$SCRIPT_DIR/yt6801-common.sh"

# The YT6801_*_PATH/DIR overrides are test-only (see test/smoke.bats), like
# YT6801_SKIP_ROOT_CHECK; they keep the tests away from the real system.
INSTALL_DIR="${YT6801_INSTALL_DIR:-/opt/yt6801-auto-installer}"
SYSTEMD_DIR="${YT6801_SYSTEMD_DIR:-/etc/systemd/system}"
ETC_MODULES="${YT6801_ETC_MODULES:-/etc/modules}"
SERVICE_NAME="yt6801-reinstall.service"
PKG_NAME="tuxedo-yt6801"

package_installed() {
    [ "$(dpkg-query -W -f='${Status}' "$PKG_NAME" 2>/dev/null || true)" = "install ok installed" ]
}

# Safety check, before touching anything: if the ethernet port only works
# because of the TUXEDO module, removing the package unloads it on the spot
# (its prerm runs `rmmod yt6801`), which cuts an SSH session running over
# that port, and leaves the port dead after every reboot.
if [ "$KEEP_DRIVER" -eq 0 ] && [ "$FORCE" -eq 0 ] && package_installed &&
    [ "$(yt6801_bound_driver)" = "$YT6801_TUXEDO_MODULE" ] && ! yt6801_native_driver >/dev/null; then
    cat >&2 <<EOF
Refusing to remove the driver: your YT6801 ethernet port is running on the
TUXEDO module and kernel $(uname -r) has no driver of its own for it.
Removing it would cut the network right now and after every reboot.

  - To keep the driver and only remove the auto-installer:
      sudo ./uninstall.sh --keep-driver
  - Linux 7.0+ includes a driver (dwmac-motorcomm); boot one, then run this again.
  - To remove it anyway (you will need another way to get online):
      sudo ./uninstall.sh --force
EOF
    exit 1
fi

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
if [ -f "$SYSTEMD_DIR/$SERVICE_NAME" ]; then
    echo "==> Removing service file..."
    rm -f "${SYSTEMD_DIR:?}/$SERVICE_NAME"
fi

# Reload systemd and clear any failed-state entry left behind by the unit
systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Removing $INSTALL_DIR..."
    rm -rf "${INSTALL_DIR:?}"
fi

if [ "$KEEP_DRIVER" -eq 1 ]; then
    echo "==> Uninstallation complete (driver kept, as requested)."
    exit 0
fi

# Purge the driver package. Its prerm runs `dkms remove --all`, which also
# drops the module from every kernel. Wait for the dpkg lock instead of
# failing when unattended-upgrades happens to be running.
if package_installed; then
    echo "==> Removing the $PKG_NAME driver package..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get -o DPkg::Lock::Timeout=300 purge -y "$PKG_NAME"
    else
        dpkg --purge "$PKG_NAME"
    fi
else
    echo "==> The $PKG_NAME package is not installed; nothing to purge."
fi

# Drop the boot-time module load added by install_yt6801_if_needed.sh;
# leaving it makes systemd-modules-load fail at every boot.
if [ -f "$ETC_MODULES" ] && grep -qxF "$YT6801_TUXEDO_MODULE" "$ETC_MODULES"; then
    echo "==> Removing '$YT6801_TUXEDO_MODULE' from $ETC_MODULES..."
    # Rewrite in place with `cat >` (not `sed -i`/`mv`) to keep the file's
    # owner, mode and inode.
    modules_tmp="$(mktemp)"
    grep -vxF "$YT6801_TUXEDO_MODULE" "$ETC_MODULES" >"$modules_tmp" || true
    cat "$modules_tmp" >"$ETC_MODULES"
    rm -f "$modules_tmp"
fi

# If the TUXEDO module was driving the port, purging it leaves the device
# unbound until the next boot. Load the kernel's own driver right away so
# the network comes back on its own.
if [ -z "$(yt6801_bound_driver)" ] && NATIVE_MODULE="$(yt6801_in_tree_module)" && [ -n "$NATIVE_MODULE" ]; then
    echo "==> Loading the kernel's own driver ($NATIVE_MODULE)..."
    modprobe "$NATIVE_MODULE" || echo "    Could not load $NATIVE_MODULE now; it will load on the next boot."
fi

echo "==> Uninstallation complete."
if NATIVE_DRIVER="$(yt6801_native_driver)"; then
    echo "    The kernel's own driver ($NATIVE_DRIVER) handles the YT6801."
fi
