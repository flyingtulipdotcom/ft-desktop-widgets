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

## Set your wallets

Any one of these:

- **From the dropdown**: *Add a wallet…* (bottom, and in the Account submenu) opens a small dialog for one address;
  *Wallets…* edits the whole list (comma separated); *Remove 0x…* in the Account submenu drops the wallet shown.
  Saved one per line in `~/Library/Application Support/FlyingTulip/menubar-wallet`.
- **Plugin settings window** (xbar: click the plugin in the menu bar > *Open plugin...*, or the plugin's entry in the
  xbar settings; SwiftBar: plugin entry > *Preferences*). Paste one address or several, comma separated, into
  **VAR_WALLET**. When not empty it wins over the file above.
- Clear them by emptying both. Market data keeps working without a wallet.

Only public addresses (0x + 40 hex characters) are ever needed.

## Several wallets

- The menu bar shows one wallet at a time and the next one every minute (each run of the plugin). With more than one
  wallet the title ends with the shown wallet's short address and ⇄. *Next wallet ⇄* at the top of the dropdown
  switches at once, and the Account submenu lists every wallet: click one to show it.
- If any wallet's health factor is at or below `VAR_HF_WARN`, that wallet is shown in the same run and stays shown
  while it is low (*Next wallet* peeks at the others, the next run comes back). The notification names the wallet.
- The wallets you are not looking at are checked in the background: their health factor (`/mm/lend`) every run while
  they have debt, every 10 minutes otherwise. Everything else is fetched for the wallet shown only.

## The dropdown

Three submenus instead of one long list: **Market** (price, fees, both charts), **Account** (the shown wallet's health
factor per chain, PnL, FT earned with its breakdown, points per chain and rank, ftPUT, and the wallet list) and
**Positions**. Each submenu's title line already carries the main numbers.

## Settings

| variable | default | meaning |
|---|---|---|
| `VAR_WALLET` | empty | public addresses to show, comma separated |
| `VAR_HF_WARN` | `1.40` | warning notification at or below this health factor |
| `VAR_HF_CRITICAL` | `1.30` | critical notification at or below this health factor (keep it above 1.25) |
| `VAR_NOTIFICATIONS` | `true` | show macOS notifications; `false` keeps only the coloured title |
| `VAR_NOTIFY_COOLDOWN_MIN` | `30` | minimum minutes between two notifications of the same level |
| `VAR_PRICE_CHAIN` | `1` | chain of the FT-ftUSD market price: `1` Ethereum or `146` Sonic |
| `VAR_ANALYTICS` | `true` | Advanced: anonymous usage stats, `false` turns them off (see "Anonymous usage stats") |

The file carries both the xbar metadata (`<xbar.var>`) and the SwiftBar one (`<swiftbar.environment>`). If your SwiftBar
shows every setting twice, delete the `<swiftbar.environment>` line.

## What each number is

- **FT price**: FT-ftUSD market price (`/mm/spot/tickers`), 30-day line from `/mm/spot/market/klines`. A market price,
  not the NAV used for accounting.
- **Fees**: last 24h application fees (`/fees/application`), 31-day bars, and the day-over-day change between the last
  two finished days.
- **HF**: lowest `healthFactor` among your chains that carry debt (`/mm/lend?user=`). No debt shows `∞`.
- **PnL**: sum of `unrealizedPnl` over chains (`/mm/spot/account/summary`).
- **FT earned**: all time and all chains. sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending)
  (`/account/dashboard?view=rewards`). The dropdown splits it by source and by chain. It is what the wallet's sftUSD
  staking and Lend supply have paid out over time, so it does not follow the wallet's current size: a small wallet
  that staked sftUSD for months can show more than a large wallet that only started supplying Lend last week. FT held
  in ftPUTs is not counted.
- **Points / rank**: the all-chains total from `/points` (the same number the leaderboard ranks), split per chain in
  the dropdown, and the all-chains rank found in `/points/leaderboard` (searched at most every 10 minutes). The big
  number on flyingtulip.com/rewards is one chain at a time (the chain picker in the site header), and the all-networks
  total is the small line under it.
