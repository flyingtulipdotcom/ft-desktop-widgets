using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using AdaptiveCards.Templating;
using Xunit;

namespace FlyingTulip.Widget.Tests;

public class CardTests
{
    public static IEnumerable<object[]> TabsAndSizes()
    {
        foreach (var tab in WidgetState.Tabs)
            foreach (var size in new[] { WidgetSize.Medium, WidgetSize.Large })
                yield return new object[] { tab, size };
        yield return new object[] { "market", WidgetSize.Small };
    }

    static async Task<(Rig rig, WidgetState st)> Loaded(bool two = false)
    {
        var rig = new Rig(statsOn: false);
        var st = rig.Store.Widget("w1");
        if (two) { st.Wallets = new() { Fx.Wallet, Fx.Wallet2 }; st.Normalize(); }
        await rig.Hub.RefreshMarketAsync(1);
        await rig.Hub.RefreshWalletAsync(Fx.Wallet);
        return (rig, st);
    }

    static JsonNode Expand(string template, string data)
    {
        var json = new AdaptiveCardTemplate(template).Expand(new EvaluationContext { Root = JsonNode.Parse(data)!.ToString() });
        return JsonNode.Parse(json)!;
    }

    static IEnumerable<JsonNode> Walk(JsonNode? n)
    {
        if (n is null) yield break;
        yield return n;
        if (n is JsonObject o) foreach (var kv in o) foreach (var c in Walk(kv.Value)) yield return c;
        else if (n is JsonArray a) foreach (var x in a) foreach (var c in Walk(x)) yield return c;
    }

    [Theory, MemberData(nameof(TabsAndSizes))]
    public async Task Template_binds_to_the_live_shaped_data_with_nothing_left_unbound(string tab, WidgetSize size)
    {
        var (rig, st) = await Loaded(two: true);
        var card = Expand(CardTemplates.Template(tab, size), CardData.Json(rig.Snapshot(st), tab, size));
        var text = card.ToJsonString();
        Assert.DoesNotMatch(new Regex(@"\$\{"), text);
        Assert.DoesNotContain("\"$when\"", text); Assert.DoesNotContain("\"$data\"", text);
        Assert.Equal("AdaptiveCard", card["type"]!.GetValue<string>());
        Assert.Equal("1.5", card["version"]!.GetValue<string>());
        if (tab == "market") Assert.Contains("$0.1501", text);   // the FT-ftUSD market price from the ticker fixture
        Assert.Contains("Flying Tulip", text);
    }

    [Theory, MemberData(nameof(TabsAndSizes))]
    public async Task Every_data_key_the_template_uses_exists_in_the_data(string tab, WidgetSize size)
    {
        var (rig, st) = await Loaded();
        var data = JsonNode.Parse(CardData.Json(rig.Snapshot(st), tab, size))!.AsObject();
        var missing = new List<string>();
        void Visit(JsonNode? n, JsonObject? scope)
        {
            if (n is JsonObject o)
            {
                var s = scope;
                if (o["$data"] is JsonNode d)
                {
                    var key = Regex.Match(d.GetValue<string>(), @"\$\{(\w+)\}").Groups[1].Value;
                    Assert.True(data.ContainsKey(key), "repeat key " + key);
                    s = (data[key] as JsonArray)?.FirstOrDefault()?.AsObject();
                    if (s is null) return;   // nothing to repeat for this data: nothing to check
                }
                foreach (var kv in o)
                {
                    if (kv.Key == "$data") continue;
                    if (kv.Value is JsonValue v && v.TryGetValue<string>(out var str))
                    { foreach (Match m in Regex.Matches(str, @"\$\{(\w+)\}")) if ((s ?? data)[m.Groups[1].Value] is null) missing.Add(m.Groups[1].Value); }
                    else Visit(kv.Value, s);
                }
            }
            else if (n is JsonArray a) foreach (var x in a) Visit(x, scope);
        }
        Visit(JsonNode.Parse(CardTemplates.Template(tab, size)), null);
        Assert.Empty(missing.Distinct());
    }

