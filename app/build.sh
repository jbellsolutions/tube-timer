#!/bin/bash
# Builds "Tube Timer.app" into app/build/. Use ../install.sh to build AND install.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Tube Timer"
VERSION="$(cat VERSION)"
BUILD="build/$NAME.app"

rm -rf build
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources" build/AppIcon.iconset

echo "• Compiling…"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then   # release builds run on Apple Silicon and Intel Macs
  swiftc -O -target arm64-apple-macos13.0 main.swift requests.swift relay.swift -o build/TubeTimer-arm64
  swiftc -O -target x86_64-apple-macos13.0 main.swift requests.swift relay.swift -o build/TubeTimer-x86_64
  lipo -create build/TubeTimer-arm64 build/TubeTimer-x86_64 -output "$BUILD/Contents/MacOS/TubeTimer"
else
  swiftc -O -target "$(uname -m)-apple-macos13.0" main.swift requests.swift relay.swift -o "$BUILD/Contents/MacOS/TubeTimer"
fi
cp party.html nope.html earn.html content/*.json "$BUILD/Contents/Resources/"

echo "• Drawing the icon…"
swift icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$BUILD/Contents/Resources/AppIcon.icns"

cat > "$BUILD/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.tubetimer.app</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>TubeTimer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSAppleEventsUsageDescription</key><string>Tube Timer checks whether YouTube is open in your browser and closes it when time is up.</string>
</dict></plist>
EOF

# Ad-hoc signature (free). A paid Apple Developer ID signature is only needed for a notarized download.
codesign --force --deep -s - "$BUILD"
echo "• Built: app/$BUILD"