- **ftPUT gain**: from `/tge/ftPUT/user/<wallet>`: FT held x FT market price minus cost basis, also as a percentage.
- **Positions**: `/mm/spot/account/positions` per chain.

## Liquidation alerts

Positions can be liquidated while the health factor is below 1.25. A warning fires at or below `VAR_HF_WARN`, a critical
alert at or below `VAR_HF_CRITICAL`; each fires once per upward crossing, with a 0.05 hysteresis and a cooldown per level.
Alert state is kept per wallet in `~/Library/Caches/com.flyingtulip.menubar/state.json`, so it survives restarts. Alerts are only
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

## Anonymous usage stats

To learn how the widgets are used, the plugin sends a few anonymous events to [Plausible](https://plausible.io)
(`https://plausible.io/api/event`, site "widget"). **No wallet address, balance, position, health factor or any other
account data is ever sent.** Each event is one small background `curl`, fire and forget: if it fails, nothing changes
in the menu. The menu bar plugin cannot see the dropdown being opened or a submenu being shown, so it sends no
"Panel open" or "Tab view"; while usage stats are on, a link runs the plugin once (the click is counted) and then
opens the page.

**Turn it off**: *Settings > Advanced > Anonymous usage stats* in the dropdown, or set **VAR_ANALYTICS** to false in the
plugin settings. Nothing is sent while it is off.

| Event | When | Values sent with it |
|---|---|---|
| pageview | at launch (Windows, Omarchy) and once a day while it runs (all three) | `os` (e.g. "Windows 11", "macOS 15", "Arch Linux"), `host` (Rainmeter version, xbar or SwiftBar, Quickshell), `walletsConfigured` (0, 1, 2 or 3+) |
| Panel open | the panel is opened (Omarchy), the mouse comes over the skin, at most once per 30 minutes (Windows) | |
| Tab view | a tab is picked (Windows, Omarchy) | `tab`: market, account or positions |
| Link click | an element that opens flyingtulip.com is clicked | `element` (see below), `url` (the page opened; any wallet address in it is replaced by ":address") |
| Wallet switch | the switch icon or "Next wallet" is used (not the automatic rotation) | |
| Settings open | the wallet settings are opened | |
| Wallet added, Wallet removed | a wallet is added or removed (never which one) | |
| HF alert shown | a health factor notification is shown | `level`: warning or danger (never the value or the wallet) |
| Refresh | the refresh button is used | |
| Fetch error | an API call fails, at most once an hour per endpoint | `endpoint`: ticker, fees, klines, lend, summary, positions, rewards, points, leaderboard, ftput |

Every event also carries `platform` (windows, macos or omarchy) and `version`. Each event name is sent at most 30 times
an hour. Element ids, the same on every platform where the element exists: `header-logo`, `header-title`,
`header-wallet`, `header-status`, `header-open-site`, `menu-open-site`, `banner-hf`, `tabs-rule`, `market-header`,
`market-ft-price`, `market-fees`, `market-day-over-day`, `market-fees-chart`, `market-price-chart`, `account-header`,
`account-hint`, `account-wallets-note`, `account-hf`, `account-hf-<chain>` (e.g. `account-hf-sonic`), `account-pnl`,
`account-ft-earned`, `account-ft-earned-detail`, `account-ft-earned-chart`, `account-ft-earned-daily`, `account-points`,
`account-points-detail`, `account-points-positions`, `account-ftput`, `account-ftput-positions`, `positions-header`,
`positions-card`, `positions-row`, `positions-more`, `positions-empty`, `footer-updated`, `footer-open-site`,
`footer-disclaimer`.

## Disclaimer, license

Informational only, not financial advice; figures can be delayed, incomplete or wrong; provided "as is" (see
[../LICENSE](../LICENSE)). MIT. The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by
the MIT license.
