#!/bin/bash
# Tube Timer installer for macOS 13+.
#
#   curl -fsSL https://raw.githubusercontent.com/jbellsolutions/tube-timer/main/install.sh | bash
#
# Builds the app from source on this Mac (so there are no "unidentified developer" warnings),
# installs it to ~/Applications, adds it to the Dock, and opens it at login.
set -euo pipefail

REPO="jbellsolutions/tube-timer"
BRANCH="main"
NAME="Tube Timer"
DEST="$HOME/Applications/$NAME.app"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

bold "⏱  Installing Tube Timer"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Tube Timer runs on macOS right now. Windows is coming soon!"; exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 13 )); then
  echo "Tube Timer needs macOS 13 (Ventura) or newer."; exit 1
fi

# Apple's free command line tools include the Swift compiler.
if ! xcrun --find swiftc >/dev/null 2>&1; then
  bold "Tube Timer needs Apple's free Command Line Tools (one time, about 5 minutes)."
  echo "A window will pop up: click Install. When it finishes, run this installer again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

# Use this folder if we're running from a downloaded copy; otherwise download the latest source.
SRC=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [[ -n "$HERE" && -f "$HERE/app/main.swift" ]]; then
  SRC="$HERE"
else
  SRC="$(mktemp -d)"
  echo "• Downloading the latest version…"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz -C "$SRC" --strip-components=1
fi

"$SRC/app/build.sh"

echo "• Installing to ~/Applications…"
pkill -x TubeTimer 2>/dev/null || true
pkill -x YouTubeLimit 2>/dev/null || true   # earlier name of this app
mkdir -p "$HOME/Applications"
rm -rf "$DEST" "$HOME/Applications/YouTube Limit.app"
cp -R "$SRC/app/build/$NAME.app" "$DEST"

# Desktop shortcut (and remove the old-name one).
rm -f "$HOME/Desktop/YouTube Limit"
ln -sfn "$DEST" "$HOME/Desktop/$NAME"

# Dock: swap out the old-name icon, add Tube Timer once.
/usr/bin/python3 - "$DEST" <<'PY' && killall Dock 2>/dev/null || true
import plistlib, subprocess, sys
dest = sys.argv[1]
raw = subprocess.run(["defaults", "export", "com.apple.dock", "-"], capture_output=True).stdout
dock = plistlib.loads(raw)
apps = dock.get("persistent-apps", [])
url = lambda t: t.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
kept = [t for t in apps if "YouTube%20Limit.app" not in url(t)]
changed = len(kept) != len(apps)
if not any("Tube%20Timer.app" in url(t) for t in kept):
    kept.append({"tile-data": {"file-data": {"_CFURLString": "file://" + dest.replace(" ", "%20") + "/", "_CFURLStringType": 15}}})
    changed = True
if not changed:
    sys.exit(1)  # nothing to do; skip restarting the Dock
dock["persistent-apps"] = kept
subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=plistlib.dumps(dock), check=True)
PY

open "$DEST" --args "$@"

bold "✅ Tube Timer is installed!"
cat <<'EOF'

Next steps:
  1. Create your 4-digit parent PIN when asked.
  2. Open YouTube in Chrome or Safari. When macOS asks to let Tube Timer
     control your browser, click OK. (If you missed it: System Settings →
     Privacy & Security → Automation → Tube Timer.)
  3. Optional, for the most accurate timer: in Chrome, turn on
     View → Developer → Allow JavaScript from Apple Events.

Find Tube Timer in your Dock, on your Desktop, or as the 🐔 in the menu bar.
EOF
