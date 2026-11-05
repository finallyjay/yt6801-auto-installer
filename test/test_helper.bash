# Shared helpers for the bats suites (loaded with `load test_helper`).
#
# Safety contract: tests must NEVER perform a real dpkg/apt install, load a
# kernel module, touch systemd or reboot the machine. Every command a script
# under test could use for that is replaced by a recording stub placed ahead
# of the real binaries on PATH; each stub appends its name and arguments to
# $CALLS_LOG, so tests assert exactly what was (and was not) invoked.
#
# The hardware (sysfs, the kernel's modules.alias) and the install locations
# are faked through test-only YT6801_* overrides, like
# YT6801_SKIP_ROOT_CHECK, so nothing outside the sandbox is ever touched.

common_setup() {
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

# fake_package_installed [state] - makes dpkg-query report tuxedo-yt6801 in
# the given dpkg state ("installed" by default).
fake_package_installed() {
    write_stub dpkg-query "echo -n ${1:-installed}"
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

common_teardown() {
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

# copy_repo <dest> - copies the repo files, tracked or new but not ignored
# (no .git), so tests see work in progress too.
copy_repo() {
    local dest="$1" f
    mkdir -p "$dest"
    (cd "$REPO_ROOT" && git ls-files --cached --others --exclude-standard) | while IFS= read -r f; do
        mkdir -p "$dest/$(dirname "$f")"
        cp "$REPO_ROOT/$f" "$dest/$f"
    done
}

# fake_release_version <repo-copy> <version> - gives a repo copy a VERSION
# and a matching CHANGELOG section, so tools/build-release.sh accepts it.
fake_release_version() {
    echo "$2" >"$1/VERSION"
    {
        echo "# Changelog"
        echo
        echo "## [$2](https://github.com/finallyjay/yt6801-auto-installer/compare/v1.0.0...v$2) (2030-01-01)"
        echo
        echo "### Added"
        echo "- Something new"
        echo
        echo "## [1.0.0] - 2026-03-30"
        echo
        echo "- Old entry"
    } >"$1/CHANGELOG.md"
}
