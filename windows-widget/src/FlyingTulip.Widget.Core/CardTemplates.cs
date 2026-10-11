using System.Text.Json.Nodes;

namespace FlyingTulip.Widget;

/// <summary>
/// The Adaptive Card templates (Adaptive Cards template language, ${...} bound by the widget host to the data JSON that
/// CardData builds). One per tab and size. They never depend on the data: lists are repeated with $data and optional
/// blocks are switched with $when.
/// </summary>
public static class CardTemplates
{
    public static string Template(string tab, WidgetSize size) => Build(tab, size).ToJsonString(CardJson.Pretty);

    public static string Customize() => BuildCustomize().ToJsonString(CardJson.Pretty);

    static JsonObject Build(string tab, WidgetSize size)
    {
        if (size == WidgetSize.Small) return Small();
        var body = new List<JsonNode?> { Header(size) };
        if (size == WidgetSize.Large) body.Add(TabsSet().Pad("none"));
        body.AddRange(tab switch { "account" => Account(size), "positions" => Positions(size), _ => Market(size) });
        body.Add(Footer(size));
        return Ac.Card(body.ToArray());
    }

    // ---- chrome -------------------------------------------------------------------------------------------------

    static JsonObject Logo() => Ac.Image("${logo}", "small", "Flying Tulip", width: "26px", height: "26px").Sel(Ac.Open("header-logo", "${siteUrl}"));

    static JsonObject TabsSet() => Ac.Actions(
        Ac.Exec("Market", "tab_market", null, "${tabMarket}"),
        Ac.Exec("Account", "tab_account", null, "${tabAccount}"),
        Ac.Exec("Positions", "tab_positions", null, "${tabPositions}"));

    static JsonObject Header(WidgetSize size)
    {
        if (size == WidgetSize.Large)
            return Ac.Cols(
                Ac.Col("auto", Logo()).Mid(),
                Ac.Col("stretch",
                    Ac.Text("Flying Tulip", size: "default", weight: "bolder"),
                    Ac.Text("${walletLine}", size: "small", subtle: true, maxLines: 1)).Mid(),
                Ac.Col("auto", Ac.Actions(
                    Ac.Exec("⇄", "next", null, null, "Next wallet").When("${multi}"),
                    Ac.Exec("⚙︎", "customize", null, null, "Wallets…"),
                    Ac.Exec("↻", "refresh", null, null, "Refresh now"))).Mid());
        return Ac.Cols(
            Ac.Col("auto", Logo()).Mid(),
            Ac.Col("stretch", TabsSet()).Mid(),
            Ac.Col("auto", Ac.Actions(
                Ac.Exec("⇄", "next", null, null, "Next wallet").When("${multi}"),
                Ac.Exec("↻", "refresh", null, null, "Refresh now"))).Mid());
    }

    static JsonObject Footer(WidgetSize size)
    {
        var left = size == WidgetSize.Large ? "${updated}" : "${footL}";
        return Ac.Cols(
            Ac.Col("stretch", Ac.Text(left, size: "small", subtle: true, maxLines: 1)).Sel(Ac.Open("footer-updated", "${siteUrl}")),
            Ac.Col("auto", Ac.Text("Open flyingtulip.com →", size: "small", color: "accent", align: "right"))
                .Sel(Ac.Open("footer-open-site", "${siteUrl}"))).Pad(size == WidgetSize.Large ? "small" : "none");
    }

    // ---- small: the title line only (FT price, fees, HF) --------------------------------------------------------

    static JsonObject Small() => Ac.Card(
        Ac.Cols(
            Ac.Col("auto", Logo()).Mid(),
            Ac.Col("stretch", Ac.Text("Flying Tulip", weight: "bolder", maxLines: 1)).Mid()),
        Ac.Box(new JsonNode?[]
        {
            Ac.Cap("FT PRICE"),
            Ac.Text("${price}", size: "large", weight: "bolder"),
            Ac.Text("${change}", size: "small", color: "${changeColor}").When("${hasChange}"),
        }, Ac.Open("market-ft-price", "${priceUrl}")),
        Ac.Cols(
            Ac.Col("stretch", Ac.Cap("FEES 24H"), Ac.Text("${fees}", size: "medium", weight: "bolder"))
                .Sel(Ac.Open("market-fees", "${feesUrl}")),
            Ac.Col("stretch", Ac.Cap("HF"), Ac.Text("${hfValue}", size: "medium", weight: "bolder", color: "${hfColor}"))
                .Sel(Ac.Open("account-hf", "${hfUrl}")).When("${hasWallet}")).Pad("small"));

