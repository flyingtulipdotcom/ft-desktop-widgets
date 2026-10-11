using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FlyingTulip.Widget;

/// <summary>Everything the card shows, read from the caches at one moment.</summary>
public sealed class Snapshot
{
    public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
    public MarketData Market { get; set; } = new();
    public WalletData? Wallet { get; set; }
    public string WalletAddr { get; set; } = "";
    public List<string> Wallets { get; set; } = new();
    public List<string> BadWallets { get; set; } = new();
    public int PriceChain { get; set; } = 1;
    public bool RefreshFailed { get; set; }
    public bool StatsOn { get; set; } = true;
    public string Notice { get; set; } = "";
    public string WalletsText { get; set; } = "";
    public double HfWarn { get; set; } = 1.40;
    public double HfCritical { get; set; } = 1.30;
}

/// <summary>The data JSON the templates bind to: texts, colours (Adaptive Card colour names) and the charts as PNG data URIs.</summary>
public static class CardData
{
    const double LargeInner = 308, MediumHalf = 144, MediumGauge = 184, LargeGauge = 176;
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    static string Delta(double v) => !double.IsFinite(v) || Math.Abs(v) < 0.005 ? "default" : (v > 0 ? "good" : "attention");
    static string LevelColor(int level) => level == 2 ? "attention" : (level == 1 ? "warning" : "good");
    static string Style(bool on) => on ? "positive" : "default";
    static string Slug(string s) => Regex.Replace(s.ToLowerInvariant(), "[^a-z0-9]+", "-").Trim('-');
    static string MD(string iso) => iso.Length >= 10 ? iso.Substring(5, 5) : iso;
    static string Trunc(string x, int n) => x.Length > n ? x[..n] : x;

    public static string Json(Snapshot s, string tab, WidgetSize size) => Build(s, tab, size).ToJsonString(CardJson.Options);

    public static JsonObject Build(Snapshot s, string tab, WidgetSize size)
    {
        var d = new JsonObject();
        Common(d, s, tab);
        if (size == WidgetSize.Small) { MarketBasics(d, s); Hf(d, s); return d; }
        switch (tab)
        {
            case "account": AccountData(d, s, size); break;
            case "positions": PositionsData(d, s, size); break;
            default: MarketPart(d, s, size); break;
        }
        return d;
    }

    static void Common(JsonObject d, Snapshot s, string tab)
    {
        var n = s.Wallets.Count;
        var idx = s.Wallets.IndexOf(s.WalletAddr);
        d["logo"] = Charts.Logo();
        d["siteUrl"] = Origin.Site;
        d["multi"] = n > 1;
        d["walletLine"] = s.WalletAddr.Length > 0
            ? Fmt.ShortAddr(s.WalletAddr) + (n > 1 ? "  " + (idx + 1) + "/" + n : "")
            : "Market, fees and your account";
        d["tabMarket"] = Style(tab == "market"); d["tabAccount"] = Style(tab == "account"); d["tabPositions"] = Style(tab == "positions");
        var local = s.Now.ToLocalTime();
        var updated = "updated " + (s.Market.Price is null && s.Market.Fees is null ? "—" : local.ToString("HH:mm:ss", Inv)) + (s.RefreshFailed ? "  · retrying" : "");
        d["updated"] = updated;
        d["footL"] = s.WalletAddr.Length > 0 ? d["walletLine"]!.GetValue<string>() + "  ·  " + updated : updated;
    }

    // ---- market ---------------------------------------------------------------------------------------------------

    static void MarketBasics(JsonObject d, Snapshot s)
    {
        var p = s.Market.Price?.Value; var f = s.Market.Fees?.Value;
        var ch = p?.ChangePct24h ?? double.NaN;
        d["price"] = p is null ? "—" : Fmt.Price(p.Price);
        d["hasChange"] = p is not null && double.IsFinite(ch);
        d["change"] = double.IsFinite(ch) ? Fmt.Pct(ch) + " 24h" : "";
        d["changeColor"] = Delta(ch);
        d["changeShort"] = double.IsFinite(ch) ? Fmt.Pct(ch) : "";
        d["fees"] = f is null ? "—" : Fmt.Usd(f.Period24h);
        d["priceUrl"] = Origin.MarketUrl("FT-ftUSD", s.PriceChain);
        d["feesUrl"] = Origin.Pages.Fees;
    }

