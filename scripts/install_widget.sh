#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/CodexUsageMonitor.app"
DEST="/Applications/CodexUsageMonitor.app"
PLUGIN="$DEST/Contents/PlugIns/CodexUsageWidget.appex"
AGENT="$HOME/Library/LaunchAgents/com.codexusage.CodexUsageMonitor.refresh.plist"

xcodebuild \
  -project "$ROOT/CodexUsageMonitor.xcodeproj" \
  -scheme CodexUsageMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_HARDENED_RUNTIME=NO \
  -quiet \
  build

if [[ -f "$AGENT" ]]; then
  launchctl bootout "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || true
fi
pkill -x CodexUsageMonitor >/dev/null 2>&1 || true
pkill -x CodexUsageWidget >/dev/null 2>&1 || true
for installed_app in "$DEST"; do
  installed_plugin="$installed_app/Contents/PlugIns/CodexUsageWidget.appex"
  if [[ -d "$installed_plugin" ]]; then
    pluginkit -r "$installed_plugin" >/dev/null 2>&1 || true
  fi
done
BACKUP="$ROOT/build/install-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
STAGED="$BACKUP/New-CodexUsageMonitor.app"
ditto "$APP" "$STAGED"
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$BACKUP/Previous-CodexUsageMonitor.app"
fi
if ! mv "$STAGED" "$DEST"; then
  if [[ -d "$BACKUP/Previous-CodexUsageMonitor.app" ]]; then
    mv "$BACKUP/Previous-CodexUsageMonitor.app" "$DEST"
  fi
  exit 1
fi

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f -R -trusted "$DEST"
pluginkit -a "$PLUGIN"

# Resume the existing refresh schedule immediately after replacement, including
# installs where the user does not reopen the workspace window.
if [[ -f "$AGENT" ]]; then
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi
/usr/bin/open "$DEST"

echo "Installed $DEST"
echo "Registered $PLUGIN"
pluginkit -m -A -i com.codexusage.CodexUsageMonitor.widget3 2>/dev/null || true
