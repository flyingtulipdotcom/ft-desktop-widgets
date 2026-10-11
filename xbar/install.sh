#!/usr/bin/env bash
# Installs Flying Tulip in the macOS menu bar.
#   macOS 13 or later: the native app (newest macos-v* release) into /Applications (or ~/Applications), then opens it.
#   Older macOS, or if any step fails: the xbar / SwiftBar plugin.
# Usage: curl -fsSL https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/xbar/install.sh | bash
# Choose by hand: FT_WIDGET=xbar (the plugin) or FT_WIDGET=native (the app, no fallback), e.g.
#   curl -fsSL <url above> | FT_WIDGET=xbar bash
# Default is auto. FT_REMOVE_XBAR=1 also removes an old Flying Tulip xbar/SwiftBar plugin without asking.
set -euo pipefail

REPO="flyingtulipdotcom/ft-desktop-widgets"
RELEASES_URL="${FT_RELEASES_URL:-https://api.github.com/repos/$REPO/releases?per_page=100}"
PLUGIN_URL="https://raw.githubusercontent.com/$REPO/main/xbar/Cryptocurrency/FlyingTulip/flyingtulip.1m.sh"
PLUGIN_NAME="flyingtulip.1m.sh"
APP_NAME="Flying Tulip.app"
BUNDLE_ID="com.flyingtulip.widget"
WIDGET="$(printf '%s' "${FT_WIDGET:-auto}" | tr '[:upper:]' '[:lower:]')"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for macOS." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