    [Theory, MemberData(nameof(TabsAndSizes))]
    public async Task Actions_are_verbs_the_controller_handles_and_links_carry_an_element_and_a_site_url(string tab, WidgetSize size)
    {
        var (rig, st) = await Loaded();
        var card = Expand(CardTemplates.Template(tab, size), CardData.Json(rig.Snapshot(st), tab, size));
        var verbs = new[] { "tab_market", "tab_account", "tab_positions", "next", "customize", "refresh", "open" };
        foreach (var n in Walk(card).OfType<JsonObject>().Where(o => o["type"]?.GetValue<string>() == "Action.Execute"))
        {
            var verb = n["verb"]!.GetValue<string>();
            Assert.Contains(verb, verbs);
            if (verb != "open") continue;
            var d = n["data"]!;
            Assert.Matches("^[a-z0-9-]+$", d["element"]!.GetValue<string>());
            Assert.True(Origin.IsSiteUrl(d["url"]!.GetValue<string>()), d["url"]!.ToString());
        }
        Assert.DoesNotContain("Action.OpenUrl", card.ToJsonString());
    }

    [Fact]
    public async Task Element_ids_are_the_documented_ones()
    {
        var known = new HashSet<string>(new[] { "header-logo", "market-ft-price", "market-fees", "market-day-over-day", "market-fees-chart",
            "market-price-chart", "account-hint", "account-hf", "account-pnl", "account-ft-earned", "account-points", "account-ftput",
            "account-points-positions", "account-ftput-positions", "positions-card", "positions-row", "footer-updated", "footer-open-site" });
        var (rig, st) = await Loaded();
        foreach (var tab in WidgetState.Tabs) foreach (var size in new[] { WidgetSize.Small, WidgetSize.Medium, WidgetSize.Large })
        {
            var card = Expand(CardTemplates.Template(tab, size), CardData.Json(rig.Snapshot(st), tab, size));
            foreach (var o in Walk(card).OfType<JsonObject>().Where(o => o["verb"]?.GetValue<string>() == "open"))
            {
                var el = o["data"]!["element"]!.GetValue<string>();
                Assert.True(known.Contains(el) || Regex.IsMatch(el, "^account-hf-[a-z]+$"), el);
            }
        }
    }

    [Fact]
    public async Task Tabs_highlight_the_active_one_and_the_wallet_switch_shows_only_with_several_wallets()
    {
        var (rig, st) = await Loaded(two: true);
        var d = JsonNode.Parse(CardData.Json(rig.Snapshot(st), "account", WidgetSize.Large))!;
        Assert.Equal("positive", d["tabAccount"]!.GetValue<string>());
        Assert.Equal("default", d["tabMarket"]!.GetValue<string>());
        Assert.True(d["multi"]!.GetValue<bool>());
        Assert.Equal("0x38a5…2d62  1/2", d["walletLine"]!.GetValue<string>());
        var one = new Snapshot { Wallets = new() { Fx.Wallet }, WalletAddr = Fx.Wallet };
        Assert.False(JsonNode.Parse(CardData.Json(one, "market", WidgetSize.Large))!["multi"]!.GetValue<bool>());
        var card = Expand(CardTemplates.Template("account", WidgetSize.Large), CardData.Json(one, "account", WidgetSize.Large));
        Assert.DoesNotContain("\"next\"", card.ToJsonString());   // no switch with one wallet
        var two = Expand(CardTemplates.Template("account", WidgetSize.Large), CardData.Json(rig.Snapshot(st), "account", WidgetSize.Large));
        Assert.Contains("\"next\"", two.ToJsonString());
    }

