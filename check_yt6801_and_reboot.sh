#!/bin/bash
set -euo pipefail

# Boot-time check of yt6801-reinstall.service (as root, after
# install_yt6801_if_needed.sh): if the TUXEDO module is needed but still not
# loaded, try modprobe, and reboot once if that does not help either.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLAG="$SCRIPT_DIR/yt6801_reboot_once.flag"
# shellcheck source=yt6801-common.sh
. "$SCRIPT_DIR/yt6801-common.sh"
yt6801_require_root check_yt6801_and_reboot.sh

echo "=== $(date): Checking YT6801 module status ==="

# Never reboot over a missing TUXEDO module that is not supposed to be there.
if reason="$(yt6801_tuxedo_unneeded)"; then
    echo "$(date): $reason; no reboot needed."
    rm -f "$FLAG"
    exit 0
fi

if yt6801_tuxedo_loaded; then
    echo "$(date): Module loaded successfully."
    rm -f "$FLAG"
    exit 0
fi

if [ -f "$FLAG" ]; then
    echo "$(date): Module still not loaded; reboot already done once. Skipping reboot."
    exit 0
fi

echo "$(date): Module not loaded; attempting modprobe $YT6801_TUXEDO_MODULE before considering reboot."
modprobe "$YT6801_TUXEDO_MODULE" || true
if yt6801_tuxedo_loaded; then
    echo "$(date): Module loaded successfully after modprobe; no reboot needed."
    exit 0
fi

echo "$(date): Module still not loaded after modprobe; rebooting once."
touch "$FLAG"
sync
# Absolute path on purpose: a hijacked PATH cannot trigger a reboot.
if ! /usr/bin/systemctl reboot; then
    echo "$(date): ERROR: the reboot failed; it will be retried on the next boot."
    rm -f "$FLAG"
    exit 1
fi
