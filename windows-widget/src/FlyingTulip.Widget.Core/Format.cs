using System.Globalization;
using System.Numerics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FlyingTulip.Widget;

/// <summary>Number helpers and the display formats shared with the other Flying Tulip widgets.</summary>
public static class Fmt
{
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static double Num(JsonNode? n)
    {
        if (n is not JsonValue v) return double.NaN;
        if (v.TryGetValue<double>(out var d)) return double.IsFinite(d) ? d : double.NaN;
        if (v.TryGetValue<string>(out var s) && !string.IsNullOrWhiteSpace(s) &&
            double.TryParse(s, NumberStyles.Float, Inv, out d) && double.IsFinite(d)) return d;
        return double.NaN;
    }

    public static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// <summary>Exact decimal shift of an integer string (display precision only). NaN when it is not an integer string.</summary>
    public static double RawUnits(string? s, int dec)
    {
        if (string.IsNullOrEmpty(s) || !Regex.IsMatch(s, "^[0-9]+$")) return double.NaN;
        return (double)BigInteger.Parse(s, Inv) / Math.Pow(10, dec);
    }
    public static double RawFt(string? s) => RawUnits(s, 18);

    static string F(double v, int digits) => v.ToString("F" + digits, Inv);

    public static string Usd(double v)
    {
        if (!double.IsFinite(v)) return "—";
        var a = Math.Abs(v);
        if (a >= 1e6) return "$" + F(a / 1e6, 2) + "M";
        if (a >= 1e4) return "$" + F(a / 1e3, 1) + "k";
        if (a >= 1e3) return "$" + F(a / 1e3, 2) + "k";
        return "$" + F(a, a >= 100 ? 0 : 2);
    }

    public static string SignedUsd(double v)
    {
        if (!double.IsFinite(v)) return "—";
        if (Math.Abs(v) < 0.005) return "$0.00";
        return (v < 0 ? "-" : "+") + Usd(v);
    }

    public static string Price(double p) => !double.IsFinite(p) ? "—" : "$" + F(p, p >= 1 ? 2 : 4);

    public static string Hf(double? hf)
    {
        if (hf is null || !double.IsFinite(hf.Value)) return "∞";
        return hf.Value >= 100 ? ">100" : F(hf.Value, 2);
    }

    public static string Pct(double v)
    {
        if (!double.IsFinite(v)) return "—";
        return (v >= 0 ? "+" : "") + (Math.Abs(v) >= 100 ? F(v, 0) : F(v, 1)) + "%";
    }

    public static string Ft(double v)
    {
        if (!double.IsFinite(v)) return "—";
        if (v < 0.01) return v <= 0 ? "0" : "<0.01";
        if (v < 10) return F(v, 2);
        if (v < 1000) return F(v, 1);
        if (v < 1e6) return F(v / 1e3, v < 1e4 ? 2 : 1) + "K";
        return F(v / 1e6, 2) + "M";
    }

    public static string Points(double v)
    {
        if (!double.IsFinite(v)) return "—";
        var a = Math.Abs(v);
        if (a >= 1e9) return F(a / 1e9, 2) + "B";
        if (a >= 1e6) return F(a / 1e6, a >= 1e8 ? 0 : 1) + "M";
        if (a >= 1e3) return F(a / 1e3, a >= 1e5 ? 0 : 1) + "K";
        return F(a, 0);
    }

    public static string Size(double v)
    {
        if (!double.IsFinite(v)) return "—";
        var a = Math.Abs(v);
        if (a >= 1e6) return F(a / 1e6, 2) + "M";
        if (a >= 1e4) return F(a / 1e3, 1) + "K";
        if (a >= 100) return F(a, 0);
        if (a >= 1) return F(a, 2);
        return F(a, 4);
    }

    public static string Thousands(double n) => Math.Round(n).ToString("N0", Inv);

    public static string ShortAddr(string a) => a.Length > 12 ? a[..6] + "…" + a[^4..] : a;

    public static bool IsAddress(string? a) => a is not null && Regex.IsMatch(a, "^0x[0-9a-fA-F]{40}$");

    public static string NormalizeWallet(string? s)
    {
        var t = (s ?? "").Trim();
        return IsAddress(t) ? t.ToLowerInvariant() : "";
    }

    /// <summary>"0xA, 0xB" (commas, spaces, semicolons or new lines) to a lowercase list without duplicates, plus the invalid parts.</summary>
    public static (List<string> List, List<string> Bad) ParseWallets(string? text)
    {
        var list = new List<string>(); var bad = new List<string>();
        foreach (var part in Regex.Split(text ?? "", @"[\s,;]+"))
        {
            if (part.Length == 0) continue;
            var w = NormalizeWallet(part);
            if (w.Length == 0) bad.Add(part);
            else if (!list.Contains(w)) list.Add(w);
        }
        return (list, bad);
    }
}
