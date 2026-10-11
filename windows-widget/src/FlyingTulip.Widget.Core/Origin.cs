using System.Text.RegularExpressions;

namespace FlyingTulip.Widget;

/// <summary>The public flyingtulip.com pages the widget links to, and the origin marker added while usage stats are on.</summary>
public static class Origin
{
    public const string Site = "https://flyingtulip.com/";
    public const string Platform = "windows-widget";
    public const string Version = "1.0.0";

    public static class Pages
    {
        public const string Fees = Site + "statistics/";
        public const string Health = Site + "lend/dashboard/";
        public const string Portfolio = Site + "trade/portfolio/";
        public const string Rewards = Site + "rewards/";
        public const string Points = Site + "rewards/leaderboard/";
        public const string PointsActivity = Site + "rewards/my-activity/";
        public const string Put = Site + "allocation/positions/";
    }

    /// <summary>Spot market page for a symbol such as "FT-ftUSD" on a chain id.</summary>
    public static string MarketUrl(string? symbol, int chainId)
    {
        var q = "symbol=" + Uri.EscapeDataString(string.IsNullOrEmpty(symbol) ? "FT-ftUSD" : symbol);
        if (chainId > 0) q += "&chainId=" + chainId;
        return Site + "trade/?" + q + "&marketType=spot";
    }

    public static bool IsSiteUrl(string? url) => url is not null && url.StartsWith("https://flyingtulip.com/", StringComparison.Ordinal);

    public static string OsSlug(string? s)
    {
        var t = Regex.Replace((s ?? "").ToLowerInvariant(), "[^a-z0-9]+", "-").Trim('-');
        return t.Length == 0 ? "windows" : t;
    }

    public static string ElementId(string? element) => Regex.Replace((element ?? "").ToLowerInvariant(), "[^a-z0-9-]", "");

    /// <summary>
    /// Where a visit to flyingtulip.com came from, only while usage stats are on:
    /// ?utm_source=ft-widget&amp;utm_medium=windows-widget&amp;utm_content=&lt;element&gt; (after the query the URL already has) and
    /// #ftw=windows-widget.&lt;os-slug&gt;.&lt;version, dots as dashes&gt;.&lt;element&gt; (left out when the URL already has an anchor).
    /// </summary>
    public static string WithOrigin(string url, string? element, string? os)
    {
        var el = ElementId(element);
        var i = url.IndexOf('#');
        var baseUrl = i < 0 ? url : url[..i];
        var hash = i < 0 ? null : url[(i + 1)..];
        var q = (baseUrl.Contains('?') ? "&" : "?") + "utm_source=ft-widget&utm_medium=" + Platform + "&utm_content=" + el;
        if (hash is not null) return baseUrl + q + "#" + hash;
        return baseUrl + q + "#ftw=" + Platform + "." + OsSlug(os) + "." + Version.Replace('.', '-') + "." + el;
    }

    public static string OsLabel(Version v) => v.Major >= 10 ? (v.Build >= 22000 ? "Windows 11" : "Windows 10") : "Windows";
}
