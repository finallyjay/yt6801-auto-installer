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

    for cmd in dpkg dpkg-query dpkg-deb depmod systemctl modprobe lsmod sync sudo; do
        write_stub "$cmd" "exit 0"
    done

    export PATH="$STUBDIR:$PATH"
    export YT6801_SKIP_ROOT_CHECK=1
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
# an empty deb/ subdir), so the script's SCRIPT_DIR-relative log/flag files
# never touch the real repo and an install run sees no .deb packages unless
# a test puts one there. Prints the path to the copy.
sandbox_copy() {
    local script="$1"
    local dir="$SANDBOX/${script%.sh}"
    mkdir -p "$dir/deb"
    cp "$REPO_ROOT/$script" "$dir/$script"
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

    local script script_dir
    script="$(sandbox_copy install_yt6801_if_needed.sh)"
    script_dir="$(dirname "$script")"

    run "$script"

    [ "$status" -ne 0 ]
    [ -f "$script_dir/install_yt6801.log" ]
    grep -q "ERROR: No .deb package found" "$script_dir/install_yt6801.log"

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
    grep -q "reboot already done once" "$script_dir/install_yt6801.log"
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
