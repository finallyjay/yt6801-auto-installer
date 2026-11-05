#!/usr/bin/env bats
#
# Tests for install.sh: the local install from a release folder, and the
# `curl | bash` bootstrap, which is exercised end to end against a real
# release built by tools/build-release.sh and served from a file:// URL.
# See test_helper.bash for the stubs, fakes and safety contract.

load test_helper

setup() {
    common_setup
    INSTALLER="$SANDBOX/installer"
    copy_repo "$INSTALLER"

    # dpkg-deb answers like for the bundled TUXEDO package.
    write_stub dpkg-deb 'case "$3" in Package) echo tuxedo-yt6801 ;; Version) echo 1.0.28-1 ;; esac'
    # Loading the module binds the fake device to it, like the real kernel.
    write_stub modprobe "ln -sfn \"$SANDBOX/drivers/yt6801\" \"$YT6801_SYSFS_PCI/0000:01:00.0/driver\"; mkdir -p \"$SANDBOX/drivers/yt6801\""
    # Build dependencies present by default.
    write_stub dkms "exit 0"
    mkdir -p "$YT6801_MODULES_DIR/build"
    rm -rf "$YT6801_INSTALL_DIR" "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service"
}

teardown() {
    common_teardown
}

@test "install.sh and uninstall.sh share an identical bootstrap block" {
    diff <(sed -n '/^# >>> bootstrap/,/^# <<< bootstrap/p' "$REPO_ROOT/install.sh") \
        <(sed -n '/^# >>> bootstrap/,/^# <<< bootstrap/p' "$REPO_ROOT/uninstall.sh")
    [ -n "$(sed -n '/^# >>> bootstrap/,/^# <<< bootstrap/p' "$REPO_ROOT/install.sh")" ]
}

@test "install.sh --help works without root" {
    unset YT6801_SKIP_ROOT_CHECK

    run bash "$INSTALLER/install.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    assert_no_privileged_calls
}

@test "install.sh installs the driver and the boot service" {
    run bash "$INSTALLER/install.sh" --yes

    [ "$status" -eq 0 ]
    [[ "$output" == *"All done!"* ]]
    # The tool, including the offline uninstaller, is copied and enabled.
    for f in install_yt6801_if_needed.sh check_yt6801_and_reboot.sh yt6801-common.sh uninstall.sh; do
        [ -x "$YT6801_INSTALL_DIR/$f" ]
    done
    [ -f "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service" ]
    grep -q "^systemctl enable yt6801-reinstall.service" "$CALLS_LOG"
    # The driver package is installed and loaded at boot.
    grep -q "^dpkg -i .*tuxedo-yt6801_" "$CALLS_LOG"
    grep -qx yt6801 "$YT6801_ETC_MODULES"
    # Nothing to fetch: dkms and the headers were already there.
    [ "$(calls_of apt-get)" -eq 0 ]
}

@test "install.sh installs missing dkms and kernel headers first" {
    rm -f "$STUBDIR/dkms"
    rmdir "$YT6801_MODULES_DIR/build"
    if command -v dkms >/dev/null 2>&1; then
        skip "dkms is installed on this machine"
    fi

    run bash "$INSTALLER/install.sh" --yes

    [ "$status" -eq 0 ]
    grep -q "^apt-get .*install -y dkms linux-headers-" "$CALLS_LOG"
}

@test "install.sh does nothing on a kernel with its own YT6801 driver" {
    fake_bind "0000:01:00.0" dwmac-motorcomm

    run bash "$INSTALLER/install.sh" --yes

    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to install"* ]]
    [ ! -d "$YT6801_INSTALL_DIR" ]
    [ "$(calls_of dpkg)" -eq 0 ]
    [ "$(calls_of apt-get)" -eq 0 ]
    [ "$(calls_of systemctl)" -eq 0 ]
}

@test "install.sh does nothing without a YT6801 controller" {
    fake_no_yt6801

    run bash "$INSTALLER/install.sh" --yes

    [ "$status" -eq 0 ]
    [[ "$output" == *"No Motorcomm YT6801 ethernet controller found"* ]]
    [ ! -d "$YT6801_INSTALL_DIR" ]
    [ "$(calls_of dpkg)" -eq 0 ]
}

# Builds a release of the installer and prints the directory serving it.
build_fake_release() {
    local repo="$SANDBOX/release-repo"
    copy_repo "$repo"
    fake_release_version "$repo" 9.8.7
    "$repo/tools/build-release.sh" 9.8.7 "$SANDBOX/release" >/dev/null
    echo "$SANDBOX/release"
}

@test "piped install.sh downloads its own release, verifies it and runs it" {
    local release
    release="$(build_fake_release)"
    export YT6801_RELEASE_BASE_URL="file://$release"

    # Exactly how users run it: the script arrives on stdin.
    run bash -s -- --yes <"$release/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Downloading the YT6801 auto-installer v9.8.7"* ]]
    [[ "$output" == *"Checksum verified"* ]]
    [[ "$output" == *"installer v9.8.7"* ]]
    [[ "$output" == *"All done!"* ]]
    [ -f "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service" ]
}

@test "piped install.sh refuses a release whose checksum does not match" {
    local release
    release="$(build_fake_release)"
    echo "tampered" >>"$release/yt6801-auto-installer-9.8.7.tar.gz"
    export YT6801_RELEASE_BASE_URL="file://$release"

    run bash -s -- --yes <"$release/install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Checksum verification FAILED"* ]]
    [[ "$output" != *"YT6801 ethernet driver installer"* ]]
    [ "$(calls_of dpkg)" -eq 0 ]
    [ ! -d "$YT6801_INSTALL_DIR" ]
}

@test "piped install.sh asks for sudo before downloading anything" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "test runner itself is root"
    fi
    local release
    release="$(build_fake_release)"
    export YT6801_RELEASE_BASE_URL="file://$release"
    unset YT6801_SKIP_ROOT_CHECK

    run bash -s <"$release/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Please run it with sudo"* ]]
    [[ "$output" != *"Downloading"* ]]
}

@test "piped uninstall.sh downloads its release and runs the uninstaller" {
    local release
    release="$(build_fake_release)"
    export YT6801_RELEASE_BASE_URL="file://$release"
    fake_alias dwmac_motorcomm # safe to remove the driver

    run bash -s -- --yes <"$release/uninstall.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Checksum verified"* ]]
    [[ "$output" == *"Uninstallation complete"* ]]
    [ ! -e "$YT6801_SYSTEMD_DIR/yt6801-reinstall.service" ]
}
