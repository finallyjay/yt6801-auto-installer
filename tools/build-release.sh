#!/bin/bash
set -euo pipefail

# Builds the release assets for a tag, into an output directory:
#
#   yt6801-auto-installer-<version>.tar.gz  everything needed to install offline
#   yt6801-auto-installer.tar.gz            same bytes, fixed name, so
#                                           releases/latest/download/... works
#   install.sh, uninstall.sh                standalone copies for `curl | bash`
#   SHA256SUMS                              checksums of all the above
#   release-notes.md                        the CHANGELOG section for <version>
#
# Every shipped script that declares `YT6801_RELEASE_VERSION=""` gets the
# version stamped in, so a script fetched from a release only ever downloads
# the files of that same release.
#
# Usage: tools/build-release.sh <version> [output-dir]   (version without "v")

usage() {
    echo "Usage: $0 <version> [output-dir]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
VERSION="${1#v}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${2:-$REPO_ROOT/dist}"
NAME="yt6801-auto-installer"
STAGE_NAME="$NAME-$VERSION"

# Files shipped in the tarball, relative to the repo root.
SHIPPED_FILES=(
    install.sh
    setup.sh
    uninstall.sh
    install_yt6801_if_needed.sh
    check_yt6801_and_reboot.sh
    yt6801-common.sh
    yt6801-reinstall.service
    deb
    README.md
    CHANGELOG.md
    LICENSE
    VERSION
)
# Scripts also published as standalone release assets.
STANDALONE_SCRIPTS=(install.sh uninstall.sh)

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "'$VERSION' is not a X.Y.Z version"

FILE_VERSION="$(tr -d '[:space:]' <"$REPO_ROOT/VERSION")"
[ "$FILE_VERSION" = "$VERSION" ] || fail "VERSION file says '$FILE_VERSION', not '$VERSION'"

NOTES="$(awk -v v="$VERSION" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$REPO_ROOT/CHANGELOG.md")"
[ -n "$(echo "$NOTES" | tr -d '[:space:]')" ] || fail "CHANGELOG.md has no '## [$VERSION]' section"

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

# stamp <file> - writes the release version into a shipped script, and fails
# if a script declares YT6801_RELEASE_VERSION but did not get it (e.g. the
# placeholder was reformatted), rather than shipping a script that would
# silently fetch "latest" instead of its own release.
stamp() {
    sed "s/^YT6801_RELEASE_VERSION=\"\"/YT6801_RELEASE_VERSION=\"$VERSION\"/" "$1" >"$1.tmp"
    mv "$1.tmp" "$1"
    if grep -q '^YT6801_RELEASE_VERSION=' "$1" && ! grep -q "^YT6801_RELEASE_VERSION=\"$VERSION\"" "$1"; then
        fail "could not stamp the version into $(basename "$1")"
    fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/$STAGE_NAME"
mkdir -p "$STAGE"

for f in "${SHIPPED_FILES[@]}"; do
    [ -e "$REPO_ROOT/$f" ] || fail "missing $f"
    cp -R "$REPO_ROOT/$f" "$STAGE/"
done
for f in "$STAGE"/*.sh; do
    stamp "$f"
    chmod 0755 "$f"
done

mkdir -p "$OUT_DIR"
TARBALL="$STAGE_NAME.tar.gz"

# Reproducible archive with GNU tar (CI); plain tar elsewhere (e.g. macOS).
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
    if ! EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null)}" || [ -z "$EPOCH" ]; then
        echo "WARNING: no git history or SOURCE_DATE_EPOCH; the archive is not reproducible" >&2
        EPOCH="$(date +%s)"
    fi
    tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
        -C "$WORK" -cf - "$STAGE_NAME" | gzip -9n >"$OUT_DIR/$TARBALL"
else
    tar -C "$WORK" -cf - "$STAGE_NAME" | gzip -9n >"$OUT_DIR/$TARBALL"
fi
cp "$OUT_DIR/$TARBALL" "$OUT_DIR/$NAME.tar.gz"

for f in "${STANDALONE_SCRIPTS[@]}"; do
    cp "$STAGE/$f" "$OUT_DIR/$f"
done

echo "$NOTES" >"$OUT_DIR/release-notes.md"

(
    cd "$OUT_DIR"
    sha256 "$TARBALL" "$NAME.tar.gz" "${STANDALONE_SCRIPTS[@]}" >SHA256SUMS
)

echo "Built $NAME $VERSION in $OUT_DIR:"
(cd "$OUT_DIR" && ls -1)