xbar_dir="$HOME/Library/Application Support/xbar/plugins"
# Plugin directories that exist (xbar and/or SwiftBar), one per line.
plugin_dirs() {
  if [ -d "/Applications/xbar.app" ] || [ -d "$HOME/Applications/xbar.app" ] || [ -d "$xbar_dir" ]; then
    printf '%s\n' "$xbar_dir"
  fi
  local sb
  sb="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  if [ -n "$sb" ]; then printf '%s\n' "${sb/#\~/$HOME}"; fi
}

install_plugin() {
  local dirs=() d
  while IFS= read -r d; do [ -n "$d" ] && dirs+=("$d"); done < <(plugin_dirs)
  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "Neither xbar nor SwiftBar found. Install one first: https://xbarapp.com or https://github.com/swiftbar/SwiftBar" >&2
    exit 1
  fi
  local plug="$tmp/$PLUGIN_NAME"
  curl -fsSL "$PLUGIN_URL" -o "$plug"
  head -1 "$plug" | grep -q '^#!/usr/bin/env bash' || { echo "Download looks wrong, aborting." >&2; exit 1; }
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
    install -m 755 "$plug" "$d/$PLUGIN_NAME"
    echo "Installed to $d/$PLUGIN_NAME"
  done
  open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true
  open -g "swiftbar://refreshallplugins" 2>/dev/null || true
  echo "Done. Set your wallet in the plugin settings to see health factor, PnL and FT earned."
}

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Prints "tag|zip name|zip url|zip digest|SHA256SUMS url" for the newest macos-vX.Y.Z release that has a .zip.
find_release() {
  local auth=()
  # FT_GITHUB_TOKEN (optional, for CI or shared IPs hitting the anonymous API rate limit) is sent to the releases API only.
  case "$RELEASES_URL" in https://api.github.com/*) [ -n "${FT_GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $FT_GITHUB_TOKEN") ;; esac
  curl -fsSL --retry 2 -H "User-Agent: ft-desktop-widgets-installer" ${auth[@]+"${auth[@]}"} "$RELEASES_URL" -o "$tmp/releases.json" || return 1
  FT_JSON="$tmp/releases.json" osascript -l JavaScript -e '
    ObjC.import("Foundation");
    var env = $.NSProcessInfo.processInfo.environment;
    var path = ObjC.unwrap(env.objectForKey("FT_JSON"));
    var text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
    (function () {
    var best = null, bestV = null;
    JSON.parse(text).forEach(function (r) {
      var m = /^macos-v(\d+)\.(\d+)\.(\d+)$/.exec(r.tag_name || "");
      if (!m || r.draft || r.prerelease) return;
      var zip = (r.assets || []).filter(function (a) { return /\.zip$/.test(a.name); })[0];
      if (!zip) return;
      var v = [+m[1], +m[2], +m[3]];
      var newer = !bestV || v[0] > bestV[0] || (v[0] == bestV[0] && (v[1] > bestV[1] || (v[1] == bestV[1] && v[2] > bestV[2])));
      if (newer) { best = r; bestV = v; }
    });
    if (!best) return "";
    var zip = best.assets.filter(function (a) { return /\.zip$/.test(a.name); })[0];
    var sums = best.assets.filter(function (a) { return a.name == "SHA256SUMS"; })[0];
    return [best.tag_name, zip.name, zip.browser_download_url, zip.digest || "", sums ? sums.browser_download_url : ""].join("|");
    })()
  ' 2>/dev/null
}

# Installs the native app. Returns non-zero with a message in $why when it cannot (the caller falls back).
# A checksum mismatch exits the whole script instead: it is never a reason to fall back.
install_native() {
  local rel tag zname zurl zdigest surl
  rel="$(find_release)" || { why="could not look up the releases"; return 1; }
  [ -n "$rel" ] || { why="no macos-v* release with a .zip was found"; return 1; }
  IFS='|' read -r tag zname zurl zdigest surl <<<"$rel"
  echo "Flying Tulip menu bar app ${tag#macos-v} ($tag)"

  curl -fsSL "$zurl" -o "$tmp/$zname" || { why="the download failed"; return 1; }

  # Expected hash: the release's SHA256SUMS, else the digest GitHub publishes for the asset.
  local want=""
  if [ -n "$surl" ]; then
    curl -fsSL "$surl" -o "$tmp/SHA256SUMS" || { why="could not download SHA256SUMS"; return 1; }
    want="$(awk -v n="$zname" '{f=$2; sub(/^\*/,"",f); if (f==n) print tolower($1)}' "$tmp/SHA256SUMS" | head -1)"
  elif [ "${zdigest#sha256:}" != "$zdigest" ]; then
    want="$(printf '%s' "${zdigest#sha256:}" | tr '[:upper:]' '[:lower:]')"
  fi
  [ -n "$want" ] || { why="the release publishes no checksum for $zname"; return 1; }
  if [ "$(sha256_of "$tmp/$zname")" != "$want" ]; then
    echo "Checksum mismatch for $zname. Nothing was installed. Try again later, and report it if it keeps happening." >&2
    exit 1
  fi
  echo "Checksum verified (sha256)."

  mkdir -p "$tmp/x"
  ditto -x -k "$tmp/$zname" "$tmp/x" || { why="the archive could not be unpacked"; return 1; }
  [ -d "$tmp/x/$APP_NAME" ] || { why="the archive has no $APP_NAME"; return 1; }
  [ "$(defaults read "$tmp/x/$APP_NAME/Contents/Info" CFBundleIdentifier 2>/dev/null || true)" = "$BUNDLE_ID" ] || { why="the app has an unexpected bundle identifier"; return 1; }
  codesign --verify --deep "$tmp/x/$APP_NAME" 2>/dev/null || { why="the app's code signature is invalid"; return 1; }

  local destdir="/Applications"
  if [ ! -w "$destdir" ]; then
    destdir="$HOME/Applications"
    mkdir -p "$destdir"
  fi
  local dest="$destdir/$APP_NAME"

  # Quit a running copy so it is replaced in place.
  if pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null 2>&1; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null 2>&1 || break; sleep 1; done
  fi
  rm -rf "$dest" 2>/dev/null || { why="could not replace $dest"; return 1; }
  ditto "$tmp/x/$APP_NAME" "$dest" || { why="could not copy the app to $destdir"; return 1; }

  # Files fetched with curl are not quarantined, so Gatekeeper stays quiet. If something added the flag anyway, drop it:
  # the app is not notarized yet and the checksum above has just been verified.
  if xattr -p com.apple.quarantine "$dest" >/dev/null 2>&1; then
    echo "Removing the download quarantine flag (the app is not notarized yet; its checksum was verified above)."
    xattr -dr com.apple.quarantine "$dest" || true
  fi
  echo "Installed $dest"

  open "$dest" || echo "Could not open it automatically. Open it from $destdir (right-click, Open, if macOS asks)."
  local n
  for n in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null 2>&1 && break; sleep 1; done
  echo "Flying Tulip lives in the menu bar (the tulip, top right; there is no Dock icon). Click it, then the gear to add your wallets."
  return 0
}

# Offers to remove an old xbar / SwiftBar Flying Tulip plugin so there are not two Flying Tulip items.
old_plugins() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && [ -f "$d/$PLUGIN_NAME" ] && printf '%s\n' "$d/$PLUGIN_NAME"
  done < <(plugin_dirs)
  return 0
}

offer_plugin_removal() {
  local found=() f
  while IFS= read -r f; do [ -n "$f" ] && found+=("$f"); done < <(old_plugins)
  [ "${#found[@]}" -gt 0 ] || return 0
  echo "The old xbar/SwiftBar plugin is also installed, so you would see two Flying Tulip items."
  local answer="n"
  if [ "${FT_REMOVE_XBAR:-}" = "1" ]; then
    answer="y"
  elif { true </dev/tty; } 2>/dev/null; then
    printf 'Remove the plugin now? [y/N] ' >/dev/tty
    read -r answer </dev/tty || answer="n"
  fi
  case "$answer" in
    y|Y|yes|YES)
      for f in "${found[@]}"; do rm -f "$f" && echo "Removed $f"; done
      open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true
      open -g "swiftbar://refreshallplugins" 2>/dev/null || true
      ;;
    *)
      for f in "${found[@]}"; do echo "  To remove it:  rm '$f'"; done
      ;;
  esac
}

main() {
  case "$WIDGET" in
    xbar) install_plugin; exit 0 ;;
    auto|native) ;;
    *) echo "FT_WIDGET must be auto, native or xbar (it is '$WIDGET')." >&2; exit 1 ;;
  esac

  why=""
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if [ "$WIDGET" = "auto" ] && [ "${major:-0}" -lt 13 ]; then
    echo "Using the xbar/SwiftBar plugin instead of the native app: this is macOS $(sw_vers -productVersion), the app needs macOS 13 or later."
    install_plugin
    exit 0
  fi

  if install_native; then
    offer_plugin_removal
    exit 0
  fi

  if [ "$WIDGET" = "native" ]; then
    echo "The native app could not be installed: $why." >&2
    exit 1
  fi
  echo "Could not install the native app: $why."
  echo "Using the xbar/SwiftBar plugin instead (force the app with FT_WIDGET=native to see the error)."
  install_plugin
}

main
