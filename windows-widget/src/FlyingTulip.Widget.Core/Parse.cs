using System.Text.Json.Nodes;

namespace FlyingTulip.Widget;

public sealed record FeesData(double Period24h, double Lifetime, List<(string Name, double Usd)> Products);
public sealed record PriceData(double Price, double ChangePct24h, string SampledAt);
public sealed record ChainHealth(int ChainId, string Name, double? Hf, double DebtUsd, double EquityUsd, double LiqHf);
public sealed record DatedValue(string Date, double Value);
public sealed record EarnedChain(int ChainId, string Name, double Sft, double Lend);
public sealed record RewardsData(double TotalFt, double ClaimableFt, double SftClaimed, double SftPending, double SftFt,
    double LendReceived, double LendPending, double LendFt, List<EarnedChain> Chains);
public sealed record PutRow(string Nft, string Symbol, int ChainId, double Capital, double Strike, double CostUsd, double Ft, string Since);
public sealed record PutsData(int Count, double CostUsd, double FtHeld, List<PutRow> Rows);
public sealed record PutGainData(double ValueUsd, double GainUsd, double GainPct);
public sealed record PointsChain(int ChainId, string Name, double Points);
public sealed record PointsData(double Total, List<PointsChain> Chains);
public sealed record RankPage(bool Found, int Rank, int Dir, int Total, bool Empty);
public sealed record RankData(int Rank, int Total);
public sealed record PositionData(string Network, int ChainId, string Market, string Symbol, string Side, double Size,
    double Entry, double Mark, double PnlUsd, double PnlPct, double Leverage, double ValueUsd);
public sealed record RewardsPoint(long Ts, string Date, double Earned, double Claimed);
public sealed record BreakdownRow(string Label, double PositionUsd, double Multiplier);

/// <summary>Parsers for the public API answers. Every one tolerates missing fields and returns null on an unusable payload.</summary>
public static class Parse
{
    public const double DefaultLiqHf = 1.25;
    public static readonly Dictionary<int, string> HfChains = new() { [146] = "Sonic", [1] = "Ethereum", [56] = "BNB", [143] = "Monad" };
    public static readonly int[] HfChainIds = { 146, 1, 56, 143 };

    static string ChainName(int id, string? fallback = null) =>
        HfChains.TryGetValue(id, out var n) ? n : (fallback ?? id.ToString());

    public static FeesData? Fees(JsonNode? body)
    {
        var d = body?["data"];
        var totals = d?["totals"];
        if (totals is null) return null;
        var period = Fmt.Num(totals["period_usd"]);
        if (!double.IsFinite(period)) return null;
        var products = new List<(string, double)>();
        if (d?["byProduct"] is JsonObject bp)
            foreach (var kv in bp)
            {
                var v = Fmt.Num(kv.Value?["period_usd"]);
                if (double.IsFinite(v)) products.Add((kv.Key, v));
            }
        products = products.OrderByDescending(p => p.Item2).ToList();
        return new FeesData(period, Fmt.Num(totals["lifetime_usd"]), products);
    }

    public static PriceData? Price(JsonNode? body)
    {
        if (body?["data"]?["tickers"] is not JsonArray ts) return null;
        foreach (var t in ts)
        {
            if (Fmt.Str(t?["display_symbol"]) != "FT-ftUSD") continue;
            var p = Fmt.Num(t?["price"]);
            if (!double.IsFinite(p)) return null;
            return new PriceData(p, Fmt.Num(t?["price_change_pct_24h"]), Fmt.Str(t?["sampled_at"]) ?? "");
        }
        return null;
    }

    public static List<ChainHealth> Lend(JsonNode? body)
    {
        var d = body?["data"] ?? body;
        var outList = new List<ChainHealth>();
        if (d?["chains"] is not JsonArray chains) return outList;
        foreach (var c in chains)
        {
            var m = c?["userMetrics"];
            var debt = Fmt.Num(m?["totalDebtUsd"]);
            var hf = Fmt.Num(m?["healthFactor"]);
            var hasDebt = double.IsFinite(debt) && debt > 0.01;
            var id = (int)Fmt.Num(c?["chainId"]);
            var liq = Fmt.Num(c?["hfLiquidationThreshold"]);
            outList.Add(new ChainHealth(id, ChainName(id, Fmt.Str(c?["chainName"])),
                hasDebt && double.IsFinite(hf) ? hf : null, double.IsFinite(debt) ? debt : 0,
                Fmt.Num(m?["equityUsd"]), double.IsFinite(liq) ? liq : DefaultLiqHf));
        }
        return outList;
    }

