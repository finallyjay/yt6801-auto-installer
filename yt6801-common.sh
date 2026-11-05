#!/bin/bash
# Shared helpers for the YT6801 auto-installer scripts (sourced, not run).
#
# Linux 7.0 added an in-tree driver for the YT6801 (dwmac-motorcomm). These
# helpers tell whether a machine has the controller and whether its kernel
# already drives it, so the scripts never fight that driver.
#
# Every YT6801_* path override below, like YT6801_SKIP_ROOT_CHECK, is a
# test-only switch used by test/*.bats to fake the system; it is not a
# supported configuration interface.

# The constants below are used by the scripts that source this file.
# shellcheck disable=SC2034
YT6801_PCI_VENDOR="0x1f0a"
YT6801_PCI_DEVICE="0x6801" # also hardcoded in the alias match below
YT6801_TUXEDO_MODULE="yt6801"
PKG_NAME="tuxedo-yt6801"
SERVICE_NAME="yt6801-reinstall.service"
INSTALL_DIR="${YT6801_INSTALL_DIR:-/opt/yt6801-auto-installer}"
SYSTEMD_DIR="${YT6801_SYSTEMD_DIR:-/etc/systemd/system}"
ETC_MODULES="${YT6801_ETC_MODULES:-/etc/modules}"

# yt6801_require_root <script> - fails with a hint unless running as root.
# Required up front, rather than sudo inside the scripts, so a cancelled or
# expired sudo prompt can never leave a change half-applied.
yt6801_require_root() {
    if [ "$(id -u)" -ne 0 ] && [ -z "${YT6801_SKIP_ROOT_CHECK:-}" ]; then
        echo "This script must be run as root (use: sudo ./$1)." >&2
        return 1
    fi
}

yt6801_sysfs_pci() {
    echo "${YT6801_SYSFS_PCI:-/sys/bus/pci/devices}"
}

yt6801_modules_dir() {
    echo "${YT6801_MODULES_DIR:-/lib/modules/$(uname -r)}"
}

