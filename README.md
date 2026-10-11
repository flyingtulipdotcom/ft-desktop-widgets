# Flying Tulip desktop widgets

Menu bar and desktop widgets that put [Flying Tulip](https://flyingtulip.com) on your screen:

    [tulip] $0.1502  fees $954  HF 1.92

- **FT price**: the FT-ftUSD market price (the traded mark, never the NAV used for accounting)
- **Application fees**: last 24 hours, with day-over-day change and a 31-day bar chart
- **For the wallets you set (optional, one or several)**: lowest health factor across chains (infinity with no debt;
  liquidation starts below 1.25; a warning notification at or below 1.40 and a critical one at or below 1.30, once per
  crossing with a cooldown), unrealized PnL, FT earned (all time, split into sftUSD yield and Lend rewards), points
  (all chains, split per chain) and rank, ftPUT gain, open positions
- **Several wallets**: one is shown at a time and the next one every minute, with a switch icon to jump to the next one.
  A wallet whose health factor gets low is shown at once and stays shown while it is low, and its notification names it.
  The hidden wallets' health is checked in the background.
- **Laid out to fit**: three tabs on Windows (Market, Account, Positions, the last one remembered), three submenus in
  the macOS dropdown. Settings are one click away: the cog on the Windows skin, "Wallets…" in the macOS dropdown.
- Links to flyingtulip.com: every dropdown line (xbar/SwiftBar) and every meter (Rainmeter) opens its page, e.g. the FT-ftUSD market, statistics, lend dashboard, trade portfolio, rewards and ftPUT. The menu bar title itself only opens the dropdown.

All data comes from the public Flying Tulip API (`https://api.flyingtulip.com`). No API keys, no RPC, no private data.
The widgets only read data for the public address you give them and never send transactions or ask for a key.

| Platform | Widget | Folder |
|---|---|---|
| macOS | Native menu bar app (SwiftUI) | [`macos/`](macos) |
| macOS | xbar and SwiftBar plugin (the alternative) | [`xbar/`](xbar) |
| Windows | Windows 11 Widgets Board widget | [`windows-widget/`](windows-widget) |
| Windows | Rainmeter skin (Windows 10, or no Widgets Board) | [`rainmeter/`](rainmeter) |

## Install

One line per OS. Each picks the native widget when the machine supports it and says why when it falls back.

**Windows** (PowerShell):

    irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex

- Windows 11 with the Widgets Board: installs the native widget from the newest `windows-widget-v*` release. The test
  build is signed with a self-signed certificate, so the script asks for ONE administrator prompt to trust it (it adds
  the certificate to the Trusted People store and nothing else), installs the Windows App Runtime if missing, then the
  package. Add it with **Win+W, Add widgets (+), Flying Tulip**.
- Windows 10, Windows Server, no Widgets Board, a declined administrator prompt, or any failed step: installs the
  Rainmeter skin instead (Rainmeter must be installed), and prints the reason.
- Force one: `$env:FT_WIDGET = "native"` (no fallback, errors are shown) or `$env:FT_WIDGET = "rainmeter"`, set before
  the line above. Re-running upgrades in place.

**macOS** (Terminal):

    curl -fsSL https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/xbar/install.sh | bash

- macOS 13 or later: installs the native menu bar app from the newest `macos-v*` release into `/Applications`
  (`~/Applications` if that is not writable), opens it and tells you it lives in the menu bar. The app is not notarized
  yet; a download made by curl is not quarantined so macOS does not prompt, and the script clears the quarantine flag if
  one is present. If the old xbar/SwiftBar plugin is installed it offers to remove it so you do not get two Flying Tulip
  items (default: keep it and print the `rm` command; `FT_REMOVE_XBAR=1` removes it without asking).
- macOS 12 or older, or any failed step: installs the xbar/SwiftBar plugin instead (xbar or SwiftBar must be installed),
  and prints the reason.
- Force one: `curl -fsSL <url> | FT_WIDGET=xbar bash` (the plugin) or `FT_WIDGET=native` (the app, no fallback).
  Re-running upgrades in place.

Both scripts download from this repository's GitHub releases, verify the files against the release's `SHA256SUMS`
(and stop without installing anything on a mismatch), contain no secrets and send nothing themselves. They are short
enough to read before you run them. Manual install steps are in [macos/README.md](macos/README.md),
[windows-widget/README.md](windows-widget/README.md), [xbar/README.md](xbar/README.md) and
[rainmeter/README.md](rainmeter/README.md).

On Linux, see the [Omarchy bar plugin](https://github.com/flyingtulipdotcom/omarchy-ft-bar).

## Anonymous usage stats

The widgets send a few anonymous events (launches, panel opens, tabs and links used, failed API calls) to Plausible,
with the platform and the widget version. No wallet address, balance, position or other account data is ever sent.
Each widget has an "Anonymous usage stats" switch under its Advanced settings; the full list of events is in
[rainmeter/README.md](rainmeter/README.md#anonymous-usage-stats) and [xbar/README.md](xbar/README.md#anonymous-usage-stats).

## Disclaimer

Informational only. This is not financial advice and not a substitute for monitoring your positions yourself.
Figures can be delayed, incomplete or wrong, and a notification can be late or missed (the app can be closed, the API
can be down, the network can be offline). The software is provided "as is", without warranty of any kind (see
[LICENSE](LICENSE)).

## License and trademarks

MIT, see [LICENSE](LICENSE). The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by the
MIT license: you may use them to refer to Flying Tulip, but not to suggest that a modified or unrelated product is
made or endorsed by Flying Tulip.
