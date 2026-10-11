using System.Text.Json.Nodes;
using FlyingTulip.Widget;

namespace FlyingTulip.Widget.Tests;

public static class Fx
{
    public static string Read(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", name));
    public static JsonNode Json(string name) => JsonNode.Parse(Read(name))!;
    public const string Wallet = "0x38a564a38be5dfb6ef2ab765da1e4397d03c2d62";
    public const string Wallet2 = "0x47a761bb9e970ac93cb571c4614c4ca643714e4f";

    public const string Rewards = """
    {"success":true,"data":{"chains":[{"chainId":146,
      "staking":{"pending_yield_ft":"3000000000000000000","claimed_yield_ft":"100000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false},
      "lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"50000000000000000000","pendingFtRaw":"0"}}}}]}}
    """;
    public const string Points = """
    {"data":{"chains":[{"isAllChains":true,"userMetrics":{"totalPoints":922000}},
      {"isAllChains":false,"chainData":{"id":146,"name":"Sonic"},"userMetrics":{"totalPoints":900000}},
      {"isAllChains":false,"chainData":{"id":1,"name":"Ethereum"},"userMetrics":{"totalPoints":22000}}]}}
    """;
    public const string Puts = """
    {"data":{"positions":[{"nft_id":"7","token_symbol":"USDT","token_decimals":6,"chain_id":1,"created_at":"2026-01-20T10:00:00Z","strike":"99960146","current_capital":"1000000000","current_ft":"9996014600000000000000","withdrawn_ft":"0"}]}}
    """;
    public const string Positions = """
    [{"chainId":146,"network":"Sonic","symbol":"wS-ftUSD","sizeCurrency":"wS","side":"long","size":"1000","markPrice":"0.05","entryPrice":"0.04","pnlAmount":"5","pnlPct":"10","blendedLeverage":"3"}]
    """;
    public const string Breakdown = """
    {"data":{"pointsBreakdown":[{"productLabel":"Lend","activityLabel":"Borrow","positionUsd":1711.2,"multiplier":1},{"product":"ftusd","activity":"hold","positionUsd":2091.7,"multiplier":1.5}]}}
    """;

    public static string History(long nowSec)
    {
        long day = 86400, today = nowSec / day * day;
        var pts = Enumerable.Range(1, 12).Select(i => today - i * day - 1).Reverse()
            .Select((ts, i) => $"{{\"timestampUnixSeconds\":{ts},\"claimedFtRaw\":\"{i}000000000000000000\",\"totalEarnedFtRaw\":\"{(i + 1) * 2}000000000000000000\"}}");
        return "{\"data\":{\"points\":[" + string.Join(",", pts) + "]}}";
    }

    public static string LeaderboardPage(string url, string wallet, int rank)
    {
        var page = int.Parse(System.Text.RegularExpressions.Regex.Match(url, @"page=(\d+)").Groups[1].Value);
        var rows = new List<string>();
        for (int r = (page - 1) * 500 + 1; r <= Math.Min(page * 500, 2000); r++)
            rows.Add($"{{\"rank\":{r},\"userWallet\":\"{(r == rank ? wallet : "0x" + r.ToString().PadLeft(40, '0'))}\",\"totalPoints\":{1000000 - r * 100}}}");
        return "{\"data\":{\"pagination\":{\"total\":2000},\"leaderboard\":[" + string.Join(",", rows) + "]}}";
    }
}

/// <summary>An API that answers from fixtures (the public answers, recorded) and remembers what was asked.</summary>
public sealed class FakeHttp : IHttp
{
    public readonly List<string> Calls = new();
    public readonly List<string> Fail = new();
    public Func<string, string?>? Override;

    public Task<string?> GetAsync(string url)
    {
        Calls.Add(url);
        if (Fail.Any(f => url.Contains(f))) return Task.FromResult<string?>(null);
        var o = Override?.Invoke(url);
        if (o is not null) return Task.FromResult<string?>(o);
        string? body =
            url.Contains("/mm/spot/tickers?chainId=1") ? Fx.Read("tickers.json") :
            url.Contains("fees/application?period=1d") ? Fx.Read("fees.json") :
            url.Contains("fees/application?period=1m") ? Fx.Read("fees_series.json") :
            url.Contains("klines") ? Fx.Read("klines.json") :
            url.Contains("/mm/lend?user=") && url.Contains("chainId=143") ? "{\"data\":{\"chains\":[]}}" :
            url.Contains("/mm/lend?user=") ? Fx.Read("lend.json") :
            url.Contains("account/summary") && url.Contains("chainId=146") ? "[{\"chainId\":146,\"unrealizedPnl\":\"12.5\"}]" :
            url.Contains("account/summary") && url.Contains("chainId=1") ? "[{\"chainId\":1,\"unrealizedPnl\":\"-2\"}]" :
            url.Contains("account/summary") ? null :
            url.Contains("account/dashboard") ? Fx.Rewards :
            url.Contains("points/breakdown") ? Fx.Breakdown :
            url.Contains("points/leaderboard") ? Fx.LeaderboardPage(url, Fx.Wallet, 777) :
            url.Contains("/points?walletAddress") ? Fx.Points :
            url.Contains("account/positions") && url.Contains("chainId=146") ? Fx.Positions :
            url.Contains("account/positions") ? "[]" :
            url.Contains("ftPUT") ? Fx.Puts : null;
        return Task.FromResult(body);
    }
}

public sealed class FakeSink : IEventSink
{
    public readonly List<(string Body, string Ua)> Posts = new();
    public Task PostAsync(string body, string userAgent) { Posts.Add((body, userAgent)); return Task.CompletedTask; }
    public IEnumerable<JsonNode> Events => Posts.Select(p => JsonNode.Parse(p.Body)!);
    public IEnumerable<string> Names => Events.Select(e => e["name"]!.GetValue<string>());
}

public sealed class Rig
{
    public readonly FakeHttp Http = new();
    public readonly FakeSink Sink = new();
    public readonly List<string> Opened = new();
    public readonly StateStore Store;
    public readonly UsageStats Stats;
    public readonly DataHub Hub;
    public readonly WidgetController Ctl;
    public DateTimeOffset Now = DateTimeOffset.Parse("2026-10-11T12:00:00Z");

    public Rig(bool statsOn = true)
    {
        Store = new StateStore(Path.Combine(Path.GetTempPath(), "ftw-test-" + Guid.NewGuid().ToString("N") + ".json"));
        Store.State.StatsOn = statsOn;
        Stats = new UsageStats(Sink, () => Store.State.StatsOn, () => Now, Store.State.Counters);
        Hub = new DataHub(Http, () => Now);
        Ctl = new WidgetController(Store, Hub, Stats, "Windows 11", () => Now, u => Opened.Add(u));
        Store.Widget("w1").Wallets = new() { Fx.Wallet };
        Store.Widget("w1").Normalize();
    }

    public Snapshot Snapshot(WidgetState st) => new()
    {
        Now = Now, Market = Hub.Market, Wallets = st.Wallets.ToList(), WalletAddr = st.Cur,
        Wallet = st.Cur.Length > 0 ? Hub.Wallet(st.Cur) : null, PriceChain = st.PriceChain,
    };
}
