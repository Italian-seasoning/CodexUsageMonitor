#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DistributionDerivedData"
BUILD_APP="$DERIVED_DATA/Build/Products/Release/CodexUsageMonitor.app"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP="$STAGE/CodexUsageMonitor.app"
REFRESH_BIN="$APP/Contents/MacOS/CodexUsageRefreshSnapshot"
WIDGET="$APP/Contents/PlugIns/CodexUsageWidget.appex"
ARCHIVE="$DIST/CodexUsageMonitor-macOS.zip"
DMG_ROOT="$DIST/dmg-root"
DMG="$DIST/CodexUsageMonitor-macOS.dmg"

rm -rf "$DERIVED_DATA" "$DIST"
mkdir -p "$STAGE" "$DMG_ROOT"

xcodebuild \
  -project "$ROOT/CodexUsageMonitor.xcodeproj" \
  -scheme CodexUsageMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  -quiet \
  build

ditto "$BUILD_APP" "$APP"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc \
    -O \
    -sdk "$SDK" \
    -target "$ARCH-apple-macos14.0" \
    "$ROOT/Shared/CodexUsageSnapshot.swift" \
    "$ROOT/CodexUsageMonitor/HeadroomSavingsCollector.swift" \
    "$ROOT/scripts/RefreshSnapshot.swift" \
    -o "$DIST/CodexUsageRefreshSnapshot-$ARCH"
done
lipo -create \
  "$DIST/CodexUsageRefreshSnapshot-arm64" \
  "$DIST/CodexUsageRefreshSnapshot-x86_64" \
  -output "$REFRESH_BIN"
rm "$DIST/CodexUsageRefreshSnapshot-arm64" "$DIST/CodexUsageRefreshSnapshot-x86_64"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "No Developer ID Application certificate found; creating an ad-hoc signed build."
fi

if [[ "$IDENTITY" != "-" && -z "${NOTARY_PROFILE:-}" ]]; then
  echo "A Developer ID identity was found, but NOTARY_PROFILE is missing." >&2
  echo "Refusing to create a misleading unnotarized public release." >&2
  exit 1
fi

codesign --force --options runtime --sign "$IDENTITY" "$REFRESH_BIN"
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --options runtime --entitlements "$ROOT/CodexUsageWidget/CodexUsageWidget.entitlements" --sign "$IDENTITY" "$WIDGET"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
ditto "$APP" "$DMG_ROOT/CodexUsageMonitor.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT/DISTRIBUTION.md" "$DMG_ROOT/Read Me.md"
hdiutil create -quiet -volname "Codex Usage Monitor" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG"

if [[ "$IDENTITY" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "Notarization skipped. Set NOTARY_PROFILE after installing a Developer ID Application certificate."
fi

shasum -a 256 "$ARCHIVE" "$DMG" > "$DIST/SHA256SUMS.txt"

echo "Created $ARCHIVE"
echo "Created $DMG"
echo "Signing identity: $IDENTITY"
