#!/usr/bin/env bats
#
# Smoke tests for the boot-time scripts (install_yt6801_if_needed.sh,
# check_yt6801_and_reboot.sh) and uninstall.sh. See test_helper.bash for the
# stubs and fakes, and for the safety contract every test follows.
#
# Known, documented limitation: check_yt6801_and_reboot.sh invokes the
# reboot command by its absolute path (`/usr/bin/systemctl reboot`), not via
# a PATH lookup. That is intentional hardening (a hijacked PATH cannot
# trigger a spurious reboot), but it also means the PATH-based systemctl stub
# cannot intercept that call. We therefore never execute the one branch that
# reaches it - "module still not loaded, and no reboot-once flag exists yet".

load test_helper

setup() {
    common_setup
}

teardown() {
    common_teardown
}

@test "install_yt6801_if_needed.sh fails cleanly when no .deb package is present" {
    write_stub lsmod "exit 0" # module not loaded, no matching output

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: No .deb package found"* ]]

    # Nothing privileged was ever attempted.
    [ "$(calls_of dpkg)" -eq 0 ]
    [ "$(calls_of dpkg-deb)" -eq 0 ]
    [ "$(calls_of sudo)" -eq 0 ]
}

@test "check_yt6801_and_reboot.sh exits 0 without rebooting when the module is already loaded" {
    write_stub lsmod 'echo "yt6801 16384 0"'

    local script
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [ "$(calls_of systemctl)" -eq 0 ]
}

@test "check_yt6801_and_reboot.sh does not reboot again once the once-only flag is set" {
    write_stub lsmod "exit 0" # module still not loaded

    local script script_dir
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"
    script_dir="$(dirname "$script")"
    touch "$script_dir/yt6801_reboot_once.flag"

    run "$script"

    [ "$status" -eq 0 ]
    [ "$(calls_of systemctl)" -eq 0 ]
    [[ "$output" == *"reboot already done once"* ]]
    [ -f "$script_dir/yt6801_reboot_once.flag" ]
}

@test "install_yt6801_if_needed.sh refuses to run as non-root" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "test runner itself is root; cannot exercise the non-root rejection path"
    fi
    unset YT6801_SKIP_ROOT_CHECK

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run as root"* ]]

    # The script must exit before touching anything privileged.
    assert_no_privileged_calls
}

@test "check_yt6801_and_reboot.sh refuses to run as non-root" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "test runner itself is root; cannot exercise the non-root rejection path"
    fi
    unset YT6801_SKIP_ROOT_CHECK

    local script
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"

    run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run as root"* ]]
    assert_no_privileged_calls
}

@test "install_yt6801_if_needed.sh does nothing when no YT6801 controller is present" {
    fake_no_yt6801

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No Motorcomm YT6801 controller detected"* ]]
    [ "$(calls_of dpkg)" -eq 0 ]
    [ "$(calls_of dpkg-deb)" -eq 0 ]
    [ "$(calls_of modprobe)" -eq 0 ]
}

@test "install_yt6801_if_needed.sh skips the TUXEDO package when the in-kernel driver is bound" {
    fake_bind "0000:01:00.0" dwmac-motorcomm

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already provides a YT6801 driver (dwmac-motorcomm)"* ]]
    [ "$(calls_of dpkg)" -eq 0 ]
    [ "$(calls_of modprobe)" -eq 0 ]
}

@test "install_yt6801_if_needed.sh skips the TUXEDO package when the kernel ships an in-tree driver" {
    fake_alias dwmac_motorcomm # available, but not bound yet

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already provides a YT6801 driver (dwmac_motorcomm)"* ]]
    [ "$(calls_of dpkg)" -eq 0 ]
}

@test "install_yt6801_if_needed.sh does not mistake the TUXEDO module itself for an in-tree driver" {
    fake_alias yt6801 # alias added by a previous TUXEDO DKMS install
    fake_bind "0000:01:00.0" yt6801

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    # Falls through to the normal TUXEDO path (which then fails on the empty
    # deb/ directory) instead of claiming a native driver exists.
    [[ "$output" != *"already provides a YT6801 driver"* ]]
    [[ "$output" == *"ERROR: No .deb package found"* ]]
}

@test "check_yt6801_and_reboot.sh never reboots when the kernel drives the YT6801 natively" {
    write_stub lsmod "exit 0" # TUXEDO module not loaded
    fake_bind "0000:01:00.0" dwmac-motorcomm

    local script script_dir
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"
    script_dir="$(dirname "$script")"
    touch "$script_dir/yt6801_reboot_once.flag" # stale flag from an older run

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"provides its own YT6801 driver"* ]]
    [ "$(calls_of systemctl)" -eq 0 ]
    [ "$(calls_of modprobe)" -eq 0 ]
    [ ! -f "$script_dir/yt6801_reboot_once.flag" ]
}

