import Foundation

/// Anonymous usage stats (Plausible), same events and values as the other widgets. Only the event name, the platform,
/// the version, `native` and the few values the app passes (os, host, tab, element, url, level, endpoint, a wallet
/// count bucket) are sent. Never a wallet address, balance or position: any 0x address inside a value becomes
/// ":address". Nothing is sent while the switch is off. Each event name is capped at 30 per hour.
public enum Stats {
    public static let version = "2.0.0"
    public static let endpoint = "https://plausible.io/api/event"
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) FlyingTulipWidget/" + version
    public static let cap = 30

    public static func value(_ v: String) -> String {
        let r = v.replacingOccurrences(of: "0x[0-9a-fA-F]{40}", with: ":address", options: .regularExpression)
        return String(r.prefix(300))
    }

    public static func body(_ name: String, _ props: [String: String] = [:]) -> Data {
        var p: [String: String] = ["platform": "macos", "version": version, "native": "true"]
        for (k, v) in props { p[k] = value(v) }
        let obj: [String: Any] = ["name": name, "url": "app://widget/macos", "domain": "widget", "props": p]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }

    public static func osSlug(_ s: String) -> String {
        let l = s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let t = l.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return t.isEmpty ? "macos" : t
    }

    /// Element ids: lowercase letters, digits and dashes only.
    public static func sanitize(_ s: String) -> String {
        var v = String.UnicodeScalarView()
        for u in s.lowercased().unicodeScalars where (u >= "a" && u <= "z") || (u >= "0" && u <= "9") || u == "-" { v.append(u) }
        return String(v)
    }

    public static func walletsBucket(_ n: Int) -> String { n >= 3 ? "3+" : String(n) }

    public static func osLabel() -> String {
        "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
    }

    /// Where a visit to flyingtulip.com came from, only while usage stats are on:
    ///   ?utm_source=ft-widget&utm_medium=macos&utm_content=<element>  (added to the query the URL already has)
    ///   #ftw=macos.<os-slug>.<version, dots as dashes>.<element>      (left out when the URL already has an anchor)
    public static func originUrl(_ url: String, element: String, os: String) -> String {
        let el = sanitize(element)
        let hashIdx = url.firstIndex(of: "#")
        let base = hashIdx.map { String(url[..<$0]) } ?? url
        let hash = hashIdx.map { String(url[url.index(after: $0)...]) }
        let q = (base.contains("?") ? "&" : "?") + "utm_source=ft-widget&utm_medium=macos&utm_content=" + el
        if let h = hash { return base + q + "#" + h }
        return base + q + "#ftw=macos." + osSlug(os) + "." + version.replacingOccurrences(of: ".", with: "-") + "." + el
    }

    public static func endpointName(forSource key: String) -> String? {
        let k = key.components(separatedBy: "@").first.orEmpty
        let table = ["price": "ticker", "fees": "fees", "feesSeries": "fees", "klines": "klines", "lend": "lend", "pnl": "summary",
                     "rewards": "rewards", "points": "points", "positions": "positions", "puts": "ftput", "rank": "leaderboard",
                     "history": "rewards-history", "breakdown": "points-breakdown"]
        return table[k]
    }
}

public protocol StatsTransport {
    func post(_ body: Data)
}

/// Fire and forget POST to Plausible.
public struct PlausibleTransport: StatsTransport {
    public init() {}
    public func post(_ body: Data) {
        guard let url = URL(string: Stats.endpoint) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Stats.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}

public final class UsageStats {
    private let settings: SettingsStore
    private let transport: StatsTransport
    private let now: () -> Date
    private var hour: Int = -1
    private var counts: [String: Int] = [:]
    private var errAt: [String: Double] = [:]

    public init(settings: SettingsStore, transport: StatsTransport, now: @escaping () -> Date = Date.init) {
        self.settings = settings; self.transport = transport; self.now = now
        if let saved = settings.statsCounters {
            hour = saved.hour; counts = saved.counts
        }
    }

    public var enabled: Bool { settings.analytics }

    /// Sends one event unless usage stats are off or the name is over its hourly cap. Returns true when it went out.
    @discardableResult
    public func send(_ name: String, _ props: [String: String] = [:]) -> Bool {
        guard enabled else { return false }
        return sendForced(name, props)
    }

    /// Same as `send` but without the switch check: the one last event on the way off.
    @discardableResult
    func sendForced(_ name: String, _ props: [String: String]) -> Bool {
        let h = Int(now().timeIntervalSince1970 / 3600)
        if hour != h { hour = h; counts = [:] }
        let c = counts[name] ?? 0
        if c >= Stats.cap { return false }
        counts[name] = c + 1
        settings.statsCounters = StatsCounters(hour: hour, counts: counts)
        transport.post(Stats.body(name, props))
        return true
    }

    /// The switch under Advanced: "Usage stats off" is the last event, then nothing; back on sends "Usage stats on".
    public func setEnabled(_ on: Bool) {
        let os = Stats.osLabel()
        if on == settings.analytics { return }
        if !on {
            sendForced("Usage stats off", ["os": os])
            settings.analytics = false
        } else {
            settings.analytics = true
            send("Usage stats on", ["os": os])
        }
    }

    public func pageviewIfDue(walletCount: Int, force: Bool = false) {
        guard enabled else { return }
        let nowMs = now().timeIntervalSince1970 * 1000
        if !force, nowMs - settings.pageAt < 86_400_000 { return }
        if send("pageview", ["os": Stats.osLabel(), "host": "native", "walletsConfigured": Stats.walletsBucket(walletCount)]) {
            settings.pageAt = nowMs
        }
    }

    /// A failed or unusable answer, at most once an hour per endpoint.
    public func fetchError(source: String) {
        guard enabled, let ep = Stats.endpointName(forSource: source) else { return }
        let nowMs = now().timeIntervalSince1970 * 1000
        if nowMs - (errAt[ep] ?? 0) < 3_600_000 { return }
        errAt[ep] = nowMs
        send("Fetch error", ["endpoint": ep])
    }

    /// The URL to open for a flyingtulip.com link, counting the click while usage stats are on.
    public func linkTarget(url: String, element: String) -> String? {
        guard url.hasPrefix("https://flyingtulip.com/") else { return nil }
        let el = String(Stats.sanitize(element).prefix(60))
        guard enabled else { return url }
        send("Link click", ["element": el, "url": url])
        return Stats.originUrl(url, element: el, os: Stats.osLabel())
    }
}
