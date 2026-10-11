using System.Text.Json.Nodes;

namespace FlyingTulip.Widget;

public interface IHttp
{
    /// <summary>The body of a GET, or null on any failure (HTTP error, timeout, network).</summary>
    Task<string?> GetAsync(string url);
}

public sealed class HttpFetcher : IHttp
{
    readonly HttpClient _http;
    public HttpFetcher(HttpClient http) { _http = http; }
    public async Task<string?> GetAsync(string url)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.TryAddWithoutValidation("Accept", "application/json");
            req.Headers.TryAddWithoutValidation("User-Agent", UsageStats.UserAgent);
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(12));
            using var res = await _http.SendAsync(req, cts.Token);
            if (!res.IsSuccessStatusCode) return null;
            return await res.Content.ReadAsStringAsync(cts.Token);
        }
        catch { return null; }
    }
}

public sealed class Cached<T>
{
    public T Value { get; init; } = default!;
    public DateTimeOffset At { get; init; }
}

public sealed class MarketData
{
    public Cached<PriceData>? Price;
    public Cached<FeesData>? Fees;
    public Cached<List<DatedValue>>? FeesSeries;
    public Cached<List<DatedValue>>? Klines;
}

public sealed class WalletData
{
    public Cached<List<ChainHealth>>? Lend;
    public Cached<Dictionary<int, double>>? Pnl;
    public Cached<RewardsData>? Rewards;
    public Cached<PointsData>? Points;
    public Cached<List<PositionData>>? Positions;
    public Cached<PutsData?>? Puts;
    public Cached<List<BreakdownRow>>? Breakdown;
    public Cached<RankData?>? Rank;
}

/// <summary>
/// Reads the public Flying Tulip API (https://api.flyingtulip.com), no keys. Each source keeps its last good value when a
/// call fails. Slow sources (chart series, leaderboard rank, points breakdown) are refreshed every 10 minutes.
/// </summary>
public sealed class DataHub
{
    public const string Api = "https://api.flyingtulip.com";
    public static readonly TimeSpan SlowTtl = TimeSpan.FromSeconds(600);

    readonly IHttp _http;
    readonly Func<DateTimeOffset> _now;
    readonly Action<string>? _onError;
    readonly object _lock = new();
    public MarketData Market { get; } = new();
    readonly Dictionary<string, WalletData> _wallets = new();

    public DataHub(IHttp http, Func<DateTimeOffset> now, Action<string>? onFetchError = null)
    {
        _http = http; _now = now; _onError = onFetchError;
    }

    public WalletData Wallet(string w)
    {
        lock (_lock)
        {
            if (!_wallets.TryGetValue(w, out var d)) _wallets[w] = d = new WalletData();
            return d;
        }
    }

    // The JSON literal null is an answer, not a failure (positions answers it for a wallet with none).
    sealed record Answer(bool Ok, JsonNode? Node);

    async Task<Answer> GetJson(string url)
    {
        var text = (await _http.GetAsync(url))?.Trim();
        if (string.IsNullOrEmpty(text)) { Fail(url); return new Answer(false, null); }
        if (text == "null") return new Answer(true, null);
        try { return new Answer(true, JsonNode.Parse(text)); }
        catch { Fail(url); return new Answer(false, null); }
    }

    void Fail(string url)
    {
        var ep = Parse.EndpointName(url);
        if (ep.Length > 0) _onError?.Invoke(ep);
    }

    bool Due(DateTimeOffset? at) => at is null || _now() - at.Value >= SlowTtl;
    Cached<T> Now<T>(T v) => new() { Value = v, At = _now() };

    public async Task RefreshMarketAsync(int priceChain)
    {
        var chain = priceChain == 146 ? 146 : 1;
        var priceT = GetJson(Api + "/mm/spot/tickers?chainId=" + chain);
        var feesT = GetJson(Api + "/fees/application?period=1d&granularity=day");
        Task<Answer>? seriesT = Due(Market.FeesSeries?.At) ? GetJson(Api + "/fees/application?period=1m&granularity=day") : null;
        Task<Answer>? klinesT = Due(Market.Klines?.At)
            ? GetJson(Api + "/mm/spot/market/klines?symbol=FT-ftUSD&chainId=" + chain + "&interval=1d&limit=30") : null;

        var p = await priceT;
        var price = p.Ok ? Parse.Price(p.Node) : null;
        if (price is null && chain != 146)
        {
            var alt = await GetJson(Api + "/mm/spot/tickers?chainId=146");   // Sonic ticker when the chain has no FT-ftUSD market
            price = alt.Ok ? Parse.Price(alt.Node) : null;
        }
        if (price is not null) Market.Price = Now(price);
        var f = await feesT;
        var fees = f.Ok ? Parse.Fees(f.Node) : null;
        if (fees is not null) Market.Fees = Now(fees); else if (f.Ok) Fail(Api + "/fees/application");
        if (seriesT is not null)
        {
            var s = await seriesT; var v = s.Ok ? Parse.FeesSeries(s.Node) : null;
            if (v is not null) Market.FeesSeries = Now(v);
        }
        if (klinesT is not null)
        {
            var k = await klinesT; var v = k.Ok ? Parse.Klines(k.Node) : null;
            if (v is not null) Market.Klines = Now(v);
        }
    }

