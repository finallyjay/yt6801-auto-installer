#!/bin/bash
set -euo pipefail

# This script is launched by systemd (as root) via ExecStartPost, but can
# also be run manually. It needs root to load kernel modules and trigger a
# reboot, so require it up front rather than failing partway through.
# YT6801_SKIP_ROOT_CHECK is set only by the bats test suite (test/smoke.bats)
# to exercise this script's logic without requiring the test runner to be root.
if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
    echo "This script must be run as root (use: sudo ./check_yt6801_and_reboot.sh)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLAG="$SCRIPT_DIR/yt6801_reboot_once.flag"

echo "=== $(date): Checking YT6801 module status ==="

# Check if the module is loaded
if ! lsmod | grep -q yt6801; then
    if [ -f "$FLAG" ]; then
        echo "$(date): Module still not loaded; reboot already done once. Skipping reboot."
    else
        echo "$(date): Module not loaded; attempting modprobe yt6801 before considering reboot."
        modprobe yt6801 || true
        if lsmod | awk '{print $1}' | grep -qx yt6801; then
            echo "$(date): Module loaded successfully after modprobe; no reboot needed."
        else
            echo "$(date): Module still not loaded after modprobe; rebooting required."
            touch "$FLAG"
            sync
            /usr/bin/systemctl reboot || true
        fi
    fi
else
    echo "$(date): Module loaded successfully."
    [ -f "$FLAG" ] && rm -f "$FLAG"
fi

exit 0
