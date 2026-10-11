# Flying Tulip widget for the Windows 11 Widgets Board

A native widget for the Windows 11 Widgets Board (Win+W), built with the Windows App SDK widget provider API (C#, .NET 8, an
`IWidgetProvider` COM server, Adaptive Card templates plus data JSON, packaged as an MSIX with the `com.microsoft.windows.widgets`
app extension). Same data, fields and public API as the [Rainmeter skin](../rainmeter), the [xbar plugin](../xbar) and the
[Omarchy plugin](https://github.com/flyingtulipdotcom/omarchy-ft-bar), and it follows the look of the Omarchy panel.

One widget, **Flying Tulip**, with the same three tabs as the Omarchy panel, switched by the buttons at the top (the tab is
remembered per widget):

| Tab | What it shows |
|---|---|
| **Market** | fees last 24h, FT price (the FT-ftUSD market price, never the NAV used for accounting) with its 24h change, day over day; daily fees for 31 days with the per-product split; the FT market price for 30 days |
| **Account** | health factor per chain with the liquidation line, PnL (unrealized), FT earned (all time, sftUSD yield and Lend rewards, value at the market price), points (all chains) with the rank, ftPUT gain |
| **Positions** | open positions (mark, entry, PnL), the positions that earn points, ftPUT positions |

Sizes: **small** is the title line (FT price with 24h change, fees 24h, HF); **medium** and **large** have the tabs. Every tab fits
without scrolling; what does not fit a size is left out of that size (the large widget has no "FT earned over time" chart, the
medium widget shows one health factor row, the lowest). The charts and health bars are drawn by the provider as PNGs in the Omarchy
colours (an Adaptive Card cannot draw them); everything else is card text.

**Wallets**: the widget's menu (three dots) has **Customize widget**, which opens the wallets form (one or several public
addresses, comma separated). With several wallets the next one is shown on each refresh after 50 seconds, and the `⇄` button
switches at once. The form also has the chain of the FT price and, under **Advanced**, the **Anonymous usage stats** switch.

## Install

See the [release](https://github.com/flyingtulipdotcom/ft-desktop-widgets/releases?q=windows-widget): `install.ps1`, or the
steps by hand (trust the test certificate or enable Developer Mode, install the Windows App Runtime 1.8, open the `.msix`).

## Anonymous usage stats

Same as the other widgets: anonymous events to [Plausible](https://plausible.io) (site "widget"), **no wallet address, balance,
position or other account data is ever sent**, on by default, off with the **Anonymous usage stats** switch in the customize form
(one last "Usage stats off" event, then nothing). The platform is `windows-widget`. Event names and values are those of
[xbar/README.md](../xbar/README.md#anonymous-usage-stats): `pageview` (`os`, `host` "Widgets Board", `walletsConfigured`),
`Panel open`, `Tab view` (`tab`), `Link click` (`element`, `url`), `Wallet switch`, `Settings open`, `Wallet added`,
`Wallet removed`, `Refresh`, `Fetch error` (`endpoint`), `Usage stats off`, `Usage stats on`. There is no `HF alert shown`: the
widget shows no notifications, it colours the health factor (amber at 1.40 or below, red at 1.30 or below).

While usage stats are on, every flyingtulip.com page the widget opens carries the origin marker
`?utm_source=ft-widget&utm_medium=windows-widget&utm_content=<element>#ftw=windows-widget.<os-slug>.<version>.<element>`
(for example `...&utm_content=market-ft-price#ftw=windows-widget.windows-11.1-0-0.market-ft-price`); off, the plain URL is opened.
The element ids are the ones of the other widgets (`market-ft-price`, `market-fees`, `account-hf`, `account-hf-sonic`, `account-pnl`,
`account-ft-earned`, `account-points`, `account-ftput`, `positions-row`, `footer-open-site`, ...).

## Layout of the code

- `src/FlyingTulip.Widget.Core`: no Windows API. Parsers, formats, the Adaptive Card templates (`CardTemplates`), the data JSON
  (`CardData`), the charts (`Charts`, a tiny PNG canvas), usage stats, the state file and the controller that turns the
  board's verbs into state and a new card. Unit tested on any OS.
- `src/FlyingTulip.Widget.Provider`: the `IWidgetProvider` / `IWidgetProvider2` COM server and its class factory.
- `package/AppxManifest.xml`, `build/package.ps1`: the MSIX (makeappx + signtool).
- `tools/Preview`, `preview/render.mjs`: card templates and data from the live API, rendered by the Adaptive Cards JavaScript
  renderer for the CI previews.

## Build and test

```
dotnet test tests/FlyingTulip.Widget.Core.Tests          # any OS
dotnet publish src/FlyingTulip.Widget.Provider -c Release -r win-x64 -o out/publish     # Windows
pwsh build/package.ps1 -Publish out/publish -Shot some.png -OutDir out/dist             # MSIX with a self-signed test certificate
```

CI (`.github/workflows/windows-widget.yml`): tests, the previews, the MSIX and zip on a Windows runner, a probe for the Widgets
Board, an optional real-signing job, and a release on a `windows-widget-v*` tag.

## Previews and the Widgets Board

GitHub's Windows runners are Windows Server, which has no Widgets Board, so CI cannot screenshot the real board. The previews
in the pull requests and job summaries are the widget's real templates, bound to live public data, drawn by the official Adaptive
Cards JavaScript renderer with a host config that stands in for the Windows 11 widget host, labelled "Adaptive Card preview
(Windows 11 host config)". They differ from the board in the font (Segoe UI Variable on Windows), the accent colour (the board
uses the user's Windows accent colour for the active tab and links, the preview uses the Flying Tulip purple) and the exact
sizes of the widget tiles (approximate).

## Real signing and the Microsoft Store

The release is signed with a self-signed test certificate. For a certificate Windows trusts by itself, add the repository secrets
`WINDOWS_CERT_PFX` (the .pfx, base64) and `WINDOWS_CERT_PASSWORD`: the `sign` job then rebuilds the package with the certificate's
subject as publisher and uploads it. For the Microsoft Store, reserve the app name in Partner Center, use the identity name,
publisher and publisher display name it gives you in `package/AppxManifest.xml`, and upload the unsigned package (the Store signs
it); a Store build does not need the certificate or the install script.

## Disclaimer

Informational only, not financial advice; figures can be delayed, incomplete or wrong; provided "as is" (see
[../LICENSE](../LICENSE)). MIT. The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by the MIT
license.
