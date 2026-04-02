#!/bin/zsh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APPLICATIONS_DIR="$HOME/Applications"
DERIVED_DATA_DIR="$REPO_DIR/.build/Singletion"
APP_BUILD_PATH="$DERIVED_DATA_DIR/Build/Products/Release/Singletion.app"
APP_INSTALL_PATH="$APPLICATIONS_DIR/Singletion.app"
APP_EXECUTABLE_PATH="$APP_INSTALL_PATH/Contents/MacOS/Singletion"
APP_PROCESS_PATTERN="$APP_INSTALL_PATH/Contents/MacOS/Singletion"

mkdir -p "$APPLICATIONS_DIR"

xcodegen generate >/dev/null

xcodebuild \
  -project "$REPO_DIR/Singletion.xcodeproj" \
  -scheme Singletion \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

osascript -e 'tell application id "dev.umeboshi.Singletion" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -f '/Singletion.app/Contents/MacOS/Singletion' || true
rm -rf "$APP_INSTALL_PATH"
ditto "$APP_BUILD_PATH" "$APP_INSTALL_PATH"
"$APP_EXECUTABLE_PATH" >/dev/null 2>&1 &

for _ in {1..20}; do
  if pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
    echo "Installed Singletion.app to:"
    echo "  $APP_INSTALL_PATH"
    exit 0
  fi

  sleep 0.25
done

echo "Failed to launch installed Singletion.app at:"
echo "  $APP_INSTALL_PATH" >&2
exit 1
