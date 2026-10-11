using System.Text.Json.Nodes;
using Xunit;

namespace FlyingTulip.Widget.Tests;

public class ControllerTests
{
    static JsonObject Open(string element, string url) => new() { ["element"] = element, ["url"] = url };

    [Fact]
    public async Task Tab_switch_is_remembered_per_widget_and_counted()
    {
        var rig = new Rig();
        await rig.Ctl.RenderAsync("w1", WidgetSize.Large, force: true);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "tab_account", null);
        Assert.Equal("account", rig.Store.Widget("w1").Tab);
        Assert.Equal("market", rig.Store.Widget("w2").Tab);   // another instance keeps its own
        var data = JsonNode.Parse((await rig.Ctl.RenderAsync("w1", WidgetSize.Large)).Data)!;
        Assert.Equal("positive", data["tabAccount"]!.GetValue<string>());
        var ev = rig.Sink.Events.First(e => e["name"]!.GetValue<string>() == "Tab view");
        Assert.Equal("account", ev["props"]!["tab"]!.GetValue<string>());
    }

    [Fact]
    public void State_survives_a_restart_and_a_damaged_file_starts_empty()
    {
        var path = Path.Combine(Path.GetTempPath(), "ftw-persist-" + Guid.NewGuid().ToString("N") + ".json");
        var a = new StateStore(path);
        var w = a.Widget("w1"); w.Tab = "positions"; w.Wallets = new() { Fx.Wallet, Fx.Wallet2 }; w.Cur = Fx.Wallet2;
        a.State.StatsOn = false; a.Save();
        var b = new StateStore(path);
        Assert.Equal("positions", b.Widget("w1").Tab);
        Assert.Equal(Fx.Wallet2, b.Widget("w1").Cur);
        Assert.False(b.State.StatsOn);
        File.WriteAllText(path, "{ not json");
        Assert.Equal("market", new StateStore(path).Widget("w1").Tab);
    }

    [Fact]
    public async Task Next_switches_wallet_and_each_refresh_past_50s_rotates()
    {
        var rig = new Rig();
        var st = rig.Store.Widget("w1"); st.Wallets = new() { Fx.Wallet, Fx.Wallet2 }; st.Normalize();
        await rig.Ctl.RenderAsync("w1", WidgetSize.Large, force: true);
        Assert.Equal(Fx.Wallet, st.Cur);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "next", null);
        Assert.Equal(Fx.Wallet2, st.Cur);
        Assert.Contains("Wallet switch", rig.Sink.Names);
        rig.Now = rig.Now.AddSeconds(20);
        await rig.Ctl.RenderAsync("w1", WidgetSize.Large, rotate: true);
        Assert.Equal(Fx.Wallet2, st.Cur);   // too soon
        rig.Now = rig.Now.AddSeconds(40);
        await rig.Ctl.RenderAsync("w1", WidgetSize.Large, rotate: true);
        Assert.Equal(Fx.Wallet, st.Cur);    // rotated, not counted as a manual switch
        Assert.Single(rig.Sink.Names.Where(n => n == "Wallet switch"));
    }

    [Fact]
    public async Task Customize_save_sets_wallets_chain_and_counts_added_and_removed_never_which()
    {
        var rig = new Rig();
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "customize", null);
        Assert.True(rig.Store.Widget("w1").Customizing);
        Assert.Contains("Settings open", rig.Sink.Names);
        var r = await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "save", null, new Dictionary<string, string>
            { ["wallets"] = Fx.Wallet2 + ", " + Fx.Wallet.ToUpperInvariant().Replace("0X", "0x"), ["priceChain"] = "146", ["analytics"] = "true" });
        var st = rig.Store.Widget("w1");
        Assert.False(st.Customizing); Assert.False(r.Customizing);
        Assert.Equal(new[] { Fx.Wallet2, Fx.Wallet }, st.Wallets);
        Assert.Equal(146, st.PriceChain);
        Assert.Contains("Wallet added", rig.Sink.Names);
        Assert.DoesNotContain("Wallet removed", rig.Sink.Names);
        foreach (var p in rig.Sink.Posts) { Assert.DoesNotContain("0x38a5", p.Body, StringComparison.OrdinalIgnoreCase); Assert.DoesNotContain("0x47a7", p.Body, StringComparison.OrdinalIgnoreCase); }
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "save", null, new Dictionary<string, string> { ["wallets"] = "", ["priceChain"] = "1", ["analytics"] = "true" });
        Assert.Empty(st.Wallets);
        Assert.Contains("Wallet removed", rig.Sink.Names);
    }

    [Fact]
    public async Task A_bad_address_keeps_the_customize_card_open_with_the_message()
    {
        var rig = new Rig();
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "customize", null);
        var r = await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "save", null, new Dictionary<string, string> { ["wallets"] = "0xnope", ["analytics"] = "true" });
        Assert.True(r.Customizing);
        Assert.Equal("Not a valid address: 0xnope. Use 0x followed by 40 hex characters.", JsonNode.Parse(r.Data)!["notice"]!.GetValue<string>());
        Assert.Equal(new[] { Fx.Wallet }, rig.Store.Widget("w1").Wallets);   // unchanged
    }

    [Fact]
    public async Task Opt_out_toggle_sends_off_then_nothing_and_links_open_plain()
    {
        var rig = new Rig();
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "customize", null);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "save", null, new Dictionary<string, string> { ["wallets"] = Fx.Wallet, ["analytics"] = "false" });
        Assert.False(rig.Store.State.StatsOn);
        Assert.Equal("Usage stats off", rig.Sink.Names.Last());
        var before = rig.Sink.Posts.Count;
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "tab_account", null);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "refresh", null);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "open", Open("market-fees", "https://flyingtulip.com/statistics/"));
        Assert.Equal(before, rig.Sink.Posts.Count);                                  // nothing sent while off
        Assert.Equal(new[] { "https://flyingtulip.com/statistics/" }, rig.Opened);   // plain url: no marker
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "customize", null);
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "save", null, new Dictionary<string, string> { ["wallets"] = Fx.Wallet, ["analytics"] = "true" });
        Assert.Equal("Usage stats on", rig.Sink.Names.Last());
    }

    [Fact]
    public async Task Link_click_is_counted_and_opens_the_page_with_the_origin_marker()
    {
        var rig = new Rig();
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "open", Open("account-points", "https://flyingtulip.com/rewards/leaderboard/"));
        var click = rig.Sink.Events.Single(e => e["name"]!.GetValue<string>() == "Link click");
        Assert.Equal("account-points", click["props"]!["element"]!.GetValue<string>());
        Assert.Equal("https://flyingtulip.com/rewards/leaderboard/", click["props"]!["url"]!.GetValue<string>());
        Assert.Equal("https://flyingtulip.com/rewards/leaderboard/?utm_source=ft-widget&utm_medium=windows-widget&utm_content=account-points#ftw=windows-widget.windows-11.1-0-0.account-points",
            Assert.Single(rig.Opened));
    }

    [Fact]
    public async Task Only_flyingtulip_pages_are_ever_opened()
    {
        var rig = new Rig();
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "open", Open("x", "https://evil.example/"));
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "open", Open("x", "file:///c:/windows/system32/calc.exe"));
        Assert.Empty(rig.Opened);
        Assert.DoesNotContain("Link click", rig.Sink.Names);
    }

    [Fact]
    public async Task Refresh_counts_and_forces_a_new_read_and_panel_open_is_once_per_30_minutes()
    {
        var rig = new Rig();
        await rig.Ctl.RenderAsync("w1", WidgetSize.Large, force: true);
        var n = rig.Http.Calls.Count(c => c.Contains("tickers"));
        await rig.Ctl.ActionAsync("w1", WidgetSize.Large, "refresh", null);
        Assert.Equal(n + 1, rig.Http.Calls.Count(c => c.Contains("tickers")));
        Assert.Contains("Refresh", rig.Sink.Names);
        await rig.Ctl.ActivatedAsync("w1"); await rig.Ctl.ActivatedAsync("w1");
        Assert.Single(rig.Sink.Names.Where(x => x == "Panel open"));
        Assert.Single(rig.Sink.Names.Where(x => x == "pageview"));
        rig.Now = rig.Now.AddMinutes(31);
        await rig.Ctl.ActivatedAsync("w1");
        Assert.Equal(2, rig.Sink.Names.Count(x => x == "Panel open"));
    }

    [Fact]
    public async Task A_failing_endpoint_keeps_the_last_good_value_and_counts_one_fetch_error()
    {
        var rig = new Rig();
        var errors = new List<string>();
        var hub = new DataHub(rig.Http, () => rig.Now, errors.Add);
        await hub.RefreshMarketAsync(1);
        Assert.NotNull(hub.Market.Price);
        rig.Http.Fail.Add("tickers");
        await hub.RefreshMarketAsync(1);
        Assert.NotNull(hub.Market.Price);   // last good
        Assert.Contains("ticker", errors);
        await rig.Stats.FetchErrorAsync("ticker"); await rig.Stats.FetchErrorAsync("ticker");
        var errs = rig.Sink.Events.Where(e => e["name"]!.GetValue<string>() == "Fetch error").ToList();
        Assert.Single(errs);
        Assert.Equal("ticker", errs[0]["props"]!["endpoint"]!.GetValue<string>());
    }

    [Fact]
    public async Task Positions_endpoint_answering_null_means_none_open_not_unavailable()
    {
        var rig = new Rig(statsOn: false);
        rig.Http.Override = u => u.Contains("account/positions") ? "null" : null;
        await rig.Hub.RefreshMarketAsync(1); await rig.Hub.RefreshWalletAsync(Fx.Wallet);
        var d = JsonNode.Parse(CardData.Json(rig.Snapshot(rig.Store.Widget("w1")), "positions", WidgetSize.Large))!;
        Assert.True(d["noPos"]!.GetValue<bool>());
    }

    [Fact]
    public async Task Rank_is_found_by_binary_search_over_the_leaderboard_pages()
    {
        var rig = new Rig(statsOn: false);
        await rig.Hub.RefreshWalletAsync(Fx.Wallet);
        var rank = rig.Hub.Wallet(Fx.Wallet).Rank!.Value!;
        Assert.Equal(777, rank.Rank); Assert.Equal(2000, rank.Total);
        Assert.True(rig.Http.Calls.Count(c => c.Contains("leaderboard")) <= 8);
    }
}
