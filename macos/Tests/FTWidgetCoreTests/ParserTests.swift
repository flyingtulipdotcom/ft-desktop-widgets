import XCTest
@testable import FTWidgetCore

final class ParserTests: XCTestCase {
    func testPriceIsTheMarketMark() throws {
        let p = try XCTUnwrap(Parse.price(try fixture("tickers")))
        XCTAssertEqual(p.price, 0.150151694355331498, accuracy: 1e-12)
        XCTAssertEqual(p.changePct24h, 2.727891, accuracy: 1e-5)
        XCTAssertEqual(Fmt.price(p.price), "$0.1502")
        XCTAssertNil(Parse.price(json(#"{"data":{"tickers":[{"display_symbol":"X-ftUSD","price":"1"}]}}"#)))
        XCTAssertNil(Parse.price(json(#"{"data":{"tickers":[{"display_symbol":"FT-ftUSD","price":"oops"}]}}"#)))
        XCTAssertNil(Parse.price(nil))
    }

    func testFees() throws {
        let f = try XCTUnwrap(Parse.fees(try fixture("fees")))
        XCTAssertEqual(f.period24h, 954.345952, accuracy: 1e-6)
        XCTAssertEqual(f.lifetime, 120704.438833, accuracy: 1e-6)
        XCTAssertEqual(Fmt.usd(f.period24h), "$954")
        XCTAssertFalse(f.products.isEmpty)
        XCTAssertEqual(f.products.map { $0.usd }, f.products.map { $0.usd }.sorted(by: >))
        XCTAssertNil(Parse.fees(json(#"{"data":{}}"#)))
    }

    func testSeriesAndKlines() throws {
        let s = try XCTUnwrap(Parse.feesSeries(try fixture("fees_series")))
        XCTAssertEqual(s.count, 31)
        XCTAssertEqual(s[0].date, "2026-09-10")
        XCTAssertEqual(s[0].value, 1580.338822, accuracy: 1e-6)
        let k = try XCTUnwrap(Parse.klines(try fixture("klines")))
        XCTAssertEqual(k.count, 30)
        XCTAssertEqual(k[0].date, "2026-09-11")
        XCTAssertEqual(k[0].value, 0.100950591269940267, accuracy: 1e-12)
        // day over day skips the partial current day
        let today = DayValue(date: "2026-10-11", value: 5)
        let rows = [DayValue(date: "2026-10-07", value: 100), DayValue(date: "2026-10-08", value: 100),
                    DayValue(date: "2026-10-09", value: 100), DayValue(date: "2026-10-10", value: 110), today]
        let now = ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z")!
        XCTAssertEqual(Parse.feesDayOverDay(rows, now: now), 10, accuracy: 1e-9)
        XCTAssertTrue(Parse.feesDayOverDay(Array(rows.prefix(3)), now: now).isNaN)
    }

    func testLendHealth() throws {
        let chains = Parse.mergeChains([Parse.lend(try fixture("lend")), Parse.lend(nil)])
        XCTAssertEqual(chains.map { $0.chainId }, [146, 1, 56])
        let low = try XCTUnwrap(Parse.lowestHf(chains))
        XCTAssertEqual(low.name, "Sonic")
        XCTAssertEqual(low.hf ?? 0, 1.9, accuracy: 1e-9)
        XCTAssertEqual(low.liqHf, 1.25)
        XCTAssertNil(chains.first { $0.chainId == 1 }?.hf, "no debt means no health factor")
        XCTAssertEqual(Fmt.hf(nil), "∞")
        XCTAssertEqual(Fmt.hf(150), ">100")
        XCTAssertEqual(Fmt.hf(1.926), "1.93")
        XCTAssertNil(Parse.lowestHf([]))
    }

    func testRewardsAllTimeAndUnknowns() throws {
        let ok = json("""
        {"success":true,"data":{"chains":[
          {"chainId":146,"staking":{"pending_yield_ft":"1000000000000000000","claimed_yield_ft":"2000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false},
           "lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"3000000000000000000","pendingFtRaw":"500000000000000000"}}}},
          {"chainId":1,"lend":{"userMetrics":{}}}]}}
        """)
        let r = try XCTUnwrap(Parse.rewards(ok))
        XCTAssertEqual(r.sftFt, 3, accuracy: 1e-9)
        XCTAssertEqual(r.lendFt, 3.5, accuracy: 1e-9)
        XCTAssertEqual(r.totalFt, 6.5, accuracy: 1e-9)
        XCTAssertEqual(r.claimableFt, 1, accuracy: 1e-9)
        XCTAssertEqual(Parse.earnedByChain(r), "Sonic 6.5")
        // a stale claimed figure makes the total unknown instead of wrong
        let stale = json(#"{"data":{"chains":[{"chainId":146,"staking":{"pending_yield_ft":"1","claimed_yield_ft":"1","claimed_yield_indexed_through_block":5,"claimed_yield_stale":true}}]}}"#)
        XCTAssertTrue(try XCTUnwrap(Parse.rewards(stale)).totalFt.isNaN)
        let errored = json(#"{"data":{"sectionErrors":{"lend":"x"},"chains":[]}}"#)
        XCTAssertTrue(try XCTUnwrap(Parse.rewards(errored)).totalFt.isNaN)
        XCTAssertNil(Parse.rewards(json(#"{"success":false,"data":{"chains":[]}}"#)))
        XCTAssertEqual(rawUnits("123456789012345678901", 18), 123.456789012345678901, accuracy: 1e-9)
        XCTAssertTrue(rawUnits("12x", 18).isNaN)
    }

    func testPutsGainUsesTheMarketPrice() throws {
        let b = json("""
        {"data":{"positions":[{"nft_id":7,"token_symbol":"USDC","token_decimals":6,"strike":"100000000",
          "current_capital":"1000000000","current_ft":"5000000000000000000000","withdrawn_ft":"1000000000000000000000","created_at":"2026-01-02T00:00:00Z"}]}}
        """)
        let p = try XCTUnwrap(Parse.puts(b))
        XCTAssertEqual(p.costUsd, 1000, accuracy: 1e-6)
        XCTAssertEqual(p.ftHeld, 6000, accuracy: 1e-6)
        let g = try XCTUnwrap(Parse.putGain(p, ftPrice: 0.15))
        XCTAssertEqual(g.valueUsd, 900, accuracy: 1e-6)
        XCTAssertEqual(g.gainUsd, -100, accuracy: 1e-6)
        XCTAssertEqual(g.gainPct, -10, accuracy: 1e-6)
        XCTAssertNil(Parse.putGain(p, ftPrice: .nan))
        XCTAssertNil(Parse.puts(json(#"{"data":{"positions":[]}}"#)))
    }

    func testPointsRankAndBreakdown() throws {
        let b = json("""
        {"data":{"chains":[
         {"isAllChains":true,"userMetrics":{"totalPoints":1000}},
         {"isAllChains":false,"chainData":{"id":146,"name":"Sonic"},"userMetrics":{"totalPoints":600}},
         {"isAllChains":false,"chainData":{"id":1,"name":"Ethereum"},"userMetrics":{"totalPoints":400}},
         {"isAllChains":false,"chainData":{"id":56,"name":"BNB"},"userMetrics":{"totalPoints":0}}]}}
        """)
        let p = try XCTUnwrap(Parse.points(b))
        XCTAssertEqual(p.total, 1000)
        XCTAssertEqual(p.chains.map { $0.name }, ["Sonic", "Ethereum"])
        XCTAssertEqual(Fmt.points(662_300), "662K")
        let page = json(#"{"data":{"pagination":{"total":6789},"leaderboard":[{"userWallet":"0xAAA","rank":1,"totalPoints":900},{"userWallet":"0xBBB","rank":2,"totalPoints":800}]}}"#)
        XCTAssertEqual(Parse.rankInPage(page, wallet: "0xbbb", myPoints: 800).rank, 2)
        XCTAssertEqual(Parse.rankInPage(page, wallet: "0xccc", myPoints: 1000).dir, -1)
        XCTAssertEqual(Parse.rankInPage(page, wallet: "0xccc", myPoints: 10).dir, 1)
        XCTAssertTrue(Parse.rankInPage(json(#"{"data":{"leaderboard":[]}}"#), wallet: "0x", myPoints: 1).empty)
        let bd = Parse.pointsBreakdown(json(#"{"data":{"pointsBreakdown":[{"productLabel":"Lend","activityLabel":"Borrow","positionUsd":1711.19,"multiplier":1}]}}"#))
        XCTAssertEqual(bd.first?.label, "Lend Borrow")
    }

    func testPositionsAndNull() throws {
        let b = json(#"[{"chainId":146,"symbol":"ETH-ftUSD","sizeCurrency":"ETH","side":"short","size":"2","markPrice":"2000","entryPrice":"2100","pnlAmount":"200","pnlPct":"4.7","blendedLeverage":"3"},{"chainId":1,"symbol":"X","size":"0","markPrice":"1"}]"#)
        let ps = Parse.positions(b)
        XCTAssertEqual(ps.count, 1)
        XCTAssertEqual(ps[0].side, "short")
        XCTAssertEqual(ps[0].network, "Sonic")
        XCTAssertEqual(ps[0].valueUsd, 4000, accuracy: 1e-9)
        XCTAssertTrue(Parse.positions(nil).isEmpty)
        if case .null = Client.decode(Data("null".utf8)) {} else { XCTFail("null body is an answer, not a failure") }
        if case .failed = Client.decode(Data("<html>".utf8)) {} else { XCTFail("garbage is a failure") }
    }

    func testRewardsHistoryDailyGains() throws {
        let day = 86400
        let base = (1_790_000_000 / day) * day
        func pt(_ d: Int, _ e: String) -> String { #"{"timestampUnixSeconds":\#(base + d * day + day - 1),"claimedFtRaw":"0","totalEarnedFtRaw":"\#(e)"}"# }
        let body = json(#"{"data":{"points":["# + [pt(0, "1000000000000000000"), pt(1, "3000000000000000000"), pt(2, "3000000000000000000"), pt(9, "9000000000000000000")].joined(separator: ",") + "]}}")
        let now = Date(timeIntervalSince1970: Double(base + 20 * day))
        let h = try XCTUnwrap(Parse.rewardsHistory(body, now: now))
        XCTAssertEqual(h.count, 4)
        let g = Parse.dailyGains(h)
        XCTAssertEqual(g.map { $0.value }, [2, 0], "a gap in the days is skipped, never a fake spike")
        // today's partial sample is ignored
        let today = Date(timeIntervalSince1970: Double(base + 9 * day + 100))
        XCTAssertEqual(Parse.rewardsHistory(body, now: today)?.count, 3)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.usd(1080), "$1.08k")
        XCTAssertEqual(Fmt.usd(954.3), "$954")
        XCTAssertEqual(Fmt.signedUsd(-13100), "-$13.1k")
        XCTAssertEqual(Fmt.signedUsd(0.001), "$0.00")
        XCTAssertEqual(Fmt.pct(-9.34), "-9.3%")
        XCTAssertEqual(Fmt.pct(120), "+120%")
        XCTAssertEqual(Fmt.ft(5880), "5.88K")
        XCTAssertEqual(Fmt.ft(0.001), "<0.01")
        XCTAssertEqual(Fmt.thousands(6789), "6,789")
        XCTAssertEqual(Fmt.shortAddr(testWallet), "0x38A5…2D62")
        XCTAssertEqual(Wallets.parse("\(testWallet), \(testWallet.lowercased()); 0x12").list, [testWallet.lowercased()])
        XCTAssertEqual(Wallets.parse("0x12").bad, ["0x12"])
    }
}