    static void MarketPart(JsonObject d, Snapshot s, WidgetSize size)
    {
        MarketBasics(d, s);
        var large = size == WidgetSize.Large;
        var dod = Parse.FeesDayOverDay(s.Market.FeesSeries?.Value, s.Now);
        d["dod"] = double.IsFinite(dod) ? Fmt.Pct(dod) : "—";
        d["dodColor"] = Delta(dod);

        var fs = s.Market.FeesSeries?.Value;
        bool hasFees = fs is { Count: > 1 };
        d["hasFeesChart"] = hasFees; d["noFeesChart"] = !hasFees;
        d["feesCap"] = "DAILY FEES · LAST " + (fs?.Count ?? 31) + " DAYS";
        if (hasFees)
        {
            var v = fs!.Select(x => x.Value).ToList();
            d["feesMax"] = "max " + Fmt.Usd(v.Max());
            d["feesStart"] = MD(fs![0].Date); d["feesEnd"] = MD(fs[^1].Date);
            d["feesChart"] = large ? Charts.BarChart(v, LargeInner, 30, Charts.Tulip, Charts.Tulip300) : Charts.BarChart(v, MediumHalf, 18, Charts.Tulip, Charts.Tulip300);
        }
        else { d["feesMax"] = ""; d["feesStart"] = ""; d["feesEnd"] = ""; d["feesChart"] = ""; }

        var products = (s.Market.Fees?.Value.Products ?? new()).Where(p => p.Usd > 0).ToList();
        bool stack = products.Count > 0 && s.Market.Fees!.Value.Period24h > 0;
        d["hasStack"] = stack;
        d["stackImg"] = stack ? Charts.StackBar(products.Select((p, i) => (p.Usd, Charts.ProductColors[i % Charts.ProductColors.Length])).ToList(), LargeInner, 6) : "";
        for (int i = 0; i < 4; i++)
        {
            var has = i < products.Count;
            d["hasLeg" + (i + 1)] = has;
            d["leg" + (i + 1) + "Dot"] = has ? Charts.Dot(Charts.ProductColors[i % Charts.ProductColors.Length]) : "";
            d["leg" + (i + 1) + "Text"] = has ? products[i].Name.Replace("_", " ") + " " + Fmt.Usd(products[i].Usd) : "";
        }

        var ks = s.Market.Klines?.Value;
        bool hasPrice = ks is { Count: > 1 };
        d["hasPriceChart"] = hasPrice; d["noPriceChart"] = !hasPrice;
        if (hasPrice)
        {
            var v = ks!.Select(x => x.Value).ToList();
            d["priceRange"] = Fmt.Price(v.Min()) + " – " + Fmt.Price(v.Max());
            d["priceChart"] = large ? Charts.LineChart(v, LargeInner, 30, Charts.Tulip400) : Charts.LineChart(v, MediumHalf, 18, Charts.Tulip400);
        }
        else { d["priceRange"] = ""; d["priceChart"] = ""; }
    }

    // ---- account --------------------------------------------------------------------------------------------------

    static void WalletFlags(JsonObject d, Snapshot s)
    {
        var has = s.WalletAddr.Length > 0;
        d["hasWallet"] = has;
        d["noWallet"] = !has && s.BadWallets.Count == 0;
        d["walletBad"] = !has && s.BadWallets.Count > 0;
        d["noWalletCard"] = !has;
        d["badText"] = s.BadWallets.Count > 0 ? "Not a valid address: " + Trunc(s.BadWallets[0], 24) + " (0x + 40 hex characters)" : "";
        d["siteUrl"] = Origin.Site;
    }

    static void Hf(JsonObject d, Snapshot s)
    {
        WalletFlags(d, s);
        var lend = s.Wallet?.Lend?.Value;
        var low = Parse.LowestHf(lend);
        d["hfUrl"] = Origin.Pages.Health;
        d["hfValue"] = lend is null ? "—" : (low is null ? "∞" : Fmt.Hf(low.Hf));
        d["hfColor"] = low is null ? (lend is null ? "default" : "good") : LevelColor(Parse.HfLevel(low.Hf!.Value, s.HfWarn, s.HfCritical));
        d["hfChain"] = low is null ? (lend is null ? "" : "no debt") : low.Name;
    }

