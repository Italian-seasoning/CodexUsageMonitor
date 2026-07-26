#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_VERSION="${1:-}"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/CodexUsageMonitor}"
DIST="$ROOT/dist"
RELEASE_DIR="$DIST/github-release"
SPARKLE_BIN="$ROOT/build/DistributionDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 1; }

"$ROOT/scripts/package_release.sh"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Sparkle generate_appcast was not produced by the release build." >&2; exit 1; }

APP="$DIST/stage/CodexUsageMonitor.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
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
cp "$DIST/CodexUsageMonitor-macOS.dmg" "$RELEASE_DIR/CodexUsageMonitor-macOS.dmg"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE" CodexUsageMonitor-macOS.dmg > SHA256SUMS.txt)
TITLE="Codex Usage Monitor $VERSION preview"
SIGNING_AUTHORITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(.*\)$/\1/p' | head -1)"
if [[ "$SIGNING_AUTHORITY" == Apple\ Development:* ]]; then
  NOTES="Apple Development-signed preview. The release is Sparkle-signed for automatic updates, but is not Apple Developer ID signed or notarized for public distribution. macOS may require Control-click, then Open."
else
  NOTES="Ad-hoc signed preview. The release is Sparkle-signed for automatic updates, but is not Apple Developer ID signed or notarized. macOS may require Control-click, then Open."
fi
ASSETS=(
  "$RELEASE_DIR/$ARCHIVE"
  "$RELEASE_DIR/appcast.xml"
  "$RELEASE_DIR/CodexUsageMonitor-macOS.dmg"
  "$RELEASE_DIR/SHA256SUMS.txt"
)

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$TAG" --repo "$REPOSITORY" --clobber "${ASSETS[@]}"
  gh release edit "$TAG" --repo "$REPOSITORY" --title "$TITLE" --notes "$NOTES"
else
  gh release create "$TAG" --repo "$REPOSITORY" --target "$(git -C "$ROOT" rev-parse HEAD)" --title "$TITLE" --notes "$NOTES" "${ASSETS[@]}"
fi

echo "Published $REPOSITORY $TAG"
