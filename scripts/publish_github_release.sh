#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.1.2}"
TAG="v$VERSION"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/CodexUsageMonitor}"
DIST="$ROOT/dist"
RELEASE_DIR="$DIST/github-release"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/CodexUsageMonitor-gkgkkkkzgbvwbnhhixwmeffcecix/SourcePackages/artifacts/sparkle/Sparkle/bin"

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 1; }
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Build once in Xcode to resolve Sparkle tools." >&2; exit 1; }

"$ROOT/scripts/package_release.sh"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp "$DIST/CodexUsageMonitor-macOS.zip" "$RELEASE_DIR/CodexUsageMonitor-$VERSION-macOS.zip"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  "$RELEASE_DIR"

gh release create "$TAG" \
  --repo "$REPOSITORY" \
  --title "Codex Usage Monitor $VERSION" \
  --generate-notes \
  "$RELEASE_DIR/CodexUsageMonitor-$VERSION-macOS.zip" \
  "$RELEASE_DIR/appcast.xml" \
  "$DIST/CodexUsageMonitor-macOS.dmg" \
  "$DIST/SHA256SUMS.txt"

echo "Published $REPOSITORY $TAG"
