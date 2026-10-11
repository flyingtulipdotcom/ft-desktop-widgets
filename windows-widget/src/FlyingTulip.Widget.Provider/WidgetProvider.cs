using System.Diagnostics;
using System.Text.Json.Nodes;
using FlyingTulip.Widget;
using Microsoft.Windows.Widgets.Providers;
using BoardSize = Microsoft.Windows.Widgets.WidgetSize;
using CardSize = FlyingTulip.Widget.WidgetSize;

namespace FlyingTulip.Widget.Provider;

/// <summary>
/// The Windows 11 Widgets Board provider (IWidgetProvider): the board creates, activates and customizes widget instances and
/// sends the verbs of the card here; everything the card shows and does lives in FlyingTulip.Widget.Core.
/// </summary>
sealed class WidgetProvider : IWidgetProvider, IWidgetProvider2
{
    readonly WidgetController _ctl;
    readonly Dictionary<string, (CardSize Size, bool Active)> _widgets = new();
    readonly object _lock = new();
    readonly Timer _timer;
    DateTime _emptySince = DateTime.UtcNow;
    public ManualResetEvent Exited { get; } = new(false);

    public WidgetProvider()
    {
        var http = new HttpClient();
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FlyingTulipWidget");
        var store = new StateStore(Path.Combine(dir, "state.json"));
        UsageStats? stats = null;
        var hub = new DataHub(new HttpFetcher(http), () => DateTimeOffset.UtcNow, ep => { _ = stats?.FetchErrorAsync(ep); });
        stats = new UsageStats(new HttpEventSink(http), () => store.State.StatsOn, () => DateTimeOffset.UtcNow, store.State.Counters);
        _ctl = new WidgetController(store, hub, stats, Origin.OsLabel(Environment.OSVersion.Version), () => DateTimeOffset.UtcNow, OpenUrl);
        // widgets that already exist (the board restarted this process)
        try
        {
            foreach (var id in WidgetManager.GetDefault().GetWidgetIds())
            {
                var info = WidgetManager.GetDefault().GetWidgetInfo(id);
                if (info is not null) Track(info.WidgetContext);
            }
        }
        catch { /* none yet */ }
        _timer = new Timer(_ => Tick(), null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));
    }

    static CardSize Map(BoardSize s) => s switch { BoardSize.Small => CardSize.Small, BoardSize.Medium => CardSize.Medium, _ => CardSize.Large };

    static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { /* no browser: nothing to do */ }
    }

    void Track(WidgetContext c) { lock (_lock) _widgets[c.Id] = (Map(c.Size), c.IsActive); }

    async Task Push(string id, Rendered r)
    {
        await Task.Yield();
        var o = new WidgetUpdateRequestOptions(id) { Template = r.Template, Data = r.Data };
        WidgetManager.GetDefault().UpdateWidget(o);
    }

    async void Safe(Func<Task> work)
    {
        try { await work(); } catch { /* a failed update leaves the last card on the board */ }
    }

    public void CreateWidget(WidgetContext c) => Safe(async () =>
    {
        Track(c);
        await Push(c.Id, await _ctl.RenderAsync(c.Id, Map(c.Size), force: true));
    });

    public void DeleteWidget(string widgetId, string customState)
    {
        lock (_lock) { _widgets.Remove(widgetId); if (_widgets.Count == 0) _emptySince = DateTime.UtcNow; }
        _ctl.Store.Remove(widgetId);
    }

    public void OnActionInvoked(WidgetActionInvokedArgs args) => Safe(async () =>
    {
        var c = args.WidgetContext; Track(c);
        JsonObject data = new();
        try { if (!string.IsNullOrEmpty(args.Data) && JsonNode.Parse(args.Data) is JsonObject o) data = o; } catch { }
        var inputs = new Dictionary<string, string>();
        foreach (var kv in data) if (kv.Value is JsonValue v && v.TryGetValue<string>(out var s)) inputs[kv.Key] = s;
        else if (kv.Value is JsonValue b && b.TryGetValue<bool>(out var bv)) inputs[kv.Key] = bv ? "true" : "false";
        await Push(c.Id, await _ctl.ActionAsync(c.Id, Map(c.Size), args.Verb, data, inputs));
    });

    public void OnWidgetContextChanged(WidgetContextChangedArgs args) => Safe(async () =>
    {
        var c = args.WidgetContext; Track(c);
        await Push(c.Id, await _ctl.RenderAsync(c.Id, Map(c.Size), fetch: false));   // a new size: same data, another card
    });

    public void Activate(WidgetContext c) => Safe(async () =>
    {
        Track(c);
        await _ctl.ActivatedAsync(c.Id);
        await Push(c.Id, await _ctl.RenderAsync(c.Id, Map(c.Size), force: true));
    });

    public void Deactivate(string widgetId)
    {
        lock (_lock) if (_widgets.TryGetValue(widgetId, out var w)) _widgets[widgetId] = (w.Size, false);
    }

    // the "Customize widget" entry of the board's menu
    public void OnCustomizationRequested(WidgetCustomizationRequestedArgs args) => Safe(async () =>
    {
        var c = args.WidgetContext; Track(c);
        await Push(c.Id, await _ctl.ActionAsync(c.Id, Map(c.Size), "customize", null));
    });

    void Tick()
    {
        List<(string Id, CardSize Size)> active;
        lock (_lock)
        {
            active = _widgets.Where(w => w.Value.Active).Select(w => (w.Key, w.Value.Size)).ToList();
            if (_widgets.Count == 0 && DateTime.UtcNow - _emptySince > TimeSpan.FromMinutes(2)) Exited.Set();
        }
        foreach (var (id, size) in active)
            Safe(async () => await Push(id, await _ctl.RenderAsync(id, size, rotate: true)));
    }
}
