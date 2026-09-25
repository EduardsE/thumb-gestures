#!/bin/bash
# Stop Thumb Gestures and remove the app and the login item.
LABEL="local.thumbgestures.ThumbGestures"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "/Applications/Thumb Gestures.app"
echo "Removed. Also remove 'Thumb Gestures' from System Settings > Privacy & Security > Accessibility."
