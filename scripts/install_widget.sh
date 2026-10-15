#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/Runway.app"
DEST="/Applications/Runway.app"
PLUGIN="$DEST/Contents/PlugIns/RunwayWidget.appex"
AGENT="$HOME/Library/LaunchAgents/com.codexusage.Runway.refresh.plist"
LEGACY_APP="/Applications/CodexUsageMonitor.app"
LEGACY_AGENT="$HOME/Library/LaunchAgents/com.codexusage.CodexUsageMonitor.refresh.plist"

xcodebuild \
  -project "$ROOT/Runway.xcodeproj" \
  -scheme Runway \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_HARDENED_RUNTIME=NO \
  -quiet \
  build

for agent in "$AGENT" "$LEGACY_AGENT"; do
  if [[ -f "$agent" ]]; then
    launchctl bootout "gui/$(id -u)" "$agent" >/dev/null 2>&1 || true
  fi
done
pkill -f '^/Applications/(Runway|CodexUsageMonitor)[.]app/Contents/' >/dev/null 2>&1 || true
BACKUP="$ROOT/build/install-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
STAGED="$BACKUP/New-Runway.app"
ditto "$APP" "$STAGED"
if [[ -e "$LEGACY_APP" && ! -L "$LEGACY_APP" ]]; then
  mv "$LEGACY_APP" "$BACKUP/Previous-CodexUsageMonitor.app"
fi
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$BACKUP/Previous-Runway.app"
fi
if ! mv "$STAGED" "$DEST"; then
  if [[ -d "$BACKUP/Previous-Runway.app" ]]; then
    mv "$BACKUP/Previous-Runway.app" "$DEST"
  fi
  if [[ -d "$BACKUP/Previous-CodexUsageMonitor.app" ]]; then
    mv "$BACKUP/Previous-CodexUsageMonitor.app" "$LEGACY_APP"
  fi
  exit 1
fi
if [[ -L "$LEGACY_APP" ]]; then rm "$LEGACY_APP"; fi
ln -s Runway.app "$LEGACY_APP"
if [[ -f "$LEGACY_AGENT" ]]; then
  mv "$LEGACY_AGENT" "$BACKUP/Previous-CodexUsageMonitor.refresh.plist"
fi

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f -R -trusted "$DEST"
pluginkit -a "$PLUGIN"
# WidgetKit keeps executable paths in existing sessions after an app rename.
/usr/bin/killall chronod >/dev/null 2>&1 || true

# Resume the existing refresh schedule immediately after replacement, including
# installs where the user does not reopen the workspace window.
if [[ -f "$AGENT" ]]; then
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi
/usr/bin/open "$DEST"

echo "Installed $DEST"
echo "Registered $PLUGIN"
pluginkit -m -A -i com.codexusage.CodexUsageMonitor.widget3 2>/dev/null || true
