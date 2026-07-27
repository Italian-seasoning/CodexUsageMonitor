#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/CodexUsageMonitor.app"
DEST="$HOME/Applications/CodexUsageMonitor.app"
PLUGIN="$DEST/Contents/PlugIns/CodexUsageWidget.appex"
AGENT="$HOME/Library/LaunchAgents/com.nolankrahn.CodexUsageMonitor.refresh.plist"

xcodebuild \
  -project "$ROOT/CodexUsageMonitor.xcodeproj" \
  -scheme CodexUsageMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build

mkdir -p "$HOME/Applications"
if [[ -f "$AGENT" ]]; then
  launchctl bootout "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || true
fi
pkill -x CodexUsageMonitor >/dev/null 2>&1 || true
pkill -x CodexUsageWidget >/dev/null 2>&1 || true
if [[ -d "$PLUGIN" ]]; then
  pluginkit -r "$PLUGIN" >/dev/null 2>&1 || true
fi
rm -rf "$DEST"
rm -rf "$HOME/Library/Saved Application State/com.nolankrahn.CodexUsageMonitor.savedState"
ditto "$APP" "$DEST"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f -R -trusted "$DEST"
pluginkit -a "$PLUGIN"

echo "Installed $DEST"
echo "Registered $PLUGIN"
pluginkit -m -A -i com.nolankrahn.CodexUsageMonitor.widget 2>/dev/null || true
