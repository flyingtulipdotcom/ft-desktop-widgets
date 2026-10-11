import Foundation

public struct AlertConfig: Equatable {
    public var warn: Double
    public var critical: Double
    public var cooldownMs: Double
    public var hyst: Double = 0.05
    public init(warn: Double, critical: Double, cooldownMs: Double, hyst: Double = 0.05) {
        self.warn = warn; self.critical = critical; self.cooldownMs = cooldownMs; self.hyst = hyst
    }
}

/// level: 0 ok, 1 warning, 2 critical. last: ms of the last notification per level.
public struct AlertState: Codable, Equatable {
    public var level: Int = 0
    public var last1: Double = -1e18
    public var last2: Double = -1e18
    public init(level: Int = 0, last1: Double = -1e18, last2: Double = -1e18) { self.level = level; self.last1 = last1; self.last2 = last2 }
}

public struct AlertNotice: Equatable {
    public var level: Int
    public var hf: Double
    public var chain: String
    public var liqHf: Double
    public var wallet: String?
}

public enum Alerts {
    /// A level only clears once HF is back above its threshold + hysteresis.
    public static func level(hf: Double, cfg: AlertConfig, prev: Int) -> Int {
        var lvl = 0
        if hf <= cfg.critical { lvl = 2 } else if hf <= cfg.warn { lvl = 1 }
        if prev == 2 && lvl < 2 && hf <= cfg.critical + cfg.hyst { lvl = 2 }
        if prev >= 1 && lvl < 1 && hf <= cfg.warn + cfg.hyst { lvl = 1 }
        return lvl
    }

    /// Notifies once per upward crossing, never twice for the same level within the cooldown.
    /// entry == nil (no debt) resets to level 0.
    public static func decide(state: AlertState, entry: ChainHealth?, cfg: AlertConfig, nowMs: Double) -> (state: AlertState, notice: AlertNotice?) {
        var st = state
        guard let entry = entry, let hf = entry.hf else { st.level = 0; return (st, nil) }
        let lvl = level(hf: hf, cfg: cfg, prev: st.level)
        var notice: AlertNotice?
        let last = lvl == 2 ? st.last2 : st.last1
        if lvl > st.level && nowMs - last >= cfg.cooldownMs {
            notice = AlertNotice(level: lvl, hf: hf, chain: entry.name, liqHf: entry.liqHf, wallet: nil)
            if lvl == 2 { st.last2 = nowMs } else { st.last1 = nowMs }
        }
        st.level = lvl
        return (st, notice)
    }

    /// n.wallet (short address), when set, names the wallet so a notification says which one of several it is about.
    public static func text(_ n: AlertNotice) -> (critical: Bool, title: String, body: String) {
        let hf = String(format: "%.2f", n.hf), who = n.wallet.map { $0 + ": " } ?? ""
        let liq = String(format: "%.2f", n.liqHf)
        if n.level == 2 {
            return (true, "FT account near liquidation", who + n.chain + " HF " + hf + " (liquidation below " + liq + "). Add collateral or repay now.")
        }
        return (false, "FT account health low", who + n.chain + " HF " + hf + " (liquidation below " + liq + ").")
    }

    public static func threshold(_ v: Double, fallback: Double) -> Double { v.isFinite && v > 1 ? v : fallback }

    /// The wallet whose health factor is at or below the warning line (the lowest one when several are), else nil.
    public static func pinnedWallet(levels: [String: Int], lowestHf: [String: Double], wallets: [String]) -> String? {
        var best: String?, bestHf = Double.infinity
        for w in wallets {
            guard (levels[w] ?? 0) >= 1, let hf = lowestHf[w] else { continue }
            if hf < bestHf { best = w; bestHf = hf }
        }
        return best
    }
}
