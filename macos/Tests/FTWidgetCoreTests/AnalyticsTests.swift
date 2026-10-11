import XCTest
@testable import FTWidgetCore

final class AnalyticsTests: XCTestCase {
    func make(now: @escaping () -> Date = Date.init) -> (UsageStats, CaptureTransport, SettingsStore) {
        let s = freshSettings(), t = CaptureTransport()
        return (UsageStats(settings: s, transport: t, now: now), t, s)
    }

    func testOriginMarkersMatchThePlugin() {
        let u = Stats.originUrl("https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=1&marketType=spot", element: "market-ft-price", os: "macOS 15")
        XCTAssertEqual(u, "https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=1&marketType=spot&utm_source=ft-widget&utm_medium=macos&utm_content=market-ft-price#ftw=macos.macos-15.2-0-0.market-ft-price")
        XCTAssertEqual(Stats.originUrl("https://flyingtulip.com/", element: "header-logo", os: "macOS 14"),
                       "https://flyingtulip.com/?utm_source=ft-widget&utm_medium=macos&utm_content=header-logo#ftw=macos.macos-14.2-0-0.header-logo")
        // an existing anchor is kept and no marker hash is added
        XCTAssertEqual(Stats.originUrl("https://flyingtulip.com/a/#x", element: "e", os: "macOS 15"),
                       "https://flyingtulip.com/a/?utm_source=ft-widget&utm_medium=macos&utm_content=e#x")
        // the element id is sanitised
        XCTAssertTrue(Stats.originUrl("https://flyingtulip.com/", element: "Bad Id!?", os: "macOS 15").hasSuffix(".badid"))
    }

    func testLinksAreCountedAndMarkedOnlyWhileStatsAreOn() {
        let (st, t, s) = make()
        let target = st.linkTarget(url: Pages.fees, element: "market-fees")
        XCTAssertEqual(target, Stats.originUrl(Pages.fees, element: "market-fees", os: Stats.osLabel()))
        XCTAssertEqual(t.names, ["Link click"])
        let props = t.events[0]["props"] as? [String: String]
        XCTAssertEqual(props?["element"], "market-fees")
        XCTAssertEqual(props?["url"], Pages.fees)
        s.analytics = false
        XCTAssertEqual(st.linkTarget(url: Pages.fees, element: "market-fees"), Pages.fees, "off: the plain URL, no marker")
        XCTAssertEqual(t.names.count, 1)
        XCTAssertNil(st.linkTarget(url: "https://evil.example/", element: "x"), "only flyingtulip.com opens")
    }

    func testPayloadShape() throws {
        let ev = try XCTUnwrap(try JSONSerialization.jsonObject(with: Stats.body("Tab view", ["tab": "account"])) as? [String: Any])
        XCTAssertEqual(ev["name"] as? String, "Tab view")
        XCTAssertEqual(ev["domain"] as? String, "widget")
        XCTAssertEqual(ev["url"] as? String, "app://widget/macos")
        let p = try XCTUnwrap(ev["props"] as? [String: String])
        XCTAssertEqual(p["platform"], "macos")
        XCTAssertEqual(p["native"], "true")
        XCTAssertEqual(p["version"], Stats.version)
        XCTAssertEqual(p["tab"], "account")
        XCTAssertEqual(Stats.userAgent, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) FlyingTulipWidget/\(Stats.version)")
    }

    func testNoWalletDataIsEverSent() {
        let (st, t, s) = make()
        s.wallets = [testWallet.lowercased()]
        st.send("Link click", ["element": "account-pnl", "url": "https://flyingtulip.com/trade/portfolio/?a=\(testWallet)"])
        st.pageviewIfDue(walletCount: 2, force: true)
        st.send("Wallet added")
        st.send("HF alert shown", ["level": "danger"])
        st.fetchError(source: "lend@\(testWallet)")
        XCTAssertFalse(t.bodies.isEmpty)
        for b in t.bodies {
            let text = String(data: b, encoding: .utf8)!.lowercased()
            XCTAssertFalse(text.contains(testWallet.lowercased()), "wallet address leaked: \(text)")
            XCTAssertFalse(text.range(of: "0x[0-9a-f]{40}", options: .regularExpression) != nil)
        }
        XCTAssertTrue(String(data: t.bodies[0], encoding: .utf8)!.contains(":address"))
        let pv = t.events.first { ($0["name"] as? String) == "pageview" }?["props"] as? [String: String]
        XCTAssertEqual(pv?["walletsConfigured"], "2")
        XCTAssertEqual(pv?["host"], "native")
        XCTAssertEqual(t.events.first { ($0["name"] as? String) == "Fetch error" }?["props"] as? [String: String] != nil, true)
    }

