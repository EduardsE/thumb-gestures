#!/bin/bash
# Build "Thumb Gestures.app" into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Thumb Gestures.app"
swift build -c release --product ThumbGestures
BIN="$(swift build -c release --show-bin-path)/ThumbGestures"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/ThumbGestures"

swift tools/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Sign with a local certificate if one exists, so macOS keeps the Accessibility
# permission across rebuilds. Without it, sign ad-hoc (the permission can reset).
IDENTITY="${SIGN_IDENTITY:-Local App Signing}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
