#!/usr/bin/env bash
# Builds the universal "Flying Tulip.app" into macos/dist, ad-hoc signed (or signed with $SIGN_IDENTITY).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-2.0.0}"
APP="dist/Flying Tulip.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/FlyingTulip"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlyingTulip"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/logo.png "$APP/Contents/Resources/logo.png"

# App icon: the logo on the dark tile the panel uses.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/logo.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/logo.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || echo "icon build skipped"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/FlyingTulip"
echo "built $APP"
