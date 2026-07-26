#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DistributionDerivedData"
BUILD_APP="$DERIVED_DATA/Build/Products/Release/CodexUsageMonitor.app"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP="$STAGE/CodexUsageMonitor.app"
WIDGET="$APP/Contents/PlugIns/CodexUsageWidget.appex"
ARCHIVE="$DIST/CodexUsageMonitor-macOS.zip"
DMG_ROOT="$DIST/dmg-root"
DMG="$DIST/CodexUsageMonitor-macOS.dmg"
DMG_RW="$DIST/CodexUsageMonitor-macOS-rw.dmg"
DMG_VOLUME="Codex Usage Monitor"
DMG_BACKGROUND="$ROOT/scripts/assets/dmg-background.png"

rm -rf "$DERIVED_DATA" "$DIST"
mkdir -p "$STAGE" "$DMG_ROOT/.background"

xcodebuild \
  -project "$ROOT/CodexUsageMonitor.xcodeproj" \
  -scheme CodexUsageMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  -quiet \
  build

ditto "$BUILD_APP" "$APP"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "No Developer ID Application identity found; creating an ad-hoc signed build."
fi

if [[ "$IDENTITY" == Developer\ ID\ Application:* && -z "${NOTARY_PROFILE:-}" ]]; then
  echo "A Developer ID identity was found, but NOTARY_PROFILE is missing." >&2
  echo "Refusing to create a misleading unnotarized public release." >&2
  exit 1
fi

SIGN_OPTIONS=""
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_OPTIONS="--options runtime"
fi
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --deep $SIGN_OPTIONS --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force $SIGN_OPTIONS --entitlements "$ROOT/CodexUsageWidget/CodexUsageWidget.entitlements" --sign "$IDENTITY" "$WIDGET"
codesign --force $SIGN_OPTIONS --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
ditto "$APP" "$DMG_ROOT/CodexUsageMonitor.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$DMG_BACKGROUND" "$DMG_ROOT/.background/dmg-background.png"
chflags hidden "$DMG_ROOT/.background"

hdiutil detach "/Volumes/$DMG_VOLUME" -force >/dev/null 2>&1 || true
hdiutil create -quiet -volname "$DMG_VOLUME" -srcfolder "$DMG_ROOT" -ov -format UDRW "$DMG_RW"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW" | awk '/Apple_HFS|Apple_APFS/ { print $1; exit }')"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DMG_VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {120, 120, 840, 600}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set text size of theViewOptions to 13
    set label position of theViewOptions to bottom
    set background picture of theViewOptions to file ".background:dmg-background.png"
    set position of item "CodexUsageMonitor.app" of container window to {185, 220}
    set position of item "Applications" of container window to {535, 220}
    update without registering applications
    delay 2
    close container window
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet
hdiutil convert "$DMG_RW" -quiet -format UDZO -o "$DMG"
rm -f "$DMG_RW"

if [[ "$IDENTITY" == Developer\ ID\ Application:* && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "Notarization skipped. Set NOTARY_PROFILE after installing a Developer ID Application certificate."
fi

shasum -a 256 "$ARCHIVE" "$DMG" > "$DIST/SHA256SUMS.txt"

echo "Created $ARCHIVE"
echo "Created $DMG"
echo "Signing identity: $IDENTITY"