    [Fact]
    public async Task Account_shows_the_numbers_of_the_account_endpoints_with_colour_names()
    {
        var (rig, st) = await Loaded();
        var d = JsonNode.Parse(CardData.Json(rig.Snapshot(st), "account", WidgetSize.Large))!;
        Assert.Equal("1.90", d["hfValue"]!.GetValue<string>());
        Assert.Equal("good", d["hfColor"]!.GetValue<string>());
        Assert.Equal("Sonic", d["hfChain"]!.GetValue<string>());
        Assert.Equal("+$10.50", d["pnl"]!.GetValue<string>());    // 12.5 + -2 summed over chains
        Assert.Equal("good", d["pnlColor"]!.GetValue<string>());
        Assert.Equal("153.0 FT", d["earned"]!.GetValue<string>());
        Assert.Equal("922K", d["points"]!.GetValue<string>());
        Assert.Equal("rank #777 of 2000", d["pointsSub1"]!.GetValue<string>());
        Assert.True(d["hasPut"]!.GetValue<bool>());
        var rows = d["chains"]!.AsArray();
        Assert.Equal(3, rows.Count);
        Assert.StartsWith("data:image/png;base64,", rows[0]!["bar"]!.GetValue<string>());
        Assert.Equal("no debt", rows.First(r => r!["name"]!.GetValue<string>() == "Ethereum")!["value"]!.GetValue<string>());
    }

    [Fact]
    public async Task Low_health_factor_turns_the_value_amber_then_red()
    {
        var rig = new Rig(statsOn: false);
        static string Lend(double hf) => "{\"data\":{\"chains\":[{\"chainId\":146,\"hfLiquidationThreshold\":1.25,\"userMetrics\":{\"totalDebtUsd\":1000,\"healthFactor\":" + hf.ToString(System.Globalization.CultureInfo.InvariantCulture) + ",\"equityUsd\":500}}]}}";
        rig.Http.Override = u => u.Contains("/mm/lend?user=") && !u.Contains("143") ? Lend(1.35) : null;
        await rig.Hub.RefreshMarketAsync(1); await rig.Hub.RefreshWalletAsync(Fx.Wallet);
        var st = rig.Store.Widget("w1");
        Assert.Equal("warning", JsonNode.Parse(CardData.Json(rig.Snapshot(st), "account", WidgetSize.Medium))!["hfColor"]!.GetValue<string>());
        rig.Http.Override = u => u.Contains("/mm/lend?user=") && !u.Contains("143") ? Lend(1.28) : null;
        await rig.Hub.RefreshWalletAsync(Fx.Wallet);
        Assert.Equal("attention", JsonNode.Parse(CardData.Json(rig.Snapshot(st), "account", WidgetSize.Small))!["hfColor"]!.GetValue<string>());
    }

    [Fact]
    public async Task Positions_tab_lists_positions_points_positions_and_ftput()
    {
        var (rig, st) = await Loaded();
        var d = JsonNode.Parse(CardData.Json(rig.Snapshot(st), "positions", WidgetSize.Large))!;
        var p = d["positions"]!.AsArray();
        Assert.Single(p);
        Assert.Equal("wS  long 3.0x", p[0]!["sym"]!.GetValue<string>());
        Assert.Equal("+$5.00", p[0]!["pnl"]!.GetValue<string>());
        Assert.Equal("https://flyingtulip.com/trade/?symbol=wS-ftUSD&chainId=146&marketType=spot", p[0]!["url"]!.GetValue<string>());
        Assert.Equal("1 open", d["posCount"]!.GetValue<string>());
        Assert.True(d["hasPts"]!.GetValue<bool>()); Assert.True(d["hasPuts"]!.GetValue<bool>());
        Assert.Equal("x1.00", d["pts"]![0]!["mult"]!.GetValue<string>());
        Assert.Equal("#7 USDT", d["puts"]![0]!["label"]!.GetValue<string>());
    }

    [Fact]
    public void No_wallet_shows_the_add_your_wallet_card_and_a_bad_address_says_so()
    {
        var d = JsonNode.Parse(CardData.Json(new Snapshot(), "account", WidgetSize.Large))!;
        Assert.True(d["noWallet"]!.GetValue<bool>()); Assert.False(d["hasWallet"]!.GetValue<bool>());
        var card = Expand(CardTemplates.Template("account", WidgetSize.Large), d.ToJsonString()).ToJsonString();
        Assert.Contains("Add your wallet", card);
        var bad = JsonNode.Parse(CardData.Json(new Snapshot { BadWallets = new() { "0x123" } }, "account", WidgetSize.Large))!;
        Assert.Equal("Not a valid address: 0x123 (0x + 40 hex characters)", bad["badText"]!.GetValue<string>());
    }

