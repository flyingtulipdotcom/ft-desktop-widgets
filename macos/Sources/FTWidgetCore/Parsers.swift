import Foundation

// Parsers for the public API answers. They tolerate missing fields and return nil (or an empty list) on unusable
// payloads. Field logic is a direct port of the xbar/SwiftBar plugin.

func num(_ v: Any?) -> Double {
    switch v {
    case let n as NSNumber:
        let d = n.doubleValue
        return d.isFinite ? d : .nan
    case let s as String:
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .nan }
        if let d = Double(t), d.isFinite { return d }
        return .nan
    default:
        return .nan
    }
}

func str(_ v: Any?) -> String {
    switch v {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
func list(_ v: Any?) -> [Any]? { v as? [Any] }

/// Exact decimal shift of an integer string (display precision only).
public func rawUnits(_ s: Any?, _ dec: Int) -> Double {
    guard let s = s as? String, !s.isEmpty, s.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
        if let n = s as? NSNumber, !(n is Bool) { return n.doubleValue / pow(10, Double(dec)) }
        return .nan
    }
    if s.count <= 15 { return (Double(s) ?? .nan) / pow(10, Double(dec)) }
    let cut = s.count - dec
    if cut <= 0 { return Double("0." + String(repeating: "0", count: -cut) + s) ?? .nan }
    let idx = s.index(s.startIndex, offsetBy: cut)
    return Double(String(s[..<idx]) + "." + String(s[idx...])) ?? .nan
}

func rawFt(_ s: Any?) -> Double { rawUnits(s, 18) }

public enum Parse {
    public static func fees(_ body: Any?) -> FeesData? {
        guard let d = dict(dict(body)?["data"]), let totals = dict(d["totals"]) else { return nil }
        let period = num(totals["period_usd"])
        guard period.isFinite else { return nil }
        var products: [(name: String, usd: Double)] = []
        for (k, v) in dict(d["byProduct"]) ?? [:] {
            let u = num(dict(v)?["period_usd"])
            if u.isFinite { products.append((k, u)) }
        }
        products.sort { $0.usd != $1.usd ? $0.usd > $1.usd : $0.name < $1.name }
        return FeesData(period24h: period, lifetime: num(totals["lifetime_usd"]), products: products)
    }

    public static func price(_ body: Any?) -> PriceData? {
        guard let ts = list(dict(dict(body)?["data"])?["tickers"]) else { return nil }
        for t in ts {
            guard let t = dict(t), str(t["display_symbol"]) == "FT-ftUSD" else { continue }
            let p = num(t["price"])
            if !p.isFinite { return nil }
            return PriceData(price: p, changePct24h: num(t["price_change_pct_24h"]), sampledAt: str(t["sampled_at"]))
        }
        return nil
    }

    public static func lend(_ body: Any?) -> [ChainHealth] {
        let b = dict(body)
        let d = dict(b?["data"]) ?? b
        guard let chains = list(d?["chains"]) else { return [] }
        var out: [ChainHealth] = []
        for c in chains {
            guard let c = dict(c) else { continue }
            let m = dict(c["userMetrics"]) ?? [:]
            let debt = num(m["totalDebtUsd"]), hf = num(m["healthFactor"])
            let hasDebt = debt.isFinite && debt > 0.01
            let id = Int(num(c["chainId"]).isFinite ? num(c["chainId"]) : -1)
            let liq = num(c["hfLiquidationThreshold"])
            out.append(ChainHealth(
                chainId: id,
                name: hfChains[id] ?? (str(c["chainName"]).isEmpty ? String(id) : str(c["chainName"])),
                hf: hasDebt && hf.isFinite ? hf : nil,
                debtUsd: debt.isFinite ? debt : 0,
                equityUsd: num(m["equityUsd"]),
                liqHf: liq.isFinite ? liq : defaultLiqHf))
        }
        return out
    }

    /// Unrealized PnL of the first summary row (the answer is an array).
    public static func summary(_ body: Any?) -> Double? {
        let b = body
        let arr = list(b) ?? list(dict(b)?["data"]) ?? []
        guard let first = dict(arr.first) else { return nil }
        let p = num(first["unrealizedPnl"])
        return p.isFinite ? p : 0
    }

    public static func mergeChains(_ lists: [[ChainHealth]]) -> [ChainHealth] {
        var byId: [Int: ChainHealth] = [:]
        for l in lists { for c in l { byId[c.chainId] = c } }
        return byId.values.sorted {
            let a = hfChainIds.firstIndex(of: $0.chainId) ?? -1, b = hfChainIds.firstIndex(of: $1.chainId) ?? -1
            return a < b
        }
    }

    public static func lowestHf(_ chains: [ChainHealth]) -> ChainHealth? {
        var best: ChainHealth?
        for c in chains {
            guard let h = c.hf else { continue }
            if best == nil || h < best!.hf! { best = c }
        }
        return best
    }

    /// FT earned, all time and all chains: sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending).
    /// NaN total when any piece is unknown or a section errored.
    public static func rewards(_ body: Any?) -> RewardsData? {
        let b = dict(body)
        guard (b?["success"] as? Bool) != false, let d = dict(b?["data"]), let chains = list(d["chains"]) else { return nil }
        let errs = dict(d["sectionErrors"]) ?? [:]
        func truthy(_ v: Any?) -> Bool {
            if let b = v as? Bool { return b }
            if v == nil || v is NSNull { return false }
            if let n = v as? NSNumber { return n.doubleValue != 0 }
            if let s = v as? String { return !s.isEmpty }
            return true
        }
        let stakingFailed = truthy(errs["staking"]), lendFailed = truthy(errs["lend"])
        var known = !stakingFailed && !lendFailed
        var r = RewardsData()
        for c in chains {
            guard let c = dict(c) else { continue }
            let st = dict(c["staking"])
            let lendObj = dict(c["lend"])
            let lm = dict(lendObj?["userMetrics"])
            var pendingSft: Double = st != nil ? rawFt(st!["pending_yield_ft"]) : (stakingFailed ? .nan : 0)
            var claimedSft: Double
            if let st = st {
                let idx = st["claimed_yield_indexed_through_block"]
                let indexed = truthy(idx) && !(idx is NSNull)
                claimedSft = (indexed && !truthy(st["claimed_yield_stale"])) ? rawFt(st["claimed_yield_ft"]) : .nan
            } else { claimedSft = stakingFailed ? .nan : 0 }
            var rec: Double = lendFailed ? .nan : 0, pen: Double = lendFailed ? .nan : 0
            if lendObj != nil {
                let fr = dict(lm?["ftRewards"])
                if lm != nil && truthy(lm?["ftRewardsError"]) { rec = .nan; pen = .nan }
                else if let fr = fr { rec = rawFt(fr["receivedFtRaw"]); pen = rawFt(fr["pendingFtRaw"]) }
                else if lm == nil { rec = .nan; pen = .nan }
                else { rec = 0; pen = 0 }
            }
            if pendingSft.isFinite { r.claimableFt += pendingSft }
            if !pendingSft.isFinite || !claimedSft.isFinite || !rec.isFinite || !pen.isFinite { known = false; continue }
            pendingSft = max(pendingSft, 0); claimedSft = max(claimedSft, 0)
            r.sftClaimed += claimedSft; r.sftPending += pendingSft; r.lendReceived += rec; r.lendPending += pen
            let id = Int(num(c["chainId"]).isFinite ? num(c["chainId"]) : -1)
            r.chains.append(ChainEarned(chainId: id, name: hfChains[id] ?? str(c["chainId"]), sft: claimedSft + pendingSft, lend: rec + pen))
        }
        r.sftFt = r.sftClaimed + r.sftPending
        r.lendFt = r.lendReceived + r.lendPending
        r.totalFt = known ? r.sftFt + r.lendFt : .nan
        return r
    }

    /// Chains that earned something, as "Sonic 95.4, Ethereum 0.06".
    public static func earnedByChain(_ r: RewardsData?) -> String {
        guard let r = r else { return "" }
        return r.chains.filter { $0.sft + $0.lend >= 0.005 }.map { $0.name + " " + Fmt.ft($0.sft + $0.lend) }.joined(separator: ", ")
    }

    /// /tge/ftPUT/user/<wallet>: cost basis = sum(current_capital * strike), FT held = current_ft + withdrawn_ft.
    public static func puts(_ body: Any?) -> PutsData? {
        guard let ps = list(dict(dict(body)?["data"])?["positions"]), !ps.isEmpty else { return nil }
        var cost = 0.0, ftHeld = 0.0
        var rows: [PutRow] = []
        for p in ps {
            guard let p = dict(p) else { continue }
            var dec = num(p["token_decimals"])
            if !dec.isFinite {
                let d2 = num(dict(p["tokenData"])?["decimals"])
                dec = d2.isFinite && d2 != 0 ? d2 : 18
            }
            let strike = rawUnits(p["strike"], 8)
            let cap = rawUnits(p["current_capital"], Int(dec))
            let ftC = rawUnits(p["current_ft"], 18)
            var ftW = rawUnits(p["withdrawn_ft"], 18)
            if !strike.isFinite || !cap.isFinite || !ftC.isFinite { continue }
            if !ftW.isFinite { ftW = 0 }
            cost += cap * strike; ftHeld += ftC + ftW
            var sym = str(p["token_symbol"])
            if sym.isEmpty { sym = str(dict(p["tokenData"])?["symbol"]) }
            if sym.isEmpty { sym = "?" }
            rows.append(PutRow(nft: str(p["nft_id"]), symbol: sym, costUsd: cap * strike, strike: strike, ft: ftC + ftW,
                               since: String(str(p["created_at"]).prefix(10))))
        }
        if rows.isEmpty { return nil }
        return PutsData(count: rows.count, costUsd: cost, ftHeld: ftHeld, rows: rows)
    }

    /// gain = FT held x FT MARKET price - cost basis (never NAV)
    public static func putGain(_ puts: PutsData?, ftPrice: Double) -> PutGain? {
        guard let puts = puts, ftPrice.isFinite else { return nil }
        let value = puts.ftHeld * ftPrice, gain = value - puts.costUsd
        return PutGain(valueUsd: value, gainUsd: gain, gainPct: puts.costUsd > 0 ? gain / puts.costUsd * 100 : .nan)
    }

    /// /points?walletAddress=: the all-chains total (what the leaderboard ranks) plus each chain's share, largest first.
    public static func points(_ body: Any?) -> PointsData? {
        guard let chains = list(dict(dict(body)?["data"])?["chains"]) else { return nil }
        var total = Double.nan
        var per: [ChainPoints] = []
        for c in chains {
            guard let c = dict(c) else { continue }
            let v = dict(c["userMetrics"]) != nil ? num(dict(c["userMetrics"])?["totalPoints"]) : .nan
            if (c["isAllChains"] as? Bool) == true { total = v; continue }
            if !(v > 0) { continue }
            let cd = dict(c["chainData"])
            let idv = num(cd?["id"])
            let id = idv.isFinite ? Int(idv) : -1
            per.append(ChainPoints(chainId: id, name: hfChains[id] ?? (str(cd?["name"]).isEmpty ? "?" : str(cd?["name"])), points: v))
        }
        if !total.isFinite { return nil }
        per.sort { $0.points > $1.points }
        return PointsData(total: total, chains: per)
    }

    /// /points/breakdown: the positions earning points.
    public static func pointsBreakdown(_ body: Any?) -> [PointsRow] {
        guard let rows = list(dict(dict(body)?["data"])?["pointsBreakdown"]) else { return [] }
        return rows.compactMap { r in
            guard let r = dict(r) else { return nil }
            let product = str(r["productLabel"]).isEmpty ? str(r["product"]) : str(r["productLabel"])
            let activity = str(r["activityLabel"]).isEmpty ? str(r["activity"]) : str(r["activityLabel"])
            return PointsRow(label: product + " " + activity, positionUsd: num(r["positionUsd"]), multiplier: num(r["multiplier"]))
        }
    }

    /// Leaderboard page -> found / rank / direction. dir -1: wallet is on an earlier page, +1 later.
    public static func rankInPage(_ body: Any?, wallet: String, myPoints: Double) -> RankPage {
        let d = dict(dict(body)?["data"])
        let total = Int(num(dict(d?["pagination"])?["total"]).isFinite ? num(dict(d?["pagination"])?["total"]) : 0)
        guard let lb = list(d?["leaderboard"]), !lb.isEmpty else {
            return RankPage(found: false, rank: 0, dir: 0, total: total, empty: true)
        }
        let w = wallet.lowercased()
        for e in lb {
            if let e = dict(e), str(e["userWallet"]).lowercased() == w {
                return RankPage(found: true, rank: Int(num(e["rank"]).isFinite ? num(e["rank"]) : 0), dir: 0, total: total)
            }
        }
        let first = num(dict(lb.first)?["totalPoints"]), last = num(dict(lb.last)?["totalPoints"])
        return RankPage(found: false, rank: 0, dir: myPoints > first ? -1 : (myPoints < last ? 1 : 0), total: total)
    }

    public static func positions(_ body: Any?) -> [PositionRow] {
        let arr = list(body) ?? list(dict(body)?["data"]) ?? []
        var out: [PositionRow] = []
        for p in arr {
            guard let p = dict(p) else { continue }
            let size = num(p["size"]), mark = num(p["markPrice"])
            if !size.isFinite || size <= 0 { continue }
            let cid = num(p["chainId"])
            let id = cid.isFinite ? Int(cid) : -1
            let symbol = str(p["symbol"])
            var sym = str(p["sizeCurrency"])
            if sym.isEmpty { sym = symbol.components(separatedBy: "-").first.orEmpty }
            if sym.isEmpty { sym = "?" }
            let lev = num(p["blendedLeverage"]).isFinite && num(p["blendedLeverage"]) != 0 ? num(p["blendedLeverage"]) : num(p["leverage"])
            let net = str(p["network"])
            out.append(PositionRow(
                chainId: id, network: net.isEmpty ? (hfChains[id] ?? String(id)) : net, symbol: sym, market: symbol,
                side: str(p["side"]).lowercased() == "short" ? "short" : "long",
                size: size, entry: num(p["entryPrice"]), mark: mark, pnlUsd: num(p["pnlAmount"]), pnlPct: num(p["pnlPct"]),
                leverage: lev, valueUsd: mark.isFinite ? size * mark : .nan))
        }
        return out
    }

    public static func sortPositions(_ rows: [PositionRow]) -> [PositionRow] {
        rows.sorted { (a, b) in (b.valueUsd.isFinite ? b.valueUsd : 0) < (a.valueUsd.isFinite ? a.valueUsd : 0) }
    }

    public static func feesSeries(_ body: Any?) -> [DayValue]? {
        guard let s = list(dict(dict(body)?["data"])?["series"]), !s.isEmpty else { return nil }
        var out: [DayValue] = []
        for e in s {
            guard let e = dict(e) else { continue }
            let v = num(e["total_usd"])
            if v.isFinite { out.append(DayValue(date: str(e["date"]), value: v)) }
        }
        return out.isEmpty ? nil : out
    }

    static func isoDay(_ ms: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    /// Market closes (never NAV).
    public static func klines(_ body: Any?) -> [DayValue]? {
        guard let arr = list(body), !arr.isEmpty else { return nil }
        var out: [DayValue] = []
        for e in arr {
            guard let e = dict(e) else { continue }
            let c = num(e["close"])
            if c.isFinite { out.append(DayValue(date: isoDay(num(e["time"])), value: c)) }
        }
        return out.isEmpty ? nil : out
    }

    /// Day-over-day % across FINISHED days (the last bucket is the partial current day).
    public static func feesDayOverDay(_ series: [DayValue]?, now: Date) -> Double {
        guard let series = series, series.count >= 4 else { return .nan }
        let today = isoDay(now.timeIntervalSince1970 * 1000)
        let rows = String(series[series.count - 1].date.prefix(10)) == today ? Array(series.dropLast()) : series
        if rows.count < 2 { return .nan }
        let last = rows[rows.count - 1].value, prev = rows[rows.count - 2].value
        return prev > 0 ? (last - prev) / prev * 100 : .nan
    }

    /// /account/rewards/history: cumulative FT earned across all chains at UTC day ends (today's partial sample ignored).
    public static func rewardsHistory(_ body: Any?, now: Date) -> [HistoryPoint]? {
        guard let pts = list(dict(dict(body)?["data"])?["points"]), !pts.isEmpty else { return nil }
        let day = 86400
        let today = Int(now.timeIntervalSince1970) / day * day
        var rows: [HistoryPoint] = []
        for p in pts {
            guard let p = dict(p) else { continue }
            let tsd = num(p["timestampUnixSeconds"])
            guard tsd.isFinite else { continue }
            let ts = Int(tsd)
            if ts >= today || ts % day != day - 1 { continue }
            let e = rawUnits(p["totalEarnedFtRaw"], 18)
            let c = rawUnits(p["claimedFtRaw"], 18)
            if !e.isFinite { continue }
            rows.append(HistoryPoint(ts: ts, date: isoDay(Double(ts) * 1000), earned: e, claimed: c.isFinite ? c : 0))
        }
        rows.sort { $0.ts < $1.ts }
        return rows.isEmpty ? nil : rows
    }

    /// Per-day FT gained from a cumulative series.
    public static func dailyGains(_ series: [HistoryPoint]?, claimed: Bool = false) -> [DayValue] {
        guard let s = series, s.count > 1 else { return [] }
        var out: [DayValue] = []
        for i in 1..<s.count {
            if s[i].ts - s[i - 1].ts != 86400 { continue }
            let a = claimed ? s[i].claimed : s[i].earned, b = claimed ? s[i - 1].claimed : s[i - 1].earned
            out.append(DayValue(date: s[i].date, value: max(0, a - b)))
        }
        return out
    }
}
