#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="Pasty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Pasty "$APP/Contents/MacOS/Pasty"
cp Support/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Pasty"
codesign --force --sign - --identifier com.zack.pasty "$APP"

echo "Built $(pwd)/$APP"
