#!/usr/bin/env bash
# CI only: run the xbar/SwiftBar plugin on macOS, save its output and take screenshots of it in SwiftBar.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_SRC="$ROOT/xbar/Cryptocurrency/FlyingTulip/flyingtulip.1m.sh"
OUT="$ROOT/out"
PLUGINS="$HOME/swiftbar-plugins"
WALLET="${FT_CI_WALLET:?}"
mkdir -p "$OUT" "$PLUGINS"

log() { echo "[ci] $*"; }

# Usage stats must stay off in CI. Belt and braces: the setting, and the Plausible host does not resolve.
echo "127.0.0.1 plausible.io" | sudo tee -a /etc/hosts >/dev/null

# ---- 1. run the plugin directly --------------------------------------------------------------------
log "running the plugin directly"
export VAR_WALLET="$WALLET" VAR_ANALYTICS=false VAR_NOTIFICATIONS=false
bash "$PLUGIN_SRC" >"$OUT/plugin-stdout.txt" 2>"$OUT/plugin-stderr.txt"
rc=$?
log "exit $rc, $(wc -c <"$OUT/plugin-stdout.txt") bytes, $(wc -l <"$OUT/plugin-stdout.txt") lines"
# Readable copy: base64 images shortened.
sed -E 's/(image=|templateImage=)[A-Za-z0-9+\/=]{40,}/\1<base64>/g' "$OUT/plugin-stdout.txt" >"$OUT/plugin-stdout-readable.txt"
head -40 "$OUT/plugin-stdout-readable.txt"
fail=0
if [ "$rc" -ne 0 ]; then log "FAIL: plugin exited $rc"; cat "$OUT/plugin-stderr.txt"; fail=1; fi
if [ ! -s "$OUT/plugin-stdout.txt" ]; then log "FAIL: plugin printed nothing"; fail=1; fi
if grep -q 'FT offline' "$OUT/plugin-stdout.txt"; then log "FAIL: plugin shows FT offline"; fail=1; fi
if ! grep -q '^---' "$OUT/plugin-stdout.txt"; then log "FAIL: no dropdown separator in output"; fail=1; fi
if [ "$fail" -ne 0 ]; then exit 1; fi

# ---- 2. SwiftBar ----------------------------------------------------------------------------------
log "installing SwiftBar"
brew install --cask swiftbar >"$OUT/brew.log" 2>&1 || { tail -20 "$OUT/brew.log"; exit 1; }
install -m 755 "$PLUGIN_SRC" "$PLUGINS/flyingtulip.1m.sh"
mkdir -p "$HOME/Library/Application Support/FlyingTulip"
printf '%s\n' "$WALLET" >"$HOME/Library/Application Support/FlyingTulip/menubar-wallet"

defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGINS"
defaults write com.ameba.SwiftBar MakePluginExecutable -bool true
# SwiftBar stores per-plugin variables next to the plugin.
printf '{"VAR_ANALYTICS":"false","VAR_NOTIFICATIONS":"false","VAR_WALLET":"%s"}\n' "$WALLET" >"$PLUGINS/flyingtulip.1m.sh.vars.json"
cp "$PLUGINS/flyingtulip.1m.sh.vars.json" "$PLUGINS/.flyingtulip.1m.sh.vars.json" 2>/dev/null || true
launchctl setenv VAR_ANALYTICS false
launchctl setenv VAR_WALLET "$WALLET"

shot() { screencapture -x "$OUT/$1.png" 2>>"$OUT/screencapture.log" || log "screencapture $1 failed"; }

log "screen: $(system_profiler SPDisplaysDataType 2>/dev/null | grep -i resolution | head -1)"

xattr -dr com.apple.quarantine /Applications/SwiftBar.app 2>&1 | tee -a "$OUT/swiftbar-launch.log" || true
open /Applications/SwiftBar.app >>"$OUT/swiftbar-launch.log" 2>&1 || log "open failed"
sleep 5
if ! pgrep -x SwiftBar >/dev/null; then
  log "SwiftBar not running after open, starting the binary directly"
  nohup /Applications/SwiftBar.app/Contents/MacOS/SwiftBar >>"$OUT/swiftbar-run.log" 2>&1 &
  sleep 5
fi
ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i swiftbar >>"$OUT/swiftbar-launch.log" || true
log "waiting for the plugin to render"
for i in $(seq 1 30); do
  pgrep -x SwiftBar >/dev/null && ls "$HOME/Library/Caches/com.flyingtulip.menubar" >/dev/null 2>&1 && break
  sleep 2
done
sleep 10
pgrep -x SwiftBar >/dev/null && log "SwiftBar running" || log "SwiftBar NOT running"
osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>&1 | tee "$OUT/processes.txt" || true

shot full-screen
# Menu bar strip (the screen is 1920x1080 points on the runner).
screencapture -x -R0,0,1920,28 "$OUT/menubar-title.png" 2>>"$OUT/screencapture.log" || true
screencapture -x -R1300,0,620,28 "$OUT/menubar-title-right.png" 2>>"$OUT/screencapture.log" || true

# ---- 3. open the dropdown -------------------------------------------------------------------------
log "opening the dropdown"
cat >"$OUT/click.applescript" <<'AS'
tell application "System Events"
  tell process "SwiftBar"
    set out to ""
    repeat with i from 1 to (count of menu bars)
      try
        set out to out & "menu bar " & i & ": " & (count of menu bar items of menu bar i) & " items" & linefeed
      end try
    end repeat
    return out
  end tell
end tell
AS
osascript "$OUT/click.applescript" >"$OUT/click.log" 2>&1 || true
cat "$OUT/click.log"
# A real mouse click with cliclick on the status item (AX press does not open a SwiftBar menu on CI).
brew install cliclick >>"$OUT/brew.log" 2>&1 || { log "cliclick install failed"; exit 1; }
# The widget sits left of the search icon; click at its title (x about 1600 points).
cliclick m:1600,12 >>"$OUT/click.log" 2>&1 || true
sleep 1
cliclick c:1600,12 >>"$OUT/click.log" 2>&1 || true
sleep 3
cropshot() { screencapture -x -R"$2" "$OUT/$1.png" 2>>"$OUT/screencapture.log" || log "screencapture $1 failed"; }
cropshot dropdown-open 1400,0,520,340
# Submenus open on hover, to the left of the menu (it is at the right edge of the screen).
cliclick m:1600,118 >>"$OUT/click.log" 2>&1; sleep 2; cropshot submenu-market 700,0,1220,620
cliclick m:1600,140 >>"$OUT/click.log" 2>&1; sleep 2; cropshot submenu-account 700,0,1220,900
cliclick m:1600,162 >>"$OUT/click.log" 2>&1; sleep 2; cropshot submenu-positions 700,0,1220,620
cliclick kp:esc >/dev/null 2>&1 || true
rm -f "$OUT/full-screen.png"

# Keep the SwiftBar and TCC diagnostics for the report.
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" 'select service,client,auth_value from access' >"$OUT/tcc-user.txt" 2>&1 || true
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" 'select service,client,auth_value from access' >"$OUT/tcc-system.txt" 2>&1 || true
ls -la "$PLUGINS" >"$OUT/plugins-dir.txt"
pkill -x SwiftBar || true
ls -la "$OUT"
