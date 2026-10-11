using System.Text.Json.Nodes;

namespace FlyingTulip.Widget;

public sealed record Rendered(string Template, string Data, bool Customizing);

/// <summary>
/// The widget's behaviour, with no Windows API in it: it owns what each widget instance remembers (tab, wallets, the wallet
/// shown), turns the host's verbs (tab_market, next, refresh, customize, save, open ...) into state changes, anonymous
/// usage events and a fresh card, and opens pages through the callback it is given.
/// </summary>
public sealed class WidgetController
{
    public const int RotateMs = 50000;   // each refresh past this shows the next wallet

    readonly StateStore _store;
    readonly DataHub _hub;
    readonly UsageStats _stats;
    readonly string _os;
    readonly Func<DateTimeOffset> _now;
    readonly Action<string> _openUrl;
    DateTimeOffset _marketAt = DateTimeOffset.MinValue;
    readonly Dictionary<string, DateTimeOffset> _walletAt = new();

    public WidgetController(StateStore store, DataHub hub, UsageStats stats, string os, Func<DateTimeOffset> now, Action<string> openUrl)
    {
        _store = store; _hub = hub; _stats = stats; _os = os; _now = now; _openUrl = openUrl;
    }

    public StateStore Store => _store;

    /// <summary>The widget came into view: the board opened it.</summary>
    public async Task ActivatedAsync(string id, string host = "Widgets Board")
    {
        var st = _store.Widget(id);
        await _stats.PanelOpenAsync();
        await _stats.PageviewAsync(_os, host, st.Wallets.Count);
        _store.Save();
    }

    /// <summary>Fetches what the card needs and builds it. force skips the short throttle between fetches.</summary>
    public async Task<Rendered> RenderAsync(string id, WidgetSize size, bool force = false, bool rotate = false, bool fetch = true)
    {
        var st = _store.Widget(id); st.Normalize();
        var now = _now();
        if (rotate && st.Wallets.Count > 1 && st.ShownAt > 0 && now.ToUnixTimeMilliseconds() - st.ShownAt >= RotateMs)
            Next(st, now);
        if (st.ShownAt == 0) st.ShownAt = now.ToUnixTimeMilliseconds();
        if (fetch && !st.Customizing) await FetchAsync(st, force);
        _store.Save();
        return Compose(st, size);
    }

    async Task FetchAsync(WidgetState st, bool force)
    {
        var now = _now();
        if (force || now - _marketAt >= TimeSpan.FromSeconds(20))
        {
            _marketAt = now;
            await _hub.RefreshMarketAsync(st.PriceChain);
        }
        if (st.Cur.Length > 0 && (force || !_walletAt.TryGetValue(st.Cur, out var at) || now - at >= TimeSpan.FromSeconds(20)))
        {
            _walletAt[st.Cur] = now;
            await _hub.RefreshWalletAsync(st.Cur);
        }
    }

    Snapshot Snap(WidgetState st) => new()
    {
        Now = _now(), Market = _hub.Market, Wallets = st.Wallets.ToList(), WalletAddr = st.Cur,
        Wallet = st.Cur.Length > 0 ? _hub.Wallet(st.Cur) : null,
        PriceChain = st.PriceChain, StatsOn = _stats.On, Notice = st.Notice, WalletsText = string.Join(", ", st.Wallets),
        RefreshFailed = _hub.Market.Price is null && _hub.Market.Fees is null,
    };

    Rendered Compose(WidgetState st, WidgetSize size)
    {
        var snap = Snap(st);
        if (st.Customizing) return new Rendered(CardTemplates.Customize(), CardData.CustomizeJson(snap), true);
        return new Rendered(CardTemplates.Template(st.Tab, size), CardData.Json(snap, st.Tab, size), false);
    }

    void Next(WidgetState st, DateTimeOffset now)
    {
        if (st.Wallets.Count < 2) return;
        st.Cur = st.Wallets[(Math.Max(0, st.Wallets.IndexOf(st.Cur)) + 1) % st.Wallets.Count];
        st.ShownAt = now.ToUnixTimeMilliseconds();
    }

    /// <summary>Handles one verb of the card. inputs: the customize form's fields (id to value), null for other verbs.</summary>
    public async Task<Rendered> ActionAsync(string id, WidgetSize size, string verb, JsonNode? data, IReadOnlyDictionary<string, string>? inputs = null)
    {
        var st = _store.Widget(id); st.Normalize();
        var now = _now();
        switch (verb)
        {
            case "tab_market": case "tab_account": case "tab_positions":
                st.Tab = verb[4..];
                await _stats.SendAsync("Tab view", ("tab", st.Tab));
                break;
            case "next":
                if (st.Wallets.Count > 1) { Next(st, now); await _stats.SendAsync("Wallet switch"); }
                break;
            case "refresh":
                await _stats.SendAsync("Refresh");
                return await RenderAsync(id, size, force: true);
            case "customize":
                st.Customizing = true; st.Notice = "";
                await _stats.SendAsync("Settings open");
                break;
            case "done":
                st.Customizing = false; st.Notice = "";
                break;
            case "save":
                await SaveAsync(st, inputs ?? new Dictionary<string, string>());
                if (!st.Customizing) return await RenderAsync(id, size, force: true);
                break;
            case "open":
                await OpenAsync(data);
                break;
        }
        return await RenderAsync(id, size);
    }

    async Task SaveAsync(WidgetState st, IReadOnlyDictionary<string, string> inputs)
    {
        inputs.TryGetValue("wallets", out var text);
        var (list, bad) = Fmt.ParseWallets(text);
        if (bad.Count > 0)
        {
            st.Notice = "Not a valid address: " + (bad[0].Length > 24 ? bad[0][..24] : bad[0]) + ". Use 0x followed by 40 hex characters.";
            st.Customizing = true;
            return;
        }
        // usage stats first: the switch can send its last event while it is still on
        if (inputs.TryGetValue("analytics", out var an))
            await _stats.SwitchAsync(!string.Equals(an, "false", StringComparison.OrdinalIgnoreCase), _os, v => _store.State.StatsOn = v);
        var before = st.Wallets.ToList();
        st.Wallets = list;
        st.Cur = list.Contains(st.Cur) ? st.Cur : list.FirstOrDefault() ?? "";
        if (inputs.TryGetValue("priceChain", out var pc)) st.PriceChain = pc == "146" ? 146 : 1;
        if (list.Any(w => !before.Contains(w))) await _stats.SendAsync("Wallet added");
        if (before.Any(w => !list.Contains(w))) await _stats.SendAsync("Wallet removed");
        st.Customizing = false; st.Notice = "";
        _marketAt = DateTimeOffset.MinValue;
    }

    async Task OpenAsync(JsonNode? data)
    {
        var url = Fmt.Str(data?["url"]) ?? "";
        if (!Origin.IsSiteUrl(url)) return;
        var el = Origin.ElementId(Fmt.Str(data?["element"]));
        await _stats.SendAsync("Link click", ("element", el), ("url", url));
        _openUrl(_stats.On ? Origin.WithOrigin(url, el, _os) : url);
    }
}
