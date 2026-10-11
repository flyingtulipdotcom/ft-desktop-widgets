import AppKit
import FTWidgetCore
import SwiftUI

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @State var contentH: CGFloat = 400

    var body: some View {
        VStack(spacing: 10) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 6) {
                Pill(text: "Market", selected: model.tab == "market") { model.setTab("market") }
                Pill(text: "Account", selected: model.tab == "account") { model.setTab("account") }
                Pill(text: "Positions", selected: model.tab == "positions") { model.setTab("positions") }
                Spacer()
            }
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch model.tab {
                    case "account": AccountTab()
                    case "positions": PositionsTab()
                    default: MarketTab()
                    }
                }
                .padding(.vertical, 1)
                .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
            }
            .onPreferenceChange(ContentHeightKey.self) { contentH = $0 }
            .frame(height: min(max(contentH, 120), 680))
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: 400)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    var header: some View {
        HStack(spacing: 9) {
            Button { model.openLink(Pages.home, "header-logo") } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x0c091a))
                        RoundedRectangle(cornerRadius: 9).stroke(Theme.tulip.opacity(0.4), lineWidth: 1)
                        if let l = Logo.image { Image(nsImage: l).resizable().interpolation(.high).frame(width: 20, height: 20) }
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Flying Tulip").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        Text(model.current.isEmpty ? "Market, fees and your account"
                             : Fmt.shortAddr(model.current) + (model.wallets.count > 1 ? "  \(model.walletIndex + 1)/\(model.wallets.count)" : ""))
                            .font(.system(size: 10)).foregroundColor(model.current.isEmpty ? Theme.faint : Theme.sub)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 8) {
                if model.wallets.count > 1 { IconButton(symbol: "arrow.left.arrow.right") { model.nextWallet() } }
                IconButton(symbol: "gearshape.fill") { model.openSettings() }
                IconButton(symbol: "arrow.clockwise") { model.manualRefresh() }
            }
        }
        .frame(height: 34)
    }

    var footer: some View {
        HStack {
            Button { model.openLink(Pages.home, "footer-updated") } label: {
                Text("updated " + (model.lastUpdate.map { Self.clock.string(from: $0) } ?? "—") + (model.lastRefreshFailed ? "  · retrying" : ""))
                    .font(.system(size: 10)).foregroundColor(model.lastRefreshFailed ? Theme.amber : Theme.faint)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { model.openLink(Pages.home, "footer-open-site") } label: {
                Text("Open flyingtulip.com →").font(.system(size: 11)).foregroundColor(Theme.tulip400)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 20)
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// ---- Market ---------------------------------------------------------------------------------

struct MarketTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let mkt = Pages.market("FT-ftUSD", chainId: model.priceChain)
        let fees = model.fees?.value, price = model.price?.value
        let dod = Parse.feesDayOverDay(model.feesSeries?.value, now: Date())
        VStack(spacing: 10) {
            // hero stats
            Card(url: nil, alignTop: false) {
                HStack(alignment: .top, spacing: 8) {
                    LinkBox(url: Pages.fees, element: "market-fees") {
                        Stat(label: "Fees last 24h", value: fees.map { Fmt.usd($0.period24h) } ?? "—")
                    }
                    LinkBox(url: mkt, element: "market-ft-price") {
                        Stat(label: "FT price", value: price.map { Fmt.price($0.price) } ?? "—",
                             sub: price.map { $0.changePct24h.isFinite ? Fmt.pct($0.changePct24h) + " 24h" : "" } ?? "",
                             subColor: price.map { Theme.delta($0.changePct24h) } ?? Theme.sub)
                    }
                    LinkBox(url: Pages.fees, element: "market-day-over-day") {
                        Stat(label: "Day / day", value: dod.isFinite ? Fmt.pct(dod) : "—", valueColor: dod.isFinite ? Theme.delta(dod) : Theme.sub)
                    }
                }
            }
            // daily fees
            Card(url: Pages.fees, element: "market-fees-chart", alignTop: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Cap(text: "Daily fees · last \(model.feesSeries?.value.count ?? 31) days")
                    if let s = model.feesSeries?.value {
                        BarChart(values: s, maxLabel: "max " + Fmt.usd(s.map { $0.value }.max() ?? 0))
                    } else { SubText(text: "loading…") }
                    if let f = fees, f.period24h > 0 {
                        let prods = f.products.filter { $0.usd > 0 }
                        FeesStack(products: prods, total: f.period24h)
                        FlowLayout(spacing: 12, lineSpacing: 6) {
                            ForEach(Array(prods.enumerated()), id: \.offset) { i, p in
                                HStack(spacing: 5) {
                                    Circle().fill(Theme.productColors[i % Theme.productColors.count]).frame(width: 7, height: 7)
                                    SubText(text: p.name.replacingOccurrences(of: "_", with: " ") + " " + Fmt.usd(p.usd))
                                }
                            }
                        }
                    }
                }
            }
            // FT market price
            Card(url: mkt, element: "market-price-chart", alignTop: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Cap(text: "FT market price · 30 days")
                    if let k = model.klines?.value { LineArea(values: k, format: Fmt.price) } else { SubText(text: "loading…") }
                }
            }
        }
    }
}