    public static List<ChainHealth> MergeChains(params List<ChainHealth>[] lists)
    {
        var byId = new Dictionary<int, ChainHealth>();
        foreach (var l in lists) foreach (var c in l) byId[c.ChainId] = c;
        return byId.Values.OrderBy(c => { var i = Array.IndexOf(HfChainIds, c.ChainId); return i < 0 ? 99 : i; }).ToList();
    }

    public static ChainHealth? LowestHf(IEnumerable<ChainHealth>? chains)
    {
        ChainHealth? best = null;
        foreach (var c in chains ?? Array.Empty<ChainHealth>())
        {
            if (c.Hf is null) continue;
            if (best is null || c.Hf < best.Hf) best = c;
        }
        return best;
    }

    /// <summary>/mm/spot/account/summary: the unrealized PnL of one chain, null when there is no usable answer.</summary>
    public static (int ChainId, double PnlUsd)? Summary(JsonNode? body)
    {
        var arr = body as JsonArray ?? body?["data"] as JsonArray;
        if (arr is null || arr.Count == 0) return null;
        var pnl = Fmt.Num(arr[0]?["unrealizedPnl"]);
        return ((int)Fmt.Num(arr[0]?["chainId"]), double.IsFinite(pnl) ? pnl : 0);
    }

    /// <summary>/account/dashboard?view=rewards: FT earned all time and all chains (sftUSD yield + Lend FT rewards).</summary>
    public static RewardsData? Rewards(JsonNode? body)
    {
        if (body?["success"] is JsonValue sv && sv.TryGetValue<bool>(out var ok) && !ok) return null;
        if (body?["data"]?["chains"] is not JsonArray chains) return null;
        var errs = body["data"]?["sectionErrors"];
        bool stakingFailed = errs?["staking"] is not null && errs["staking"]!.ToString() is not ("false" or "null" or "");
        bool lendFailed = errs?["lend"] is not null && errs["lend"]!.ToString() is not ("false" or "null" or "");
        bool known = !stakingFailed && !lendFailed;
        double claimable = 0, sftClaimed = 0, sftPending = 0, lendReceived = 0, lendPending = 0;
        var list = new List<EarnedChain>();
        foreach (var c in chains)
        {
            var st = c?["staking"]; var lend = c?["lend"]; var lm = lend?["userMetrics"];
            double pendingSft = st is not null ? Fmt.RawFt(Fmt.Str(st["pending_yield_ft"])) : (stakingFailed ? double.NaN : 0);
            double claimedSft = double.NaN;
            if (st is not null)
            {
                var through = st["claimed_yield_indexed_through_block"];
                var stale = st["claimed_yield_stale"] is JsonValue sx && sx.TryGetValue<bool>(out var sb) && sb;
                claimedSft = through is not null && !stale ? Fmt.RawFt(Fmt.Str(st["claimed_yield_ft"])) : double.NaN;
            }
            else claimedSft = stakingFailed ? double.NaN : 0;
            double rec = lendFailed ? double.NaN : 0, pen = lendFailed ? double.NaN : 0;
            if (lend is not null)
            {
                var fr = lm?["ftRewards"];
                if (lm?["ftRewardsError"] is not null) { rec = pen = double.NaN; }
                else if (fr is not null) { rec = Fmt.RawFt(Fmt.Str(fr["receivedFtRaw"])); pen = Fmt.RawFt(Fmt.Str(fr["pendingFtRaw"])); }
                else if (lm is null) { rec = pen = double.NaN; }
                else { rec = pen = 0; }
            }
            if (double.IsFinite(pendingSft)) claimable += pendingSft;
            if (!double.IsFinite(pendingSft) || !double.IsFinite(claimedSft) || !double.IsFinite(rec) || !double.IsFinite(pen)) { known = false; continue; }
            sftClaimed += claimedSft; sftPending += pendingSft; lendReceived += rec; lendPending += pen;
            var id = (int)Fmt.Num(c?["chainId"]);
            list.Add(new EarnedChain(id, ChainName(id), claimedSft + pendingSft, rec + pen));
        }
        var sft = sftClaimed + sftPending; var lendFt = lendReceived + lendPending;
        return new RewardsData(known ? sft + lendFt : double.NaN, claimable, sftClaimed, sftPending, sft, lendReceived, lendPending, lendFt, list);
    }

