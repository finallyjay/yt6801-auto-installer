#!/usr/bin/env bats
#
# Tests for tools/build-release.sh. The release is built once per file, from
# a temporary copy of the repo with a fake version, so the real VERSION and
# CHANGELOG are never touched. copy_repo and fake_release_version come from
# test_helper.bash.

load test_helper

setup_file() {
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export COPY="$BATS_FILE_TMPDIR/repo" OUT="$BATS_FILE_TMPDIR/dist"
    copy_repo "$COPY"
    fake_release_version "$COPY" 9.8.7
    "$COPY/tools/build-release.sh" v9.8.7 "$OUT" >/dev/null
}

sha256_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$@"
    else
        shasum -a 256 -c "$@"
    fi
}

@test "build-release.sh builds every asset with valid checksums" {
    [ -f "$OUT/yt6801-auto-installer-9.8.7.tar.gz" ]
    [ -f "$OUT/install.sh" ]
    [ -f "$OUT/uninstall.sh" ]
    cmp "$OUT/yt6801-auto-installer-9.8.7.tar.gz" "$OUT/yt6801-auto-installer.tar.gz"
    (cd "$OUT" && sha256_check SHA256SUMS)
}

@test "build-release.sh ships a versioned folder with stamped scripts and notes" {
    run tar -tzf "$OUT/yt6801-auto-installer-9.8.7.tar.gz"
    [ "$status" -eq 0 ]
    for f in install.sh setup.sh uninstall.sh install_yt6801_if_needed.sh check_yt6801_and_reboot.sh \
        yt6801-common.sh yt6801-reinstall.service README.md LICENSE VERSION CHANGELOG.md; do
        [[ "$output" == *"yt6801-auto-installer-9.8.7/$f"* ]]
    done
    [[ "$output" == *"yt6801-auto-installer-9.8.7/deb/tuxedo-yt6801_"*".deb"* ]]
    [[ "$output" != *"test/"* ]]
    [[ "$output" != *"tools/"* ]]

    grep -q '^YT6801_RELEASE_VERSION="9.8.7"' "$OUT/install.sh"
    grep -q '^YT6801_RELEASE_VERSION="9.8.7"' "$OUT/uninstall.sh"
    tar -xzf "$OUT/yt6801-auto-installer-9.8.7.tar.gz" -C "$BATS_TEST_TMPDIR"
    grep -q '^YT6801_RELEASE_VERSION="9.8.7"' "$BATS_TEST_TMPDIR/yt6801-auto-installer-9.8.7/install.sh"
    [ -x "$BATS_TEST_TMPDIR/yt6801-auto-installer-9.8.7/install.sh" ]

    grep -q "Something new" "$OUT/release-notes.md"
    [ "$(grep -c "Old entry" "$OUT/release-notes.md" || true)" -eq 0 ]
}

@test "build-release.sh refuses a bad version, tag or CHANGELOG" {
    local copy="$BATS_TEST_TMPDIR/repo" out="$BATS_TEST_TMPDIR/dist"
    copy_repo "$copy"
    fake_release_version "$copy" 9.8.7

    run "$copy/tools/build-release.sh" latest "$out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a X.Y.Z version"* ]]

    run "$copy/tools/build-release.sh" 9.8.8 "$out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"VERSION file says '9.8.7', not '9.8.8'"* ]]

    echo "9.9.9" >"$copy/VERSION"
    run "$copy/tools/build-release.sh" 9.9.9 "$out"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no '## [9.9.9]' section"* ]]

    [ ! -e "$out/SHA256SUMS" ]
}

@test "build-release.sh fails instead of shipping a script it could not stamp" {
    local copy="$BATS_TEST_TMPDIR/repo"
    copy_repo "$copy"
    fake_release_version "$copy" 9.8.7
    printf "#!/bin/bash\nYT6801_RELEASE_VERSION=''\n" >"$copy/uninstall.sh"

    run "$copy/tools/build-release.sh" 9.8.7 "$BATS_TEST_TMPDIR/dist"

    [ "$status" -ne 0 ]
    [[ "$output" == *"could not stamp the version into uninstall.sh"* ]]
}
