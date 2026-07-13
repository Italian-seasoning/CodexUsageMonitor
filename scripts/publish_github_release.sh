#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_VERSION="${1:-}"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/CodexUsageMonitor}"
DIST="$ROOT/dist"
RELEASE_DIR="$DIST/github-release"
SPARKLE_BIN="$ROOT/build/DistributionDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 1; }

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
[[ -n "$IDENTITY" ]] || { echo "A Developer ID Application certificate is required to publish." >&2; exit 1; }
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo "NOTARY_PROFILE is required to publish." >&2; exit 1; }
export SIGN_IDENTITY="$IDENTITY"

"$ROOT/scripts/package_release.sh"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Sparkle generate_appcast was not produced by the release build." >&2; exit 1; }

APP="$DIST/stage/CodexUsageMonitor.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
if [[ -n "$REQUESTED_VERSION" && "$REQUESTED_VERSION" != "$VERSION" ]]; then
  echo "Requested version $REQUESTED_VERSION does not match built version $VERSION." >&2
  exit 1
fi

TAG="v$VERSION"
ARCHIVE="CodexUsageMonitor-$VERSION-macOS.zip"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp "$DIST/CodexUsageMonitor-macOS.zip" "$RELEASE_DIR/$ARCHIVE"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  "$RELEASE_DIR"

xmllint --noout "$RELEASE_DIR/appcast.xml"
rg -q 'sparkle:edSignature=' "$RELEASE_DIR/appcast.xml"
shasum -a 256 "$RELEASE_DIR/$ARCHIVE" "$DIST/CodexUsageMonitor-macOS.dmg" > "$RELEASE_DIR/SHA256SUMS.txt"

gh release create "$TAG" \
  --repo "$REPOSITORY" \
  --title "Codex Usage Monitor $VERSION (build $BUILD)" \
  --generate-notes \
  "$RELEASE_DIR/$ARCHIVE" \
  "$RELEASE_DIR/appcast.xml" \
  "$DIST/CodexUsageMonitor-macOS.dmg" \
  "$RELEASE_DIR/SHA256SUMS.txt"

echo "Published $REPOSITORY $TAG"
