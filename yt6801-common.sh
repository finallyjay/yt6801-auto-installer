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
