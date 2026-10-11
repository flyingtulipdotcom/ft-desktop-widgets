# Flying Tulip for the macOS menu bar (native app)

A native menu bar app: the Flying Tulip logo, FT price, 24h fees and, for the wallets you set, health factor, in the
menu bar. Click it for a panel with three tabs (Market, Account, Positions), the same numbers as the
[xbar/SwiftBar plugin](../xbar) and the Omarchy and Windows widgets.

    [tulip] $0.1502  fees $954  HF 1.92

The title turns amber at or below the warning health factor and red at or below the critical one. Data comes only from
`https://api.flyingtulip.com`: no keys, no RPC, and it never sends a transaction or asks for a key.

Needs macOS 13 or later. Built with SwiftUI (`MenuBarExtra`), Swift Charts and UserNotifications.

## Install

1. Download `FlyingTulip-<version>.dmg` (or the `.zip`) from the
   [releases page](https://github.com/flyingtulipdotcom/ft-desktop-widgets/releases).
2. Open the .dmg and drag **Flying Tulip** to Applications.
3. Open it. The app has no Dock icon: look for the tulip in the menu bar.

### First launch (the app is not notarized yet)

Until the app is signed with an Apple Developer ID, macOS shows "Apple could not verify..." the first time. Either:

- right-click (or Control-click) **Flying Tulip** in Applications, choose **Open**, then **Open** again; or
- try to open it once, then go to **System Settings > Privacy & Security**, scroll to the message about Flying Tulip and
  click **Open Anyway**.

You only do this once. If you prefer not to trust a prebuilt app, build it yourself (below) or use the xbar/SwiftBar
plugin, which is a readable script.

## Set your wallets

Click the gear in the panel. Add one or several public addresses (0x + 40 hex characters). Only public addresses are
ever needed. Market data works without a wallet.

## Several wallets

The menu bar shows one wallet at a time and the next one every minute. With more than one wallet the title ends with
the shown wallet's short address and a switch sign, and the switch button in the panel header jumps to the next one. A
wallet whose health factor is at or below the warning line is shown at once and stays shown while it is low, and its
notification names it. The wallets you are not looking at are checked in the background.

## Settings

- **Wallets**: add and remove.
- **Alerts**: warning and critical health factor (defaults 1.40 and 1.30; liquidation starts below 1.25), notifications
  on or off, and the minimum minutes between two notifications of the same level. Each fires once per upward crossing,
  with a 0.05 hysteresis.
- **Market**: the chain whose FT-ftUSD market price is shown (Ethereum or Sonic).
- **Launch at login**.
- **Advanced > Anonymous usage stats**: on by default, see below.

Settings live in the app's preferences (`defaults read com.flyingtulip.widget`).

## What each number is

The same as in the [xbar README](../xbar/README.md#what-each-number-is). FT is priced at the FT-ftUSD market price
(`/mm/spot/tickers`), never at the NAV used for accounting. Extra panel data, as in the Omarchy panel: the cumulative
"FT earned over time" line and daily bars (`/account/rewards/history`) and the positions earning points
(`/points/breakdown`).

## Anonymous usage stats

The app sends the same few anonymous events as the other widgets to [Plausible](https://plausible.io)
(`https://plausible.io/api/event`, site "widget"): launches and a daily page view, panel opens, tabs and links used,
failed API calls, wallet switches and counts (never which wallet), and the switch itself. **No wallet address, balance,
position, health factor or any other account data is ever sent.** The event names, values and element ids are the ones
in the [xbar README](../xbar/README.md#anonymous-usage-stats), with `platform` "macos" and one extra value, `native`
"true", so the native app can be told apart from the plugin; `host` is "native". At most 30 events of one name an hour.

**Turn it off**: gear > Advanced > Anonymous usage stats. Switching off sends one last event ("Usage stats off") and
nothing after; switching back on sends "Usage stats on". While it is on, pages the app opens on flyingtulip.com carry
the same origin marker as the plugin (`utm_source=ft-widget&utm_medium=macos&utm_content=<element>` and a
`#ftw=macos.<os>.<version>.<element>` anchor); off, the plain URL is opened.

## Build from source

Needs the Xcode command line tools (Swift 5.9 or later) on macOS 13+:

    cd macos
    swift test                      # unit tests
    scripts/build-app.sh            # universal "dist/Flying Tulip.app", ad-hoc signed
    scripts/make-dmg.sh             # dist/FlyingTulip-<version>.dmg and .zip

CI (`.github/workflows/macos-native.yml`) does the same on a macOS runner, screenshots the panel on each tab, and uploads
the .dmg and .zip as artifacts. A signing and notarization job runs only when these repository secrets exist:
`APPLE_DEVELOPER_ID_CERT_P12` (base64 of the Developer ID Application .p12), `APPLE_CERT_PASSWORD`, `APPLE_ID`,
`APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (an app-specific password). With them set, the artifact
`FlyingTulip-macos-notarized` is signed with the hardened runtime, notarized and stapled, and the first-launch step above
is no longer needed.

## Disclaimer

Informational only. This is not financial advice and not a substitute for monitoring your positions yourself. Figures can
be delayed, incomplete or wrong, and a notification can be late or missed (the app can be closed, the API can be down,
the network can be offline). Provided "as is", without warranty of any kind (see [LICENSE](../LICENSE)). The Flying Tulip
name and logo are trademarks of Flying Tulip and are not covered by the MIT license.