    func testOptOutSendsNothing() {
        let (st, t, s) = make()
        s.analytics = false
        XCTAssertFalse(st.send("Panel open"))
        st.pageviewIfDue(walletCount: 1, force: true)
        st.fetchError(source: "price")
        _ = st.linkTarget(url: Pages.home, element: "header-logo")
        XCTAssertTrue(t.bodies.isEmpty)
    }

    func testDefaultIsOn() {
        XCTAssertTrue(freshSettings().analytics)
    }

    func testSwitchSendsOneLastEventThenNothingAndOnOnReturn() {
        let (st, t, s) = make()
        st.setEnabled(false)
        XCTAssertEqual(t.names, ["Usage stats off"])
        XCTAssertFalse(s.analytics)
        XCTAssertFalse(st.send("Refresh"))
        st.setEnabled(false)
        XCTAssertEqual(t.names, ["Usage stats off"], "switching off twice is one event")
        st.setEnabled(true)
        XCTAssertEqual(t.names, ["Usage stats off", "Usage stats on"])
        XCTAssertTrue(st.send("Refresh"))
        let p = t.events[0]["props"] as? [String: String]
        XCTAssertEqual(p?["os"], Stats.osLabel())
    }

    func testThirtyPerHourPerEventName() {
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let (st, t, _) = make(now: { clock })
        for _ in 0..<45 { st.send("Refresh") }
        XCTAssertEqual(t.names.filter { $0 == "Refresh" }.count, 30)
        XCTAssertTrue(st.send("Wallet switch"), "another name has its own budget")
        clock.addTimeInterval(3600)
        XCTAssertTrue(st.send("Refresh"), "the next hour starts again")
    }

    func testFetchErrorAtMostOncePerHourPerEndpoint() {
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let (st, t, _) = make(now: { clock })
        st.fetchError(source: "price"); st.fetchError(source: "price"); st.fetchError(source: "fees"); st.fetchError(source: "feesSeries")
        XCTAssertEqual(t.names.filter { $0 == "Fetch error" }.count, 2, "price and fees; feesSeries shares the fees endpoint")
        clock.addTimeInterval(3601)
        st.fetchError(source: "price")
        XCTAssertEqual(t.names.filter { $0 == "Fetch error" }.count, 3)
    }

    func testPageviewOnceADay() {
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let (st, t, _) = make(now: { clock })
        st.pageviewIfDue(walletCount: 0); st.pageviewIfDue(walletCount: 0)
        XCTAssertEqual(t.names, ["pageview"])
        clock.addTimeInterval(86_400 + 1)
        st.pageviewIfDue(walletCount: 0)
        XCTAssertEqual(t.names, ["pageview", "pageview"])
    }

    func testSettingsDefaultsAndPersistence() {
        let s = freshSettings()
        XCTAssertEqual(s.hfWarn, 1.40); XCTAssertEqual(s.hfCritical, 1.30); XCTAssertEqual(s.cooldownMin, 30)
        XCTAssertTrue(s.notifications); XCTAssertEqual(s.priceChain, 1); XCTAssertEqual(s.tab, "market")
        s.wallets = [testWallet.lowercased()]; s.tab = "account"; s.hfWarn = 1.5; s.hfCritical = 2
        XCTAssertEqual(s.wallets, [testWallet.lowercased()]); XCTAssertEqual(s.tab, "account")
        XCTAssertEqual(s.hfCritical, 1.5, "critical never above warning")
        s.defaults.set("false", forKey: "analytics")
        XCTAssertFalse(s.analytics)
    }
}
