#!/usr/bin/env bats
#
# Tests for tools/build-release.sh. They build into a temporary directory
# from a temporary copy of the repo, so the real VERSION/CHANGELOG are only
# read, never modified.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SANDBOX="$(mktemp -d)"
    COPY="$SANDBOX/repo"
    OUT="$SANDBOX/dist"
    mkdir -p "$COPY"
    # Copy the tracked files only (no .git, no local leftovers).
    (cd "$REPO_ROOT" && git ls-files -z | xargs -0 -I{} cp -R --parents {} "$COPY/" 2>/dev/null) ||
        (cd "$REPO_ROOT" && git ls-files | while IFS= read -r f; do
            mkdir -p "$COPY/$(dirname "$f")"
            cp "$f" "$COPY/$f"
        done)
    echo "9.8.7" >"$COPY/VERSION"
    {
        echo "# Changelog"
        echo
        echo "## [9.8.7] - 2030-01-01"
        echo
        echo "### Added"
        echo "- Something new"
        echo
        echo "## [1.0.0] - 2026-03-30"
        echo
        echo "- Old entry"
    } >"$COPY/CHANGELOG.md"
    # A shipped script with the version placeholder, to check stamping.
    printf '#!/bin/bash\nYT6801_RELEASE_VERSION=""\n' >"$COPY/uninstall.sh"
}

teardown() {
    rm -rf "$SANDBOX"
}

sha256_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$@"
    else
        shasum -a 256 -c "$@"
    fi
}

@test "build-release.sh builds every asset with valid checksums" {
    run "$COPY/tools/build-release.sh" v9.8.7 "$OUT"

    [ "$status" -eq 0 ]
    [ -f "$OUT/yt6801-auto-installer-9.8.7.tar.gz" ]
    [ -f "$OUT/yt6801-auto-installer.tar.gz" ]
    [ -f "$OUT/uninstall.sh" ]
    [ -f "$OUT/SHA256SUMS" ]
    cmp "$OUT/yt6801-auto-installer-9.8.7.tar.gz" "$OUT/yt6801-auto-installer.tar.gz"
    (cd "$OUT" && sha256_check SHA256SUMS)
}

@test "build-release.sh ships the scripts, unit and driver package in a versioned folder" {
    run "$COPY/tools/build-release.sh" 9.8.7 "$OUT"
    [ "$status" -eq 0 ]

    run tar -tzf "$OUT/yt6801-auto-installer-9.8.7.tar.gz"
    [ "$status" -eq 0 ]
    for f in setup.sh uninstall.sh install_yt6801_if_needed.sh check_yt6801_and_reboot.sh \
        yt6801-common.sh yt6801-reinstall.service README.md LICENSE VERSION CHANGELOG.md; do
        [[ "$output" == *"yt6801-auto-installer-9.8.7/$f"* ]]
    done
    [[ "$output" == *"yt6801-auto-installer-9.8.7/deb/tuxedo-yt6801_"*".deb"* ]]
    # Nothing outside the versioned top-level folder, no tests or tooling.
    [[ "$output" != *"test/"* ]]
    [[ "$output" != *"tools/"* ]]
}

@test "build-release.sh stamps the release version into shipped scripts" {
    run "$COPY/tools/build-release.sh" 9.8.7 "$OUT"
    [ "$status" -eq 0 ]

    grep -qx 'YT6801_RELEASE_VERSION="9.8.7"' "$OUT/uninstall.sh"
    tar -xzf "$OUT/yt6801-auto-installer-9.8.7.tar.gz" -C "$SANDBOX"
    grep -qx 'YT6801_RELEASE_VERSION="9.8.7"' "$SANDBOX/yt6801-auto-installer-9.8.7/uninstall.sh"
    [ -x "$SANDBOX/yt6801-auto-installer-9.8.7/uninstall.sh" ]
}

@test "build-release.sh writes the CHANGELOG section as release notes" {
    run "$COPY/tools/build-release.sh" 9.8.7 "$OUT"
    [ "$status" -eq 0 ]

    grep -q "Something new" "$OUT/release-notes.md"
    [ "$(grep -c "Old entry" "$OUT/release-notes.md" || true)" -eq 0 ]
}

@test "build-release.sh refuses a tag that does not match VERSION" {
    run "$COPY/tools/build-release.sh" 9.8.8 "$OUT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"VERSION file says '9.8.7', not '9.8.8'"* ]]
    [ ! -e "$OUT/SHA256SUMS" ]
}

@test "build-release.sh refuses a version without a CHANGELOG section" {
    echo "9.9.9" >"$COPY/VERSION"

    run "$COPY/tools/build-release.sh" 9.9.9 "$OUT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"no '## [9.9.9]' section"* ]]
}

@test "build-release.sh rejects a malformed version" {
    run "$COPY/tools/build-release.sh" latest "$OUT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a X.Y.Z version"* ]]
}
