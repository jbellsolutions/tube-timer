#!/bin/bash
# Makes the downloadable app: dist/TubeTimer-<version>.dmg and .zip (for GitHub Releases / Gumroad).
set -euo pipefail
cd "$(dirname "$0")"

UNIVERSAL=1 ./build.sh
V="$(cat VERSION)"
mkdir -p dist
STAGE="$(mktemp -d)"
cp -R "build/Tube Timer.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
Installing Tube Timer
=====================

1. Drag "Tube Timer" onto the Applications folder.
2. Open Applications and double-click Tube Timer.
3. If macOS says it "can't be opened" or "can't verify the developer":
     • Open System Settings → Privacy & Security.
     • Scroll down and click "Open Anyway" next to Tube Timer, then confirm.
   (You only do this once. It appears because this early version isn't notarized by Apple yet.)
4. Create your 4-digit parent PIN.
5. Open YouTube in Chrome or Safari and click OK when macOS asks to let Tube Timer
   control your browser.

Prefer no warnings at all? Install from Terminal instead (builds on your Mac):
  curl -fsSL https://raw.githubusercontent.com/jbellsolutions/tube-timer/main/install.sh | bash

Help & community: https://jbellsolutions.github.io/tube-timer/
EOF
rm -f "dist/TubeTimer-$V.dmg" "dist/TubeTimer-$V.zip"
hdiutil create -quiet -volname "Tube Timer" -srcfolder "$STAGE" -ov -format UDZO "dist/TubeTimer-$V.dmg"
(cd build && ditto -c -k --keepParent "Tube Timer.app" "../dist/TubeTimer-$V.zip")
rm -rf "$STAGE"
echo "• Release files:"; ls -lh dist/
