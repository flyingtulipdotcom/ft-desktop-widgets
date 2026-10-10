# Flying Tulip desktop widgets

Menu bar and desktop widgets that put [Flying Tulip](https://flyingtulip.com) on your screen:

    [tulip] $0.1502  fees $954  HF 1.92

- **FT price**: the FT-ftUSD market price (the traded mark, never the NAV used for accounting)
- **Application fees**: last 24 hours, with day-over-day change and a 31-day bar chart
- **For a wallet you set (optional)**: lowest health factor across chains (infinity with no debt; liquidation starts
  below 1.25; a warning notification at or below 1.40 and a critical one at or below 1.30, once per crossing with a
  cooldown), unrealized PnL, total FT earned, points and rank, ftPUT gain, open positions
- Links to flyingtulip.com: every dropdown line (xbar/SwiftBar) and every meter (Rainmeter) opens its page, e.g. the FT-ftUSD market, statistics, lend dashboard, trade portfolio, rewards and ftPUT. The menu bar title itself only opens the dropdown.

All data comes from the public Flying Tulip API (`https://api.flyingtulip.com`). No API keys, no RPC, no private data.
The widgets only read data for the public address you give them and never send transactions or ask for a key.

| Platform | Widget | Folder |
|---|---|---|
| macOS | xbar and SwiftBar plugin | [`xbar/`](xbar) |
| Windows | Rainmeter skin | [`rainmeter/`](rainmeter) |

On Linux, see the [Omarchy bar plugin](https://github.com/flyingtulipdotcom/omarchy-ft-bar).

## Disclaimer

Informational only. This is not financial advice and not a substitute for monitoring your positions yourself.
Figures can be delayed, incomplete or wrong, and a notification can be late or missed (the app can be closed, the API
can be down, the network can be offline). The software is provided "as is", without warranty of any kind (see
[LICENSE](LICENSE)).

## License and trademarks

MIT, see [LICENSE](LICENSE). The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by the
MIT license: you may use them to refer to Flying Tulip, but not to suggest that a modified or unrelated product is
made or endorsed by Flying Tulip.
