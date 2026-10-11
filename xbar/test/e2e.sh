#!/usr/bin/env bash
# End to end on Linux: run the real plugin file with a node stand-in for osascript and the real API.
# Usage: test/e2e.sh [wallet]     (needs node and network)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$HERE/../Cryptocurrency/FlyingTulip/flyingtulip.1m.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed "s|/usr/bin/osascript|$HERE/osascript-shim.js|" "$PLUGIN" > "$T/flyingtulip.1m.sh"; chmod +x "$T/flyingtulip.1m.sh"
export HOME="$T/home" SHIM_LOG="$T/shim.log" PATH="$PATH"; mkdir -p "$HOME"
# the plugin resets PATH to the macOS one; /usr/bin must have node-free tools only, the shim uses its own shebang
sed -i 's|^export PATH=.*|export PATH="/usr/bin:/bin:$PATH"|' "$T/flyingtulip.1m.sh"
out="$(VAR_WALLET="${1:-}" "$T/flyingtulip.1m.sh")"
printf '%s\n' "$out" | sed -E 's/image=[A-Za-z0-9+\/=]{40,}/image=<base64>/' | head -${LINES_SHOWN:-12}
printf '%s\n' "$out" > "$T/out.txt"
node -e '
const {validate}=require(process.argv[1]); const fs=require("fs")
const errs=validate(fs.readFileSync(process.argv[2],"utf8").trimEnd()); console.log("format errors:", JSON.stringify(errs)); process.exit(errs.length?1:0)' "$HERE/xbar-format.js" "$T/out.txt"
test -s "$HOME/Library/Caches/com.flyingtulip.menubar/state.json" && echo "state file written"
[ -f "$SHIM_LOG" ] && cat "$SHIM_LOG" || true
# Set wallet flow
SHIM_DIALOG="  0x000000000000000000000000000000000000dEaD " "$T/flyingtulip.1m.sh" wallet
test "$(cat "$HOME/Library/Application Support/FlyingTulip/menubar-wallet")" = "0x000000000000000000000000000000000000dead" && echo "set-wallet flow ok"
"$T/flyingtulip.1m.sh" | grep -q "Account    0x0000" && echo "saved wallet picked up"
# several wallets: add one (the box starts empty), the next run on the menu's "Next wallet" shows it, remove it
W2=0x2222222222222222222222222222222222222222
SHIM_DIALOG=" $W2 " "$T/flyingtulip.1m.sh" add
test "$(cat "$HOME/Library/Application Support/FlyingTulip/menubar-wallet")" = "0x000000000000000000000000000000000000dead
$W2" && echo "add-wallet flow ok"
"$T/flyingtulip.1m.sh" next | head -1 | grep -q "0x2222…2222 ⇄" && echo "next wallet shown with the switch sign"
"$T/flyingtulip.1m.sh" remove "$W2" >/dev/null
test "$(cat "$HOME/Library/Application Support/FlyingTulip/menubar-wallet")" = "0x000000000000000000000000000000000000dead" && echo "remove-wallet flow ok"
