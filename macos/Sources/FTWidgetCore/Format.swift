import Foundation

// Number and text formatting, the same rules as the xbar/SwiftBar plugin and the other widgets.
public enum Fmt {
    static func fixed(_ v: Double, _ digits: Int) -> String {
        // JS toFixed rounds half away from zero on the decimal expansion; String(format:) is close enough for display.
        String(format: "%.\(digits)f", v)
    }

    public static func usd(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        let a = abs(v)
        if a >= 1e6 { return "$" + fixed(a / 1e6, 2) + "M" }
        if a >= 1e4 { return "$" + fixed(a / 1e3, 1) + "k" }
        if a >= 1e3 { return "$" + fixed(a / 1e3, 2) + "k" }
        return "$" + fixed(a, a >= 100 ? 0 : 2)
    }

    public static func signedUsd(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        if abs(v) < 0.005 { return "$0.00" }
        return (v < 0 ? "-" : "+") + usd(v)
    }

    public static func price(_ p: Double) -> String {
        if !p.isFinite { return "—" }
        return "$" + fixed(p, p >= 1 ? 2 : 4)
    }

    public static func hf(_ hf: Double?) -> String {
        guard let hf = hf, hf.isFinite else { return "∞" }
        return hf >= 100 ? ">100" : fixed(hf, 2)
    }

    public static func pct(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        return (v >= 0 ? "+" : "") + (abs(v) >= 100 ? fixed(v, 0) : fixed(v, 1)) + "%"
    }

    public static func ft(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        if v < 0.01 { return v <= 0 ? "0" : "<0.01" }
        if v < 10 { return fixed(v, 2) }
        if v < 1000 { return fixed(v, 1) }
        if v < 1e6 { return fixed(v / 1e3, v < 1e4 ? 2 : 1) + "K" }
        return fixed(v / 1e6, 2) + "M"
    }

    public static func points(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        let a = abs(v)
        if a >= 1e9 { return fixed(a / 1e9, 2) + "B" }
        if a >= 1e6 { return fixed(a / 1e6, a >= 1e8 ? 0 : 1) + "M" }
        if a >= 1e3 { return fixed(a / 1e3, a >= 1e5 ? 0 : 1) + "K" }
        return fixed(a, 0)
    }

    public static func size(_ v: Double) -> String {
        if !v.isFinite { return "—" }
        let a = abs(v)
        if a >= 1e6 { return fixed(a / 1e6, 2) + "M" }
        if a >= 1e4 { return fixed(a / 1e3, 1) + "K" }
        if a >= 100 { return fixed(a, 0) }
        if a >= 1 { return fixed(a, 2) }
        return fixed(a, 4)
    }

    public static func thousands(_ n: Double) -> String {
        let s = String(Int(n.rounded()))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 && ch != "-" { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    public static func shortAddr(_ a: String) -> String {
        a.count > 12 ? String(a.prefix(6)) + "…" + String(a.suffix(4)) : a
    }

    public static func ageText(_ sec: Int) -> String {
        sec < 90 ? "\(sec)s" : (sec < 5400 ? "\(Int((Double(sec) / 60).rounded()))m" : "\(Int((Double(sec) / 3600).rounded()))h")
    }
}

// Wallet addresses: 0x + 40 hex characters, stored lowercase.
public enum Wallets {
    public static func isAddress(_ a: String) -> Bool {
        let chars = Array(a.utf8)
        guard chars.count == 42, chars[0] == 0x30, chars[1] == 0x78 else { return false }
        return chars[2...].allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) || ($0 >= 0x41 && $0 <= 0x46) }
    }

    public static func normalize(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return isAddress(t) ? t.lowercased() : ""
    }

    /// "0xA, 0xB" (commas, spaces, semicolons or new lines) -> lowercase list without duplicates, plus the entries that are not addresses.
    public static func parse(_ text: String) -> (list: [String], bad: [String]) {
        var list: [String] = [], bad: [String] = []
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ", ;\n\r\t")).filter { !$0.isEmpty }
        for p in parts {
            let w = normalize(p)
            if w.isEmpty { bad.append(p) } else if !list.contains(w) { list.append(w) }
        }
        return (list, bad)
    }
}
