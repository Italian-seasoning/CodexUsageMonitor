#!/usr/bin/env bash
set -euo pipefail

if [[ "${SIGN_IDENTITY:--}" != "-" || -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Runway previews support anonymous ad-hoc signing only; identified signing and notarization are unsupported." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DistributionDerivedData"
BUILD_APP="$DERIVED_DATA/Build/Products/Release/Runway.app"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP="$STAGE/Runway.app"
WIDGET="$APP/Contents/PlugIns/RunwayWidget.appex"
ARCHIVE="$DIST/Runway-macOS.zip"
DMG_ROOT="$DIST/dmg-root"
DMG="$DIST/Runway-macOS.dmg"
DMG_RW="$DIST/Runway-macOS-rw.dmg"
DMG_VOLUME="Runway"
DMG_BACKGROUND="$ROOT/scripts/assets/dmg-background.png"

rm -rf "$DERIVED_DATA" "$DIST"
mkdir -p "$STAGE" "$DMG_ROOT/.background"

xcodebuild \
  -project "$ROOT/Runway.xcodeproj" \
  -scheme Runway \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY='-' \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  -quiet \
  build

ditto "$BUILD_APP" "$APP"

# Remove development-signing residue and local debug paths before public packaging.
while IFS= read -r -d '' file; do
  if file "$file" | grep -q 'Mach-O'; then
    codesign --remove-signature "$file" >/dev/null 2>&1 || true
    strip -S "$file" >/dev/null 2>&1 || true
  fi
done < <(find "$APP" -type f -print0)
find "$APP" -name embedded.provisionprofile -delete

if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --entitlements "$ROOT/RunwayWidget/RunwayWidget.entitlements" --sign - "$WIDGET"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
"$ROOT/scripts/verify_release_privacy.sh" "$APP"

ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
ditto "$APP" "$DMG_ROOT/Runway.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$DMG_BACKGROUND" "$DMG_ROOT/.background/dmg-background.png"
chflags hidden "$DMG_ROOT/.background"

hdiutil create -quiet -volname "$DMG_VOLUME" -srcfolder "$DMG_ROOT" -ov -format UDRW "$DMG_RW"

# Headless packaging avoids driving Finder while the user is working.
if [[ "${HEADLESS_PACKAGE:-0}" != "1" ]]; then
  hdiutil detach "/Volumes/$DMG_VOLUME" -force >/dev/null 2>&1 || true
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
    set position of item "Runway.app" of container window to {185, 220}
    set position of item "Applications" of container window to {535, 220}
    update without registering applications
    delay 2
    close container window
  end tell
end tell
APPLESCRIPT
  sync
  hdiutil detach "$DEVICE" -quiet
fi

hdiutil convert "$DMG_RW" -quiet -format UDZO -o "$DMG"
rm -f "$DMG_RW"

(cd "$DIST" && shasum -a 256 "${ARCHIVE##*/}" "${DMG##*/}" > SHA256SUMS.txt)
ln -s Runway-macOS.zip "$DIST/CodexUsageMonitor-macOS.zip"
ln -s Runway-macOS.dmg "$DIST/CodexUsageMonitor-macOS.dmg"

echo "Created $ARCHIVE"
echo "Created $DMG"
echo "Signing: anonymous ad-hoc preview (not notarized)."