/// A tap target inside a card that opens its own page (the card's own link is replaced for that area).
struct LinkBox<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let url: String
    let element: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { model.openLink(url, element) }
    }
}

struct FeesStack: View {
    let products: [(name: String, usd: Double)]
    let total: Double
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(products.enumerated()), id: \.offset) { i, p in
                    Capsule().fill(Theme.productColors[i % Theme.productColors.count])
                        .frame(width: max(2, (g.size.width - 2 * CGFloat(max(0, products.count - 1))) * CGFloat(p.usd / total)), height: 6)
                }
            }
        }
        .frame(height: 6)
    }
}

/// Wraps its children onto lines (macOS 13 Layout).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += sz.width + spacing; lineH = max(lineH, sz.height); w = max(w, x - spacing)
        }
        return CGSize(width: w, height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; lineH = max(lineH, sz.height)
        }
    }
}

// ---- Account --------------------------------------------------------------------------------

struct AddWalletCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Card(url: siteBase, element: "account-hint", alignTop: false) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add your wallet").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Text("See health factor, PnL, FT earned, points and ftPUT gains here.")
                        .font(.system(size: 11)).foregroundColor(Theme.sub).fixedSize(horizontal: false, vertical: true)
                }
                Button { model.openSettings() } label: {
                    Text("Set wallet").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.tulip))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AccountTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.current.isEmpty {
            AddWalletCard()
        } else {
            let d = model.shown
            let price = model.price?.value.price ?? .nan
            VStack(spacing: 10) {
                // health factor
                Card(url: Pages.health, element: "account-hf", alignTop: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Cap(text: "Health factor")
                            Spacer()
                            SubText(text: "red line = liquidation < 1.25", color: Theme.faint, size: 9)
                        }
                        if d.lend == nil { SubText(text: "loading…") }
                        ForEach(d.lend?.value ?? []) { c in
                            HfGauge(chain: c, warn: model.alertConfig.warn, crit: model.alertConfig.critical)
                        }
                    }
                }
                // PnL + FT earned
                let pnl = d.pnl?.value ?? .nan
                let rw = d.rewards?.value
                HStack(alignment: .top, spacing: 10) {
                    Card(url: Pages.portfolio, element: "account-pnl") {
                        Stat(label: "PnL (unrealized)", value: Fmt.signedUsd(pnl), valueColor: Theme.delta(pnl), valueSize: 18)
                    }
                    Card(url: Pages.rewards, element: "account-ft-earned") {
                        Stat(label: "FT earned · all time", value: Fmt.ft(rw?.totalFt ?? .nan) + " FT", sub: earnedSub(rw, price),
                             valueColor: Theme.tulip300, valueSize: 18)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // points + ftPUT
                let pg = Parse.putGain(d.puts?.value ?? nil, ftPrice: price)
                HStack(alignment: .top, spacing: 10) {
                    Card(url: Pages.points, element: "account-points") {
                        Stat(label: "Points · all chains", value: Fmt.points(d.points?.value.total ?? .nan), sub: pointsSub(d, pair: pg != nil), valueSize: 18)
                    }
                    if let pg = pg {
                        Card(url: Pages.put, element: "account-ftput") {
                            Stat(label: "ftPUT gain", value: Fmt.signedUsd(pg.gainUsd),
                                 sub: Fmt.pct(pg.gainPct) + "  ·  value " + Fmt.usd(pg.valueUsd),
                                 valueColor: Theme.delta(pg.gainUsd), subColor: Theme.delta(pg.gainUsd), valueSize: 18)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                EarnedChartCard()
                DailyEarnedCard()
            }
        }
    }

    func earnedSub(_ rw: RewardsData?, _ price: Double) -> String {
        guard let rw = rw, rw.totalFt.isFinite else { return "" }
        var lines = ["sftUSD yield " + Fmt.ft(rw.sftFt) + "  ·  Lend " + Fmt.ft(rw.lendFt), Parse.earnedByChain(rw)]
        var l3 = price.isFinite ? "≈ " + Fmt.usd(rw.totalFt * price) + " at market" : ""
        if rw.claimableFt > 0 { l3 += "  ·  claim " + Fmt.ft(rw.claimableFt) }
        lines.append(l3)
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func pointsSub(_ d: WalletData, pair: Bool) -> String {
        var parts: [String] = []
        if let p = d.points?.value, !p.chains.isEmpty { parts.append(p.chains.map { $0.name + " " + Fmt.points($0.points) }.joined(separator: "  ·  ")) }
        if let r = d.rank?.value ?? nil { parts.append("rank #\(r.rank) of \(r.total)") }
        return parts.joined(separator: pair ? "\n" : "  ·  ")
    }
}

struct EarnedChartCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let hist = model.shown.history[model.histRange]?.value
        let claimed = model.histSeries == "claimed"
        let series = hist?.map { DayValue(date: $0.date, value: claimed ? $0.claimed : $0.earned) }
        Card(url: Pages.rewards, element: "account-ft-earned-chart", alignTop: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Cap(text: "FT earned over time")
                    Spacer()
                    SubText(text: "all chains", color: Theme.faint, size: 9)
                }
                HStack(spacing: 6) {
                    Pill(text: "Total earned", selected: !claimed) { model.histSeries = "earned" }
                    Pill(text: "Claimed", selected: claimed) { model.histSeries = "claimed" }
                }
                if let s = series, s.count > 1 {
                    LineArea(values: s, lineColor: Theme.tulip400, format: Fmt.ft)
                } else if series == nil {
                    SubText(text: "loading…", color: Theme.faint).frame(height: 96, alignment: .center)
                } else {
                    SubText(text: "Not enough history yet.", color: Theme.faint).frame(height: 96, alignment: .center)
                }
                HStack(spacing: 6) {
                    ForEach(["7d", "30d", "90d", "all"], id: \.self) { r in
                        Pill(text: r == "all" ? "All" : r, selected: model.histRange == r) { model.setHistRange(r) }
                    }
                }
            }
        }
    }
}