    // ---- market ---------------------------------------------------------------------------------------------------

    static JsonObject LegendItem(int n) =>
        Ac.Col("stretch", Ac.Cols(
            Ac.Col("auto", Ac.Image("${leg" + n + "Dot}", "small", "", width: "8px", height: "8px")).Mid(),
            Ac.Col("stretch", Ac.Text("${leg" + n + "Text}", size: "small", subtle: true, maxLines: 1)))).When("${hasLeg" + n + "}");

    static IEnumerable<JsonNode?> Market(WidgetSize size)
    {
        var big = size == WidgetSize.Large ? "medium" : "default";
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cols(
                Ac.Col("2", Ac.Cap("FEES LAST 24H"), Ac.Text("${fees}", size: big, weight: "bolder", maxLines: 1)).Sel(Ac.Open("market-fees", "${feesUrl}")),
                Ac.Col("3", Ac.Cap("FT PRICE · 24H"), Ac.Cols(
                    Ac.Col("auto", Ac.Text("${price}", size: big, weight: "bolder", maxLines: 1)),
                    Ac.Col("stretch", Ac.Text("${changeShort}", size: "small", color: "${changeColor}", maxLines: 1)).Mid())).Sel(Ac.Open("market-ft-price", "${priceUrl}")),
                Ac.Col("2", Ac.Cap("DAY / DAY"), Ac.Text("${dod}", size: big, weight: "bolder", color: "${dodColor}", maxLines: 1)).Sel(Ac.Open("market-day-over-day", "${feesUrl}"))),
        });
        if (size == WidgetSize.Medium)
        {
            yield return Ac.Cols(
                Ac.Col("stretch", Ac.Box(new JsonNode?[]
                {
                    Ac.Cap("DAILY FEES · 31D"),
                    Ac.Image("${feesChart}", "stretch", "Daily fees, last 31 days").When("${hasFeesChart}"),
                    Ac.Text("—", subtle: true).When("${noFeesChart}"),
                }, Ac.Open("market-fees-chart", "${feesUrl}"), spacing: "none")),
                Ac.Col("stretch", Ac.Box(new JsonNode?[]
                {
                    Ac.Cap("FT PRICE · 30D"),
                    Ac.Image("${priceChart}", "stretch", "FT market price, last 30 days").When("${hasPriceChart}"),
                    Ac.Text("—", subtle: true).When("${noPriceChart}"),
                }, Ac.Open("market-price-chart", "${priceUrl}"), spacing: "none"))).Pad("small");
            yield break;
        }
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cols(Ac.Col("stretch", Ac.Cap("${feesCap}")), Ac.Col("auto", Ac.Cap("${feesMax}", align: "right"))),
            Ac.Image("${feesChart}", "stretch", "Daily fees, last 31 days").When("${hasFeesChart}"),
            Ac.Text("—", subtle: true).When("${noFeesChart}"),
            Ac.Cols(Ac.Col("stretch", Ac.Cap("${feesStart}")), Ac.Col("auto", Ac.Cap("${feesEnd}", align: "right"))).When("${hasFeesChart}"),
            Ac.Image("${stackImg}", "stretch", "Fees by product").When("${hasStack}").Pad("small"),
            Ac.Cols(LegendItem(1), LegendItem(2)).When("${hasLeg1}"),
            Ac.Cols(LegendItem(3), LegendItem(4)).When("${hasLeg3}"),
        }, Ac.Open("market-fees-chart", "${feesUrl}"));
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cols(Ac.Col("stretch", Ac.Cap("FT MARKET PRICE · 30 DAYS")), Ac.Col("auto", Ac.Cap("${priceRange}", align: "right"))),
            Ac.Image("${priceChart}", "stretch", "FT market price, last 30 days").When("${hasPriceChart}"),
            Ac.Text("—", subtle: true).When("${noPriceChart}"),
        }, Ac.Open("market-price-chart", "${priceUrl}"));
    }

    // ---- account --------------------------------------------------------------------------------------------------

    static JsonObject NoWallet() => Ac.Box(new JsonNode?[]
    {
        Ac.Text("Add your wallet", weight: "bolder").When("${noWallet}"),
        Ac.Text("See health factor, PnL, FT earned, points and ftPUT gains here.", size: "small", subtle: true, wrap: true).When("${noWallet}"),
        Ac.Text("${badText}", size: "small", color: "attention", wrap: true).When("${walletBad}"),
        Ac.Actions(Ac.Exec("Set wallet", "customize", null, "positive")),
    }, Ac.Open("account-hint", "${siteUrl}"));

    static JsonObject GaugeRow() =>
        Ac.Cols(
            Ac.Col("64px", Ac.Text("${name}", size: "small", maxLines: 1)).Mid(),
            Ac.Col("stretch", Ac.Image("${bar}", "stretch", "${name} health factor")).Mid(),
            Ac.Col("52px", Ac.Text("${value}", size: "small", weight: "bolder", color: "${color}", align: "right", maxLines: 1)).Mid())
            .Each("${chains}").Sel(Ac.Open("${element}", "${url}")).Pad("small");

    static IEnumerable<JsonNode?> Account(WidgetSize size)
    {
        yield return NoWallet().When("${noWalletCard}");
        if (size == WidgetSize.Medium)
        {
            yield return Ac.Box(new JsonNode?[]
            {
                Ac.Cols(
                    Ac.Col("stretch", Ac.Cap("PNL"), Ac.Text("${pnl}", size: "default", weight: "bolder", color: "${pnlColor}", maxLines: 1)).Sel(Ac.Open("account-pnl", "${pnlUrl}")),
                    Ac.Col("stretch", Ac.Cap("FT EARNED"), Ac.Text("${earned}", size: "default", weight: "bolder", color: "accent", maxLines: 1)).Sel(Ac.Open("account-ft-earned", "${rewardsUrl}")),
                    Ac.Col("stretch", Ac.Cap("POINTS"), Ac.Text("${points}", size: "default", weight: "bolder", maxLines: 1),
                        Ac.Text("${rank}", size: "small", subtle: true, maxLines: 1)).Sel(Ac.Open("account-points", "${pointsUrl}"))),
            }).When("${hasWallet}");
            yield return Ac.Box(new JsonNode?[] { GaugeRow() }, spacing: "small").When("${hasChains}");
            yield break;
        }
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cols(Ac.Col("stretch", Ac.Cap("HEALTH FACTOR")), Ac.Col("auto", Ac.Text("red line = liquidation < 1.25", size: "small", subtle: true, align: "right"))),
            GaugeRow(),
            Ac.Text("—", subtle: true).When("${noChains}"),
        }, Ac.Open("account-hf", "${hfUrl}")).When("${hasWallet}");
        yield return Ac.Cols(
            Ac.Col("2", Ac.Box(new JsonNode?[]
            {
                Ac.Cap("PNL (UNREALIZED)"),
                Ac.Text("${pnl}", size: "medium", weight: "bolder", color: "${pnlColor}", maxLines: 1),
                Ac.Text("${pnlSub}", size: "small", subtle: true, maxLines: 1).When("${hasPnlSub}"),
            }, Ac.Open("account-pnl", "${pnlUrl}"))),
            Ac.Col("3", Ac.Box(new JsonNode?[]
            {
                Ac.Cap("FT EARNED · ALL TIME"),
                Ac.Text("${earned}", size: "medium", weight: "bolder", color: "accent", maxLines: 1),
                Ac.Text("${earnL1}", size: "small", subtle: true, wrap: true, maxLines: 2).When("${hasEarnL1}"),
                Ac.Text("${earnL3}", size: "small", subtle: true, wrap: true, maxLines: 1).When("${hasEarnL3}"),
            }, Ac.Open("account-ft-earned", "${rewardsUrl}")))).Pad("small").When("${hasWallet}");
        yield return Ac.Cols(
            Ac.Col("stretch", Ac.Box(new JsonNode?[]
            {
                Ac.Cap("POINTS · ALL CHAINS"),
                Ac.Text("${points}", size: "medium", weight: "bolder", maxLines: 1),
                Ac.Text("${pointsSub1}", size: "small", subtle: true, wrap: true, maxLines: 2).When("${hasPointsSub1}"),
            }, Ac.Open("account-points", "${pointsUrl}"))),
            Ac.Col("stretch", Ac.Box(new JsonNode?[]
            {
                Ac.Cap("FTPUT GAIN"),
                Ac.Text("${putGain}", size: "medium", weight: "bolder", color: "${putColor}", maxLines: 1),
                Ac.Text("${putSub}", size: "small", color: "${putColor}", maxLines: 1),
            }, Ac.Open("account-ftput", "${putUrl}"))).When("${hasPut}")).Pad("small").When("${hasWallet}");
    }

    // ---- positions ------------------------------------------------------------------------------------------------

    static IEnumerable<JsonNode?> Positions(WidgetSize size)
    {
        yield return NoWallet().When("${noWalletCard}");
        var med = size == WidgetSize.Medium;
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cols(Ac.Col("stretch", Ac.Cap("POSITIONS")), Ac.Col("auto", Ac.Cap("${posCount}", align: "right"))),
            Ac.Text("No open positions.", size: "small", subtle: true).When("${noPos}"),
            Ac.Cols(
                Ac.Col("40%", Ac.Text("${sym}", size: "small", weight: "bolder", maxLines: 1),
                    med ? null : Ac.Text("${network}  ${sizeText}", size: "small", subtle: true, maxLines: 1)),
                Ac.Col("30%", Ac.Text("mark ${mark}", size: "small", subtle: !med, maxLines: 1),
                    med ? null : Ac.Text("entry ${entry}", size: "small", subtle: true, maxLines: 1)),
                Ac.Col("30%", Ac.Text("${pnl}", size: "small", weight: "bolder", color: "${color}", align: "right", maxLines: 1),
                    med ? null : Ac.Text("${pnlPct}", size: "small", color: "${color}", align: "right", maxLines: 1)))
                .Each("${positions}").Sel(Ac.Open("positions-row", "${url}")).Pad("small"),
            Ac.Text("${posMore}", size: "small", subtle: true).When("${hasMore}"),
        }, Ac.Open("positions-card", "${portfolioUrl}")).When("${hasWallet}");
        yield return Ac.Box(new JsonNode?[]
        {
            Ac.Cap("POINTS POSITIONS"),
            Ac.Cols(
                Ac.Col("50%", Ac.Text("${label}", size: "small", maxLines: 1)),
                Ac.Col("30%", Ac.Text("${usd}", size: "small", subtle: true, align: "right", maxLines: 1)),
                Ac.Col("20%", Ac.Text("${mult}", size: "small", color: "accent", align: "right", maxLines: 1))).Each("${pts}"),
        }, Ac.Open("account-points-positions", "${pointsActivityUrl}")).When("${hasPts}");
        const string PutCap = "FTPUT POSITIONS · COST = CAPITAL X PRICE AT INVESTMENT";
        yield return Ac.Box(new JsonNode?[]
        {
            size == WidgetSize.Large ? Ac.Text(PutCap, size: "small", subtle: true, wrap: true, maxLines: 2) : Ac.Cap(PutCap),
            Ac.Cols(
                Ac.Col("40%", Ac.Text("${label}", size: "small", maxLines: 1)),
                Ac.Col("35%", Ac.Text("${cost}", size: "small", subtle: true, align: "right", maxLines: 1)),
                Ac.Col("25%", Ac.Text("${since}", size: "small", subtle: true, align: "right", maxLines: 1))).Each("${puts}"),
        }, Ac.Open("account-ftput-positions", "${putUrl}")).When("${hasPuts}");
    }

    // ---- customize ------------------------------------------------------------------------------------------------

    static JsonObject BuildCustomize() => Ac.Card(
        Ac.Cols(
            Ac.Col("auto", Ac.Image("${logo}", "small", "Flying Tulip", width: "26px", height: "26px")).Mid(),
            Ac.Col("stretch", Ac.Text("Wallets", weight: "bolder"),
                Ac.Text("Public addresses only. With several, the widget shows them in turn.", size: "small", subtle: true, wrap: true))),
        Ac.Text("${notice}", size: "small", color: "attention", wrap: true).When("${hasNotice}"),
        new JsonObject
        {
            ["type"] = "Input.Text", ["id"] = "wallets", ["isMultiline"] = true, ["value"] = "${wallets}",
            ["label"] = "Public wallet addresses to show (0x...), comma separated. Leave empty to clear.", ["placeholder"] = "0x...",
        },
        new JsonObject
        {
            ["type"] = "Input.ChoiceSet", ["id"] = "priceChain", ["style"] = "compact", ["value"] = "${priceChain}",
            ["label"] = "Chain whose FT-ftUSD market price is shown.",
            ["choices"] = new JsonArray(
                new JsonObject { ["title"] = "Ethereum", ["value"] = "1" },
                new JsonObject { ["title"] = "Sonic", ["value"] = "146" }),
        },
        Ac.Text("Advanced", weight: "bolder", spacing: "medium"),
        new JsonObject
        {
            ["type"] = "Input.Toggle", ["id"] = "analytics", ["title"] = "Anonymous usage stats", ["value"] = "${statsValue}",
            ["valueOn"] = "true", ["valueOff"] = "false",
        },
        Ac.Actions(Ac.Exec("Save", "save", null, "positive"), Ac.Exec("Done", "done")));
}

static class CardJson
{
    public static readonly System.Text.Json.JsonSerializerOptions Pretty = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
    public static readonly System.Text.Json.JsonSerializerOptions Options = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
}
