#!/usr/bin/env bash
# CI only: run the native app on macOS and screenshot its panel on each tab (cliclick on the menu bar item).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${FT_APP:-$ROOT/macos/dist/Flying Tulip.app}"
OUT="$ROOT/out-native"
WALLET="${FT_CI_WALLET:?}"
DOMAIN="com.flyingtulip.widget"
mkdir -p "$OUT"
log() { echo "[ci] $*"; }

# Usage stats stay off in CI. Belt and braces: the setting, and the Plausible host does not resolve.
echo "127.0.0.1 plausible.io" | sudo tee -a /etc/hosts >/dev/null

brew install cliclick >"$OUT/brew.log" 2>&1 || { tail -5 "$OUT/brew.log"; log "cliclick install failed"; exit 1; }
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
log "screen: $(system_profiler SPDisplaysDataType 2>/dev/null | grep -i resolution | head -1)"

launch() {
  local tab="$1"
  pkill -x FlyingTulip 2>/dev/null || true
  sleep 1
  defaults delete "$DOMAIN" 2>/dev/null || true
  defaults write "$DOMAIN" wallets -array "$WALLET"
  defaults write "$DOMAIN" analytics -bool false
  defaults write "$DOMAIN" notifications -bool false
  defaults write "$DOMAIN" tab -string "$tab"
  rm -f "$OUT/frame.txt" "$OUT/frame.txt.debug"
  FT_CI_FRAME_FILE="$OUT/frame.txt" nohup "$APP/Contents/MacOS/FlyingTulip" >"$OUT/app-$tab.log" 2>&1 &
  sleep 4
  if ! pgrep -x FlyingTulip >/dev/null; then
    log "FAIL: the app is not running"; cat "$OUT/app-$tab.log"
    ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i flyingtulip | head
    for f in ~/Library/Logs/DiagnosticReports/FlyingTulip*; do [ -f "$f" ] && head -60 "$f"; done
    return 1
  fi
  # wait for data and for the item position
  for i in $(seq 1 30); do [ -s "$OUT/frame.txt" ] && [ "$i" -ge 14 ] && break; sleep 1; done
}

SCREEN_W=1920
shoot_tab() {
  local tab="$1"
  launch "$tab" || return 1
  local mid=1700 screen_h=1080 w=0
  if [ -s "$OUT/frame.txt" ]; then read -r mid screen_h w <"$OUT/frame.txt"; else log "no frame file"; cat "$OUT/frame.txt.debug" 2>/dev/null; fi
  log "$tab: menu bar item centre x=$mid (width $w)"
  local left=$((mid - 300)); [ "$left" -lt 0 ] && left=0
  screencapture -x -R"$((mid - 230)),0,460,28" "$OUT/menubar-title.png" 2>>"$OUT/screencapture.log" || true
  if [ "$tab" = market ]; then cp "$OUT/menubar-title.png" "$OUT/menubar-title-market.png"; fi
  cliclick m:"$mid",12 >>"$OUT/click.log" 2>&1; sleep 1
  cliclick c:"$mid",12 >>"$OUT/click.log" 2>&1; sleep 4
  screencapture -x -R"$left,0,600,980" "$OUT/panel-$tab.png" 2>>"$OUT/screencapture.log" || log "screencapture $tab failed"
  screencapture -x "$OUT/full-$tab.png" 2>>"$OUT/screencapture.log" || true
  cliclick kp:esc >/dev/null 2>&1 || true
  pkill -x FlyingTulip 2>/dev/null || true
}

rc=0
for t in market account positions; do shoot_tab "$t" || rc=1; done
cp "$OUT/menubar-title-market.png" "$OUT/menubar-title.png" 2>/dev/null || true
rm -f "$OUT/menubar-title-market.png"
ls -la "$OUT"
exit $rc
