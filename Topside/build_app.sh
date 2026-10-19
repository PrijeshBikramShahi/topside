#!/bin/bash
# Usage: bash build_app.sh "Developer ID Application: Your Name (TEAMID)"
# With no argument, the first installed Developer ID Application identity is selected.
# For a stable local build, Apple Development is the fallback. If neither exists,
# the build falls back to ad-hoc signing and says so explicitly.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${1:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
fi
IDENTITY="${IDENTITY:--}"
BUNDLE_ID="com.prizesh.topside"
APP="build/Topside.app"

swift build -c release --product Topside
BIN="$(swift build -c release --show-bin-path)/Topside"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Topside"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Topside</string>
  <key>CFBundleDisplayName</key><string>Topside</string>
  <key>CFBundleExecutable</key><string>Topside</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Topside reads what Spotify is playing and sends it play, pause, next and previous commands from the island.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "--- signature ---"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature" || true
if [ "$IDENTITY" = "-" ]; then
  echo "WARNING: ad-hoc signed. Install a Developer ID Application or Apple Development identity so Automation permission survives rebuilds."
elif [[ "$IDENTITY" == "Apple Development:"* ]]; then
  echo "NOTE: Apple Development provides a stable local identity. A Developer ID Application identity is still required for distribution outside the Mac App Store."
fi
echo
echo "Built $APP (bundle id: $BUNDLE_ID)"
echo "Run:  open $APP      Log: ~/Library/Logs/Topside.log"
