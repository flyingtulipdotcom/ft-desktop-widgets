using System.Text.Json.Nodes;
using Xunit;

namespace FlyingTulip.Widget.Tests;

public class ParseTests
{
    [Fact]
    public void Price_is_the_FT_ftUSD_market_price_not_nav()
    {
        var p = Parse.Price(Fx.Json("tickers.json"))!;
        Assert.Equal(0.150142400806860993, p.Price, 12);
        Assert.Null(Parse.Price(JsonNode.Parse("{\"data\":{\"tickers\":[{\"display_symbol\":\"WETH-ftUSD\",\"price\":\"1\"}]}}")));
        Assert.Null(Parse.Price(JsonNode.Parse("{}")));
    }

    [Fact]
    public void Fees_24h_lifetime_and_products_sorted()
    {
        var f = Parse.Fees(Fx.Json("fees.json"))!;
        Assert.Equal(949.658517, f.Period24h, 6);
        Assert.Equal(120841.606091, f.Lifetime, 6);
        Assert.True(f.Products.Count > 1);
        Assert.Equal(f.Products.OrderByDescending(x => x.Usd).Select(x => x.Name), f.Products.Select(x => x.Name));
        Assert.Null(Parse.Fees(JsonNode.Parse("{\"data\":{}}")));
    }

    [Fact]
    public void Series_and_klines()
    {
        var s = Parse.FeesSeries(Fx.Json("fees_series.json"))!;
        Assert.Equal(31, s.Count);
        Assert.Equal("2026-09-10", s[0].Date);
        var k = Parse.Klines(Fx.Json("klines.json"))!;
        Assert.Equal(30, k.Count);
        Assert.Equal(0.100950591269940267, k[0].Value, 12);
        Assert.Null(Parse.Klines(JsonNode.Parse("[]")));
    }

    [Fact]
    public void Day_over_day_uses_finished_days_only()
    {
        var s = Parse.FeesSeries(Fx.Json("fees_series.json"))!;
        var now = DateTimeOffset.Parse("2026-10-10T18:00:00Z");   // the last bucket is today, still partial
        var finished = s.Take(s.Count - 1).ToList();
        var expected = (finished[^1].Value - finished[^2].Value) / finished[^2].Value * 100;
        Assert.Equal(expected, Parse.FeesDayOverDay(s, now), 9);
        Assert.True(double.IsNaN(Parse.FeesDayOverDay(s.Take(3).ToList(), now)));
    }

    [Fact]
    public void Lend_health_no_debt_is_infinity_and_lowest_wins()
    {
        var chains = Parse.Lend(Fx.Json("lend.json"));
        Assert.Equal(3, chains.Count);
        Assert.Null(chains.First(c => c.ChainId == 1).Hf);
        var low = Parse.LowestHf(chains)!;
        Assert.Equal("Sonic", low.Name);
        Assert.Equal(1.9, low.Hf!.Value, 6);
        Assert.Equal(1.25, low.LiqHf);
        Assert.Equal("∞", Fmt.Hf(null));
        Assert.Equal("BNB", Parse.HfChains[56]);
    }

    [Fact]
    public void Merge_orders_chains_and_later_lists_win()
    {
        var a = new List<ChainHealth> { new(1, "Ethereum", null, 0, 0, 1.25), new(146, "Sonic", 2.0, 5, 1, 1.25) };
        var b = new List<ChainHealth> { new(146, "Sonic", 1.5, 5, 1, 1.25), new(143, "Monad", null, 0, 0, 1.25) };
        var m = Parse.MergeChains(a, b);
        Assert.Equal(new[] { 146, 1, 143 }, m.Select(c => c.ChainId));
        Assert.Equal(1.5, m[0].Hf);
    }

