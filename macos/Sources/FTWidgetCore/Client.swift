import Foundation

public enum Reply {
    case failed          // HTTP error, timeout, unreadable
    case null            // the JSON literal null: an answer, not a failure
    case json(Any)

    var value: Any? { if case .json(let v) = self { return v }; return nil }
    var isFailed: Bool { if case .failed = self { return true }; return false }
}

public enum Fetched<T> {
    case ok(T)
    case failed
    public var value: T? { if case .ok(let v) = self { return v }; return nil }
}

public protocol HTTPFetcher {
    func get(_ url: String) async -> Reply
}

public struct URLSessionFetcher: HTTPFetcher {
    let session: URLSession
    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c)
    }
    public func get(_ url: String) async -> Reply {
        guard let u = URL(string: url) else { return .failed }
        var req = URLRequest(url: u, timeoutInterval: 12)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return .failed }
        return Client.decode(data)
    }
}

/// Public API only (https://api.flyingtulip.com): no keys, no RPC.
public final class Client {
    let fetcher: HTTPFetcher
    public init(fetcher: HTTPFetcher = URLSessionFetcher()) { self.fetcher = fetcher }

    public static func decode(_ data: Data) -> Reply {
        let t = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return .failed }
        if t == "null" { return .null }
        guard let o = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return .failed }
        if o is NSNull { return .null }
        return .json(o)
    }

    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }

    public func price(chain: Int) async -> Fetched<PriceData> {
        let b = await fetcher.get(apiBase + "/mm/spot/tickers?chainId=\(chain)")
        if let p = Parse.price(b.value) { return .ok(p) }
        return .failed
    }

    public func fees() async -> Fetched<FeesData> {
        let b = await fetcher.get(apiBase + "/fees/application?period=1d&granularity=day")
        if let f = Parse.fees(b.value) { return .ok(f) }
        return .failed
    }

    public func feesSeries() async -> Fetched<[DayValue]> {
        let b = await fetcher.get(apiBase + "/fees/application?period=1m&granularity=day")
        if let s = Parse.feesSeries(b.value) { return .ok(s) }
        return .failed
    }

    public func klines(chain: Int) async -> Fetched<[DayValue]> {
        let b = await fetcher.get(apiBase + "/mm/spot/market/klines?symbol=FT-ftUSD&chainId=\(chain)&interval=1d&limit=30")
        if let k = Parse.klines(b.value) { return .ok(k) }
        return .failed
    }

    /// /mm/lend for one wallet (all chains, plus Monad which is asked for separately).
    public func lend(wallet: String) async -> Fetched<[ChainHealth]> {
        let a = Client.enc(wallet)
        async let b0 = fetcher.get(apiBase + "/mm/lend?user=" + a)
        async let b1 = fetcher.get(apiBase + "/mm/lend?user=" + a + "&chainId=143")
        let (x, y) = await (b0, b1)
        guard let xv = x.value else { return .failed }
        return .ok(Parse.mergeChains([Parse.lend(xv), Parse.lend(y.value)]))
    }

    public func pnl(wallet: String) async -> Fetched<Double> {
        let a = Client.enc(wallet)
        var total = 0.0, ok = 0
        await withTaskGroup(of: Double?.self) { g in
            for id in [146, 1, 56, 143] {
                g.addTask { Parse.summary(await self.fetcher.get(apiBase + "/mm/spot/account/summary?address=\(a)&chainId=\(id)").value) }
            }
            for await r in g { if let r = r { total += r; ok += 1 } }
        }
        return ok > 0 ? .ok(total) : .failed
    }

    public func rewards(wallet: String) async -> Fetched<RewardsData> {
        let b = await fetcher.get(apiBase + "/account/dashboard?address=" + Client.enc(wallet) + "&view=rewards")
        if let r = Parse.rewards(b.value) { return .ok(r) }
        return .failed
    }

    public func points(wallet: String) async -> Fetched<PointsData> {
        let b = await fetcher.get(apiBase + "/points?walletAddress=" + Client.enc(wallet))
        if let p = Parse.points(b.value) { return .ok(p) }
        return .failed
    }

    public func breakdown(wallet: String) async -> Fetched<[PointsRow]> {
        let b = await fetcher.get(apiBase + "/points/breakdown?walletAddress=" + Client.enc(wallet) + "&page=1&limit=50")
        if b.isFailed { return .failed }
        return .ok(Parse.pointsBreakdown(b.value))
    }

    /// Open positions across chains. The endpoint answers null for a wallet with none.
    public func positions(wallet: String) async -> Fetched<[PositionRow]> {
        let a = Client.enc(wallet)
        var all: [PositionRow] = []
        var ok = 0
        await withTaskGroup(of: [PositionRow]?.self) { g in
            for id in [146, 1, 56] {
                g.addTask {
                    let b = await self.fetcher.get(apiBase + "/mm/spot/account/positions?address=\(a)&chainId=\(id)")
                    switch b {
                    case .failed: return nil
                    case .null: return []
                    case .json(let v): return Parse.positions(v)
                    }
                }
            }
            for await r in g { if let r = r { all += r; ok += 1 } }
        }
        return ok > 0 ? .ok(Parse.sortPositions(all)) : .failed
    }

    /// nil inside .ok: the wallet has no ftPUTs.
    public func puts(wallet: String) async -> Fetched<PutsData?> {
        let b = await fetcher.get(apiBase + "/tge/ftPUT/user/" + Client.enc(wallet))
        guard let v = b.value else { return .failed }
        return .ok(Parse.puts(v))
    }

    public func rewardsHistory(wallet: String, range: String, now: Date = Date()) async -> Fetched<[HistoryPoint]> {
        let b = await fetcher.get(apiBase + "/account/rewards/history?address=" + Client.enc(wallet) + "&range=" + range)
        if let h = Parse.rewardsHistory(b.value, now: now) { return .ok(h) }
        return .failed
    }

    /// The leaderboard is sorted by points (500 per page): binary-search the page, then find the wallet.
    /// .ok(nil): the wallet is not on the board.
    public func rank(wallet: String, myPoints: Double) async -> Fetched<RankData?> {
        var lo = 1, hi = 14, steps = 0
        var page = (lo + hi) / 2
        while steps < 8 {
            steps += 1
            let b = await fetcher.get(apiBase + "/points/leaderboard?page=\(page)&limit=500")
            guard let v = b.value else { return .failed }
            let r = Parse.rankInPage(v, wallet: wallet, myPoints: myPoints)
            if r.found { return .ok(RankData(rank: r.rank, total: r.total)) }
            if r.total > 0 { hi = min(hi, max(1, Int((Double(r.total) / 500).rounded(.up)))) }
            if r.empty { hi = min(hi, page - 1) }
            else if r.dir == -1 { hi = page - 1 }
            else if r.dir == 1 { lo = page + 1 }
            else { return .ok(nil) }
            if lo > hi { return .ok(nil) }
            page = (lo + hi) / 2
        }
        return .ok(nil)
    }
}

