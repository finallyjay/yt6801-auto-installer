#!/bin/bash
# YT6801 auto-installer: one-line installer for the Motorcomm YT6801
# ethernet driver (TUXEDO tuxedo-yt6801 DKMS package).
#
#   curl -fsSL https://yt6801.finallyjay.dev/install.sh | sudo bash
#
# Piped like that, this script has no files next to it: it downloads the
# release tarball of its own version, checks it against the release's
# SHA256SUMS and runs the install.sh inside it. Run from an extracted
# release or a clone (offline install), it installs from the files next
# to it.
#
# Everything lives in functions and `main` is called on the last line, so
# a download cut short never runs a half script.

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
    cat <<'EOF'
Usage: curl -fsSL https://yt6801.finallyjay.dev/install.sh | sudo bash
       sudo ./install.sh [--yes]          (from an extracted release)

Installs the TUXEDO driver for the Motorcomm YT6801 ethernet controller,
plus a boot service that rebuilds it after kernel updates. It does nothing
on kernels that already include a driver for it (Linux 7.0+).

Options:
  -y, --yes   Do not ask for confirmation.
  -h, --help  Show this help.
EOF
}

# Copies the auto-installer to INSTALL_DIR (including the uninstaller, so it
# also works offline later).
install_files() {
    mkdir -p "$INSTALL_DIR"
    cp -R "$SCRIPT_DIR/deb" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/install_yt6801_if_needed.sh" "$SCRIPT_DIR/check_yt6801_and_reboot.sh" \
        "$SCRIPT_DIR/yt6801-common.sh" "$SCRIPT_DIR/uninstall.sh" \
        "$SCRIPT_DIR/yt6801-reinstall.service" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/*.sh
}

enable_service() {
    mkdir -p "$SYSTEMD_DIR"
    cp "$INSTALL_DIR/$SERVICE_NAME" "$SYSTEMD_DIR/"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

# Prints the newest tuxedo-yt6801 .deb shipped with the installer.
bundled_deb() {
    find "$SCRIPT_DIR/deb" -maxdepth 1 -name 'tuxedo-yt6801_*.deb' -type f | sort | tail -n 1
}

run_install() {
    local version native deb deb_version log missing=() link
    version="${YT6801_RELEASE_VERSION:-$(tr -d '[:space:]' <"$SCRIPT_DIR/VERSION" 2>/dev/null || echo dev)}"
    ui_banner "YT6801 ethernet driver installer" "v$version"

    ui_step "Checking this machine"
    ui_ok "Kernel $(uname -r)"

    if ! yt6801_device_present; then
        ui_warn "No Motorcomm YT6801 ethernet controller found on this machine."
        ui_info "Nothing to install."
        return 0
    fi
    ui_ok "Motorcomm YT6801 controller found ($(basename "$(yt6801_devices | head -n 1)"))"

    if native="$(yt6801_native_driver)"; then
        ui_ok "Your kernel already has a driver for it: $native"
        printf '\n  %sNothing to install%s: this kernel drives the YT6801 on its own.\n' "$C_GREEN$C_BOLD" "$C_RESET"
        if [ -f "$SYSTEMD_DIR/$SERVICE_NAME" ]; then
            ui_info "An older install of this tool is still here. Remove it with:"
            ui_info "  curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash"
        fi
        return 0
    fi
    if [ "$(yt6801_bound_driver)" = "$YT6801_TUXEDO_MODULE" ]; then
        ui_ok "It already runs on the TUXEDO driver; this will set it up to survive kernel updates."
    else
        ui_warn "Your kernel has no driver for it, so the ethernet port is not working yet."
    fi

    deb="$(bundled_deb)"
    if [ -z "$deb" ]; then
        ui_err "The installer has no driver package (deb/ is empty)."
        return 1
    fi
    deb_version="$(dpkg-deb -f "$deb" Version 2>/dev/null || echo "?")"

    command -v dkms >/dev/null 2>&1 || missing+=(dkms)
    [ -e "$(yt6801_modules_dir)/build" ] || missing+=("linux-headers-$(uname -r)")

    ui_step "This will"
    [ ${#missing[@]} -eq 0 ] || ui_info "Install ${missing[*]} (needs internet: Wi-Fi or USB tethering)"
    ui_info "Install the TUXEDO driver tuxedo-yt6801 $deb_version (built with DKMS)"
    ui_info "Enable $SERVICE_NAME, which rebuilds the driver after kernel updates"
    ui_info "Copy this tool to $INSTALL_DIR"
    if ! ui_confirm "Continue?" y; then
        ui_info "Cancelled. Nothing was changed."
        return 0
    fi

    log="$(mktemp "${TMPDIR:-/tmp}/yt6801-install.XXXXXX")"
    ui_step "Installing"
    if [ ${#missing[@]} -gt 0 ] &&
        ! ui_run "Installing ${missing[*]}" "$log" apt-get -o DPkg::Lock::Timeout=300 install -y "${missing[@]}"; then
        ui_info "These packages come from the internet. Connect another way (Wi-Fi, USB"
        ui_info "tethering) and run the installer again."
        return 1
    fi
    ui_run "Copying the auto-installer to $INSTALL_DIR" "$log" install_files
    ui_run "Enabling $SERVICE_NAME" "$log" enable_service
    ui_run "Building and loading the driver (DKMS, can take a few minutes)" "$log" \
        "$INSTALL_DIR/install_yt6801_if_needed.sh"

    ui_step "Result"
    if [ "$(yt6801_bound_driver)" = "$YT6801_TUXEDO_MODULE" ]; then
        link="$(yt6801_link_summary)"
        printf '\n  %sAll done!%s Your YT6801 ethernet port is ready%s.\n' "$C_GREEN$C_BOLD" "$C_RESET" "${link:+: $link}"
        rm -f "$log"
    else
        ui_warn "The driver is installed but not bound to the port yet. Rebooting usually fixes it;"
        ui_warn "the boot service also reboots once by itself if needed. Log: $log"
    fi
    ui_info "After kernel updates the driver is rebuilt at boot ($SERVICE_NAME)."
    ui_info "Logs:       sudo journalctl -u $SERVICE_NAME"
    ui_info "Uninstall:  curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash"
    ui_info "Offline:    sudo $INSTALL_DIR/uninstall.sh"
    ui_info "Moving to Linux 7.0+? It has its own driver: run the uninstaller then."
}

main() {
    local arg
    if ! SCRIPT_DIR="$(yt6801_local_dir)"; then
        yt6801_bootstrap install.sh "$@"
        return
    fi

    for arg in "$@"; do
        case "$arg" in
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

    if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
        echo "This script must be run as root (use: sudo ./install.sh)." >&2
        return 1
    fi

    # shellcheck source=yt6801-common.sh
    . "$SCRIPT_DIR/yt6801-common.sh"
    ui_init

    # Test-only overrides (see test/install.bats), like YT6801_SKIP_ROOT_CHECK.
    INSTALL_DIR="${YT6801_INSTALL_DIR:-/opt/yt6801-auto-installer}"
    SYSTEMD_DIR="${YT6801_SYSTEMD_DIR:-/etc/systemd/system}"
    SERVICE_NAME="yt6801-reinstall.service"

    run_install
}

main "$@"
