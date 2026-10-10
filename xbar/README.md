# Flying Tulip for the macOS menu bar (xbar and SwiftBar)

One plugin file, [`Cryptocurrency/FlyingTulip/flyingtulip.1m.sh`](Cryptocurrency/FlyingTulip/flyingtulip.1m.sh), that
works unchanged in [xbar](https://xbarapp.com) and [SwiftBar](https://github.com/swiftbar/SwiftBar). Refreshes every
minute (the `1m` in the file name).

Menu bar: the Flying Tulip logo, FT price, 24h fees and, when a wallet is set, health factor:

    [tulip] $0.1502  fees $954  HF 1.92

The title turns amber at or below the warning health factor and red at or below the critical one, and a macOS
notification is shown on each crossing. The dropdown groups the rest: market (price, fees by product, 31-day fees bars,
30-day FT price line), account (health factor per chain, PnL, FT earned, points and rank, ftPUT gain, positions),
refresh, "Open flyingtulip.com", and "Set wallet...".

Data comes only from `https://api.flyingtulip.com`. No keys, no RPC.

## Install

1. Install xbar or SwiftBar.
2. Copy `flyingtulip.1m.sh` into the app's plugin folder (xbar: *Open plugin folder...* in its menu; SwiftBar: the
   plugin folder you chose on first launch) and make it executable:

       chmod +x flyingtulip.1m.sh

3. Refresh all plugins (xbar: *Refresh all*; SwiftBar: *Refresh All*).

Needs nothing else: stock macOS has bash, curl and osascript. No Homebrew, Node, Python or jq.

## Set your wallet

Any one of these:

- **Plugin settings window** (xbar: click the plugin in the menu bar > *Open plugin...*, or the plugin's entry in the
  xbar settings; SwiftBar: plugin entry > *Preferences*). Paste the address into **VAR_WALLET**.
- **"Set wallet..."** in the dropdown: a small dialog, saved in
  `~/Library/Application Support/FlyingTulip/menubar-wallet`. The plugin setting, when not empty, wins over this file.
- Clear it by emptying both. Market data keeps working without a wallet.

Only a public address (0x + 40 hex characters) is ever needed.

## Settings

| variable | default | meaning |
|---|---|---|
| `VAR_WALLET` | empty | public address to track |
| `VAR_HF_WARN` | `1.40` | warning notification at or below this health factor |
| `VAR_HF_CRITICAL` | `1.30` | critical notification at or below this health factor (keep it above 1.25) |
| `VAR_NOTIFICATIONS` | `true` | show macOS notifications; `false` keeps only the coloured title |
| `VAR_NOTIFY_COOLDOWN_MIN` | `30` | minimum minutes between two notifications of the same level |
| `VAR_PRICE_CHAIN` | `1` | chain of the FT-ftUSD market price: `1` Ethereum or `146` Sonic |

The file carries both the xbar metadata (`<xbar.var>`) and the SwiftBar one (`<swiftbar.environment>`). If your SwiftBar
shows every setting twice, delete the `<swiftbar.environment>` line.

## What each number is

- **FT price**: FT-ftUSD market price (`/mm/spot/tickers`), 30-day line from `/mm/spot/market/klines`. A market price,
  not the NAV used for accounting.
- **Fees**: last 24h application fees (`/fees/application`), 31-day bars, and the day-over-day change between the last
  two finished days.
- **HF**: lowest `healthFactor` among your chains that carry debt (`/mm/lend?user=`). No debt shows `∞`.
- **PnL**: sum of `unrealizedPnl` over chains (`/mm/spot/account/summary`).
- **FT earned**: sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending), all chains
  (`/account/dashboard?view=rewards`).
- **Points / rank**: `/points` total and the rank found in `/points/leaderboard` (searched at most every 10 minutes).
- **ftPUT gain**: from `/tge/ftPUT/user/<wallet>`: FT held x FT market price minus cost basis, also as a percentage.
- **Positions**: `/mm/spot/account/positions` per chain.

## Liquidation alerts

Positions can be liquidated while the health factor is below 1.25. A warning fires at or below `VAR_HF_WARN`, a critical
alert at or below `VAR_HF_CRITICAL`; each fires once per upward crossing, with a 0.05 hysteresis and a cooldown per level.
Alert state is kept in `~/Library/Caches/com.flyingtulip.menubar/state.json`, so it survives restarts. Alerts are only
evaluated from a fresh read, never from cached data.

## Offline behaviour

Each source keeps its last good value (also across runs). A value older than 3 minutes is flagged with a warning mark in
the title and a line in the dropdown. With no network and nothing cached the title reads "FT offline". The plugin never
prints an error into the menu bar.

## How it works

stock macOS has `bash` 3.2, `curl` and `osascript` but no `jq` and no guaranteed Node or Python. The plugin is a bash
file (the shape the xbar catalogue accepts and lints) that runs the data logic as JavaScript through `osascript -l
JavaScript` (JXA), which is always present and has `JSON.parse`. It uses no Objective-C bridge: HTTP is parallel
`curl` calls started through StandardAdditions' `do shell script`, notifications are `display notification`. The
charts are tiny PNGs (4-bit palette, 144 dpi, 170x38 pt) generated in the script with no dependency.

## Tests

Run on any machine with Node (they do not need macOS):

    node test/run.js            # unit + end-to-end tests against recorded fixtures
    LIVE=1 WALLET=0x... node test/run.js   # also render once against the live API
    test/e2e.sh [wallet]        # runs the real plugin file through a Linux stand-in for osascript

What is covered and what is not is listed in [TESTING.md](TESTING.md).

## Submitting to the xbar plugin catalogue

See [CATALOGUE.md](CATALOGUE.md).

## Disclaimer, license

Informational only, not financial advice; figures can be delayed, incomplete or wrong; provided "as is" (see
[../LICENSE](../LICENSE)). MIT. The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by
the MIT license.