    static void AccountData(JsonObject d, Snapshot s, WidgetSize size)
    {
        var large = size == WidgetSize.Large;
        Hf(d, s);
        var w = s.Wallet; var price = s.Market.Price?.Value.Price ?? double.NaN;

        // HF rows: the lowest first on the medium widget, which has room for one
        var chains = w?.Lend?.Value ?? new List<ChainHealth>();
        var ordered = large ? chains.ToList() : chains.OrderBy(c => c.Hf ?? double.MaxValue).ToList();
        var rows = new JsonArray();
        foreach (var c in ordered.Take(large ? 4 : 1))
        {
            int lvl = c.Hf is double hv ? Parse.HfLevel(hv, s.HfWarn, s.HfCritical) : -1;
            rows.Add(new JsonObject
            {
                ["name"] = c.Name,
                ["bar"] = Charts.HfBar(c.Hf, c.LiqHf, s.HfWarn, s.HfCritical, large ? LargeGauge : MediumGauge),
                ["value"] = c.Hf is null ? "no debt" : Fmt.Hf(c.Hf),
                ["color"] = lvl < 0 ? "default" : LevelColor(lvl),
                ["element"] = "account-hf-" + Slug(c.Name),
                ["url"] = Origin.Pages.Health,
            });
        }
        d["chains"] = rows; d["hasChains"] = rows.Count > 0; d["noChains"] = rows.Count == 0;

        var pnlBy = w?.Pnl?.Value;
        var pnlTotal = pnlBy is null ? double.NaN : pnlBy.Values.Sum();
        d["pnl"] = Fmt.SignedUsd(pnlTotal); d["pnlColor"] = Delta(pnlTotal); d["pnlUrl"] = Origin.Pages.Portfolio;
        var sub = pnlBy is null ? "" : string.Join("  ", pnlBy.Where(k => Math.Abs(k.Value) >= 0.005)
            .Select(k => (Parse.HfChains.TryGetValue(k.Key, out var n) ? n : k.Key.ToString()) + " " + Fmt.SignedUsd(k.Value)));
        d["pnlSub"] = sub; d["hasPnlSub"] = sub.Length > 0;

        var rw = w?.Rewards?.Value;
        d["rewardsUrl"] = Origin.Pages.Rewards;
        d["earned"] = Fmt.Ft(rw?.TotalFt ?? double.NaN) + " FT";
        var known = rw is not null && double.IsFinite(rw.TotalFt);
        var l1 = known ? "sftUSD yield " + Fmt.Ft(rw!.SftFt) + "  ·  Lend " + Fmt.Ft(rw.LendFt) : "";
        var l3 = known ? (double.IsFinite(price) ? "≈ " + Fmt.Usd(rw!.TotalFt * price) + " at market" : "") + (rw!.ClaimableFt > 0 ? "  ·  claim " + Fmt.Ft(rw.ClaimableFt) : "") : "";
        if (!large) l1 = l3 = "";
        d["earnL1"] = l1; d["earnL3"] = l3;
        d["hasEarnL1"] = l1.Length > 0; d["hasEarnL3"] = l3.Length > 0;

        var pts = w?.Points?.Value; var rank = w?.Rank?.Value;
        var pg = Parse.PutGain(w?.Puts?.Value, price);
        d["hasPut"] = pg is not null;
        d["putGain"] = pg is null ? "—" : Fmt.SignedUsd(pg.GainUsd);
        d["putColor"] = pg is null ? "default" : Delta(pg.GainUsd);
        d["putSub"] = pg is null ? "" : Fmt.Pct(pg.GainPct) + "  ·  value " + Fmt.Usd(pg.ValueUsd);
        d["putUrl"] = Origin.Pages.Put;
        d["points"] = Fmt.Points(pts?.Total ?? double.NaN); d["pointsUrl"] = Origin.Pages.Points;
        var perChain = pts is null ? "" : string.Join("  ·  ", pts.Chains.Select(c => c.Name + " " + Fmt.Points(c.Points)));
        var rk = rank is null ? "" : "rank #" + rank.Rank + " of " + rank.Total;
        d["rank"] = rank is null ? "" : "rank #" + rank.Rank;
        // next to the ftPUT card there is room for the rank only; alone, the chain split and the rank share a line
        var ps1 = pg is not null ? rk : string.Join("  ·  ", new[] { perChain, rk }.Where(x => x.Length > 0));
        d["pointsSub1"] = ps1; d["hasPointsSub1"] = ps1.Length > 0;
    }

    // ---- positions ------------------------------------------------------------------------------------------------

