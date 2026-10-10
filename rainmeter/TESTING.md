# Testing the Rainmeter skin

## Covered on Linux

- `lua5.1 test/run.lua` loads the real `FlyingTulip.lua` (Lua 5.1, the version Rainmeter embeds) with a mock `SKIN`
  object and feeds it files like WebParser's `Download=1` writes. It checks: the JSON decoder (escapes, surrogate
  pairs, 20 000 rows, malformed input), every parser against recorded live shapes, formatting, lowest health factor,
  the alert state machine, and the skin behaviour: no wallet (account measures disabled, hint shown), full wallet
  (every row, colours, wallet measures enabled), the leaderboard rank search (page 7 empty, then page 2, found), amber
  and red warning states, one toast per crossing, state surviving a reload, toasts off, a bad payload keeping the last
  value, stale and offline states, invalid wallet, API text not injecting `#` / `[` / `]`, and `SetWallet`
  (validation, `Settings.inc` write, download cleanup, refresh). Mutating the code (alert comparison, ftPUT price)
  makes it fail.
- `node test/lint.js`: INI structure (sections, duplicate keys), that every meter the Lua sets and every bang target
  exists, that every download measure maps to a key and file the Lua knows (and the other way round), HTTPS and the
  public host only, wallet measures start disabled in group `Account`, Lua 5.1 syntax with `luac5.1 -p` and no 5.2+
  constructs, scrub, and static checks of `Notify.ps1`.
- `node tools/build_rmskin.js` builds the `.rmskin` (zip plus footer), refusing to package a `Settings.inc` that has a
  wallet set. The archive lists correctly with `unzip -l`.

## Not runnable here (needs Windows and Rainmeter)

- Any rendering: layout and spacing, fonts (Segoe UI, Consolas), the Shape-based bar and line charts, the hover colours,
  the amber/red border, transparency, DPI scaling.
- WebParser actually downloading with `Download=1` over HTTPS from this API, the `FinishAction` and error action names
  (`OnConnectErrAction`, `OnDownloadErrAction`), `!EnableMeasureGroup` making disabled WebParser measures fetch, and
  `!EnableMeasure` / `!UpdateMeasure` driving the one-page-at-a-time leaderboard search.
- The InputText box, and `!WriteKeyValue` into `Settings.inc` followed by `!Refresh`.
- `Notify.ps1`: no PowerShell here, so the toast has not been shown. It is the common WinRT toast recipe using Windows
  PowerShell's own AppUserModelID.
- That Rainmeter accepts the `.rmskin` (the footer format and the `RMSKIN.ini` keys follow Rainmeter's packager as
  documented; if the installer rejects it, use the by-hand install).
- `Lua` performance on the roughly 500 KB `/mm/lend` response (the decoder handles 20 000 rows in the tests; the real
  response is parsed once a minute).

## How to test on Windows

1. Install Rainmeter 4.5+. Install `FlyingTulip-1.0.0.rmskin` (or copy `Skins\FlyingTulip` into
   `Documents\Rainmeter\Skins`) and load `FlyingTulip\Main.ini`. Within a few seconds you should see the price, fees and
   both charts. Rainmeter's log (*Manage > Log*) shows any WebParser or Lua error.
2. Click **Set wallet**, paste a wallet that has debt, press Enter. The skin reloads and fills the account rows.
3. Force an alert: in `Settings.inc` set `HfWarn=9` and `HfCritical=8`, refresh the skin. The border and banner turn red
   and one toast appears; refreshing again does not repeat it (delete `@Resources\State.txt` to re-arm). Put the
   values back.
4. Run the toast alone from PowerShell: write three lines (title, body, `critical`) into a text file and run
   `powershell -NoProfile -ExecutionPolicy Bypass -File Notify.ps1 path\to\that.txt`.
5. Disconnect the network and wait three refresh intervals: values dim and the header says "stale".
