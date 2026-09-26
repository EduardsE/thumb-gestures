#!/bin/bash
# Build Thumb Gestures, copy it to /Applications, and start it at login.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="local.thumbgestures.ThumbGestures"
APP="/Applications/Thumb Gestures.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ThumbGestures.log"

./build.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootout returns before the old copy is gone. Wait (max 5 s), or bootstrap fails.
for _ in $(seq 50); do
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done
rm -rf "$APP"
cp -R "build/Thumb Gestures.app" "$APP"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>AssociatedBundleIdentifiers</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ThumbGestures</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $APP"
echo "Allow 'Thumb Gestures' in System Settings > Privacy & Security > Accessibility."
echo "Log: $LOG"
