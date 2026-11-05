#!/bin/bash
# YT6801 auto-installer: uninstaller.
#
#   curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash
#   sudo /opt/yt6801-auto-installer/uninstall.sh       (offline)
#
# Removes the boot service, /opt/yt6801-auto-installer and, by default, the
# TUXEDO driver itself. Piped into bash it fetches its release first, like
# install.sh does (see the bootstrap block).

set -euo pipefail

# >>> bootstrap: keep this block identical in install.sh and uninstall.sh
# (test/install.bats checks it).
YT6801_RELEASE_VERSION="" # stamped by tools/build-release.sh
YT6801_REPO="finallyjay/yt6801-auto-installer"

# Prints the directory of this script when its helpers are next to it (a
# release or a clone); fails when the script was piped into bash.
yt6801_local_dir() {
    local src="${BASH_SOURCE[0]:-}" dir
    [ -n "$src" ] && [ -f "$src" ] || return 1
    dir="$(cd "$(dirname "$src")" && pwd)"
    [ -f "$dir/yt6801-common.sh" ] || return 1
    echo "$dir"
}

yt6801_fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$2" "$1"
    else
        wget -q -O "$2" "$1"
    fi
}

yt6801_sha256_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c - >/dev/null
    else
        shasum -a 256 -c - >/dev/null
    fi
}

# yt6801_bootstrap <script> [args...]
# Downloads the release this script belongs to, verifies it and runs the
# bundled <script> with the same arguments.
yt6801_bootstrap() {
    local script="$1" base tarball tmp sums dir rc=0 arg wants_help=0
    shift
    for arg in "$@"; do
        case "$arg" in -h | --help) wants_help=1 ;; esac
    done
    # Fail before downloading anything; --help works without root.
    if [ "$wants_help" -eq 0 ] && [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
        echo "Please run it with sudo:  curl -fsSL https://yt6801.finallyjay.dev/$script | sudo bash" >&2
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "Neither curl nor wget is installed, so the installer cannot be downloaded." >&2
        return 1
    fi

    if [ -n "$YT6801_RELEASE_VERSION" ]; then
        base="https://github.com/$YT6801_REPO/releases/download/v$YT6801_RELEASE_VERSION"
        tarball="yt6801-auto-installer-$YT6801_RELEASE_VERSION.tar.gz"
    else
        base="https://github.com/$YT6801_REPO/releases/latest/download"
        tarball="yt6801-auto-installer.tar.gz"
    fi
    # Test-only override (test/install.bats serves a local release).
    base="${YT6801_RELEASE_BASE_URL:-$base}"

    tmp="$(mktemp -d)"
    echo "Downloading the YT6801 auto-installer${YT6801_RELEASE_VERSION:+ v$YT6801_RELEASE_VERSION}..."
    if ! yt6801_fetch "$base/$tarball" "$tmp/$tarball" || ! yt6801_fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS"; then
        echo "Download failed ($base). Check the connection, or install offline (see the README)." >&2
        rm -rf "$tmp"
        return 1
    fi
    sums="$(grep "  $tarball\$" "$tmp/SHA256SUMS" || true)"
    if [ -z "$sums" ] || ! (cd "$tmp" && echo "$sums" | yt6801_sha256_check); then
        echo "Checksum verification FAILED for $tarball; refusing to run it." >&2
        rm -rf "$tmp"
        return 1
    fi
    echo "Checksum verified."
    tar -xzf "$tmp/$tarball" -C "$tmp"
    dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'yt6801-auto-installer-*' | head -n 1)"
    if [ -z "$dir" ] || [ ! -f "$dir/$script" ]; then
        echo "The downloaded release does not contain $script." >&2
        rm -rf "$tmp"
        return 1
    fi
    # stdin is this very script when piped: give the child the terminal, or
    # nothing, so it never reads the rest of the pipe.
    if { : </dev/tty; } 2>/dev/null; then
        bash "$dir/$script" "$@" </dev/tty || rc=$?
    else
        bash "$dir/$script" "$@" </dev/null || rc=$?
    fi
    rm -rf "$tmp"
    return "$rc"
}
# <<< bootstrap

usage() {
    cat <<'USAGE'
Usage: curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash [-s -- OPTIONS]
       sudo ./uninstall.sh [OPTIONS]

Removes the YT6801 auto-installer: the boot service, its files in
/opt/yt6801-auto-installer and, by default, the TUXEDO driver itself
(the tuxedo-yt6801 package, its DKMS module and the /etc/modules entry).

Options:
  --keep-driver  Only remove the auto-installer; keep the TUXEDO driver.
  --force        Remove the driver even if the ethernet port depends on it
                 (it stops working immediately and after every reboot).
  -y, --yes      Do not ask for confirmation.
  -h, --help     Show this help.
USAGE
}

package_installed() {
    [ "$(dpkg-query -W -f='${Status}' "$PKG_NAME" 2>/dev/null || true)" = "install ok installed" ]
}

remove_service() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    fi
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
    fi
    rm -f "${SYSTEMD_DIR:?}/$SERVICE_NAME"
    systemctl daemon-reload
    # Clear any failed-state entry left behind by the unit.
    systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
}

# Purge the driver package. Its prerm runs `dkms remove --all`, which also
# drops the module from every kernel. Wait for the dpkg lock instead of
# failing when unattended-upgrades happens to be running.
purge_package() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get -o DPkg::Lock::Timeout=300 purge -y "$PKG_NAME"
    else
        dpkg --purge "$PKG_NAME"
    fi
}