    [Fact]
    public void Rewards_sum_sftUSD_yield_and_lend_rewards()
    {
        var r = Parse.Rewards(JsonNode.Parse(Fx.Rewards))!;
        Assert.Equal(153.0, r.TotalFt, 6);
        Assert.Equal(103.0, r.SftFt, 6);
        Assert.Equal(50.0, r.LendFt, 6);
        Assert.Equal(3.0, r.ClaimableFt, 6);
        Assert.Equal("Sonic 153.0", Parse.EarnedByChain(r));
    }

    [Fact]
    public void Rewards_total_is_unknown_when_a_section_errored()
    {
        var body = JsonNode.Parse("{\"success\":true,\"data\":{\"sectionErrors\":{\"lend\":true},\"chains\":[{\"chainId\":146,\"staking\":{\"pending_yield_ft\":\"0\",\"claimed_yield_ft\":\"0\",\"claimed_yield_indexed_through_block\":1,\"claimed_yield_stale\":false}}]}}");
        Assert.True(double.IsNaN(Parse.Rewards(body)!.TotalFt));
        Assert.Null(Parse.Rewards(JsonNode.Parse("{\"success\":false}")));
    }

    [Fact]
    public void Points_total_and_chains_largest_first_and_rank_page()
    {
        var p = Parse.Points(JsonNode.Parse(Fx.Points))!;
        Assert.Equal(922000, p.Total);
        Assert.Equal(new[] { "Sonic", "Ethereum" }, p.Chains.Select(c => c.Name));
        var page = JsonNode.Parse(Fx.LeaderboardPage("page=2", Fx.Wallet, 777))!;
        var r = Parse.RankInPage(page, Fx.Wallet.ToUpperInvariant().Replace("0X", "0x"), 922000);
        Assert.True(r.Found); Assert.Equal(777, r.Rank); Assert.Equal(2000, r.Total);
        var other = Parse.RankInPage(JsonNode.Parse(Fx.LeaderboardPage("page=1", Fx.Wallet, 777)), Fx.Wallet2, 5_000_000);
        Assert.False(other.Found); Assert.Equal(-1, other.Dir);   // more points than the page: an earlier page
    }

    [Fact]
    public void Positions_puts_gain_and_breakdown()
    {
        var pos = Parse.Positions(JsonNode.Parse(Fx.Positions));
        Assert.Single(pos);
        Assert.Equal("long", pos[0].Side); Assert.Equal(50.0, pos[0].ValueUsd, 6); Assert.Equal(3, pos[0].Leverage);
        Assert.Empty(Parse.Positions(JsonNode.Parse("[]")));
        var puts = Parse.Puts(JsonNode.Parse(Fx.Puts))!;
        Assert.Equal(999.60146, puts.CostUsd, 4);
        Assert.Equal("2026-01-20", puts.Rows[0].Since);
        var g = Parse.PutGain(puts, 0.15)!;   // FT held x FT MARKET price - cost basis
        Assert.Equal(9996.0146 * 0.15 - 999.60146, g.GainUsd, 3);
        Assert.Null(Parse.PutGain(puts, double.NaN));
        var br = Parse.PointsBreakdown(JsonNode.Parse(Fx.Breakdown));
        Assert.Equal(new[] { "Lend Borrow", "ftusd hold" }, br.Select(b => b.Label));
    }

