import AppKit
import Combine
import FTWidgetCore
import SwiftUI
import UserNotifications

struct Cached<T> {
    var value: T
    var at: Date
}

/// Everything fetched for one wallet.
struct WalletData {
    var lend: Cached<[ChainHealth]>?
    var pnl: Cached<Double>?
    var rewards: Cached<RewardsData>?
    var points: Cached<PointsData>?
    var positions: Cached<[PositionRow]>?
    var puts: Cached<PutsData?>?
    var rank: Cached<RankData?>?
    var breakdown: Cached<[PointsRow]>?
    var history: [String: Cached<[HistoryPoint]>] = [:]
}

func maybe<T>(_ cond: Bool, _ f: @escaping () async -> T) async -> T? {
    cond ? await f() : nil
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let slowTTL: TimeInterval = 600
    static let rotateEvery: TimeInterval = 58
    static let staleAfter: TimeInterval = 180

    let settings = SettingsStore(defaults: .standard)
    let client = Client()
    let stats: UsageStats

    @Published var wallets: [String] = []
    @Published var current = ""
    @Published var price: Cached<PriceData>?
    @Published var fees: Cached<FeesData>?
    @Published var feesSeries: Cached<[DayValue]>?
    @Published var klines: Cached<[DayValue]>?
    @Published var data: [String: WalletData] = [:]
    @Published var tab = "market"
    @Published var histRange = "30d"
    @Published var histSeries = "earned"
    @Published var lastUpdate: Date?
    @Published var lastRefreshFailed = false
    @Published var titleImage = NSImage(size: NSSize(width: 60, height: 18))
    @Published var loadedOnce = false

    private var shownAt = Date.distantPast
    private var alertStates: [String: AlertState]
    private var timer: Timer?
    private var refreshing = false
    private var observers: [NSObjectProtocol] = []
    private let notifier = Notifier()

    init() {
        let s = SettingsStore(defaults: .standard)
        stats = UsageStats(settings: s, transport: PlausibleTransport())
        alertStates = s.alertStates
        wallets = s.wallets
        current = wallets.first ?? ""
        tab = s.tab
        redrawTitle()
    }

    var walletIndex: Int { wallets.firstIndex(of: current) ?? 0 }
    var shown: WalletData { data[current] ?? WalletData() }
    var priceChain: Int { settings.priceChain }
    var alertConfig: AlertConfig { settings.alertConfig }
    var lowest: ChainHealth? { shown.lend.flatMap { Parse.lowestHf($0.value) } }
    var hfLevel: Int { lowest?.hf.map { Alerts.level(hf: $0, cfg: alertConfig, prev: 0) } ?? 0 }

    func start() {
        stats.pageviewIfDue(walletCount: wallets.count, force: true)
        if settings.notifications && !wallets.isEmpty { notifier.requestAuthorization() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(rotate: true) }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let w = note.object as? NSWindow else { return }
            if String(describing: type(of: w)).contains("MenuBarExtra") {
                Task { @MainActor in self?.panelOpened() }
            }
        })
        Task { await refresh(rotate: false) }
    }

    func panelOpened() {
        stats.send("Panel open")
        let stale = lastUpdate.map { Date().timeIntervalSince($0) > 20 } ?? true
        if stale { Task { await refresh(rotate: false) } }
    }

    // ---- actions -------------------------------------------------------------------

    func setTab(_ t: String) {
        guard t != tab else { return }
        tab = t
        settings.tab = t
        stats.send("Tab view", ["tab": t])
    }

    func manualRefresh() {
        stats.send("Refresh")
        Task { await refresh(rotate: false) }
    }

    func nextWallet() {
        guard wallets.count > 1 else { return }
        stats.send("Wallet switch")
        show(wallets[(walletIndex + 1) % wallets.count])
    }

    func show(_ w: String) {
        current = w
        shownAt = Date()
        redrawTitle()
        Task { await refresh(rotate: false) }
    }

    func setHistRange(_ r: String) {
        histRange = r
        Task { await loadHistory(current) }
    }

    func openLink(_ url: String, _ element: String) {
        guard let target = stats.linkTarget(url: url, element: element), let u = URL(string: target) else { return }
        NSWorkspace.shared.open(u)
    }

    func openSettings() {
        stats.send("Settings open")
        SettingsWindow.shared.show(model: self)
    }

    func addWallet(_ text: String) -> String? {
        let p = Wallets.parse(text)
        if let b = p.bad.first { return "Not a valid address: " + String(b.prefix(24)) + ". Use 0x followed by 40 hex characters." }
        var list = wallets
        var added = false
        for w in p.list where !list.contains(w) { list.append(w); added = true }
        if added { stats.send("Wallet added") }
        walletsChanged(list)
        return nil
    }

    func removeWallet(_ w: String) {
        let list = wallets.filter { $0 != w }
        if list.count < wallets.count { stats.send("Wallet removed") }
        walletsChanged(list)
    }

    private func walletsChanged(_ list: [String]) {
        wallets = list
        settings.wallets = list
        for k in data.keys where !list.contains(k) { data[k] = nil }
        for k in alertStates.keys where !list.contains(k) { alertStates[k] = nil }
        settings.alertStates = alertStates
        if !list.contains(current) { current = list.first ?? ""; shownAt = Date() }
        if settings.notifications && !list.isEmpty { notifier.requestAuthorization() }
        redrawTitle()
        Task { await refresh(rotate: false) }
    }

    /// Settings were changed: redraw with the new thresholds / chain and refetch what depends on them.
    func settingsChanged() {
        objectWillChange.send()
        redrawTitle()
        Task { await refresh(rotate: false) }
    }

    // ---- refresh -------------------------------------------------------------------

    private func age(_ d: Date?) -> TimeInterval { d.map { Date().timeIntervalSince($0) } ?? .infinity }

    func refresh(rotate: Bool) async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
        let now = Date()
        wallets = settings.wallets

        // which wallet to show: every minute the next one, except while one is low (it stays)
        if !wallets.contains(current) { current = wallets.first ?? ""; shownAt = now }
        if rotate, wallets.count > 1, now.timeIntervalSince(shownAt) >= Self.rotateEvery {
            var levels: [String: Int] = [:], lows: [String: Double] = [:]
            for w in wallets {
                levels[w] = alertStates[w]?.level ?? 0
                if let l = data[w]?.lend, let hf = Parse.lowestHf(l.value)?.hf { lows[w] = hf }
            }
            let next = wallets[(walletIndex + 1) % wallets.count]
            current = Alerts.pinnedWallet(levels: levels, lowestHf: lows, wallets: wallets) ?? next
            shownAt = now
        } else if shownAt == .distantPast { shownAt = now }
        stats.pageviewIfDue(walletCount: wallets.count)

        let cur = current
        let chain = settings.priceChain
        var failedSources: [String] = []
        var anyOk = false
        var freshLend: [String: [ChainHealth]] = [:]

        // market
        async let pr = client.price(chain: chain)
        async let fe = client.fees()
        let needSlow = age(feesSeries?.at) > Self.slowTTL || age(klines?.at) > Self.slowTTL
        async let fs = maybe(needSlow) { await self.client.feesSeries() }
        async let kl = maybe(needSlow) { await self.client.klines(chain: chain) }
        let (prR, feR, fsR, klR) = await (pr, fe, fs, kl)
        switch prR { case .ok(let v): price = Cached(value: v, at: now); anyOk = true; case .failed: failedSources.append("price") }
        switch feR { case .ok(let v): fees = Cached(value: v, at: now); anyOk = true; case .failed: failedSources.append("fees") }
        if let fsR = fsR { switch fsR { case .ok(let v): feesSeries = Cached(value: v, at: now); case .failed: failedSources.append("feesSeries") } }
        if let klR = klR { switch klR { case .ok(let v): klines = Cached(value: v, at: now); case .failed: failedSources.append("klines") } }
        if price == nil && chain != 146, case .ok(let v) = await client.price(chain: 146) { price = Cached(value: v, at: now) }

        // the shown wallet in full, and /mm/lend of the hidden wallets when due
        if !cur.isEmpty {
            let r = await loadWallet(cur, now: now)
            failedSources += r.failed
            if let l = r.lend { freshLend[cur] = l }
            if r.anyOk { anyOk = true }
        }
        for w in wallets where w != cur {
            let hasDebt = (data[w]?.lend?.value ?? []).contains { $0.debtUsd > 0.01 }
            if !hasDebt && age(data[w]?.lend?.at) < Self.slowTTL { continue }
            switch await client.lend(wallet: w) {
            case .ok(let l): data[w, default: WalletData()].lend = Cached(value: l, at: now); freshLend[w] = l
            case .failed: failedSources.append("lend@" + w)
            }
        }

        // alerts: the shown wallet and every hidden wallet read this run; one that just turned low is shown at once
        var jump: String?
        for w in wallets {
            guard let l = freshLend[w] else { continue }
            let up = alert(w, lend: l, now: now)
            if w != current && up && jump == nil { jump = w }
        }
        if let j = jump {
            current = j; shownAt = now
            let r = await loadWallet(j, now: now)
            failedSources += r.failed
        }
        settings.alertStates = alertStates
        for f in failedSources { stats.fetchError(source: f) }
        lastRefreshFailed = !anyOk
        lastUpdate = Date()
        loadedOnce = true
        redrawTitle()
    }

    private struct WalletLoad { var failed: [String] = []; var lend: [ChainHealth]?; var anyOk = false }

    private func loadWallet(_ w: String, now: Date) async -> WalletLoad {
        var out = WalletLoad()
        async let ld = client.lend(wallet: w)
        async let pn = client.pnl(wallet: w)
        async let rw = client.rewards(wallet: w)
        async let pt = client.points(wallet: w)
        async let po = client.positions(wallet: w)
        async let pu = client.puts(wallet: w)
        let (ldR, pnR, rwR, ptR, poR, puR) = await (ld, pn, rw, pt, po, pu)
        var d = data[w] ?? WalletData()
        switch ldR { case .ok(let v): d.lend = Cached(value: v, at: now); out.lend = v; out.anyOk = true; case .failed: out.failed.append("lend") }
        switch pnR { case .ok(let v): d.pnl = Cached(value: v, at: now); out.anyOk = true; case .failed: out.failed.append("pnl") }
        switch rwR { case .ok(let v): d.rewards = Cached(value: v, at: now); out.anyOk = true; case .failed: out.failed.append("rewards") }
        switch ptR { case .ok(let v): d.points = Cached(value: v, at: now); out.anyOk = true; case .failed: out.failed.append("points") }
        switch poR { case .ok(let v): d.positions = Cached(value: v, at: now); out.anyOk = true; case .failed: out.failed.append("positions") }
        switch puR { case .ok(let v): d.puts = Cached(value: v, at: now); out.anyOk = true; case .failed: out.failed.append("puts") }
        data[w] = d
        // slow ones: rank, points breakdown, rewards history
        if let p = d.points?.value, age(d.rank?.at) > Self.slowTTL {
            switch await client.rank(wallet: w, myPoints: p.total) {
            case .ok(let v): data[w, default: WalletData()].rank = Cached(value: v, at: now)
            case .failed: out.failed.append("rank")
            }
        }
        if age(data[w]?.breakdown?.at) > Self.slowTTL {
            switch await client.breakdown(wallet: w) {
            case .ok(let v): data[w, default: WalletData()].breakdown = Cached(value: v, at: now)
            case .failed: out.failed.append("breakdown")
            }
        }
        await loadHistory(w, failed: &out.failed)
        return out
    }

    func loadHistory(_ w: String) async {
        var f: [String] = []
        await loadHistory(w, failed: &f)
        for x in f { stats.fetchError(source: x) }
    }

    private func loadHistory(_ w: String, failed: inout [String]) async {
        guard !w.isEmpty else { return }
        for range in Set(["30d", histRange]) {
            if age(data[w]?.history[range]?.at) <= Self.slowTTL { continue }
            switch await client.rewardsHistory(wallet: w, range: range) {
            case .ok(let v): data[w, default: WalletData()].history[range] = Cached(value: v, at: Date())
            case .failed: failed.append("history")
            }
        }
    }

    /// Returns true when the wallet's level went up.
    private func alert(_ w: String, lend: [ChainHealth], now: Date) -> Bool {
        let prevState = alertStates[w] ?? AlertState()
        let dn = Alerts.decide(state: prevState, entry: Parse.lowestHf(lend), cfg: alertConfig, nowMs: now.timeIntervalSince1970 * 1000)
        alertStates[w] = dn.state
        if var n = dn.notice {
            if wallets.count > 1 { n.wallet = Fmt.shortAddr(w) }
            if settings.notifications { notifier.show(Alerts.text(n)) }
            stats.send("HF alert shown", ["level": n.level == 2 ? "danger" : "warning"])
        }
        return dn.state.level > prevState.level
    }

    // ---- title ---------------------------------------------------------------------

    var titleParts: TitleParts {
        let stale = age(price?.at) > Self.staleAfter || age(fees?.at) > Self.staleAfter ||
            (!current.isEmpty && shown.lend != nil && age(shown.lend?.at) > Self.staleAfter)
        return Title.build(price: price?.value, fees: fees?.value, lend: shown.lend?.value, wallet: current,
                           walletCount: wallets.count, alert: alertConfig, stale: stale && loadedOnce)
    }

    func redrawTitle() {
        titleImage = TitleImage.render(titleParts, offline: price == nil && fees == nil && loadedOnce)
    }
}