@test "check_yt6801_and_reboot.sh never reboots when no YT6801 controller is present" {
    write_stub lsmod "exit 0"
    fake_no_yt6801

    local script
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No Motorcomm YT6801 controller detected"* ]]
    [ "$(calls_of systemctl)" -eq 0 ]
    [ "$(calls_of modprobe)" -eq 0 ]
}

@test "uninstall.sh refuses to remove the driver when the ethernet port depends on it" {
    fake_package_installed
    fake_bind "0000:01:00.0" yt6801 # TUXEDO drives the port, no native driver

    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to remove the driver"* ]]
    # Nothing was touched.
    [ "$(calls_of apt-get)" -eq 0 ]
    [ "$(calls_of systemctl)" -eq 0 ]
    [ -d "$YT6801_INSTALL_DIR" ]
    grep -qx yt6801 "$YT6801_ETC_MODULES"
}

@test "uninstall.sh --force removes the driver even if the ethernet port depends on it" {
    fake_package_installed
    fake_bind "0000:01:00.0" yt6801

    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script" --force

    [ "$status" -eq 0 ]
    grep -q "^apt-get .*purge -y tuxedo-yt6801" "$CALLS_LOG"
    [ "$(grep -cx yt6801 "$YT6801_ETC_MODULES" || true)" -eq 0 ]
}

@test "uninstall.sh removes everything when the kernel has its own driver" {
    fake_package_installed
    fake_alias dwmac_motorcomm # native driver available, device unbound

    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [ ! -e "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service" ]
    [ ! -d "$YT6801_INSTALL_DIR" ]
    grep -q "^apt-get -o DPkg::Lock::Timeout=300 purge -y tuxedo-yt6801" "$CALLS_LOG"
    # Only the yt6801 line is gone; the rest of /etc/modules is kept.
    [ "$(grep -cx yt6801 "$YT6801_ETC_MODULES" || true)" -eq 0 ]
    grep -qx loop "$YT6801_ETC_MODULES"
    # The unbound port gets the kernel's own driver right away.
    grep -q "^modprobe dwmac_motorcomm" "$CALLS_LOG"
}

@test "uninstall.sh --keep-driver leaves the driver and /etc/modules alone" {
    fake_package_installed
    fake_bind "0000:01:00.0" yt6801

    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script" --keep-driver

    [ "$status" -eq 0 ]
    [ ! -d "$YT6801_INSTALL_DIR" ]
    [ "$(calls_of apt-get)" -eq 0 ]
    [ "$(calls_of dpkg)" -eq 0 ]
    grep -qx yt6801 "$YT6801_ETC_MODULES"
}

@test "uninstall.sh skips the purge when the package is not installed" {
    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"package is not installed"* ]]
    [ "$(calls_of apt-get)" -eq 0 ]
}

@test "uninstall.sh rejects unknown options" {
    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script" --bogus

    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option: --bogus"* ]]
    [ "$(calls_of systemctl)" -eq 0 ]
}

@test "uninstall.sh refuses to run as non-root" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "test runner itself is root; cannot exercise the non-root rejection path"
    fi
    unset YT6801_SKIP_ROOT_CHECK

    local script
    script="$(sandbox_copy uninstall.sh)"

    run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run as root"* ]]
    assert_no_privileged_calls
}

@test "install_yt6801_if_needed.sh ignores an in-tree alias for other subsystem IDs" {
    # Claims the YT6801 only on boards with subsystem 1234:5678, not ours.
    fake_alias dwmac_motorcomm "pci:v00001F0Ad00006801sv00001234sd00005678bc*sc*i*"

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [[ "$output" != *"already provides a YT6801 driver"* ]]
    [[ "$output" == *"ERROR: No .deb package found"* ]]
}

@test "install_yt6801_if_needed.sh skips the TUXEDO package when the in-tree driver is built in" {
    fake_alias dwmac_motorcomm "" modules.builtin.alias

    local script
    script="$(sandbox_copy install_yt6801_if_needed.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already provides a YT6801 driver (dwmac_motorcomm)"* ]]
    [ "$(calls_of dpkg)" -eq 0 ]
}

@test "check_yt6801_and_reboot.sh sees a native driver bound to a second YT6801" {
    write_stub lsmod "exit 0"
    fake_pci_device "0000:02:00.0" 0x1f0a 0x6801
    fake_bind "0000:02:00.0" dwmac-motorcomm # the first one stays unbound

    local script
    script="$(sandbox_copy check_yt6801_and_reboot.sh)"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"provides its own YT6801 driver (dwmac-motorcomm)"* ]]
    [ "$(calls_of systemctl)" -eq 0 ]
}
