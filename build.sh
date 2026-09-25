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

codesign --force --sign - "$APP"
echo "Built $APP"
