using System.IO.Compression;

namespace FlyingTulip.Widget;

public readonly record struct Rgba(byte R, byte G, byte B, byte A = 255)
{
    public static Rgba Hex(string hex, byte a = 255)
    {
        var h = hex.TrimStart('#');
        return new Rgba(Convert.ToByte(h[..2], 16), Convert.ToByte(h[2..4], 16), Convert.ToByte(h[4..6], 16), a);
    }
    public Rgba WithAlpha(byte a) => this with { A = a };
}

/// <summary>
/// A tiny anti-aliased RGBA canvas (3x3 supersampling) with a PNG encoder, so the provider can draw the charts and
/// gauges the Adaptive Card cannot. Coordinates are output pixels. No dependencies, no fonts, same output everywhere.
/// </summary>
public sealed class Canvas
{
    readonly int _w, _h, _ss;
    readonly float[] _p;   // premultiplied RGBA at supersampled resolution

    public int Width => _w;
    public int Height => _h;

    public Canvas(int w, int h, int ss = 3)
    {
        _w = w; _h = h; _ss = ss;
        _p = new float[w * ss * h * ss * 4];
    }

    void Blend(int ix, int iy, Rgba c, float cover = 1f)
    {
        int W = _w * _ss, H = _h * _ss;
        if (ix < 0 || iy < 0 || ix >= W || iy >= H) return;
        float a = c.A / 255f * cover;
        if (a <= 0) return;
        int o = (iy * W + ix) * 4;
        float inv = 1 - a;
        _p[o] = c.R / 255f * a + _p[o] * inv;
        _p[o + 1] = c.G / 255f * a + _p[o + 1] * inv;
        _p[o + 2] = c.B / 255f * a + _p[o + 2] * inv;
        _p[o + 3] = a + _p[o + 3] * inv;
    }

    void Region(double x0, double y0, double x1, double y1, Rgba c, Func<double, double, bool> inside)
    {
        int ax = (int)Math.Floor(x0 * _ss), bx = (int)Math.Ceiling(x1 * _ss);
        int ay = (int)Math.Floor(y0 * _ss), by = (int)Math.Ceiling(y1 * _ss);
        for (int y = ay; y < by; y++)
            for (int x = ax; x < bx; x++)
                if (inside((x + 0.5) / _ss, (y + 0.5) / _ss)) Blend(x, y, c);
    }

    public void Rect(double x0, double y0, double x1, double y1, Rgba c) => Region(x0, y0, x1, y1, c, (x, y) => x >= x0 && x < x1 && y >= y0 && y < y1);

    /// <summary>Rounded rectangle; with topOnly only the two top corners are rounded (a bar that stands on the baseline).</summary>
    public void RoundRect(double x, double y, double w, double h, double r, Rgba c, bool topOnly = false)
    {
        r = Math.Max(0, Math.Min(r, Math.Min(w, h) / 2));
        double x1 = x + w, y1 = y + h;
        Region(x, y, x1, y1, c, (px, py) =>
        {
            if (px < x || px >= x1 || py < y || py >= y1) return false;
            if (topOnly && py >= y + r) return true;
            double cx = px < x + r ? x + r : (px > x1 - r ? x1 - r : px);
            double cy = py < y + r ? y + r : (!topOnly && py > y1 - r ? y1 - r : py);
            double dx = px - cx, dy = py - cy;
            return dx * dx + dy * dy <= r * r;
        });
    }

