using System.Text.Json.Nodes;
using Xunit;

namespace FlyingTulip.Widget.Tests;

public class OriginTests
{
    [Fact]
    public void Marker_matches_the_documented_scheme()
    {
        var url = Origin.WithOrigin("https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=146&marketType=spot", "market-ft-price", "Windows 11");
        Assert.Equal("https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=146&marketType=spot&utm_source=ft-widget&utm_medium=windows-widget&utm_content=market-ft-price#ftw=windows-widget.windows-11.1-0-0.market-ft-price", url);
    }

    [Fact]
    public void Query_is_added_to_a_url_without_one_and_an_existing_anchor_is_kept()
    {
        Assert.Equal("https://flyingtulip.com/rewards/?utm_source=ft-widget&utm_medium=windows-widget&utm_content=account-points#ftw=windows-widget.windows-10.1-0-0.account-points",
            Origin.WithOrigin("https://flyingtulip.com/rewards/", "account-points", "Windows 10"));
        Assert.Equal("https://flyingtulip.com/rewards/?utm_source=ft-widget&utm_medium=windows-widget&utm_content=account-points#my-activity",
            Origin.WithOrigin("https://flyingtulip.com/rewards/#my-activity", "account-points", "Windows 11"));
    }

    [Fact]
    public void Element_ids_are_cleaned_and_only_site_pages_are_opened()
    {
        Assert.Equal("account-hf-sonic", Origin.ElementId("Account-HF-Sonic!"));
        Assert.True(Origin.IsSiteUrl("https://flyingtulip.com/lend/dashboard/"));
        Assert.False(Origin.IsSiteUrl("https://evil.example/https://flyingtulip.com/"));
        Assert.False(Origin.IsSiteUrl("http://flyingtulip.com/"));
    }

    [Fact]
    public void Market_url_and_os_labels()
    {
        Assert.Equal("https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=1&marketType=spot", Origin.MarketUrl("FT-ftUSD", 1));
        Assert.Equal("Windows 11", Origin.OsLabel(new Version(10, 0, 22631)));
        Assert.Equal("Windows 10", Origin.OsLabel(new Version(10, 0, 19045)));
        Assert.Equal("windows-11", Origin.OsSlug("Windows 11"));
    }
}

public class StatsTests
{
    [Fact]
    public async Task Payload_has_the_other_widgets_shape_with_the_windows_widget_platform()
    {
        var rig = new Rig();
        await rig.Stats.SendAsync("Link click", ("element", "market-fees"), ("url", "https://flyingtulip.com/statistics/"));
        var post = Assert.Single(rig.Sink.Posts);
        var e = JsonNode.Parse(post.Body)!;
        Assert.Equal("Link click", e["name"]!.GetValue<string>());
        Assert.Equal("app://widget/windows-widget", e["url"]!.GetValue<string>());
        Assert.Equal("widget", e["domain"]!.GetValue<string>());
        Assert.Equal("windows-widget", e["props"]!["platform"]!.GetValue<string>());
        Assert.Equal("1.0.0", e["props"]!["version"]!.GetValue<string>());
        Assert.Equal("market-fees", e["props"]!["element"]!.GetValue<string>());
        Assert.Contains("FlyingTulipWidget/1.0.0", post.Ua);
        Assert.Equal("https://plausible.io/api/event", UsageStats.Endpoint);
    }

    [Fact]
    public async Task A_wallet_address_never_leaves_even_inside_a_value()
    {
        var rig = new Rig();
        await rig.Stats.SendAsync("Link click", ("element", "x"), ("url", "https://flyingtulip.com/trade/?address=" + Fx.Wallet + "&b=" + Fx.Wallet2.ToUpperInvariant().Replace("0X", "0x")));
        var body = rig.Sink.Posts[0].Body;
        Assert.DoesNotContain("0x38a5", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("0x47a7", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(":address", body);
    }

    [Fact]
    public async Task Off_means_nothing_is_sent()
    {
        var rig = new Rig(statsOn: false);
        Assert.False(await rig.Stats.SendAsync("Refresh"));
        await rig.Stats.PanelOpenAsync();
        await rig.Stats.PageviewAsync("Windows 11", "Widgets Board", 1);
        await rig.Stats.FetchErrorAsync("lend");
        Assert.Empty(rig.Sink.Posts);
    }

    [Fact]
    public async Task An_event_name_is_capped_at_30_an_hour()
    {
        var rig = new Rig();
        for (int i = 0; i < 40; i++) await rig.Stats.SendAsync("Refresh");
        Assert.Equal(30, rig.Sink.Posts.Count);
        rig.Now = rig.Now.AddHours(1);
        Assert.True(await rig.Stats.SendAsync("Refresh"));
    }

    [Fact]
    public async Task Switching_off_sends_one_last_event_then_nothing_and_on_sends_one()
    {
        var rig = new Rig();
        await rig.Stats.SwitchAsync(false, "Windows 11", v => rig.Store.State.StatsOn = v);
        Assert.Equal(new[] { "Usage stats off" }, rig.Sink.Names);
        Assert.Equal("Windows 11", rig.Sink.Events.First()["props"]!["os"]!.GetValue<string>());
        Assert.False(rig.Store.State.StatsOn);
        await rig.Stats.SendAsync("Refresh");
        Assert.Single(rig.Sink.Posts);
        await rig.Stats.SwitchAsync(true, "Windows 11", v => rig.Store.State.StatsOn = v);
        Assert.Equal(new[] { "Usage stats off", "Usage stats on" }, rig.Sink.Names);
        await rig.Stats.SwitchAsync(true, "Windows 11", v => rig.Store.State.StatsOn = v);   // unchanged: no event
        Assert.Equal(2, rig.Sink.Posts.Count);
    }

    [Fact]
    public async Task Fetch_error_once_an_hour_per_endpoint_and_pageview_once_a_day()
    {
        var rig = new Rig();
        await rig.Stats.FetchErrorAsync("lend"); await rig.Stats.FetchErrorAsync("lend"); await rig.Stats.FetchErrorAsync("fees");
        Assert.Equal(new[] { "Fetch error", "Fetch error" }, rig.Sink.Names);
        rig.Now = rig.Now.AddMinutes(61);
        await rig.Stats.FetchErrorAsync("lend");
        Assert.Equal(3, rig.Sink.Posts.Count);
        await rig.Stats.PageviewAsync("Windows 11", "Widgets Board", 2);
        await rig.Stats.PageviewAsync("Windows 11", "Widgets Board", 2);
        var pv = rig.Sink.Events.Where(e => e["name"]!.GetValue<string>() == "pageview").ToList();
        Assert.Single(pv);
        Assert.Equal("2", pv[0]["props"]!["walletsConfigured"]!.GetValue<string>());
        Assert.Equal("3+", UsageStats.WalletsBucket(7));
    }

    [Fact]
    public async Task A_sink_that_throws_never_breaks_the_widget()
    {
        var stats = new UsageStats(new ThrowingSink(), () => true, () => DateTimeOffset.UtcNow);
        Assert.False(await stats.SendAsync("Refresh"));
    }

    sealed class ThrowingSink : IEventSink { public Task PostAsync(string b, string u) => throw new HttpRequestException("offline"); }
}
