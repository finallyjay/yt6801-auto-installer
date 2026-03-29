#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGF="$SCRIPT_DIR/install_yt6801.log"
FLAG="$SCRIPT_DIR/yt6801_reboot_once.flag"

echo "=== $(date): Checking YT6801 module status ===" >> "$LOGF"

# Check if the module is loaded
if ! lsmod | grep -q yt6801; then
    if [ -f "$FLAG" ]; then
        echo "$(date): Module still not loaded; reboot already done once. Skipping reboot." >> "$LOGF"
    else
        echo "$(date): Module not loaded; rebooting required." >> "$LOGF"
        touch "$FLAG"
        /usr/bin/systemctl reboot || true
    fi
else
    echo "$(date): Module loaded successfully." >> "$LOGF"
    [ -f "$FLAG" ] && rm -f "$FLAG"
fi

exit 0
