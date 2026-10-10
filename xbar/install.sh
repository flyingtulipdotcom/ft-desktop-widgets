#!/usr/bin/env bash
# Installs the Flying Tulip menu bar plugin for xbar and/or SwiftBar on macOS.
# Usage: curl -fsSL https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/xbar/install.sh | bash
set -euo pipefail

URL="https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/xbar/Cryptocurrency/FlyingTulip/flyingtulip.1m.sh"
NAME="flyingtulip.1m.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for macOS (xbar or SwiftBar)." >&2
  exit 1
fi

dirs=()
XBAR_DIR="$HOME/Library/Application Support/xbar/plugins"
if [ -d "/Applications/xbar.app" ] || [ -d "$HOME/Applications/xbar.app" ] || [ -d "$XBAR_DIR" ]; then
  dirs+=("$XBAR_DIR")
fi
SWIFTBAR_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -n "$SWIFTBAR_DIR" ]; then
  dirs+=("${SWIFTBAR_DIR/#\~/$HOME}")
fi

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "Neither xbar nor SwiftBar found. Install one first: https://xbarapp.com or https://github.com/swiftbar/SwiftBar" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$URL" -o "$tmp"
head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || { echo "Download looks wrong, aborting." >&2; exit 1; }

for d in "${dirs[@]}"; do
  mkdir -p "$d"
  install -m 755 "$tmp" "$d/$NAME"
  echo "Installed to $d/$NAME"
done

open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true
open -g "swiftbar://refreshallplugins" 2>/dev/null || true
echo "Done. Set your wallet in the plugin settings to see health factor, PnL and FT earned."