struct DailyEarnedCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let gains = Parse.dailyGains(model.shown.history["30d"]?.value)
        Card(url: Pages.rewards, element: "account-ft-earned-daily", alignTop: false) {
            VStack(alignment: .leading, spacing: 8) {
                Cap(text: "Daily FT earned · last \(gains.isEmpty ? 30 : gains.count) days")
                if gains.isEmpty { SubText(text: model.shown.history["30d"] == nil ? "loading…" : "Not enough history yet.", color: Theme.faint) }
                else { BarChart(values: gains, barColor: Theme.tulip400, lastColor: Theme.tulip300, maxLabel: "max " + Fmt.ft(gains.map { $0.value }.max() ?? 0) + " FT") }
            }
        }
    }
}

// ---- Positions ------------------------------------------------------------------------------

struct PositionsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.current.isEmpty {
            AddWalletCard()
        } else {
            let d = model.shown
            let pos = d.positions?.value ?? []
            VStack(spacing: 10) {
                Card(url: Pages.portfolio, element: "positions-card", alignTop: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Cap(text: "Positions")
                            Spacer()
                            SubText(text: pos.isEmpty ? "" : "\(pos.count) open", color: Theme.faint, size: 9)
                        }
                        if d.positions != nil && pos.isEmpty { SubText(text: "No open positions.", color: Theme.faint) }
                        if d.positions == nil { SubText(text: "loading…", color: Theme.faint) }
                        ForEach(Array(pos.prefix(8))) { p in PositionRowView(p: p) }
                        if pos.count > 8 { SubText(text: "+\(pos.count - 8) more", color: Theme.faint) }
                    }
                }
                let bd = d.breakdown?.value ?? []
                if !bd.isEmpty {
                    Card(url: Pages.pointsActivity, element: "account-points-positions", alignTop: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Cap(text: "Points positions")
                            ForEach(Array(bd.prefix(6).enumerated()), id: \.offset) { _, r in
                                HStack {
                                    SubText(text: r.label, color: Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                                    SubText(text: Fmt.usd(r.positionUsd))
                                    SubText(text: "x" + (r.multiplier.isFinite ? String(format: "%.2f", r.multiplier) : "?"), color: Theme.tulip300)
                                        .frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                if let puts = d.puts?.value ?? nil {
                    Card(url: Pages.put, element: "account-ftput-positions", alignTop: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Cap(text: "ftPUT positions · cost = capital x price at investment")
                            ForEach(Array(puts.rows.prefix(5).enumerated()), id: \.offset) { _, r in
                                HStack {
                                    SubText(text: "#" + r.nft + " " + r.symbol, color: Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                                    SubText(text: Fmt.usd(r.costUsd) + " @ " + Fmt.price(r.strike))
                                    SubText(text: String(r.since.dropFirst(2))).frame(width: 60, alignment: .trailing)
                                }
                            }
                            if puts.rows.count > 5 { SubText(text: "+\(puts.rows.count - 5) more", color: Theme.faint) }
                        }
                    }
                }
            }
        }
    }
}

struct PositionRowView: View {
    @EnvironmentObject var model: AppModel
    let p: PositionRow
    var body: some View {
        let lev = p.leverage.isFinite && p.leverage > 0 ? " " + String(format: p.leverage >= 10 ? "%.0fx" : "%.1fx", p.leverage) : ""
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.tulip.opacity(0.18))
                Text(String(p.symbol.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.tulip300)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(p.symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                    Text(p.side + lev).font(.system(size: 9, weight: .semibold))
                        .foregroundColor(p.side == "short" ? Theme.red : Theme.green)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill((p.side == "short" ? Theme.red : Theme.green).opacity(0.16)))
                }
                SubText(text: p.network + "  " + Fmt.size(p.size), color: Theme.faint, size: 10)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 1) {
                SubText(text: "mark " + Fmt.price(p.mark), size: 10)
                SubText(text: "entry " + Fmt.price(p.entry), color: Theme.faint, size: 10)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.signedUsd(p.pnlUsd)).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.delta(p.pnlUsd))
                Text(Fmt.pct(p.pnlPct)).font(.system(size: 10)).foregroundColor(Theme.delta(p.pnlUsd))
            }
            .frame(width: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openLink(Pages.market(p.market.isEmpty ? p.symbol + "-ftUSD" : p.market, chainId: p.chainId), "positions-row") }
    }
}
