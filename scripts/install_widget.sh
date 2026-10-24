#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/runway-install.XXXXXX")"
APP="$DERIVED_DATA/Build/Products/Release/Runway.app"
DEST="/Applications/Runway.app"
PLUGIN="$DEST/Contents/PlugIns/RunwayWidget.appex"
AGENT="$HOME/Library/LaunchAgents/com.codexusage.Runway.refresh.plist"
LEGACY_APP="/Applications/CodexUsageMonitor.app"
LEGACY_AGENT="$HOME/Library/LaunchAgents/com.codexusage.CodexUsageMonitor.refresh.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
INSTALL_COMPLETED=0
LOCK_ACQUIRED=0
LOCKFILE="$HOME/Library/Caches/com.codexusage.Runway/install.lock"

cleanup_build() {
  if [[ "$INSTALL_COMPLETED" -eq 0 ]]; then
    for installed in "$DEST" "$LEGACY_APP"; do
      previous="$DERIVED_DATA/Previous-$(basename "$installed")"
      if [[ ( -e "$previous" || -L "$previous" ) && ! -e "$installed" && ! -L "$installed" ]]; then
        if mv "$previous" "$installed"; then
          "$LSREGISTER" -f "$installed" >/dev/null 2>&1 || true
        else
          echo "Could not restore $installed; recovery copy: $previous" >&2
        fi
      fi
    done
  fi
  if [[ -d "$APP" ]]; then
    pluginkit -r "$APP/Contents/PlugIns/RunwayWidget.appex" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  fi
  if [[ "$INSTALL_COMPLETED" -eq 0 && ( -e "$DERIVED_DATA/Previous-Runway.app" || -L "$DERIVED_DATA/Previous-Runway.app" || -e "$DERIVED_DATA/Previous-CodexUsageMonitor.app" || -L "$DERIVED_DATA/Previous-CodexUsageMonitor.app" ) ]]; then
    echo "Previous application retained in $DERIVED_DATA" >&2
  else
    rm -rf "$DERIVED_DATA"
  fi
  if [[ "$LOCK_ACQUIRED" -eq 1 ]]; then rm -f "$LOCKFILE"; fi
}
trap cleanup_build EXIT

xcodebuild \
  -project "$ROOT/Runway.xcodeproj" \
  -scheme Runway \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ENABLE_HARDENED_RUNTIME=NO \
  "$@" \
  -quiet \
  build

mkdir -p "$(dirname "$LOCKFILE")"
if ! /usr/bin/shlock -p "$$" -f "$LOCKFILE"; then
  echo "Another Runway installation is running." >&2
  exit 1
fi
LOCK_ACQUIRED=1

for agent in "$AGENT" "$LEGACY_AGENT"; do
  label="$(basename "$agent" .plist)"
  service="gui/$(id -u)/$label"
  status=0
  launchctl print "$service" >/dev/null 2>&1 || status=$?
  if [[ "$status" -eq 0 ]]; then
    launchctl bootout "$service"
  elif [[ "$status" -ne 113 ]]; then
    echo "Could not inspect $service (launchctl $status)" >&2
    exit 1
  fi
  status=0
  launchctl print "$service" >/dev/null 2>&1 || status=$?
  if [[ "$status" -ne 113 ]]; then
    echo "Could not retire $service" >&2
    exit 1
  fi
  rm -f "$agent"
done
pkill -f '^/Applications/(Runway|CodexUsageMonitor)[.]app/Contents/' >/dev/null 2>&1 || true
BACKUP="$ROOT/build/install-backups.noindex/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
STAGED="$DERIVED_DATA/New-Runway.app"
ditto "$APP" "$STAGED"
for installed in "$LEGACY_APP" "$DEST"; do
  if [[ -d "$installed" && ! -L "$installed" ]]; then
    archive="$BACKUP/Previous-$(basename "$installed").zip"
    ditto -c -k --sequesterRsrc --keepParent "$installed" "$archive"
    unzip -tq "$archive" >/dev/null
  fi
done
if [[ -e "$LEGACY_APP" && ! -L "$LEGACY_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_APP"
  mv "$LEGACY_APP" "$DERIVED_DATA/Previous-CodexUsageMonitor.app"
fi
if [[ -d "$DEST" ]]; then
  "$LSREGISTER" -u "$DEST"
  mv "$DEST" "$DERIVED_DATA/Previous-Runway.app"
fi
if ! mv "$STAGED" "$DEST"; then
  exit 1
fi
INSTALL_COMPLETED=1
if [[ -L "$LEGACY_APP" ]]; then
  target="$(readlink "$LEGACY_APP")"
  if [[ "$target" == Runway.app || "$target" == "$DEST" ]]; then rm "$LEGACY_APP"; fi
fi

"$LSREGISTER" -f -R -trusted "$DEST"
pluginkit -a "$PLUGIN"
# WidgetKit keeps executable paths in existing sessions after an app rename.
/usr/bin/killall chronod >/dev/null 2>&1 || true

/usr/bin/open "$DEST"

echo "Installed $DEST"
echo "Registered $PLUGIN"
pluginkit -m -A -i com.codexusage.CodexUsageMonitor.widget3 2>/dev/null || true