/// Menu bar title: price, fees, the shown wallet's HF and, with several wallets, which one plus the switch sign.
public struct TitleParts: Equatable {
    public var price: String
    public var fees: String?
    public var hf: String?
    public var hfLevel: Int
    public var wallet: String?
    public var stale: Bool

    public var plain: String {
        var parts = [price]
        if let f = fees { parts.append(f) }
        if let h = hf { parts.append(h) }
        if let w = wallet { parts.append(w) }
        return parts.joined(separator: "  ") + (stale ? " ⚠" : "")
    }
}

public enum Title {
    public static func build(price: PriceData?, fees: FeesData?, lend: [ChainHealth]?, wallet: String, walletCount: Int,
                             alert: AlertConfig, stale: Bool) -> TitleParts {
        let low = lend.flatMap { Parse.lowestHf($0) }
        let level = low.flatMap { $0.hf }.map { Alerts.level(hf: $0, cfg: alert, prev: 0) } ?? 0
        return TitleParts(
            price: price.map { Fmt.price($0.price) } ?? "FT —",
            fees: fees.map { "fees " + Fmt.usd($0.period24h) },
            hf: (!wallet.isEmpty && lend != nil) ? "HF " + Fmt.hf(low?.hf) : nil,
            hfLevel: level,
            wallet: (!wallet.isEmpty && walletCount > 1) ? Fmt.shortAddr(wallet) + " ⇄" : nil,
            stale: stale)
    }
}
