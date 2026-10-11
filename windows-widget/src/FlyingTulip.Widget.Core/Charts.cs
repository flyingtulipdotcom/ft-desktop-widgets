namespace FlyingTulip.Widget;

/// <summary>
/// The pictures of the card, in the colours of the Omarchy panel, on a transparent background so they sit on the
/// light or the dark card alike. Sizes are CSS pixels; the PNG is drawn at 2x.
/// </summary>
public static class Charts
{
    public const int Scale = 2;
    public static readonly Rgba Tulip = Rgba.Hex("#7559ff"), Tulip300 = Rgba.Hex("#b7b1ff"), Tulip400 = Rgba.Hex("#9385ff"),
        Green = Rgba.Hex("#0fd727"), Amber = Rgba.Hex("#f5a524"), Red = Rgba.Hex("#ef4444"), Blue = Rgba.Hex("#5587f3");
    static readonly Rgba Grid = new(150, 150, 165, 36), Track = new(150, 150, 165, 60);
    public static readonly Rgba[] ProductColors = { Tulip, Tulip400, Tulip300, Green, Blue, Red };

    static Canvas New(double w, double h) => new((int)Math.Round(w * Scale), (int)Math.Round(h * Scale));

    /// <summary>Rounded-top bars, oldest first, the last one lighter (today so far), two faint grid lines.</summary>
    public static string BarChart(IReadOnlyList<double> values, double w, double h, Rgba bar, Rgba last)
    {
        var c = New(w, h); double s = Scale, W = w * s, H = h * s;
        c.Rect(0, 0, W, 0.5 * s, Grid); c.Rect(0, Math.Round(H / 2), W, Math.Round(H / 2) + 0.5 * s, Grid);
        int n = values.Count;
        if (n > 0)
        {
            double max = values.Max(); if (!(max > 0)) max = 1;
            double gap = Math.Min(3, Math.Max(1.2, w / n * 0.28)) * s, bw = Math.Max(2, (W - gap * (n - 1)) / n);
            for (int i = 0; i < n; i++)
            {
                double bh = Math.Max(1 * s, Math.Round(values[i] / max * (H - 3 * s)));
                var col = i == n - 1 ? last : bar.WithAlpha(217);
                c.RoundRect(i * (bw + gap), H - bh, bw, bh, Math.Min(3 * s, bw / 2), col, topOnly: true);
            }
        }
        return c.ToDataUri();
    }

    /// <summary>A line with a soft fade under it and a light dot on the last point.</summary>
    public static string LineChart(IReadOnlyList<double> values, double w, double h, Rgba line)
    {
        var c = New(w, h); double s = Scale, W = w * s, H = h * s, pad = 4 * s;
        int n = values.Count;
        if (n >= 2)
        {
            double lo = values.Min(), hi = values.Max(), span = hi - lo;
            if (span <= 0) span = Math.Abs(hi) > 0 ? Math.Abs(hi) : 1;
            var pts = new List<(double X, double Y)>();
            for (int i = 0; i < n; i++)
                pts.Add((pad + i * (W - pad * 2) / (n - 1), H - pad - (values[i] - lo) / span * (H - pad * 2)));
            c.AreaUnder(pts, 0, H, line, 0.32, 0.0);
            c.Polyline(pts, 1.8 * s, line);
            c.Circle(pts[^1].X, pts[^1].Y, 3 * s, Tulip300);
        }
        return c.ToDataUri();
    }

    public const double HfScaleMax = 3.0;

    /// <summary>One chain's health factor: track, fill (green / amber / red), the liquidation line. Null hf = no debt, no fill.</summary>
    public static string HfBar(double? hf, double liqHf, double warn, double crit, double w, double h = 14)
    {
        var c = New(w, h); double s = Scale, W = w * s, H = h * s, th = 6 * s, y = (H - th) / 2;
        double X(double v) => Math.Clamp((v - 1.0) / (HfScaleMax - 1.0), 0, 1) * W;
        c.RoundRect(0, y, W, th, th / 2, Track);
        if (hf is double v && double.IsFinite(v))
        {
            var col = v <= crit ? Red : (v <= warn ? Amber : Green);
            c.RoundRect(0, y, Math.Max(th, X(Math.Min(HfScaleMax, v))), th, th / 2, col);
        }
        c.RoundRect(Math.Min(W - 2 * s, Math.Max(0, X(liqHf) - 1 * s)), 1 * s, 2 * s, H - 2 * s, 1 * s, Red);
        return c.ToDataUri();
    }

    /// <summary>The per-product split of the day's fees: one rounded segment per product.</summary>
    public static string StackBar(IReadOnlyList<(double Value, Rgba Color)> parts, double w, double h = 6)
    {
        var c = New(w, h); double s = Scale, W = w * s, H = h * s, gap = 2 * s;
        double total = parts.Sum(p => p.Value);
        if (total > 0 && parts.Count > 0)
        {
            double avail = W - gap * (parts.Count - 1), x = 0;
            foreach (var (v, col) in parts)
            {
                double sw = Math.Max(2 * s, avail * v / total);
                c.RoundRect(x, 0, sw, H, H / 2, col);
                x += sw + gap;
            }
        }
        return c.ToDataUri();
    }

    public static string Dot(Rgba color, double size = 8)
    {
        var c = New(size, size);
        c.Circle(size * Scale / 2, size * Scale / 2, size * Scale / 2 - 0.5, color);
        return c.ToDataUri();
    }

    public static string Logo()
    {
        using var s = typeof(Charts).Assembly.GetManifestResourceStream("logo.png")!;
        using var ms = new MemoryStream(); s.CopyTo(ms);
        return "data:image/png;base64," + Convert.ToBase64String(ms.ToArray());
    }
}
