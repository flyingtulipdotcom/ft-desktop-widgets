using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FlyingTulip.Widget;

public interface IEventSink
{
    Task PostAsync(string body, string userAgent);
}

/// <summary>Persisted counters of the usage stats (not wallet data).</summary>
public sealed class StatCounters
{
    public long Hour { get; set; } = -1;
    public Dictionary<string, int> Counts { get; set; } = new();
    public Dictionary<string, long> ErrAt { get; set; } = new();
    public long PageAt { get; set; }
    public long OpenAt { get; set; }
}

/// <summary>
/// Anonymous usage stats (Plausible, site "widget"). Only the event name, the platform, the widget version and the few
/// values passed in (os, host, element, url, tab, level, endpoint, a wallet count bucket) are sent, fire and forget. Never a
/// wallet address, balance or position: any 0x address inside a value becomes ":address". Nothing is sent while the
/// "Anonymous usage stats" switch is off. Each event name is capped at 30 per hour.
/// </summary>
public sealed class UsageStats
{
    public const string Endpoint = "https://plausible.io/api/event";
    public const string EventUrl = "app://widget/windows-widget";
    public const int Cap = 30;
    public static readonly string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) FlyingTulipWidget/" + Origin.Version;

    readonly IEventSink _sink;
    readonly Func<bool> _isOn;
    readonly Func<DateTimeOffset> _now;
    public StatCounters Counters { get; }

    public UsageStats(IEventSink sink, Func<bool> isOn, Func<DateTimeOffset> now, StatCounters? counters = null)
    {
        _sink = sink; _isOn = isOn; _now = now; Counters = counters ?? new StatCounters();
    }

    public bool On => _isOn();

    public static string Value(string? v)
    {
        var s = Regex.Replace(v ?? "", "0x[0-9a-fA-F]{40}", ":address");
        return s.Length > 300 ? s[..300] : s;
    }

    public static string Body(string name, IEnumerable<(string Key, string Val)>? props = null)
    {
        var p = new JsonObject { ["platform"] = Origin.Platform, ["version"] = Origin.Version };
        foreach (var (k, v) in props ?? Array.Empty<(string, string)>()) p[k] = Value(v);
        var o = new JsonObject { ["name"] = name, ["url"] = EventUrl, ["domain"] = "widget", ["props"] = p };
        return o.ToJsonString(new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
    }

    /// <summary>Sends one event unless usage stats are off or the hourly cap of this event name is reached. Never throws.</summary>
    public async Task<bool> SendAsync(string name, params (string Key, string Val)[] props)
    {
        try
        {
            if (!_isOn()) return false;
            var hour = _now().ToUnixTimeSeconds() / 3600;
            if (Counters.Hour != hour) { Counters.Hour = hour; Counters.Counts = new(); }
            Counters.Counts.TryGetValue(name, out var c);
            if (c >= Cap) return false;
            Counters.Counts[name] = c + 1;
            await _sink.PostAsync(Body(name, props), UserAgent);
            return true;
        }
        catch { return false; }
    }

    /// <summary>A failed or unusable API answer, at most once an hour per endpoint.</summary>
    public async Task FetchErrorAsync(string endpoint)
    {
        if (string.IsNullOrEmpty(endpoint) || !_isOn()) return;
        var now = _now().ToUnixTimeSeconds();
        if (Counters.ErrAt.TryGetValue(endpoint, out var at) && now - at < 3600) return;
        Counters.ErrAt[endpoint] = now;
        await SendAsync("Fetch error", ("endpoint", endpoint));
    }

    /// <summary>The launch pageview, and one a day while it runs.</summary>
    public async Task PageviewAsync(string os, string host, int walletsConfigured, bool force = false)
    {
        var now = _now().ToUnixTimeSeconds();
        if (!force && Counters.PageAt != 0 && now - Counters.PageAt < 86400) return;
        if (await SendAsync("pageview", ("os", os), ("host", host), ("walletsConfigured", WalletsBucket(walletsConfigured))))
            Counters.PageAt = now;
    }

    /// <summary>The widget came into view, at most once per 30 minutes.</summary>
    public async Task PanelOpenAsync()
    {
        var now = _now().ToUnixTimeSeconds();
        if (Counters.OpenAt != 0 && now - Counters.OpenAt < 1800) return;
        if (await SendAsync("Panel open")) Counters.OpenAt = now;
    }

    public static string WalletsBucket(int n) => n >= 3 ? "3+" : n.ToString();

    /// <summary>Turns the switch: one last event (Usage stats off) while it is still on, then nothing; "Usage stats on" once back on.</summary>
    public async Task SwitchAsync(bool newOn, string os, Action<bool> persist)
    {
        var was = _isOn();
        if (was && !newOn)
        {
            await SendAsync("Usage stats off", ("os", os));
            persist(false);
        }
        else if (!was && newOn)
        {
            persist(true);
            await SendAsync("Usage stats on", ("os", os));
        }
    }
}

public sealed class HttpEventSink : IEventSink
{
    readonly HttpClient _http;
    public HttpEventSink(HttpClient http) { _http = http; }
    public async Task PostAsync(string body, string userAgent)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, UsageStats.Endpoint)
        { Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json") };
        req.Headers.TryAddWithoutValidation("User-Agent", userAgent);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var _ = await _http.SendAsync(req, cts.Token);
    }
}