    static void PositionsData(JsonObject d, Snapshot s, WidgetSize size)
    {
        var large = size == WidgetSize.Large;
        WalletFlags(d, s);
        var w = s.Wallet;
        d["portfolioUrl"] = Origin.Pages.Portfolio; d["pointsActivityUrl"] = Origin.Pages.PointsActivity; d["putUrl"] = Origin.Pages.Put;
        var all = w?.Positions?.Value ?? new List<PositionData>();
        var brk = w?.Breakdown?.Value ?? new List<BreakdownRow>();
        var puts = w?.Puts?.Value;

        // The card has no scroll, so the rows are budgeted: every box costs its caption and padding, every row its height.
        // Positions come first, the points and ftPUT boxes take what is left (at least one row, or they are left out).
        int avail = large ? 232 : 98, rowPos = large ? 30 : 17, row = 17, box = 29;
        bool hasPts = brk.Count > 0, hasPut = puts is not null;
        int Reserve(bool p, bool u) => (p ? box + row : 0) + (u ? box + row : 0);
        int maxRows = Math.Max(1, (avail - Reserve(hasPts, hasPut) - box) / rowPos);
        int shown = Math.Min(all.Count, maxRows);
        if (all.Count > shown && shown > 1) shown--;   // the "+N more" line needs a row too
        avail -= box + (all.Count == 0 ? 14 : shown * rowPos + (all.Count > shown ? 13 : 0));
        d["posCount"] = all.Count > 0 ? all.Count + " open" : "";
        d["noPos"] = w?.Positions is not null && all.Count == 0;
        var rows = new JsonArray();
        foreach (var p in all.Take(shown))
        {
            var lev = double.IsFinite(p.Leverage) && p.Leverage > 0 ? " " + p.Leverage.ToString(p.Leverage >= 10 ? "F0" : "F1", Inv) + "x" : "";
            rows.Add(new JsonObject
            {
                ["sym"] = p.Symbol + "  " + p.Side + lev, ["network"] = p.Network, ["sizeText"] = Fmt.Size(p.Size),
                ["mark"] = Fmt.Price(p.Mark), ["entry"] = Fmt.Price(p.Entry),
                ["pnl"] = Fmt.SignedUsd(p.PnlUsd), ["pnlPct"] = Fmt.Pct(p.PnlPct), ["color"] = Delta(p.PnlUsd),
                ["url"] = Origin.MarketUrl(string.IsNullOrEmpty(p.Market) ? p.Symbol + "-ftUSD" : p.Market, p.ChainId),
            });
        }
        d["positions"] = rows;
        d["hasMore"] = all.Count > shown; d["posMore"] = all.Count > shown ? "+" + (all.Count - shown) + " more" : "";

        int ptsN = hasPts ? Math.Min(Math.Min(brk.Count, 4), (avail - (hasPut ? box + row : 0) - box) / row) : 0;
        var ptsRows = new JsonArray();
        foreach (var r in brk.Take(Math.Max(0, ptsN)))
            ptsRows.Add(new JsonObject { ["label"] = r.Label, ["usd"] = Fmt.Usd(r.PositionUsd), ["mult"] = "x" + (double.IsFinite(r.Multiplier) ? r.Multiplier.ToString("F2", Inv) : "?") });
        d["pts"] = ptsRows; d["hasPts"] = ptsRows.Count > 0;
        if (ptsRows.Count > 0) avail -= box + ptsRows.Count * row;

        int putN = hasPut ? Math.Min(puts!.Rows.Count, (avail - box) / row) : 0;
        var putRows = new JsonArray();
        if (puts is not null)
            foreach (var r in puts.Rows.Take(Math.Max(0, putN)))
                putRows.Add(new JsonObject { ["label"] = "#" + r.Nft + " " + r.Symbol, ["cost"] = Fmt.Usd(r.CostUsd) + " @ " + Fmt.Price(r.Strike), ["since"] = r.Since.Length >= 10 ? r.Since[2..] : r.Since });
        d["puts"] = putRows; d["hasPuts"] = putRows.Count > 0;
    }

    // ---- customize ------------------------------------------------------------------------------------------------

    public static string CustomizeJson(Snapshot s)
    {
        var d = new JsonObject
        {
            ["logo"] = Charts.Logo(),
            ["wallets"] = s.WalletsText,
            ["notice"] = s.Notice, ["hasNotice"] = s.Notice.Length > 0,
            ["priceChain"] = s.PriceChain == 146 ? "146" : "1",
            ["statsValue"] = s.StatsOn ? "true" : "false",
        };
        return d.ToJsonString(CardJson.Options);
    }
}
