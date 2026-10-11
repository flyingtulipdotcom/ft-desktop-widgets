# Testing the Rainmeter skin

## Covered on Linux

- `lua5.1 test/run.lua` loads the skin the way Rainmeter 4.5 does, using `test/rainmeter.lua`, a small stand-in
  written from Rainmeter's source rather than from the skin's assumptions:
  - `Main.ini` and its includes are read, and the script runs in its own environment. `SKIN` is set only after the
    file has run, then `Initialize()` is called. This is the load order that broke v1.0.0, and the stand-in
    reproduces the same two errors Rainmeter logged.
  - WebParser measures are only read through the option names Rainmeter knows. They fetch on their `UpdateRate`
    counter, put the `RegExp` capture into the string value, then run `FinishAction`. A connection error runs
    `OnConnectErrorAction`, and `!CommandMeasure <measure> "Update"` forces a refetch.
  - Bangs from Lua and from actions run as they would in Rainmeter: `!SetOption` (an empty value deletes the option),
    `!WriteKeyValue`, `!EnableMeasureGroup` and the others, plus `[\NNNN]` character references.
  - The InputText box can be opened with `ExecuteBatch N` (only CommandN runs, and its `DefaultValue=""` override is
    honoured), typed into and dismissed. `#SETTINGSPATH#` can point at a test folder.
- The tests then drive it with recorded API payloads (`test/fixtures`, including a trimmed real `/mm/lend`). They check:
  - the load order and the wallet list flow, from the cog, the Wallets button and the right-click menu (add, edit the
    list, remove the wallet shown, empty clears)
  - several wallets: the header ("0x1111..1111  1/2"), the switch icon, rotation every `RotateSeconds`, values kept
    per wallet, the background health check of hidden wallets (one at a time, every 10 minutes without debt), a hidden
    wallet going low shown at once with a toast naming it and kept shown while low, a 1.0.x `Wallet=` and
    `State.txt` carried over, wallets restored from the copy outside the skin folder
  - tabs: one tab's meters at a time, the choice written to `Settings.inc` and restored, header and footer always
    shown, every meter above the footer (nothing cut off), Account rows on one grid with no hole where a detail
    line is empty
  - FT earned and points broken down on the Account tab (sftUSD yield and Lend, per chain; points per chain, rank)
  - the JSON decoder, including skipped keys, and a 500 KB `/mm/lend` body
  - every parser, the formatting, the alert state machine
  - no wallet, a full wallet, no debt (the infinity sign, `/mm/lend` slowed to every 10 minutes), positions answered
    with `null`
  - rank search (one forced fetch per page, a stale page ignored), amber and red warnings, one toast per crossing,
    state surviving a reload
  - a bad payload keeping the last value, stale/offline/connection-error states, invalid wallet, API text not
    injecting `#`, `[` or `]`, `SetWallet`
  - a Lua error showing on the skin
- `FT_SKIN_DIR=<folder> lua5.1 test/run.lua` runs the same tests against another copy of the skin. Against the v1.0.0
  release they fail with `Script Initialize() failed: FlyingTulip.lua:497: attempt to index upvalue 'SK' (a nil value)`.
- `lua5.1 test/live.lua [0xA,0xB]` runs the skin against the live public API (curl) and prints every meter, for each
  wallet in turn.
- `node test/lint.js` checks:
  - INI structure and cross references
  - every WebParser and InputText option is one Rainmeter reads (a misspelt action is silently ignored)
  - in-memory fetch with the whole-body RegExp and the cache bypassed
  - every measure maps to a Lua key and back
  - `SKIN` is read only inside `Initialize()`
  - the Lua file is ASCII, has valid Lua 5.1 syntax and no 5.2+ constructs
  - scrub, and static checks of `Notify.ps1`
- `node tools/build_rmskin.js` builds the `.rmskin` (zip plus footer) and refuses to package a `Settings.inc` that has
  a wallet set.

## Real Rainmeter on a Windows runner (CI)

`.github/workflows/windows-screenshot.yml` runs on every change under `rainmeter/`: it installs the latest Rainmeter on
a GitHub Windows runner, loads the skin with a public wallet from the points leaderboard (usage stats off, and the
Plausible host blocked), waits for the data, and captures the skin's own window with `PrintWindow` for each tab. The
screenshots are published on the `ci-screenshots` branch and shown in the run summary and on the pull request; the
job fails if the skin window is missing or the Rainmeter log has a script or WebParser error. (A plain desktop capture
comes out blank on the runner, which is why the window itself is captured.)

## Real Rainmeter under Wine (v1.0.1)

Rainmeter 4.5.27 (portable install) ran headless under a portable Wine build and Xvfb. The skin had a temporary probe
added that wrote the meter texts to the log. With no wallet, the market rows filled in within about 15 seconds
("updated", price, fees, both chart labels). The probe then called `SetWallet`:
- `!WriteKeyValue` wrote `Settings.inc`
- the skin refreshed
- health factor, PnL, FT earned, points with rank (found by the leaderboard search), ftPUT and positions all filled
  from the live API

There were no script or WebParser errors. Under the same setup, v1.0.0 logged `Script Initialize() failed ... 'SK'
(a nil value)` and then `!CommandMeasure failed ... 'cfg' (a nil value)`.

Wine could not cover everything:
- **Drawing:** Wine on Xvfb draws Rainmeter's layered windows blank, so nothing was seen.
- **The InputText box:** it is a .NET plugin, and Mono was not installed, so the box was not shown. The wallet was set
  through the same `SetWallet` call that its `Command1` makes.

## Not runnable here (needs Windows)

- Rendering: layout, fonts (Segoe UI, Consolas), the Shape charts, hover colours, the amber/red border, DPI scaling,
  and the `[\8734]` infinity sign.
- The InputText box itself: where it appears, focus, Enter and Escape.
- `Notify.ps1`: no PowerShell here, so the toast has not been shown. It is the common WinRT toast recipe using Windows
  PowerShell's own AppUserModelID.

## How to test on Windows

1. Install Rainmeter 4.5+, then run `irm https://raw.githubusercontent.com/flyingtulipdotcom/ft-desktop-widgets/main/rainmeter/install.ps1 | iex`
   (or open the `.rmskin` from the latest release). Within a few seconds the price, fees and both charts appear and the
   header says "updated HH:MM". Rainmeter's log (*Manage > Log*) shows any WebParser or Lua error.
2. Click the **cog** (top right), paste a wallet that has debt, press Enter. The skin reloads and fills the Account
   tab. Right-click > *Add a wallet...*, add a second one: the header shows "1/2" and the switch icon; click it.
   Click the three tabs; refresh the skin and check the last tab comes back.
3. Force an alert: in `Settings.inc` set `HfWarn=9` and `HfCritical=8`, refresh the skin. The border and banner turn red
   and one toast appears. Refreshing again does not repeat it (delete `@Resources\State.txt` to re-arm). Put the
   values back.
4. Run the toast alone from PowerShell: write three lines (title, body, `critical`) into a text file and run
   `powershell -NoProfile -ExecutionPolicy Bypass -File Notify.ps1 path\to\that.txt`.
5. Disconnect the network and wait three refresh intervals: values dim and the header says "stale".
