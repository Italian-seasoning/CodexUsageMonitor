#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/CodexUsageMonitor.app"
DEST="$HOME/Applications/CodexUsageMonitor.app"
PLUGIN="$DEST/Contents/PlugIns/CodexUsageWidget.appex"
REFRESH_BIN="$DEST/Contents/MacOS/CodexUsageRefreshSnapshot"
AGENT_ID="com.nolankrahn.CodexUsageMonitor.refresh"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_ID.plist"

xcodebuild \
  -project "$ROOT/CodexUsageMonitor.xcodeproj" \
  -scheme CodexUsageMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
rm -rf "$HOME/Library/Saved Application State/com.nolankrahn.CodexUsageMonitor.savedState"
ditto "$APP" "$DEST"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f -R -trusted "$DEST"
pluginkit -a "$PLUGIN"
swiftc \
  -O \
  "$ROOT/Shared/CodexUsageSnapshot.swift" \
  "$ROOT/CodexUsageMonitor/HeadroomSavingsCollector.swift" \
  "$ROOT/scripts/RefreshSnapshot.swift" \
  -o "$REFRESH_BIN"
"$REFRESH_BIN"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/CodexUsageMonitor"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$REFRESH_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodexUsageMonitor/refresh.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodexUsageMonitor/refresh.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
launchctl kickstart -k "gui/$(id -u)/$AGENT_ID"

echo "Installed $DEST"
echo "Registered $PLUGIN"
echo "Refresh agent $AGENT_ID every 60s"
pluginkit -m -A -i com.nolankrahn.CodexUsageMonitor.widget 2>/dev/null || true
