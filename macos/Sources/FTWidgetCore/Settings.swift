import Foundation

public struct StatsCounters: Codable, Equatable {
    public var hour: Int
    public var counts: [String: Int]
}

/// Everything the app remembers, in UserDefaults.
public final class SettingsStore {
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func double(_ key: String, _ fallback: Double) -> Double {
        if let n = defaults.object(forKey: key) as? NSNumber { return n.doubleValue }
        if let s = defaults.string(forKey: key), let d = Double(s) { return d }
        return fallback
    }
    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        guard let o = defaults.object(forKey: key) else { return fallback }
        if let b = o as? Bool { return b }
        if let s = o as? String { return !["false", "0", "no", "off"].contains(s.lowercased()) }
        if let n = o as? NSNumber { return n.boolValue }
        return fallback
    }

    public var wallets: [String] {
        get {
            if let arr = defaults.array(forKey: "wallets") as? [String] { return Wallets.parse(arr.joined(separator: ",")).list }
            if let s = defaults.string(forKey: "wallets") { return Wallets.parse(s).list }
            return []
        }
        set { defaults.set(newValue, forKey: "wallets") }
    }
    public var hfWarn: Double {
        get { Alerts.threshold(double("hfWarn", 1.40), fallback: 1.40) }
        set { defaults.set(newValue, forKey: "hfWarn") }
    }
    public var hfCritical: Double {
        get { min(Alerts.threshold(double("hfCritical", 1.30), fallback: 1.30), hfWarn) }
        set { defaults.set(newValue, forKey: "hfCritical") }
    }
    public var notifications: Bool {
        get { bool("notifications", true) }
        set { defaults.set(newValue, forKey: "notifications") }
    }
    public var cooldownMin: Double {
        get { let v = double("cooldownMin", 30); return v >= 1 ? v : 30 }
        set { defaults.set(newValue, forKey: "cooldownMin") }
    }
    /// Chain whose FT-ftUSD market price is shown: 1 Ethereum or 146 Sonic.
    public var priceChain: Int {
        get { double("priceChain", 1) == 146 ? 146 : 1 }
        set { defaults.set(newValue, forKey: "priceChain") }
    }
    /// Anonymous usage stats, on by default.
    public var analytics: Bool {
        get { bool("analytics", true) }
        set { defaults.set(newValue, forKey: "analytics") }
    }
    public var tab: String {
        get { let t = defaults.string(forKey: "tab") ?? "market"; return ["market", "account", "positions"].contains(t) ? t : "market" }
        set { defaults.set(newValue, forKey: "tab") }
    }
    public var pageAt: Double {
        get { double("pageAt", 0) }
        set { defaults.set(newValue, forKey: "pageAt") }
    }
    public var statsCounters: StatsCounters? {
        get { defaults.data(forKey: "statsCounters").flatMap { try? JSONDecoder().decode(StatsCounters.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "statsCounters") }
    }
    public var alertStates: [String: AlertState] {
        get { defaults.data(forKey: "alertStates").flatMap { try? JSONDecoder().decode([String: AlertState].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "alertStates") }
    }
    public var alertConfig: AlertConfig {
        AlertConfig(warn: hfWarn, critical: hfCritical, cooldownMs: cooldownMin * 60_000)
    }
}
