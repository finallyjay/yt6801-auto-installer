#!/usr/bin/env bats
#
# Smoke tests for install_yt6801_if_needed.sh and check_yt6801_and_reboot.sh.
#
# Safety contract: these tests must NEVER perform a real dpkg install, load a
# kernel module, or reboot the machine. Before any script under test runs,
# every command it could use to do so - dpkg, dpkg-query, dpkg-deb,
# systemctl, modprobe, lsmod, sync, sudo - is replaced by a recording stub
# placed ahead of the real binaries on PATH. Each stub appends its name and
# arguments to $CALLS_LOG, so tests assert exactly what was (and was not)
# invoked instead of trusting exit codes alone.
#
# All scripts under test now refuse to run unless invoked as root (they no
# longer shell out to `sudo` internally - see setup.sh/uninstall.sh for the
# rationale). The bats test runner itself is not root, so `setup()` exports
# YT6801_SKIP_ROOT_CHECK=1, a switch every script's root check honors, purely
# to let these tests exercise the scripts' logic without requiring the CI
# runner to run as root. It is not documented in the README/CLI usage on
# purpose: it is a test-only escape hatch, not a supported way to bypass the
# root requirement.
#
# Known, documented limitation: check_yt6801_and_reboot.sh invokes the
# reboot command by its absolute path (`/usr/bin/systemctl reboot`), not via
# a PATH lookup. That is intentional hardening in the script (it avoids a
# hijacked PATH triggering a spurious reboot), but it also means our
# PATH-based systemctl stub cannot intercept that specific call. We
# therefore never execute the one branch that reaches it - "module still
# not loaded, and no reboot-once flag exists yet" - because doing so on a
# real Linux CI runner would invoke the genuine systemctl binary. Every
# other branch is covered, including "module not loaded but the flag is
# already set", which proves no reboot is attempted without ever reaching
# the unstubbable line. See the PR description for the same note.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SANDBOX="$(mktemp -d)"
    STUBDIR="$SANDBOX/stubs"
    CALLS_LOG="$SANDBOX/calls.log"
    mkdir -p "$STUBDIR"
    : >"$CALLS_LOG"

    for cmd in dpkg dpkg-query dpkg-deb depmod systemctl modprobe lsmod sync sudo apt-get; do
        write_stub "$cmd" "exit 0"
    done

    export PATH="$STUBDIR:$PATH"
    export YT6801_SKIP_ROOT_CHECK=1

    # Fake hardware (see yt6801-common.sh): by default a YT6801 controller is
    # present, bound to no driver, and the "running kernel" has no in-tree
    # driver for it - the situation the TUXEDO package exists for. Tests that
    # need another situation reshape it with the fake_* helpers below.
    export YT6801_SYSFS_PCI="$SANDBOX/sys/bus/pci/devices"
    export YT6801_MODULES_DIR="$SANDBOX/lib/modules/test-kernel"
    mkdir -p "$YT6801_SYSFS_PCI" "$YT6801_MODULES_DIR" "$SANDBOX/drivers"
    : >"$YT6801_MODULES_DIR/modules.alias"
    fake_pci_device "0000:00:02.0" 0x8086 0x46d4 # unrelated device (iGPU)
    fake_pci_device "0000:01:00.0" 0x1f0a 0x6801 # the YT6801

    # Fake install locations for uninstall.sh (test-only overrides).
    export YT6801_INSTALL_DIR="$SANDBOX/opt/yt6801-auto-installer"
    export YT6801_SYSTEMD_DIR="$SANDBOX/etc/systemd/system"
    export YT6801_ETC_MODULES="$SANDBOX/etc/modules"
    mkdir -p "$YT6801_INSTALL_DIR" "$YT6801_SYSTEMD_DIR"
    touch "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service"
    printf '# /etc/modules\nloop\nyt6801\n' >"$YT6801_ETC_MODULES"
}

# fake_package_installed - makes dpkg-query report tuxedo-yt6801 as installed.
fake_package_installed() {
    write_stub dpkg-query 'echo -n "install ok installed"'
}

# fake_pci_device <address> <vendor> <device> - adds a device with the
# subsystem IDs of the real mini PC's YT6801 (2066:9806) in its modalias.
fake_pci_device() {
    local dev="$YT6801_SYSFS_PCI/$1" v d
    mkdir -p "$dev"
    echo "$2" >"$dev/vendor"
    echo "$3" >"$dev/device"
    v="$(echo "${2#0x}" | tr '[:lower:]' '[:upper:]')"
    d="$(echo "${3#0x}" | tr '[:lower:]' '[:upper:]')"
    echo "pci:v0000${v}d0000${d}sv00002066sd00009806bc02sc00i00" >"$dev/modalias"
}

# fake_bind <address> <driver> - binds a fake device to a fake driver.
fake_bind() {
    mkdir -p "$SANDBOX/drivers/$2"
    ln -sfn "$SANDBOX/drivers/$2" "$YT6801_SYSFS_PCI/$1/driver"
}

# fake_alias <module> [pattern] [file] - makes the fake kernel claim the
# YT6801 with <module> (any subsystem by default) in modules.alias, or in
# another index such as modules.builtin.alias.
fake_alias() {
    local pattern="${2:-pci:v00001F0Ad00006801sv*sd*bc*sc*i*}"
    echo "alias $pattern $1" >>"$YT6801_MODULES_DIR/${3:-modules.alias}"
}

# fake_no_yt6801 - removes the YT6801 from the fake machine.
fake_no_yt6801() {
    rm -rf "${YT6801_SYSFS_PCI:?}/0000:01:00.0"
}

teardown() {
    rm -rf "$SANDBOX"
}

# write_stub <name> <shell-body>
# (Re)creates an executable at $STUBDIR/<name> that logs its invocation to
# $CALLS_LOG and then runs <shell-body>. Tests call this to override the
# default no-op stub, e.g. to make lsmod report the module as loaded.
write_stub() {
    local name="$1"
    local body="$2"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'echo "%s $*" >> %q\n' "$name" "$CALLS_LOG"
        printf '%s\n' "$body"
    } >"$STUBDIR/$name"
    chmod +x "$STUBDIR/$name"
}

# sandbox_copy <script-name>
# Copies a script from the repo root into its own isolated directory (with
# an empty deb/ subdir), so the script's SCRIPT_DIR-relative flag file
# never touches the real repo and an install run sees no .deb packages unless
# a test puts one there. Prints the path to the copy.
sandbox_copy() {
    local script="$1"
    local dir="$SANDBOX/${script%.sh}"
    mkdir -p "$dir/deb"
    cp "$REPO_ROOT/$script" "$dir/$script"
    cp "$REPO_ROOT/yt6801-common.sh" "$dir/yt6801-common.sh"
    chmod +x "$dir/$script"
    echo "$dir/$script"
}

# calls_of <name> - number of times stub <name> was invoked.
calls_of() {
    grep -c "^$1 " "$CALLS_LOG" || true
}

# assert_no_privileged_calls - fails if any stubbed privileged command
# (dpkg, dpkg-query, dpkg-deb, depmod, modprobe, lsmod, systemctl, sync,
# sudo) was invoked. Used to prove the root check exits before any of them
# could run.
assert_no_privileged_calls() {
    local cmd
    for cmd in dpkg dpkg-query dpkg-deb depmod modprobe lsmod systemctl sync sudo; do
        [ "$(calls_of "$cmd")" -eq 0 ]
    done
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
