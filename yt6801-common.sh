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

# Prints the name of the driver bound to the first YT6801 controller, or
# nothing if it is not bound.
yt6801_bound_driver() {
    local dev
    dev="$(yt6801_devices | head -n 1)"
    [ -n "$dev" ] && [ -e "$dev/driver" ] || return 0
    basename "$(readlink -f "$dev/driver")"
}

# Prints the in-kernel module that claims the YT6801 for the running kernel
# (anything other than the TUXEDO "yt6801" module), or nothing.
yt6801_in_tree_module() {
    local alias_file
    alias_file="$(yt6801_modules_dir)/modules.alias"
    [ -r "$alias_file" ] || return 0
    awk -v tuxedo="$YT6801_TUXEDO_MODULE" '
        tolower($2) ~ /^pci:v00001f0ad00006801/ && $3 != tuxedo { print $3; exit }
    ' "$alias_file"
}

# Prints the native (non-TUXEDO) driver for the YT6801 and succeeds if the
# running kernel provides one: either it is already bound to the device, or
# the kernel's module aliases list one. Fails otherwise.
yt6801_native_driver() {
    local bound module
    bound="$(yt6801_bound_driver)"
    if [ -n "$bound" ] && [ "$bound" != "$YT6801_TUXEDO_MODULE" ]; then
        echo "$bound"
        return 0
    fi
    module="$(yt6801_in_tree_module)"
    if [ -n "$module" ]; then
        echo "$module"
        return 0
    fi
    return 1
}
