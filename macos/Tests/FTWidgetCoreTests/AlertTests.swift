import XCTest
@testable import FTWidgetCore

final class AlertTests: XCTestCase {
    let cfg = AlertConfig(warn: 1.40, critical: 1.30, cooldownMs: 30 * 60_000)
    func entry(_ hf: Double) -> ChainHealth { ChainHealth(chainId: 146, name: "Sonic", hf: hf, debtUsd: 100, equityUsd: 50, liqHf: 1.25) }

    func testLevelsAndHysteresis() {
        XCTAssertEqual(Alerts.level(hf: 2.0, cfg: cfg, prev: 0), 0)
        XCTAssertEqual(Alerts.level(hf: 1.40, cfg: cfg, prev: 0), 1, "at the warning line counts")
        XCTAssertEqual(Alerts.level(hf: 1.39, cfg: cfg, prev: 0), 1)
        XCTAssertEqual(Alerts.level(hf: 1.30, cfg: cfg, prev: 0), 2, "at the critical line counts")
        XCTAssertEqual(Alerts.level(hf: 1.33, cfg: cfg, prev: 2), 2, "stays critical inside the hysteresis band")
        XCTAssertEqual(Alerts.level(hf: 1.36, cfg: cfg, prev: 2), 1)
        XCTAssertEqual(Alerts.level(hf: 1.43, cfg: cfg, prev: 1), 1)
        XCTAssertEqual(Alerts.level(hf: 1.46, cfg: cfg, prev: 1), 0)
    }

    func testOncePerCrossingWithCooldown() {
        var st = AlertState()
        var r = Alerts.decide(state: st, entry: entry(2), cfg: cfg, nowMs: 0); XCTAssertNil(r.notice); st = r.state
        r = Alerts.decide(state: st, entry: entry(1.39), cfg: cfg, nowMs: 1e3); XCTAssertEqual(r.notice?.level, 1); st = r.state
        r = Alerts.decide(state: st, entry: entry(1.38), cfg: cfg, nowMs: 2e3); XCTAssertNil(r.notice, "no repeat while it stays low"); st = r.state
        r = Alerts.decide(state: st, entry: entry(1.29), cfg: cfg, nowMs: 3e3); XCTAssertEqual(r.notice?.level, 2); st = r.state
        r = Alerts.decide(state: st, entry: entry(1.33), cfg: cfg, nowMs: 4e3); XCTAssertNil(r.notice); XCTAssertEqual(r.state.level, 2); st = r.state
        r = Alerts.decide(state: st, entry: entry(1.6), cfg: cfg, nowMs: 5e3); XCTAssertNil(r.notice); XCTAssertEqual(r.state.level, 0); st = r.state
        // crossing again inside the cooldown stays quiet, after it fires again
        r = Alerts.decide(state: st, entry: entry(1.2), cfg: cfg, nowMs: 6e3); XCTAssertNil(r.notice); st = r.state
        r = Alerts.decide(state: AlertState(level: 0, last1: st.last1, last2: st.last2), entry: entry(1.2), cfg: cfg, nowMs: 31 * 60_000 + 7e3)
        XCTAssertEqual(r.notice?.level, 2)
        // survives a JSON round trip
        let data = try! JSONEncoder().encode(r.state)
        XCTAssertEqual(try! JSONDecoder().decode(AlertState.self, from: data), r.state)
        // no debt resets
        XCTAssertEqual(Alerts.decide(state: r.state, entry: nil, cfg: cfg, nowMs: 1).state.level, 0)
    }

    func testNotificationNamesTheWallet() {
        var n = AlertNotice(level: 1, hf: 1.386, chain: "Sonic", liqHf: 1.25, wallet: nil)
        XCTAssertEqual(Alerts.text(n).body, "Sonic HF 1.39 (liquidation below 1.25).")
        n.wallet = "0x38A5…2D62"
        XCTAssertEqual(Alerts.text(n).body, "0x38A5…2D62: Sonic HF 1.39 (liquidation below 1.25).")
        n.level = 2
        XCTAssertTrue(Alerts.text(n).critical)
        XCTAssertEqual(Alerts.text(n).title, "FT account near liquidation")
    }

    func testLowWalletJumpsToFront() {
        let ws = ["a", "b", "c"]
        XCTAssertNil(Alerts.pinnedWallet(levels: [:], lowestHf: [:], wallets: ws))
        XCTAssertEqual(Alerts.pinnedWallet(levels: ["b": 1, "c": 2], lowestHf: ["b": 1.38, "c": 1.28], wallets: ws), "c")
        XCTAssertEqual(Alerts.pinnedWallet(levels: ["a": 0, "b": 1], lowestHf: ["a": 1.1, "b": 1.38], wallets: ws), "b")
    }

    func testTitle() {
        let price = PriceData(price: 0.1502, changePct24h: 1, sampledAt: "")
        let fees = FeesData(period24h: 954, lifetime: 0, products: [])
        let lend = [entry(1.92)]
        var t = Title.build(price: price, fees: fees, lend: lend, wallet: "0xabc", walletCount: 1, alert: cfg, stale: false)
        XCTAssertEqual(t.plain, "$0.1502  fees $954  HF 1.92")
        XCTAssertEqual(t.hfLevel, 0)
        t = Title.build(price: price, fees: fees, lend: [entry(1.35)], wallet: testWallet, walletCount: 2, alert: cfg, stale: true)
        XCTAssertEqual(t.hfLevel, 1)
        XCTAssertEqual(t.plain, "$0.1502  fees $954  HF 1.35  0x38A5…2D62 ⇄ ⚠")
        t = Title.build(price: nil, fees: nil, lend: nil, wallet: "", walletCount: 0, alert: cfg, stale: false)
        XCTAssertEqual(t.plain, "FT —")
        t = Title.build(price: price, fees: fees, lend: [ChainHealth(chainId: 1, name: "Ethereum", hf: nil, debtUsd: 0, equityUsd: 1, liqHf: 1.25)], wallet: "0xabc", walletCount: 1, alert: cfg, stale: false)
        XCTAssertEqual(t.plain, "$0.1502  fees $954  HF ∞")
    }
}
