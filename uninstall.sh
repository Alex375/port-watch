#!/bin/bash
# PortWatch Uninstaller
# Removes the app, preferences, caches, logs, and kills any running instance.

set -e

APP_NAME="PortWatch"
BUNDLE_ID="com.portwatch.app"

echo "=== $APP_NAME Uninstaller ==="
echo ""
read -p "This will completely remove $APP_NAME. Continue? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# 1. Kill running process
echo "Stopping $APP_NAME..."
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    pkill -TERM -x "$APP_NAME" 2>/dev/null || true
    sleep 3
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        pkill -KILL -x "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "WARNING: Could not kill $APP_NAME (PID $(pgrep -x "$APP_NAME"))"
    else
        echo "  Stopped."
    fi
else
    echo "  Not running."
fi

# 2. Remove .app
for app_path in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    if [ -d "$app_path" ]; then
        echo "Removing $app_path..."
        rm -rf "$app_path"
        echo "  Removed."
    fi
done

# 3. Remove Application Support
if [ -d "$HOME/Library/Application Support/$APP_NAME" ]; then
    echo "Removing Application Support..."
    rm -rf "$HOME/Library/Application Support/$APP_NAME"
    echo "  Removed."
fi

# 4. Remove Preferences
if [ -f "$HOME/Library/Preferences/$BUNDLE_ID.plist" ]; then
    echo "Removing Preferences..."
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    echo "  Removed."
fi
# Also clear UserDefaults via defaults command
defaults delete "$BUNDLE_ID" 2>/dev/null || true

# 5. Remove Caches
if [ -d "$HOME/Library/Caches/$APP_NAME" ]; then
    echo "Removing Caches..."
    rm -rf "$HOME/Library/Caches/$APP_NAME"
    echo "  Removed."
fi

# 6. Remove Logs
if [ -d "$HOME/Library/Logs/$APP_NAME" ]; then
    echo "Removing Logs..."
    rm -rf "$HOME/Library/Logs/$APP_NAME"
    echo "  Removed."
fi

# 7. Final check for residual processes
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo ""
    echo "WARNING: $APP_NAME process still running (PID $(pgrep -x "$APP_NAME"))"
    echo "You may need to kill it manually: kill -9 $(pgrep -x "$APP_NAME")"
else
    echo ""
    echo "$APP_NAME has been completely removed."
fi
