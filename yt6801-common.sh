#!/bin/bash
# Shared helpers for the YT6801 auto-installer scripts.
#
# This file is sourced, not executed. It answers two questions every other
# script needs before touching the system:
#
#   1. Is there a Motorcomm YT6801 controller in this machine at all?
#   2. Does the running kernel already ship its own driver for it?
#
# Linux 7.0 added an in-tree driver for the YT6801 (dwmac-motorcomm, a glue
# driver for stmmac). On such kernels the TUXEDO DKMS package is not needed,
# and reinstalling it at every boot only fights the in-kernel driver.
#
# The sysfs and modules paths can be overridden through YT6801_SYSFS_PCI and
# YT6801_MODULES_DIR. Like YT6801_SKIP_ROOT_CHECK, these are test-only
# switches used by test/*.bats to fake the hardware; they are not a supported
# configuration interface.

YT6801_PCI_VENDOR="0x1f0a"
YT6801_PCI_DEVICE="0x6801"
YT6801_TUXEDO_MODULE="yt6801"

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
# Runs a command with its output appended to <logfile>, showing a spinner on
# a terminal. On failure it prints the last lines of the log and fails.
ui_run() {
    local msg="$1" log="$2" pid rc=0 i=0
    shift 2
    printf '\n=== %s\n' "$msg" >>"$log"
    if [ "$UI_TTY" -eq 1 ]; then
        "$@" >>"$log" 2>&1 &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s' "$C_BLUE" "${UI_SPINNER[i++ % ${#UI_SPINNER[@]}]}" "$C_RESET" "$msg"
            sleep 0.1
        done
        wait "$pid" || rc=$?
        printf '\r\033[K'
    else
        "$@" >>"$log" 2>&1 || rc=$?
    fi
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
# Asks on the terminal. Without one (or with YT6801_ASSUME_YES=1) it takes
# the default answer, so unattended runs never hang.
ui_confirm() {
    local question="$1" default="$2" hint answer
    if [ "${YT6801_ASSUME_YES:-0}" = "1" ]; then
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