    /// <summary>Chains that earned something, as "Sonic 95.4, Ethereum 0.06".</summary>
    public static string EarnedByChain(RewardsData? r) =>
        r is null ? "" : string.Join(", ", r.Chains.Where(c => c.Sft + c.Lend >= 0.005).Select(c => c.Name + " " + Fmt.Ft(c.Sft + c.Lend)));

    /// <summary>/tge/ftPUT/user/&lt;wallet&gt;: cost basis = sum(current_capital * strike), FT held = current_ft + withdrawn_ft.</summary>
    public static PutsData? Puts(JsonNode? body)
    {
        if (body?["data"]?["positions"] is not JsonArray ps || ps.Count == 0) return null;
        double cost = 0, held = 0; var rows = new List<PutRow>();
        foreach (var p in ps)
        {
            var dec = Fmt.Num(p?["token_decimals"]);
            if (!double.IsFinite(dec)) { dec = Fmt.Num(p?["tokenData"]?["decimals"]); if (!double.IsFinite(dec) || dec == 0) dec = 18; }
            var strike = Fmt.RawUnits(Fmt.Str(p?["strike"]), 8);
            var cap = Fmt.RawUnits(Fmt.Str(p?["current_capital"]), (int)dec);
            var ftC = Fmt.RawUnits(Fmt.Str(p?["current_ft"]), 18);
            var ftW = Fmt.RawUnits(Fmt.Str(p?["withdrawn_ft"]), 18);
            if (!double.IsFinite(strike) || !double.IsFinite(cap) || !double.IsFinite(ftC)) continue;
            if (!double.IsFinite(ftW)) ftW = 0;
            cost += cap * strike; held += ftC + ftW;
            var cid = Fmt.Num(p?["chain_id"]);
            var created = Fmt.Str(p?["created_at"]) ?? "";
            rows.Add(new PutRow(Fmt.Str(p?["nft_id"]) ?? "", Fmt.Str(p?["token_symbol"]) ?? Fmt.Str(p?["tokenData"]?["symbol"]) ?? "?",
                double.IsFinite(cid) ? (int)cid : 0, cap, strike, cap * strike, ftC + ftW, created.Length >= 10 ? created[..10] : ""));
        }
        return rows.Count == 0 ? null : new PutsData(rows.Count, cost, held, rows);
    }

    /// <summary>gain = FT held x FT MARKET price - cost basis (never NAV).</summary>
    public static PutGainData? PutGain(PutsData? puts, double ftPrice)
    {
        if (puts is null || !double.IsFinite(ftPrice)) return null;
        var value = puts.FtHeld * ftPrice; var gain = value - puts.CostUsd;
        return new PutGainData(value, gain, puts.CostUsd > 0 ? gain / puts.CostUsd * 100 : double.NaN);
    }

    /// <summary>/points?walletAddress=: the all-chains total (what the leaderboard ranks) plus each chain's share, largest first.</summary>
    public static PointsData? Points(JsonNode? body)
    {
        if (body?["data"]?["chains"] is not JsonArray chains) return null;
        double total = double.NaN; var per = new List<PointsChain>();
        foreach (var c in chains)
        {
            var v = c?["userMetrics"] is null ? double.NaN : Fmt.Num(c["userMetrics"]!["totalPoints"]);
            if (c?["isAllChains"] is JsonValue av && av.TryGetValue<bool>(out var all) && all) { total = v; continue; }
            if (!(v > 0)) continue;
            var idn = Fmt.Num(c?["chainData"]?["id"]);
            var id = double.IsFinite(idn) ? (int)idn : -1;
            per.Add(new PointsChain(id, HfChains.TryGetValue(id, out var n) ? n : Fmt.Str(c?["chainData"]?["name"]) ?? "?", v));
        }
        if (!double.IsFinite(total)) return null;
        return new PointsData(total, per.OrderByDescending(p => p.Points).ToList());
    }