    public void Circle(double cx, double cy, double r, Rgba c) =>
        Region(cx - r, cy - r, cx + r, cy + r, c, (x, y) => (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r);

    public void Segment(double x0, double y0, double x1, double y1, double thickness, Rgba c)
    {
        double r = thickness / 2, dx = x1 - x0, dy = y1 - y0, len2 = dx * dx + dy * dy;
        Region(Math.Min(x0, x1) - r, Math.Min(y0, y1) - r, Math.Max(x0, x1) + r, Math.Max(y0, y1) + r, c, (x, y) =>
        {
            double t = len2 == 0 ? 0 : Math.Clamp(((x - x0) * dx + (y - y0) * dy) / len2, 0, 1);
            double px = x0 + t * dx - x, py = y0 + t * dy - y;
            return px * px + py * py <= r * r;
        });
    }

    public void Polyline(IReadOnlyList<(double X, double Y)> pts, double thickness, Rgba c)
    {
        for (int i = 1; i < pts.Count; i++) Segment(pts[i - 1].X, pts[i - 1].Y, pts[i].X, pts[i].Y, thickness, c);
        if (pts.Count == 1) Circle(pts[0].X, pts[0].Y, thickness / 2, c);
    }

    /// <summary>Fills from the polyline down to the bottom with a vertical fade from alphaTop to alphaBottom.</summary>
    public void AreaUnder(IReadOnlyList<(double X, double Y)> pts, double top, double bottom, Rgba c, double alphaTop, double alphaBottom)
    {
        if (pts.Count < 2) return;
        int W = _w * _ss;
        for (int sx = (int)Math.Ceiling(pts[0].X * _ss); sx < Math.Min(W, (int)Math.Floor(pts[^1].X * _ss)); sx++)
        {
            double x = (sx + 0.5) / _ss, yLine = pts[^1].Y;
            for (int i = 1; i < pts.Count; i++)
                if (x <= pts[i].X)
                {
                    double span = pts[i].X - pts[i - 1].X, t = span <= 0 ? 0 : (x - pts[i - 1].X) / span;
                    yLine = pts[i - 1].Y + (pts[i].Y - pts[i - 1].Y) * t;
                    break;
                }
            for (int sy = (int)Math.Floor(yLine * _ss); sy < (int)Math.Ceiling(bottom * _ss); sy++)
            {
                double y = (sy + 0.5) / _ss;
                if (y < yLine) continue;
                double f = Math.Clamp((y - top) / Math.Max(1e-6, bottom - top), 0, 1);
                Blend(sx, sy, c, (float)(alphaTop + (alphaBottom - alphaTop) * f));
            }
        }
    }

    public byte[] ToPng()
    {
        int W = _w * _ss, raw = _w * 4 + 1;
        var data = new byte[raw * _h];
        float n = _ss * _ss;
        for (int y = 0; y < _h; y++)
        {
            data[y * raw] = 0;
            for (int x = 0; x < _w; x++)
            {
                float r = 0, g = 0, b = 0, a = 0;
                for (int sy = 0; sy < _ss; sy++)
                    for (int sx = 0; sx < _ss; sx++)
                    {
                        int o = ((y * _ss + sy) * W + x * _ss + sx) * 4;
                        r += _p[o]; g += _p[o + 1]; b += _p[o + 2]; a += _p[o + 3];
                    }
                r /= n; g /= n; b /= n; a /= n;
                int d = y * raw + 1 + x * 4;
                if (a > 0.0001f)
                {
                    data[d] = (byte)Math.Clamp((int)Math.Round(r / a * 255), 0, 255);
                    data[d + 1] = (byte)Math.Clamp((int)Math.Round(g / a * 255), 0, 255);
                    data[d + 2] = (byte)Math.Clamp((int)Math.Round(b / a * 255), 0, 255);
                    data[d + 3] = (byte)Math.Clamp((int)Math.Round(a * 255), 0, 255);
                }
            }
        }
        return Png.Encode(_w, _h, data);
    }

    public string ToDataUri() => "data:image/png;base64," + Convert.ToBase64String(ToPng());
}

static class Png
{
    static uint[]? _table;
    static uint Crc(byte[] buf, int start, int len)
    {
        if (_table is null)
        {
            var t = new uint[256];
            for (uint n = 0; n < 256; n++)
            {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                t[n] = c;
            }
            _table = t;
        }
        uint crc = 0xFFFFFFFFu;
        for (int i = start; i < start + len; i++) crc = _table[(crc ^ buf[i]) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        var buf = new byte[4 + data.Length];
        for (int i = 0; i < 4; i++) buf[i] = (byte)type[i];
        Array.Copy(data, 0, buf, 4, data.Length);
        s.Write(Be((uint)data.Length));
        s.Write(buf);
        s.Write(Be(Crc(buf, 0, buf.Length)));
    }

    static byte[] Be(uint v) => new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v };

    /// <param name="rgbaRows">Each row: one filter byte (0) then w*4 RGBA bytes.</param>
    public static byte[] Encode(int w, int h, byte[] rgbaRows)
    {
        using var ms = new MemoryStream();
        ms.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var ihdr = new byte[13];
        Be((uint)w).CopyTo(ihdr, 0); Be((uint)h).CopyTo(ihdr, 4);
        ihdr[8] = 8; ihdr[9] = 6;
        Chunk(ms, "IHDR", ihdr);
        using (var z = new MemoryStream())
        {
            using (var zs = new ZLibStream(z, CompressionLevel.Optimal, true)) zs.Write(rgbaRows);
            Chunk(ms, "IDAT", z.ToArray());
        }
        Chunk(ms, "IEND", Array.Empty<byte>());
        return ms.ToArray();
    }
}
