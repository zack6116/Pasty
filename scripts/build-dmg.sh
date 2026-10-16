#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARCH_LABEL="arm64" ;;
  x86_64) ARCH_LABEL="x86_64" ;;
  *) ARCH_LABEL="$ARCH" ;;
esac

./scripts/build-app.sh

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pasty-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

cp -R Pasty.app "$STAGE/Pasty.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/Pasty-${VERSION}-macos-${ARCH_LABEL}.dmg"
rm -f "$DMG"

hdiutil create \
  -volname "Pasty" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo "Built $(pwd)/$DMG"
