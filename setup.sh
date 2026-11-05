#!/bin/bash
set -euo pipefail

# Kept for compatibility with older instructions (`sudo bash setup.sh`):
# install.sh is the installer now. It checks whether this machine needs the
# driver at all, installs it and enables the boot service.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/install.sh" "$@"