    public async Task RefreshWalletAsync(string wallet)
    {
        var w = Wallet(wallet); var a = Uri.EscapeDataString(wallet);
        var lendT = GetJson(Api + "/mm/lend?user=" + a);
        var lend143T = GetJson(Api + "/mm/lend?user=" + a + "&chainId=143");
        var sumT = new[] { 146, 1, 56, 143 }.Select(id => GetJson(Api + "/mm/spot/account/summary?address=" + a + "&chainId=" + id)).ToArray();
        var rewardsT = GetJson(Api + "/account/dashboard?address=" + a + "&view=rewards");
        var pointsT = GetJson(Api + "/points?walletAddress=" + a);
        var posT = new[] { 146, 1, 56 }.Select(id => GetJson(Api + "/mm/spot/account/positions?address=" + a + "&chainId=" + id)).ToArray();
        var putsT = GetJson(Api + "/tge/ftPUT/user/" + a);
        Task<Answer>? brT = Due(w.Breakdown?.At) ? GetJson(Api + "/points/breakdown?walletAddress=" + a + "&page=1&limit=50") : null;

        var l1 = await lendT; var l2 = await lend143T;
        if (l1.Ok && l1.Node is not null) w.Lend = Now(Parse.MergeChains(Parse.Lend(l1.Node), Parse.Lend(l2.Node)));

        var pnlBy = new Dictionary<int, double>(); int ok = 0;
        foreach (var t in sumT)
        {
            var r = await t;
            var s = r.Ok ? Parse.Summary(r.Node) : null;
            if (s is not null) { pnlBy[s.Value.ChainId] = s.Value.PnlUsd; ok++; }
        }
        if (ok > 0) w.Pnl = Now(pnlBy);

        var rw = await rewardsT;
        var rewards = rw.Ok ? Parse.Rewards(rw.Node) : null;
        if (rewards is not null) w.Rewards = Now(rewards); else if (rw.Ok) Fail(Api + "/account/dashboard");

        var pt = await pointsT;
        var points = pt.Ok ? Parse.Points(pt.Node) : null;
        if (points is not null) w.Points = Now(points); else if (pt.Ok) Fail(Api + "/points?walletAddress=");

        var all = new List<PositionData>(); int pok = 0;
        foreach (var t in posT)
        {
            var r = await t;
            if (!r.Ok) continue;
            pok++; all.AddRange(Parse.Positions(r.Node));
        }
        if (pok > 0) w.Positions = Now(Parse.SortPositions(all));

        var pu = await putsT;
        if (pu.Ok) w.Puts = Now(Parse.Puts(pu.Node));

        if (brT is not null)
        {
            var b = await brT;
            if (b.Ok) w.Breakdown = Now(Parse.PointsBreakdown(b.Node));
        }
        if (points is not null || w.Points is not null)
        {
            var total = (points ?? w.Points!.Value).Total;
            if (Due(w.Rank?.At))
            {
                var rank = await FindRankAsync(wallet, total);
                if (rank.Ok) w.Rank = Now(rank.Value);
            }
        }
    }

    /// <summary>The leaderboard is sorted by points (500 per page): binary-search the page, then find the wallet.</summary>
    public async Task<(bool Ok, RankData? Value)> FindRankAsync(string wallet, double myPoints)
    {
        int lo = 1, hi = 14, steps = 0, page = (lo + hi) / 2;
        while (steps++ < 8)
        {
            var b = await GetJson(Api + "/points/leaderboard?page=" + page + "&limit=500");
            if (!b.Ok || b.Node is null) return (false, null);
            var r = Parse.RankInPage(b.Node, wallet, myPoints);
            if (r.Found) return (true, new RankData(r.Rank, r.Total));
            if (r.Total > 0) hi = Math.Min(hi, Math.Max(1, (int)Math.Ceiling(r.Total / 500.0)));
            if (r.Empty) hi = Math.Min(hi, page - 1);
            else if (r.Dir == -1) hi = page - 1;
            else if (r.Dir == 1) lo = page + 1;
            else return (true, null);
            if (lo > hi) return (true, null);
            page = (lo + hi) / 2;
        }
        return (true, null);
    }
}
