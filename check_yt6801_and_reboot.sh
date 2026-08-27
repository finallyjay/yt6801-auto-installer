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
        echo "$(date): Module not loaded; attempting modprobe yt6801 before considering reboot." >> "$LOGF"
        modprobe yt6801 || true
        if lsmod | grep -q yt6801; then
            echo "$(date): Module loaded successfully after modprobe; no reboot needed." >> "$LOGF"
        else
            echo "$(date): Module still not loaded after modprobe; rebooting required." >> "$LOGF"
            touch "$FLAG"
            sync
            /usr/bin/systemctl reboot || true
        fi
    fi
else
    echo "$(date): Module loaded successfully." >> "$LOGF"
    [ -f "$FLAG" ] && rm -f "$FLAG"
fi

exit 0
