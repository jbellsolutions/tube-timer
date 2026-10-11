#!/bin/bash
# Removes Tube Timer. Add --all to also delete its settings (PIN, limits, history).
#
#   curl -fsSL https://raw.githubusercontent.com/jbellsolutions/tube-timer/main/uninstall.sh | bash
set -uo pipefail

pkill -x TubeTimer 2>/dev/null
pkill -x YouTubeLimit 2>/dev/null
rm -rf "$HOME/Applications/Tube Timer.app" "/Applications/Tube Timer.app" "$HOME/Applications/YouTube Limit.app"
rm -f "$HOME/Desktop/Tube Timer" "$HOME/Desktop/YouTube Limit"
rm -f "$HOME/Library/LaunchAgents/com.tubetimer.app.plist" "$HOME/Library/LaunchAgents/com.homebase.youtubelimit.plist"

/usr/bin/python3 - <<'PY' && killall Dock 2>/dev/null
import plistlib, subprocess, sys
dock = plistlib.loads(subprocess.run(["defaults", "export", "com.apple.dock", "-"], capture_output=True).stdout)
apps = dock.get("persistent-apps", [])
url = lambda t: t.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
kept = [t for t in apps if "Tube%20Timer.app" not in url(t) and "YouTube%20Limit.app" not in url(t)]
if len(kept) == len(apps):
    sys.exit(1)
dock["persistent-apps"] = kept
subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=plistlib.dumps(dock), check=True)
PY

if [[ "${1:-}" == "--all" ]]; then
  defaults delete com.tubetimer.app 2>/dev/null
  rm -rf "$HOME/Library/Application Support/Tube Timer"
  echo "Settings deleted."
fi
echo "✅ Tube Timer has been removed."
