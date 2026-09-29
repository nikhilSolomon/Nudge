#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
EXEC_NAME="Nudge"
APP_NAME="Nudge"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)
EXEC="$BIN_PATH/$EXEC_NAME"

if [ ! -x "$EXEC" ]; then
    echo "Build did not produce executable at $EXEC" >&2
    exit 1
fi

APP_DIR="./build/$APP_NAME.app"
echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXEC" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "App/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "App/AppIcon.icns" ]; then
    cp "App/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || true
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo ""
echo "Built $APP_DIR"
echo ""
echo "Run with:   open \"$APP_DIR\""
