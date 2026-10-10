# Testing the xbar / SwiftBar plugin

## Covered on Linux (`node test/run.js`, `test/e2e.sh`)

- Number formatting, wallet normalisation, all parsers against the recorded live shapes (price, fees, fee series, klines).
- Lowest health factor across chains, infinity with no debt.
- Alert state machine: once per upward crossing, hysteresis, cooldown, survives the JSON state round trip.
- End to end with a fake I/O layer: no wallet (and no account calls made), full wallet, invalid wallet, notifications
  on/off, warning then critical, stale fallback after API failure, "FT offline", slow-source caching (10 min), wallet
  change resets state, Sonic price fallback, pipes and newlines in API text, the "Set wallet" prompt.
- Output validated against the xbar plugin API in CONTRIBUTING.md (separator, submenu depth, known parameters, base64
  images, no stray pipes).
- Both PNG chart generators produce valid PNGs (chunk CRCs, zlib/adler32 via Node's `zlib`, IHDR size, palette depth);
  the logo is a PNG.
- The plugin file itself: executable, bash shebang, required xbar metadata, six `VAR_*` settings all passed through,
  `bash -n`, `shellcheck` clean with the catalogue's own exclusion list, scrub (no internal hosts or real wallets).
- `test/e2e.sh` runs the real `.sh` through `test/osascript-shim.js`, a stand-in that evaluates the embedded JavaScript
  in a bare `vm` context with `Application.currentApplication().doShellScript` (including macOS's `\n` to `\r`
  conversion), against the live API: parallel curl, state file, the "Set wallet" flow and the wallet file are real.
- A live run with a wallet that has real debt and positions (HF, per-chain rows, rank search) rendered and validated.

## Not runnable here (needs a Mac)

- Real menu bar rendering in xbar and in SwiftBar: logo size, title colour, Menlo alignment, dark and light mode,
  chart image scale (the PNGs carry 144 dpi so they should show at 170x38 pt; not seen).
- That `osascript -l JavaScript -e <script> <args>` hands the arguments to `run(argv)` and prints the return value as
  expected on the macOS versions you support (the plugin merges stderr into stdout to be safe).
- `do shell script` behaviour on macOS (the shim imitates it) and non-ASCII API text.
- Notifications: `display notification` appears under "Script Editor" on current macOS and needs notification
  permission for it the first time; the "Set wallet..." dialog and its activation from a background plugin.
- xbar's settings window picking up the `<xbar.var>` lines, SwiftBar's settings picking up `<xbar.var>` or
  `<swiftbar.environment>` (and whether it shows them twice), and `shell=... param1=wallet terminal=false` from the
  "Set wallet..." item in both apps.
- Run time of one refresh on a real machine (about 4 s for three runs on this Linux box, mostly the 500 KB `/mm/lend`
  response; JXA start-up adds a few hundred ms).

## How to test on a Mac

1. `chmod +x flyingtulip.1m.sh`, drop it in the plugin folder, refresh. You should see the logo, a price and fees.
2. Run it by hand to see the raw output: `./flyingtulip.1m.sh | head`. The first line is the menu bar title.
3. Set the wallet from the plugin settings, or from "Set wallet..." (use a wallet with debt for the HF).
4. Force an alert without a real position: set `VAR_HF_WARN` to a high value such as `9` (and `VAR_HF_CRITICAL` to `8`)
   with a wallet that has debt. A notification appears on the next refresh, once.
   Reset them afterwards. Delete `~/Library/Caches/com.flyingtulip.menubar/state.json` to re-arm.
5. Go offline (turn Wi-Fi off) and refresh: the title keeps the last values with a warning mark.
6. Check dark and light menu bars, and a Retina and non-Retina display.
