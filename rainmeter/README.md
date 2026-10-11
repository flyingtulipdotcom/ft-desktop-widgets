# Flying Tulip for Windows (Rainmeter)

A [Rainmeter](https://www.rainmeter.net) skin that puts Flying Tulip on your desktop: FT market price, 24h application
fees with a 31-day bar chart and a 30-day FT price line and, for the wallets you set, health factor with liquidation
alerts, PnL, FT earned, points and rank, ftPUT gain and open positions. Dark panel with the Flying Tulip purple accent,
in three tabs (Market, Account, Positions) so nothing is cut off; the skin remembers the last tab.

Data comes only from `https://api.flyingtulip.com`. No keys, no RPC.

## Install

- **One line** (PowerShell): `irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex`
  downloads the latest release's `.rmskin` and opens Rainmeter's installer.
- **Package**: download `FlyingTulip-<version>.rmskin` from the latest release (or build it with
  `node tools/build_rmskin.js`, needs Node and `zip`), open it with Rainmeter and click Install. Your `Settings.inc` is kept when you install a newer version.
- **By hand** (always works): copy `Skins/FlyingTulip` into `Documents\Rainmeter\Skins\`, then in Rainmeter *Refresh
  all* and load `FlyingTulip\Main.ini`.

Needs Rainmeter 4.5 or later (the Shape meter and the bundled WebParser and InputText plugins). The toast notification
needs Windows 10 or later with Windows PowerShell 5.1 (preinstalled).

## Set your wallets

- Click the **cog** at the top right of the skin (or **Wallets** at the bottom, or right-click the skin > *Wallets and
  settings...*). A box opens with your wallet list: add, change or remove addresses (comma separated) and press Enter.
  Each is validated (0x + 40 hex characters), written lowercase to `@Resources\Settings.inc`, and the skin reloads.
  An empty box clears every wallet.
- Right-click > *Add a wallet...* opens an empty box for one more address. *Remove the wallet shown* drops the one on
  screen. *Edit the settings file* opens `Settings.inc` for the alert thresholds and refresh times.

The InputText plugin that draws the input box ships with Rainmeter. Only public addresses are ever needed.

Your wallets survive updates: Rainmeter keeps `Settings.inc` values when a newer `.rmskin` is installed, and the skin also
keeps a copy outside its own folder (`FlyingTulip-wallets.txt` in Rainmeter's settings folder) that it reads back if
the skin folder is ever replaced. A 1.0.x `Wallet=` is still read.

## Several wallets

- The skin shows one wallet at a time (its short address and "1/2" under the title) and the next one every minute
  (`RotateSeconds`). The switch icon next to the address, or right-click > *Show the next wallet*, switches at once.
- If any wallet's health factor is at or below `HfWarn`, that wallet is shown at once and stays shown while it is low
  (switching peeks at the others; the next minute it comes back). The toast names the wallet.
- The wallets that are not shown are checked in the background, one request at a time: their health factor
  (`/mm/lend`) every `RefreshSeconds` while they have debt, every 10 minutes otherwise. Everything else is fetched
  for the wallet shown only.

## Settings (`@Resources\Settings.inc`)

| variable | default | meaning |
|---|---|---|
| `Wallets` | empty | public addresses to show, comma separated |
| `Wallet` | empty | the single wallet of 1.0.x, still read (the skin keeps it equal to the first one) |
| `RotateSeconds` | `60` | seconds each wallet is shown before the next one (minimum 10) |
| `HfWarn` | `1.40` | warning at or below this health factor |
| `HfCritical` | `1.30` | critical at or below this health factor (keep it above 1.25) |
| `NotifyCooldownMin` | `30` | minimum minutes between two notifications of the same level |
| `Notifications` | `1` | `1` shows a Windows toast on a crossing, `0` keeps only the on-skin warning |
| `PriceChainId` | `1` | chain of the FT-ftUSD market price: `1` Ethereum or `146` Sonic |
| `RefreshSeconds` | `60` | seconds between refreshes (minimum 15) |
| `Tab` | | the tab last shown (written by the skin when you click a tab) |
| `Analytics` | `1` | Advanced: anonymous usage stats, `0` turns them off (see "Anonymous usage stats") |

## Liquidation alerts

Positions can be liquidated while the health factor is below 1.25. At or below `HfWarn` the skin border turns amber and a
banner shows the health factor; at or below `HfCritical` both turn red. Each level also shows one Windows toast (a short
PowerShell script, `@Resources\Notify.ps1`), once per upward crossing with a 0.05 hysteresis and a cooldown per level.
The alert state is saved per wallet in `@Resources\State.txt`, so reloading the skin does not repeat a notification. The on-skin
warning is always shown, so the skin still warns you if toasts are blocked (Focus Assist, group policy) or turned off.

## What each number is

The same as in the macOS plugin: see [../xbar/README.md](../xbar/README.md#what-each-number-is). FT price is the
FT-ftUSD market price, never the NAV used for accounting. "FT earned, all time" and "Points, all chains" show their
breakdown when you hover them: FT earned split into sftUSD yield and Lend FT rewards and by chain, points per chain
and the leaderboard rank. FT earned is what the wallet's sftUSD staking and Lend supply have paid out over time, so a
smaller wallet can show more than a larger one. flyingtulip.com/rewards shows points for one chain at a time, with the
all-networks total in the small line under it.

## How it works

WebParser measures (`@Resources\Data.inc`, generated by `tools/gen_data_inc.sh`) fetch each endpoint into memory:
`RegExp=(?s)^(.*)$` captures the whole JSON body as the measure's string value, and `FinishAction` calls the Lua script
(`@Resources\Lua\FlyingTulip.lua`), which reads it with `SKIN:GetMeasure(name):GetStringValue()`, decodes it with a
small built-in decoder, computes everything and sets the text and chart shapes. Nothing is written to disk. The
`/mm/lend` answer is about 500 KB: the decoder skips the parts the skin never reads (chart series, asset lists), and
while nothing is borrowed on any chain it is fetched every 10 minutes instead of every `RefreshSeconds`.
If the script hits an error, the header says "script error, see log" and Rainmeter's log (*Manage > Log*) has the
details. Wallet measures start disabled and are enabled only when a valid wallet is set. Charts are
Shape meters (rectangles for the bars, a path with a filled area for the line), drawn by Lua.

## Offline behaviour

A value that has not refreshed for 3 intervals dims and the header says "stale HH:MM". A response that is not valid JSON
or has an unexpected shape is ignored and the last good value stays. With nothing received for 20 seconds the header says
"offline".

## Tests

Linux or anywhere with Lua 5.1 and Node (no Rainmeter needed):

    lua5.1 test/run.lua     # the skin loaded the way Rainmeter loads it (test/rainmeter.lua), recorded API payloads
    lua5.1 test/live.lua [0x...]   # the same against the live public API, prints every meter
    node test/lint.js       # INI structure, meter and measure cross references, Lua 5.1 syntax, scrub

What is and is not covered: [TESTING.md](TESTING.md).

## Anonymous usage stats

To learn how the widgets are used, the skin sends a few anonymous events to [Plausible](https://plausible.io)
(`https://plausible.io/api/event`, site "widget"). **No wallet address, balance, position, health factor or any other
account data is ever sent.** Each event is one small request from a hidden PowerShell (`@Resources\UsageStats.ps1`),
fire and forget: if it fails, nothing changes on the skin.

**Turn it off**: right-click the skin > *Advanced: anonymous usage stats on or off*, or set `Analytics=0` in
`Settings.inc` (under Advanced settings). Nothing is sent while it is off.

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

Informational only, not financial advice; figures can be delayed, incomplete or wrong; notifications can be late or
missed; provided "as is" (see [../LICENSE](../LICENSE)). MIT. The Flying Tulip name and logo are trademarks of Flying
Tulip and are not covered by the MIT license.

## Links

Every meter opens its page on flyingtulip.com: the header and footer open the home page, the FT price
meters and chart the FT-ftUSD spot market on the chain you set in `PriceChainId`, fees and the fees chart
the statistics page, health factor the lend dashboard, PnL and positions the trade portfolio (each position
row opens that market on its own chain), FT earned the rewards page, points the leaderboard and ftPUT the
ftPUT positions page.