    /// <summary>/points/breakdown: the positions that earn points, with their multiplier.</summary>
    public static List<BreakdownRow> PointsBreakdown(JsonNode? body)
    {
        var list = new List<BreakdownRow>();
        if (body?["data"]?["pointsBreakdown"] is not JsonArray rows) return list;
        foreach (var r in rows)
        {
            var prod = Fmt.Str(r?["productLabel"]) ?? Fmt.Str(r?["product"]) ?? "";
            var act = Fmt.Str(r?["activityLabel"]) ?? Fmt.Str(r?["activity"]) ?? "";
            list.Add(new BreakdownRow((prod + " " + act).Trim(), Fmt.Num(r?["positionUsd"]), Fmt.Num(r?["multiplier"])));
        }
        return list;
    }

    /// <summary>One leaderboard page. Dir -1: the wallet is on an earlier page, +1 on a later one.</summary>
    public static RankPage RankInPage(JsonNode? body, string wallet, double myPoints)
    {
        var lb = body?["data"]?["leaderboard"] as JsonArray;
        var totalN = Fmt.Num(body?["data"]?["pagination"]?["total"]);
        int total = double.IsFinite(totalN) ? (int)totalN : 0;
        if (lb is null || lb.Count == 0) return new RankPage(false, 0, 0, total, true);
        var w = wallet.ToLowerInvariant();
        foreach (var e in lb)
            if ((Fmt.Str(e?["userWallet"]) ?? "").ToLowerInvariant() == w)
                return new RankPage(true, (int)Fmt.Num(e?["rank"]), 0, total, false);
        var first = Fmt.Num(lb[0]?["totalPoints"]); var last = Fmt.Num(lb[^1]?["totalPoints"]);
        return new RankPage(false, 0, myPoints > first ? -1 : (myPoints < last ? 1 : 0), total, false);
    }

    public static List<PositionData> Positions(JsonNode? body)
    {
        var list = new List<PositionData>();
        var arr = body as JsonArray ?? body?["data"] as JsonArray;
        if (arr is null) return list;
        foreach (var p in arr)
        {
            var size = Fmt.Num(p?["size"]); var mark = Fmt.Num(p?["markPrice"]);
            if (!double.IsFinite(size) || size <= 0) continue;
            var idn = Fmt.Num(p?["chainId"]); var id = double.IsFinite(idn) ? (int)idn : 0;
            var sym = Fmt.Str(p?["symbol"]) ?? "";
            var lev = Fmt.Num(p?["blendedLeverage"]); if (!(lev > 0)) lev = Fmt.Num(p?["leverage"]);
            list.Add(new PositionData(Fmt.Str(p?["network"]) ?? ChainName(id), id, sym,
                Fmt.Str(p?["sizeCurrency"]) ?? (sym.Split('-')[0] is { Length: > 0 } s0 ? s0 : "?"),
                (Fmt.Str(p?["side"]) ?? "").ToLowerInvariant() == "short" ? "short" : "long", size,
                Fmt.Num(p?["entryPrice"]), mark, Fmt.Num(p?["pnlAmount"]), Fmt.Num(p?["pnlPct"]), lev,
                double.IsFinite(mark) ? size * mark : double.NaN));
        }
        return list;
    }

    public static List<PositionData> SortPositions(IEnumerable<PositionData> rows) =>
        rows.OrderByDescending(r => double.IsFinite(r.ValueUsd) ? r.ValueUsd : 0).ToList();

    public static List<DatedValue>? FeesSeries(JsonNode? body)
    {
        if (body?["data"]?["series"] is not JsonArray s || s.Count == 0) return null;
        var list = new List<DatedValue>();
        foreach (var e in s)
        {
            var v = Fmt.Num(e?["total_usd"]);
            if (double.IsFinite(v)) list.Add(new DatedValue(Fmt.Str(e?["date"]) ?? "", v));
        }
        return list.Count == 0 ? null : list;
    }