    [Fact]
    public void Rewards_history_ignores_a_partial_today_and_daily_gains_are_differences()
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var s = Parse.RewardsSeries(JsonNode.Parse(Fx.History(now)), now)!;
        Assert.Equal(12, s.Count);
        Assert.Equal(11, Parse.DailyGains(s).Count);
        Assert.All(Parse.DailyGains(s), g => Assert.Equal(2.0, g.Value, 6));
    }

    [Theory]
    [InlineData("https://api.flyingtulip.com/mm/spot/tickers?chainId=1", "ticker")]
    [InlineData("https://api.flyingtulip.com/fees/application?period=1d", "fees")]
    [InlineData("https://api.flyingtulip.com/mm/spot/market/klines?symbol=FT-ftUSD", "klines")]
    [InlineData("https://api.flyingtulip.com/mm/lend?user=0xabc", "lend")]
    [InlineData("https://api.flyingtulip.com/mm/lend?user=0xabc&chainId=143", "")]
    [InlineData("https://api.flyingtulip.com/mm/spot/account/summary?address=0xabc&chainId=1", "summary")]
    [InlineData("https://api.flyingtulip.com/account/dashboard?address=0xabc&view=rewards", "rewards")]
    [InlineData("https://api.flyingtulip.com/points/leaderboard?page=1", "leaderboard")]
    [InlineData("https://api.flyingtulip.com/points?walletAddress=0xabc", "points")]
    [InlineData("https://api.flyingtulip.com/mm/spot/account/positions?address=0xabc&chainId=1", "positions")]
    [InlineData("https://api.flyingtulip.com/tge/ftPUT/user/0xabc", "ftput")]
    public void Endpoint_names_for_the_fetch_error_event(string url, string name) => Assert.Equal(name, Parse.EndpointName(url));
}

public class FormatTests
{
    [Theory]
    [InlineData(954.35, "$954")] [InlineData(12.3456, "$12.35")] [InlineData(1080, "$1.08k")] [InlineData(20800, "$20.8k")]
    [InlineData(2_500_000, "$2.50M")] [InlineData(double.NaN, "—")]
    public void Usd(double v, string expected) => Assert.Equal(expected, Fmt.Usd(v));

    [Theory]
    [InlineData(0.150151, "$0.1502")] [InlineData(2507.5, "$2507.50")] [InlineData(double.NaN, "—")]
    public void Price(double v, string expected) => Assert.Equal(expected, Fmt.Price(v));

    [Theory]
    [InlineData(2.7278, "+2.7%")] [InlineData(-9.3, "-9.3%")] [InlineData(150.4, "+150%")]
    public void Pct(double v, string expected) => Assert.Equal(expected, Fmt.Pct(v));

    [Theory]
    [InlineData(0.0, "0")] [InlineData(0.004, "<0.01")] [InlineData(5.884, "5.88")] [InlineData(95.43, "95.4")] [InlineData(5880.0, "5.88K")] [InlineData(25000.0, "25.0K")] [InlineData(2.5e6, "2.50M")]
    public void Ft(double v, string expected) => Assert.Equal(expected, Fmt.Ft(v));

    [Theory]
    [InlineData(922000.0, "922K")] [InlineData(30_900_000.0, "30.9M")] [InlineData(1.5e9, "1.50B")] [InlineData(42.0, "42")]
    public void Points(double v, string expected) => Assert.Equal(expected, Fmt.Points(v));

    [Fact]
    public void Hf_and_signed_usd_and_wallets()
    {
        Assert.Equal("1.92", Fmt.Hf(1.9234)); Assert.Equal(">100", Fmt.Hf(120));
        Assert.Equal("+$13.1k", Fmt.SignedUsd(13100)); Assert.Equal("$0.00", Fmt.SignedUsd(0.001)); Assert.Equal("-$5.00", Fmt.SignedUsd(-5));
        Assert.Equal("0x38a5…2d62", Fmt.ShortAddr(Fx.Wallet));
        var (list, bad) = Fmt.ParseWallets(Fx.Wallet.ToUpperInvariant().Replace("0X", "0x") + ", " + Fx.Wallet2 + ";" + Fx.Wallet + " nope");
        Assert.Equal(new[] { Fx.Wallet, Fx.Wallet2 }, list);
        Assert.Equal(new[] { "nope" }, bad);
    }

    [Fact]
    public void Hf_levels_are_colour_only()
    {
        Assert.Equal(0, Parse.HfLevel(1.9)); Assert.Equal(1, Parse.HfLevel(1.35)); Assert.Equal(2, Parse.HfLevel(1.28));
    }
}