# Prints the sysfs path of every YT6801 controller, one per line.
yt6801_devices() {
    local dev vendor device
    for dev in "$(yt6801_sysfs_pci)"/*; do
        [ -r "$dev/vendor" ] && [ -r "$dev/device" ] || continue
        vendor="$(cat "$dev/vendor")"
        device="$(cat "$dev/device")"
        if [ "$vendor" = "$YT6801_PCI_VENDOR" ] && [ "$device" = "$YT6801_PCI_DEVICE" ]; then
            echo "$dev"
        fi
    done
}

# Succeeds if at least one YT6801 controller is present.
yt6801_device_present() {
    [ -n "$(yt6801_devices)" ]
}

# Prints the driver bound to each YT6801 controller, one per line (nothing
# for an unbound controller).
yt6801_bound_drivers() {
    local dev
    while IFS= read -r dev; do
        [ -n "$dev" ] && [ -e "$dev/driver" ] || continue
        basename "$(readlink -f "$dev/driver")"
    done < <(yt6801_devices)
}

# Prints the driver bound to the first YT6801 controller, or nothing.
yt6801_bound_driver() {
    yt6801_bound_drivers | head -n 1
}

# Prints the in-kernel module that claims a YT6801 for the running kernel
# (anything other than the TUXEDO "yt6801" module), or nothing. Each alias
# pattern is matched as a glob against the controller's own modalias, so an
# alias limited to other subsystem IDs does not count. Built-in drivers are
# listed in modules.builtin.alias rather than modules.alias.
yt6801_in_tree_module() {
    local dir dev modalias file keyword pattern module
    dir="$(yt6801_modules_dir)"
    while IFS= read -r dev; do
        [ -r "$dev/modalias" ] || continue
        modalias="$(cat "$dev/modalias")"
        for file in "$dir/modules.alias" "$dir/modules.builtin.alias"; do
            [ -r "$file" ] || continue
            while read -r keyword pattern module; do
                [ "$keyword" = "alias" ] && [ "$module" != "$YT6801_TUXEDO_MODULE" ] || continue
                # shellcheck disable=SC2053 # $pattern is a glob on purpose
                if [[ "$modalias" == $pattern ]]; then
                    echo "$module"
                    return 0
                fi
            done < <(grep -i '^alias pci:v00001F0Ad00006801' "$file")
        done
    done < <(yt6801_devices)
}

# Prints the native (non-TUXEDO) driver for the YT6801 and succeeds if the
# running kernel provides one: either it is already bound to a controller,
# or the kernel's module aliases match one. Fails otherwise.
yt6801_native_driver() {
    local bound module
    while IFS= read -r bound; do
        if [ "$bound" != "$YT6801_TUXEDO_MODULE" ]; then
            echo "$bound"
            return 0
        fi
    done < <(yt6801_bound_drivers)
    module="$(yt6801_in_tree_module)"
    if [ -n "$module" ]; then
        echo "$module"
        return 0
    fi
    return 1
}

# Prints why the TUXEDO driver is not needed here and succeeds, or fails
# when it is needed (a YT6801 the running kernel cannot drive).
yt6801_tuxedo_unneeded() {
    local native
    if ! yt6801_device_present; then
        echo "No Motorcomm YT6801 controller detected"
    elif native="$(yt6801_native_driver)"; then
        echo "Kernel $(uname -r) already provides a YT6801 driver ($native); the TUXEDO package is not needed"
    else
        return 1
    fi
}

# Succeeds if the TUXEDO module is loaded. awk reads all of lsmod's output,
# so lsmod never dies of SIGPIPE, and compares the module name exactly.
yt6801_tuxedo_loaded() {
    lsmod | awk -v m="$YT6801_TUXEDO_MODULE" '$1 == m { found = 1 } END { exit !found }'
}

# yt6801_newest_deb <dir> - sets DEB_PKG and DEB_VERSION to the newest
# tuxedo-yt6801 package in <dir>, or fails if there is none. Candidates are
# filtered by their package name, not their file name, and compared with
# dpkg --compare-versions (sort -V ignores Debian version rules).
yt6801_newest_deb() {
    local candidate name version
    DEB_PKG=""
    DEB_VERSION=""
    while IFS= read -r candidate; do
        name="$(dpkg-deb -f "$candidate" Package 2>/dev/null)" || continue
        [ "$name" = "$PKG_NAME" ] || continue
        version="$(dpkg-deb -f "$candidate" Version 2>/dev/null)" || continue
        if [ -z "$DEB_VERSION" ] || dpkg --compare-versions "$version" gt "$DEB_VERSION"; then
            DEB_PKG="$candidate"
            DEB_VERSION="$version"
        fi
    done < <(find "$1" -maxdepth 1 -name '*.deb' -type f 2>/dev/null)
    [ -n "$DEB_PKG" ]
}

# ---------------------------------------------------------------------------
# Friendly terminal output for install.sh and uninstall.sh.
#
# Colours and symbols only when stdout is a terminal (and NO_COLOR is unset),
# so logs and pipes get plain text. Questions are read from /dev/tty, since
# under `curl ... | sudo bash` stdin is the script itself.
# ---------------------------------------------------------------------------

ui_init() {
    UI_TTY=0
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
        UI_TTY=1
        C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
        C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
    fi
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8* | *utf8* | *UTF8* | *utf-8*)
        S_OK="✔" S_ERR="✖" S_WARN="!" S_INFO="•" S_STEP="▸"
        UI_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        ;;
    *)
        S_OK="ok" S_ERR="x" S_WARN="!" S_INFO="-" S_STEP=">"
        UI_SPINNER=("-" "\\" "|" "/")
        ;;
    esac
}

ui_banner() {
    printf '\n%s%s%s %s%s%s\n' "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "${2:-}" "$C_RESET"
}

ui_step() {
    printf '\n%s%s%s %s%s%s\n' "$C_BLUE" "$S_STEP" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

ui_ok() { printf '  %s%s%s %s\n' "$C_GREEN" "$S_OK" "$C_RESET" "$*"; }
ui_info() { printf '  %s%s%s %s\n' "$C_DIM" "$S_INFO" "$C_RESET" "$*"; }
ui_warn() { printf '  %s%s%s %s\n' "$C_YELLOW" "$S_WARN" "$C_RESET" "$*"; }
ui_err() { printf '  %s%s%s %s\n' "$C_RED" "$S_ERR" "$C_RESET" "$*" >&2; }

# ui_run <message> <logfile> <command...>
# Runs a command with its output appended to <logfile>, with a spinner on a
# terminal, and prints its result; on failure it shows the end of the log
# and fails. The command always runs as a background job: called from an
# `if`/`||` context, bash would disable `set -e` inside shell functions and
# only their last command would count. Ctrl-C stops the job too.
ui_run() {
    local msg="$1" log="$2" pid rc=0 i=0
    shift 2
    printf '\n=== %s\n' "$msg" >>"$log"
    "$@" >>"$log" 2>&1 &
    pid=$!
    trap 'kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf "\n" >&2; ui_err "Interrupted: $msg"; exit 130' INT TERM
    if [ "$UI_TTY" -eq 1 ]; then
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s' "$C_BLUE" "${UI_SPINNER[i++ % ${#UI_SPINNER[@]}]}" "$C_RESET" "$msg"
            sleep 0.1
        done
    fi
    wait "$pid" || rc=$?
    trap - INT TERM
    [ "$UI_TTY" -eq 0 ] || printf '\r\033[K'
    if [ "$rc" -eq 0 ]; then
        ui_ok "$msg"
    else
        ui_err "$msg (failed)"
        tail -n 15 "$log" | sed 's/^/      /' >&2
        ui_info "Full log: $log"
    fi
    return "$rc"
}

# ui_confirm <question> <default: y|n>
# Asks on the terminal; without one it takes the default, so unattended runs
# never hang. YT6801_ASSUME_YES (--yes) only answers questions whose default
# is yes: a question defaulting to no guards something dangerous, which only
# an explicit flag such as uninstall.sh --force may skip. Answers in English
# or Spanish ("s"/"si") are accepted.
ui_confirm() {
    local question="$1" default="$2" hint answer
    if [ "$default" = "y" ] && [ "${YT6801_ASSUME_YES:-0}" = "1" ]; then
        return 0
    fi
    if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    if ! { : </dev/tty; } 2>/dev/null; then
        [ "$default" = "y" ]
        return
    fi
    printf '\n  %s %s ' "$question" "$hint"
    read -r answer </dev/tty || answer=""
    case "${answer:-$default}" in
    [yY] | [yY][eE][sS] | [sS] | [sS][iI] | [sS][íÍ]) return 0 ;;
    *) return 1 ;;
    esac
}

# ui_done <message> - the final, highlighted line of a run.
ui_done() {
    printf '\n  %s%s%s\n' "$C_GREEN$C_BOLD" "$*" "$C_RESET"
}

# Prints "<iface> (<state>[, <speed> Mb/s])" for the first YT6801, if any.
yt6801_link_summary() {
    local dev iface="" state speed="" path
    dev="$(yt6801_devices | head -n 1)"
    [ -n "$dev" ] && [ -d "$dev/net" ] || return 0
    for path in "$dev/net"/*; do
        [ -e "$path" ] && iface="$(basename "$path")" && break
    done
    [ -n "$iface" ] || return 0
    state="$(cat "$dev/net/$iface/operstate" 2>/dev/null || echo unknown)"
    if [ "$state" = "up" ]; then
        speed="$(cat "$dev/net/$iface/speed" 2>/dev/null || true)"
    fi
    echo "$iface ($state${speed:+, $speed Mb/s})"
}