    /// <summary>Market closes (never NAV).</summary>
    public static List<DatedValue>? Klines(JsonNode? body)
    {
        if (body is not JsonArray a || a.Count == 0) return null;
        var list = new List<DatedValue>();
        foreach (var k in a)
        {
            var c = Fmt.Num(k?["close"]); var t = Fmt.Num(k?["time"]);
            if (double.IsFinite(c) && double.IsFinite(t))
                list.Add(new DatedValue(DateTimeOffset.FromUnixTimeMilliseconds((long)t).UtcDateTime.ToString("yyyy-MM-dd"), c));
        }
        return list.Count == 0 ? null : list;
    }

    /// <summary>/account/rewards/history: cumulative FT at UTC day ends (a partial today is ignored).</summary>
    public static List<RewardsPoint>? RewardsSeries(JsonNode? body, long nowSec)
    {
        if (body?["data"]?["points"] is not JsonArray pts || pts.Count == 0) return null;
        const long Day = 86400;
        var today = nowSec / Day * Day;
        var rows = new List<RewardsPoint>();
        foreach (var p in pts)
        {
            var tsn = Fmt.Num(p?["timestampUnixSeconds"]);
            if (!double.IsFinite(tsn)) continue;
            var ts = (long)tsn;
            if (ts >= today || ts % Day != Day - 1) continue;
            var e = Fmt.RawUnits(Fmt.Str(p?["totalEarnedFtRaw"]), 18);
            var c = Fmt.RawUnits(Fmt.Str(p?["claimedFtRaw"]), 18);
            if (!double.IsFinite(e)) continue;
            rows.Add(new RewardsPoint(ts, DateTimeOffset.FromUnixTimeSeconds(ts).UtcDateTime.ToString("yyyy-MM-dd"), e, double.IsFinite(c) ? c : 0));
        }
        rows.Sort((a, b) => a.Ts.CompareTo(b.Ts));
        return rows.Count == 0 ? null : rows;
    }

    /// <summary>Per-day FT gained from a cumulative series (earned or claimed).</summary>
    public static List<DatedValue> DailyGains(List<RewardsPoint>? series, bool claimed = false)
    {
        var list = new List<DatedValue>();
        if (series is null) return list;
        for (int i = 1; i < series.Count; i++)
        {
            if (series[i].Ts - series[i - 1].Ts != 86400) continue;
            var cur = claimed ? series[i].Claimed : series[i].Earned; var prev = claimed ? series[i - 1].Claimed : series[i - 1].Earned;
            list.Add(new DatedValue(series[i].Date, Math.Max(0, cur - prev)));
        }
        return list;
    }

    /// <summary>Day-over-day % across finished days (the last bucket is the partial current day).</summary>
    public static double FeesDayOverDay(List<DatedValue>? series, DateTimeOffset now)
    {
        if (series is null || series.Count < 4) return double.NaN;
        var today = now.UtcDateTime.ToString("yyyy-MM-dd");
        var rows = series[^1].Date.Length >= 10 && series[^1].Date[..10] == today ? series.Take(series.Count - 1).ToList() : series;
        if (rows.Count < 2) return double.NaN;
        double last = rows[^1].Value, prev = rows[^2].Value;
        return prev > 0 ? (last - prev) / prev * 100 : double.NaN;
    }

    /// <summary>0 ok, 1 warning, 2 critical (colour only: the widget shows no notifications).</summary>
    public static int HfLevel(double hf, double warn = 1.40, double critical = 1.30) => hf <= critical ? 2 : (hf <= warn ? 1 : 0);

    public static string EndpointName(string url)
    {
        var path = url.Replace("https://api.flyingtulip.com", "");
        if (path.Contains("chainId=143")) return "";
        if (path.StartsWith("/mm/spot/tickers")) return "ticker";
        if (path.StartsWith("/fees/")) return "fees";
        if (path.Contains("klines")) return "klines";
        if (path.StartsWith("/mm/lend")) return "lend";
        if (path.Contains("account/summary")) return "summary";
        if (path.Contains("account/positions")) return "positions";
        if (path.Contains("account/dashboard")) return "rewards";
        if (path.Contains("rewards/history")) return "rewards-history";
        if (path.StartsWith("/points/leaderboard")) return "leaderboard";
        if (path.StartsWith("/points/breakdown")) return "points-breakdown";
        if (path.StartsWith("/points")) return "points";
        if (path.StartsWith("/tge/ftPUT")) return "ftput";
        return "other";
    }
}