    [Fact]
    public async Task Market_numbers_use_the_market_price_and_the_fee_series()
    {
        var (rig, st) = await Loaded();
        var d = JsonNode.Parse(CardData.Json(rig.Snapshot(st), "market", WidgetSize.Large))!;
        Assert.Equal("$0.1501", d["price"]!.GetValue<string>());
        Assert.Equal("$950", d["fees"]!.GetValue<string>());
        Assert.Equal("DAILY FEES · LAST 31 DAYS", d["feesCap"]!.GetValue<string>());
        Assert.True(d["hasFeesChart"]!.GetValue<bool>()); Assert.True(d["hasPriceChart"]!.GetValue<bool>());
        Assert.StartsWith("data:image/png;base64,", d["feesChart"]!.GetValue<string>());
        Assert.True(d["hasStack"]!.GetValue<bool>());
        Assert.Equal("09-10", d["feesStart"]!.GetValue<string>());
    }

    [Fact]
    public void Customize_card_has_the_wallets_field_the_chain_and_the_stats_toggle_default_on()
    {
        var snap = new Snapshot { WalletsText = Fx.Wallet + ", " + Fx.Wallet2, StatsOn = true };
        var card = Expand(CardTemplates.Customize(), CardData.CustomizeJson(snap));
        var inputs = Walk(card).OfType<JsonObject>().Where(o => (o["type"]?.GetValue<string>() ?? "").StartsWith("Input.")).ToList();
        Assert.Equal(new[] { "wallets", "priceChain", "analytics" }, inputs.Select(i => i["id"]!.GetValue<string>()));
        Assert.Equal(Fx.Wallet + ", " + Fx.Wallet2, inputs[0]["value"]!.GetValue<string>());
        Assert.Equal("Anonymous usage stats", inputs[2]["title"]!.GetValue<string>());
        Assert.Equal("true", inputs[2]["value"]!.GetValue<string>());
        Assert.DoesNotContain("${", card.ToJsonString());
        Assert.Contains(Walk(card).OfType<JsonObject>(), o => o["verb"]?.GetValue<string>() == "save");
    }

    [Fact]
    public void No_tracking_word_anywhere_in_the_cards()
    {
        foreach (var tab in WidgetState.Tabs) foreach (var size in new[] { WidgetSize.Small, WidgetSize.Medium, WidgetSize.Large })
            Assert.DoesNotContain("track", CardTemplates.Template(tab, size), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("track", CardTemplates.Customize(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Charts_are_valid_pngs_of_the_requested_size_and_survive_flat_data()
    {
        foreach (var uri in new[] { Charts.BarChart(new double[] { 0, 0, 0 }, 100, 30, Charts.Tulip, Charts.Tulip300), Charts.LineChart(new double[] { 1, 1, 1 }, 100, 30, Charts.Tulip),
            Charts.HfBar(1.9, 1.25, 1.4, 1.3, 120), Charts.HfBar(null, 1.25, 1.4, 1.3, 120), Charts.StackBar(new[] { (5.0, Charts.Tulip), (1.0, Charts.Green) }, 120), Charts.Dot(Charts.Red) })
        {
            var bytes = Convert.FromBase64String(uri["data:image/png;base64,".Length..]);
            Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, bytes[..8]);
            Assert.Equal("IHDR", System.Text.Encoding.ASCII.GetString(bytes, 12, 4));
        }
        var b = Convert.FromBase64String(Charts.HfBar(1.9, 1.25, 1.4, 1.3, 120, 14)["data:image/png;base64,".Length..]);
        int w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19], h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
        Assert.Equal(240, w); Assert.Equal(28, h);   // drawn at 2x
    }
}
