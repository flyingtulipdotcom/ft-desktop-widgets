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
| Windows | Rainmeter skin | [`rainmeter/`](rainmeter) |

## Install on macOS

Two ways, the same data and alerts:

1. **Native app** (macOS 13 or later): download the `.dmg` from the [releases page](https://github.com/flyingtulipdotcom/ft-desktop-widgets/releases) (look for `macos-v…`), drag Flying Tulip to Applications and open it. It is not notarized yet, so the first time use right-click > Open, or System Settings > Privacy & Security > Open Anyway. Details in [macos/README.md](macos/README.md).
2. **xbar or SwiftBar plugin**: one script, see [xbar/README.md](xbar/README.md).

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
