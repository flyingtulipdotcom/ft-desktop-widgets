import Foundation

public let apiBase = "https://api.flyingtulip.com"
public let siteBase = "https://flyingtulip.com/"
public let defaultLiqHf = 1.25
public let hfChains: [Int: String] = [146: "Sonic", 1: "Ethereum", 56: "BNB", 143: "Monad"]
public let hfChainIds = [146, 1, 56, 143]

/// Public flyingtulip.com pages the panel links to.
public enum Pages {
    public static let home = siteBase
    public static let fees = siteBase + "statistics/"
    public static let health = siteBase + "lend/dashboard/"
    public static let portfolio = siteBase + "trade/portfolio/"
    public static let rewards = siteBase + "rewards/"
    public static let points = siteBase + "rewards/leaderboard/"
    public static let pointsActivity = siteBase + "rewards/my-activity/"
    public static let put = siteBase + "allocation/positions/"

    /// Spot market page for a symbol such as "FT-ftUSD" on a chain id.
    public static func market(_ symbol: String = "FT-ftUSD", chainId: Int?) -> String {
        let sym = symbol.isEmpty ? "FT-ftUSD" : symbol
        var q = "symbol=" + sym.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))).orEmpty
        if let c = chainId, c > 0 { q += "&chainId=\(c)" }
        return siteBase + "trade/?" + q + "&marketType=spot"
    }
}

extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

public struct PriceData: Equatable {
    public var price: Double
    public var changePct24h: Double
    public var sampledAt: String
}

public struct FeesData: Equatable {
    public var period24h: Double
    public var lifetime: Double
    public var products: [(name: String, usd: Double)]
    public static func == (a: FeesData, b: FeesData) -> Bool {
        a.period24h == b.period24h && a.lifetime == b.lifetime && a.products.map { $0.name } == b.products.map { $0.name }
    }
}

public struct DayValue: Equatable {
    public var date: String
    public var value: Double
    public init(date: String, value: Double) { self.date = date; self.value = value }
}

public struct ChainHealth: Equatable, Identifiable {
    public var chainId: Int
    public var name: String
    public var hf: Double?          // nil: no debt
    public var debtUsd: Double
    public var equityUsd: Double
    public var liqHf: Double
    public var id: Int { chainId }
}

public struct ChainEarned: Equatable {
    public var chainId: Int
    public var name: String
    public var sft: Double
    public var lend: Double
}

public struct RewardsData: Equatable {
    public var totalFt: Double = .nan
    public var claimableFt: Double = 0
    public var sftClaimed: Double = 0
    public var sftPending: Double = 0
    public var lendReceived: Double = 0
    public var lendPending: Double = 0
    public var sftFt: Double = 0
    public var lendFt: Double = 0
    public var chains: [ChainEarned] = []
}

public struct PutRow: Equatable {
    public var nft: String
    public var symbol: String
    public var costUsd: Double
    public var strike: Double
    public var ft: Double
    public var since: String
}

public struct PutsData: Equatable {
    public var count: Int
    public var costUsd: Double
    public var ftHeld: Double
    public var rows: [PutRow]
}

public struct PutGain: Equatable {
    public var valueUsd: Double
    public var gainUsd: Double
    public var gainPct: Double
}

public struct ChainPoints: Equatable {
    public var chainId: Int
    public var name: String
    public var points: Double
}

public struct PointsData: Equatable {
    public var total: Double
    public var chains: [ChainPoints]
}

public struct PointsRow: Equatable {
    public var label: String
    public var positionUsd: Double
    public var multiplier: Double
}

public struct RankData: Equatable {
    public var rank: Int
    public var total: Int
}

public struct RankPage: Equatable {
    public var found: Bool
    public var rank: Int
    public var dir: Int
    public var total: Int
    public var empty: Bool = false
}

public struct PositionRow: Equatable, Identifiable {
    public var chainId: Int
    public var network: String
    public var symbol: String
    public var market: String
    public var side: String
    public var size: Double
    public var entry: Double
    public var mark: Double
    public var pnlUsd: Double
    public var pnlPct: Double
    public var leverage: Double
    public var valueUsd: Double
    public var id: String { "\(chainId):\(market):\(side)" }
}

public struct HistoryPoint: Equatable {
    public var ts: Int
    public var date: String
    public var earned: Double
    public var claimed: Double
}
