#!/usr/bin/env bash
# Packs macos/dist/Flying Tulip.app into FlyingTulip-<version>.dmg and .zip next to it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-2.0.0}"
APP="dist/Flying Tulip.app"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "dist/FlyingTulip-$VERSION.dmg" "dist/FlyingTulip-$VERSION.zip"
hdiutil create -volname "Flying Tulip" -srcfolder "$STAGE" -ov -format UDZO "dist/FlyingTulip-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/FlyingTulip-$VERSION.zip"
ls -la dist