# Drop the boot-time module load added by install_yt6801_if_needed.sh;
# leaving it makes systemd-modules-load fail at every boot. Rewritten in
# place with `cat >` (not `sed -i`/`mv`) to keep its owner, mode and inode.
clean_etc_modules() {
    local tmp
    tmp="$(mktemp)"
    grep -vxF "$YT6801_TUXEDO_MODULE" "$ETC_MODULES" >"$tmp" || true
    cat "$tmp" >"$ETC_MODULES"
    rm -f "$tmp"
}

run_uninstall() {
    local native module
    ui_banner "YT6801 auto-installer: uninstall" "${YT6801_RELEASE_VERSION:+v$YT6801_RELEASE_VERSION}"

    # Safety check, before touching anything: if the ethernet port only works
    # because of the TUXEDO module, removing the package unloads it on the
    # spot (its prerm runs `rmmod yt6801`), which cuts an SSH session running
    # over that port, and leaves the port dead after every reboot.
    if [ "$KEEP_DRIVER" -eq 0 ] && [ "$FORCE" -eq 0 ] && package_installed &&
        [ "$(yt6801_bound_driver)" = "$YT6801_TUXEDO_MODULE" ] && ! yt6801_native_driver >/dev/null; then
        ui_warn "Your YT6801 ethernet port is running on the TUXEDO driver, and kernel"
        ui_warn "$(uname -r) has no driver of its own for it. Removing it cuts the"
        ui_warn "network right now (including SSH over that port) and after every reboot."
        if ! ui_confirm "Remove the driver anyway?" n; then
            ui_err "Refusing to remove the driver while the ethernet port depends on it."
            ui_info "Keep the driver, remove only this tool:   add --keep-driver"
            ui_info "Linux 7.0+ has its own driver (dwmac-motorcomm): boot one, then run this again."
            ui_info "Remove it anyway (you need another way online):   add --force"
            return 1
        fi
    fi

    ui_step "This will"
    ui_info "Remove $SERVICE_NAME and $INSTALL_DIR"
    if [ "$KEEP_DRIVER" -eq 0 ]; then
        ui_info "Remove the TUXEDO driver (tuxedo-yt6801, its DKMS module, the /etc/modules entry)"
    fi
    if ! ui_confirm "Continue?" y; then
        ui_info "Cancelled. Nothing was changed."
        return 0
    fi

    LOG="$(mktemp "${TMPDIR:-/tmp}/yt6801-uninstall.XXXXXX")"
    ui_step "Uninstalling"
    ui_run "Removing $SERVICE_NAME" "$LOG" remove_service
    if [ -d "$INSTALL_DIR" ]; then
        ui_run "Removing $INSTALL_DIR" "$LOG" rm -rf "${INSTALL_DIR:?}"
    fi

    if [ "$KEEP_DRIVER" -eq 1 ]; then
        ui_ok "Driver kept, as requested."
    else
        if package_installed; then
            ui_run "Removing the $PKG_NAME driver package" "$LOG" purge_package
        else
            ui_info "The $PKG_NAME package is not installed; nothing to purge."
        fi
        if [ -f "$ETC_MODULES" ] && grep -qxF "$YT6801_TUXEDO_MODULE" "$ETC_MODULES"; then
            ui_run "Removing '$YT6801_TUXEDO_MODULE' from $ETC_MODULES" "$LOG" clean_etc_modules
        fi
        # If the TUXEDO module was driving the port, purging it leaves the
        # device unbound until the next boot. Load the kernel's own driver
        # right away so the network comes back on its own.
        if [ -z "$(yt6801_bound_driver)" ] && module="$(yt6801_in_tree_module)" && [ -n "$module" ]; then
            ui_run "Loading the kernel's own driver ($module)" "$LOG" modprobe "$module" ||
                ui_info "It will load on the next boot."
        fi
    fi

    printf '\n  %sUninstallation complete.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
    if native="$(yt6801_native_driver)"; then
        ui_info "The kernel's own driver ($native) handles the YT6801."
    fi
    rm -f "$LOG"
}

main() {
    local arg
    if ! SCRIPT_DIR="$(yt6801_local_dir)"; then
        yt6801_bootstrap uninstall.sh "$@"
        return
    fi

    KEEP_DRIVER=0
    FORCE=0
    for arg in "$@"; do
        case "$arg" in
        --keep-driver) KEEP_DRIVER=1 ;;
        --force) FORCE=1 ;;
        -y | --yes) export YT6801_ASSUME_YES=1 ;;
        -h | --help)
            usage
            return 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            usage >&2
            return 2
            ;;
        esac
    done

    # Require root up front instead of prompting for `sudo` command-by-command:
    # a mid-script sudo prompt the user cancels (or a stale credential cache
    # timing out) would leave the uninstall half-applied.
    # YT6801_SKIP_ROOT_CHECK is set only by the bats test suite to exercise
    # this script's logic without requiring the test runner to be root.
    if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
        echo "This script must be run as root (use: sudo ./uninstall.sh)." >&2
        return 1
    fi

    # shellcheck source=yt6801-common.sh
    . "$SCRIPT_DIR/yt6801-common.sh"
    ui_init

    # Test-only overrides (see test/smoke.bats), like YT6801_SKIP_ROOT_CHECK.
    INSTALL_DIR="${YT6801_INSTALL_DIR:-/opt/yt6801-auto-installer}"
    SYSTEMD_DIR="${YT6801_SYSTEMD_DIR:-/etc/systemd/system}"
    ETC_MODULES="${YT6801_ETC_MODULES:-/etc/modules}"
    SERVICE_NAME="yt6801-reinstall.service"
    PKG_NAME="tuxedo-yt6801"

    run_uninstall
}

main "$@"
