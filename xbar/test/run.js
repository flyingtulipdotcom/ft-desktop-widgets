// node test/run.js           offline unit + end-to-end tests with fixtures
// LIVE=1 node test/run.js    also run once against the real API (no wallet) and print the menu
// LIVE=1 WALLET=0x... node test/run.js   same with a wallet
const assert = require("assert"), fs = require("fs"), path = require("path"), zlib = require("zlib"), cp = require("child_process")
const { load } = require("./load"), { validate } = require("./xbar-format")
const M = load()
const fx = n => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", n), "utf8"))
const DEAD = "0x000000000000000000000000000000000000dEaD"
let passed = 0
const ok = (name, fn) => { fn(); passed++; console.log("ok  " + name) }

// ---- formatting and parsers ----
ok("formatters", () => {
  assert.equal(M.fmtHf(null), "∞"); assert.equal(M.fmtHf(150), ">100"); assert.equal(M.fmtHf(1.2345), "1.23")
  assert.equal(M.fmtUsd(1152.98), "$1.15k"); assert.equal(M.fmtSignedUsd(-5), "-$5.00"); assert.equal(M.fmtPrice(0.15015), "$0.1502")
  assert.equal(M.fmtFt(470.83), "470.8"); assert.equal(M.fmtPoints(1234567), "1.2M"); assert.equal(M.fmtPct(-3.456), "-3.5%")
})
ok("wallet normalisation", () => {
  assert.equal(M.normalizeWallet(" " + DEAD + " "), DEAD.toLowerCase()); assert.equal(M.normalizeWallet("0x123"), "")
})
ok("price is the FT-ftUSD market mark", () => {
  const p = M.parsePrice(fx("tickers.json")); assert(p && p.price > 0 && p.price < 10)
  assert.equal(M.parsePrice({ data: { tickers: [{ display_symbol: "WBTC-ftUSD", price: "1" }] } }), null)
})
ok("fees + series + klines parse the live shapes", () => {
  const f = M.parseFees(fx("fees.json")); assert(f.period24h >= 0 && f.products.length > 0)
  assert.equal(M.parseFeesSeries(fx("fees_series.json")).length, 31); assert.equal(M.parseKlines(fx("klines.json")).length, 30)
  assert(isFinite(M.feesDayOverDay(M.parseFeesSeries(fx("fees_series.json")), Date.now())))
})
ok("lend: no debt is infinity, lowest HF across chains", () => {
  const body = { data: { chains: [
    { chainId: 146, hfLiquidationThreshold: 1.25, userMetrics: { totalDebtUsd: 900, healthFactor: 1.8, equityUsd: 100 } },
    { chainId: 1, userMetrics: { totalDebtUsd: 50, healthFactor: 1.33, equityUsd: 10 } },
    { chainId: 56, userMetrics: { totalDebtUsd: 0, healthFactor: 999 } }] } }
  const l = M.mergeChains([M.parseLend(body)]); assert.equal(l.length, 3)
  assert.equal(M.lowestHf(l).name, "Ethereum"); assert.equal(M.lowestHf([l[2]]), null)
})
ok("alert state machine: once per crossing, hysteresis, cooldown", () => {
  const cfg = { warn: 1.4, critical: 1.3, cooldownMs: 30 * 60e3 }, e = hf => ({ hf, name: "Sonic", liqHf: 1.25 })
  let st = { level: 0, last: {} }, r
  r = M.decideNotify(st, e(2), cfg, 0); assert(!r.notify); st = r.state
  r = M.decideNotify(st, e(1.39), cfg, 1e3); assert(r.notify && r.notify.level === 1); st = r.state
  r = M.decideNotify(st, e(1.38), cfg, 2e3); assert(!r.notify)
  r = M.decideNotify(st, e(1.29), cfg, 3e3); assert(r.notify && r.notify.level === 2); st = r.state
  r = M.decideNotify(st, e(1.33), cfg, 4e3); assert(!r.notify && r.state.level === 2); st = r.state
  r = M.decideNotify(st, e(1.6), cfg, 5e3); assert(!r.notify && r.state.level === 0); st = r.state
  r = M.decideNotify(st, e(1.39), cfg, 6e3); assert(!r.notify)
  r = M.decideNotify(JSON.parse(JSON.stringify(r.state)), e(1.2), cfg, 31 * 60e3 + 7e3); assert(r.notify && r.notify.level === 2)  // survives a JSON round trip
  assert.equal(M.decideNotify(r.state, null, cfg, 1).state.level, 0)
})

// ---- PNG ----
function checkPng(b64, w, h) {
  const buf = Buffer.from(b64, "base64")
  assert.deepEqual([...buf.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10])
  let p = 8, idat = [], seen = []
  while (p < buf.length) {
    const len = buf.readUInt32BE(p), type = buf.toString("latin1", p + 4, p + 8), data = buf.subarray(p + 8, p + 8 + len)
    assert.equal(buf.readUInt32BE(p + 8 + len), require("zlib").crc32 ? require("zlib").crc32(buf.subarray(p + 4, p + 8 + len)) : M.crc32(buf, p + 4, p + 8 + len), "crc " + type)
    seen.push(type); if (type === "IDAT") idat.push(data)
    if (type === "IHDR") { assert.equal(data.readUInt32BE(0), w); assert.equal(data.readUInt32BE(4), h); assert.equal(data[8], 4); assert.equal(data[9], 3) }
    p += 12 + len
  }
  assert.deepEqual(seen, ["IHDR", "PLTE", "pHYs", "IDAT", "IEND"])
  const raw = zlib.inflateSync(Buffer.concat(idat))   // verifies the zlib header and adler32
  assert.equal(raw.length, (Math.ceil(w / 2) + 1) * h)
  return raw
}
ok("bar chart PNG is a valid PNG", () => checkPng(M.barChartPng(Array.from({ length: 31 }, (_, i) => i * 3 + 1)), 340, 76))
ok("line chart PNG is a valid PNG", () => checkPng(M.lineChartPng(Array.from({ length: 30 }, (_, i) => 0.1 + Math.sin(i / 4) / 50)), 340, 76))
ok("charts survive flat and single-spike data", () => { M.barChartPng([0, 0, 0]); M.lineChartPng([1, 1, 1]); M.barChartPng([5, 0, 0, 0]) })
ok("logo is a PNG", () => assert.equal(Buffer.from(M.LOGO_B64, "base64").toString("latin1", 1, 4), "PNG"))
if (process.env.DUMP_PNG) {
  fs.writeFileSync(process.env.DUMP_PNG + "/bars.png", Buffer.from(M.barChartPng(M.parseFeesSeries(fx("fees_series.json")).map(x => x.total)), "base64"))
  fs.writeFileSync(process.env.DUMP_PNG + "/line.png", Buffer.from(M.lineChartPng(M.parseKlines(fx("klines.json")).map(x => x.close)), "base64"))
}

// ---- end to end with a fake I/O layer ----
function leaderboardPage(url, rank, pts) {
  const page = Number(url.match(/page=(\d+)/)[1]), rows = []
  for (let r = (page - 1) * 500 + 1; r <= Math.min(page * 500, 2000); r++)
    rows.push({ rank: r, userWallet: r === rank ? DEAD : "0x" + String(r).padStart(40, "0"), totalPoints: r === rank ? pts : 1e6 - r * 100 })
  return { data: { pagination: { total: 2000 }, leaderboard: rows } }
}
function world(opts) {
  opts = Object.assign({ hf: 1.9, fail: [] }, opts)
  const hfFor = u => { for (const k in (opts.hfBy || {})) if (u.toLowerCase().includes(k)) return typeof opts.hfBy[k] === "function" ? opts.hfBy[k]() : opts.hfBy[k]; return opts.hf }
  const routes = [
    [/tickers\?chainId=1$/, fx("tickers.json")], [/fees\/application\?period=1d/, fx("fees.json")],
    [/fees\/application\?period=1m/, fx("fees_series.json")], [/klines/, fx("klines.json")],
    [/mm\/lend\?user=.*chainId=143/, { data: { chains: [] } }],
    [/mm\/lend\?user=/, u => ({ data: { chains: [
      { chainId: 146, hfLiquidationThreshold: 1.25, userMetrics: { totalDebtUsd: 1000, healthFactor: hfFor(u), equityUsd: 500 } },
      { chainId: 1, userMetrics: { totalDebtUsd: 0, healthFactor: 0, equityUsd: 25 } }] } })],
    [/account\/summary.*chainId=146/, [{ chainId: 146, unrealizedPnl: "12.5" }]],
    [/account\/summary.*chainId=1$/, [{ chainId: 1, unrealizedPnl: "-2" }]],
    [/account\/summary/, null],
    [/account\/dashboard/, { success: true, data: { chains: [{ chainId: 146,
      staking: { pending_yield_ft: "3000000000000000000", claimed_yield_ft: "100000000000000000000", claimed_yield_indexed_through_block: 5, claimed_yield_stale: false },
      lend: { userMetrics: { ftRewards: { receivedFtRaw: "50000000000000000000", pendingFtRaw: "0" } } } }] } }],
    [/points\/leaderboard/, u => leaderboardPage(u, 777, 922000)],
    [/points\?walletAddress/, { data: { chains: [{ isAllChains: true, userMetrics: { totalPoints: 922000 } }] } }],
    [/positions.*chainId=146/, [{ chainId: 146, network: "Sonic", symbol: "wS-ftUSD", sizeCurrency: "wS", side: "long", size: "1000", markPrice: "0.05", pnlAmount: "5", pnlPct: "10", blendedLeverage: "3" }]],
    [/positions/, []],
    [/ftPUT/, { data: { positions: [{ nft_id: "7", token_symbol: "USDT", token_decimals: 6, strike: "99960146", current_capital: "1000000000", current_ft: "9996014600000000000000", withdrawn_ft: "0" }] } }]
  ]
  const files = {}, notes = [], calls = [], posts = [], opened = []
  const io = {
    fetchAll(urls) {
      calls.push(urls.slice())
      return urls.map(u => {
        if (opts.fail.some(f => u.includes(f))) return null
        for (const [re, body] of routes) if (re.test(u)) { const b = typeof body === "function" ? body(u) : body; return b === null ? null : JSON.stringify(b) }
        return null
      })
    },
    readFile: p => (p in files ? files[p] : null), writeFile: (p, t) => { files[p] = t },
    notify: (t, b, u) => notes.push({ t, b, u }), prompt: () => opts.prompt, alert: m => notes.push({ alert: m }),
    post: lists => { for (const l of lists) posts.push(l) }, osVersion: () => "15.1", openUrl: u => opened.push(u)
  }
  return { io, files, notes, calls, posts, opened }
}
const args = (o) => Object.assign({ cmd: "run", wallet: "", hfWarn: "1.40", hfCritical: "1.30", notify: "true", cooldownMin: "30", priceChain: "1",
  stateDir: "/s", walletFile: "/w/wallet", self: "/p/flyingtulip.1m.sh", analytics: "false" }, o)
const NOW = Date.parse("2026-10-10T17:00:00Z")

ok("no wallet: market only, valid format, no account calls", () => {
  const w = world(), out = M.main(w.io, args({}), NOW)
  assert.deepEqual(validate(out), [])
  const title = out.split("\n")[0]; assert(/^\$0\.\d{4}  fees \$/.test(title) && title.includes("image="), title); assert(!title.includes("HF"))
  assert(out.includes("Add a wallet")); assert(!w.calls.flat().some(u => /user=|address=|walletAddress/.test(u)))
  assert(out.includes("href=https://flyingtulip.com/statistics/")); assert(out.includes("refresh=true")); assert(!/YES|NO\b.*live/i.test(out))
  assert(w.calls.flat().every(u => u.startsWith("https://api.flyingtulip.com/")))
})
ok("wallet: HF, PnL, FT earned, points+rank, ftPUT, positions", () => {
  const w = world(), out = M.main(w.io, args({ wallet: DEAD }), NOW)
  assert.deepEqual(validate(out), [])
  assert(/^\$0\.\d{4}  fees \$\S+  HF 1\.90 \|/.test(out.split("\n")[0]), out.split("\n")[0])
  for (const s of ["Health      1.90  Sonic (lowest)", "PnL         +$10.50", "FT earned   153.0 FT", "rank #777 of 2,000", "Positions  1 open", "ftPUT       "])
    assert(out.includes(s), "missing: " + s + "\n" + out)
  assert(out.includes("0x0000…dead".replace("dead", "dEaD").toLowerCase()) || out.includes("0x0000…dead"))
  assert(!out.includes("Wallet is not"))
})
// Two real wallet shapes (addresses removed): the smaller one claimed sftUSD yield months ago, the larger one only
// supplies Lend and earns small rewards whose raw amounts have 17 digits (0.01 to 0.1 FT).
const SMALL_REWARDS = { success: true, data: { chains: [
  { chainId: 1, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 26165977 }, lend: { userMetrics: { ftRewards: null, ftRewardsError: null } } },
  { chainId: 146, staking: { pending_yield_ft: "0", claimed_yield_ft: "95386787178560501045", claimed_yield_indexed_through_block: 80722469 }, lend: { userMetrics: { ftRewards: null } } }] } }
const LARGE_REWARDS = { success: true, data: { chains: [
  { chainId: 1, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 26165977 }, lend: { userMetrics: { ftRewards: { receivedFtRaw: "0", pendingFtRaw: "60167126473248989" } } } },
  { chainId: 146, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 80722469 }, lend: { userMetrics: { ftRewards: { receivedFtRaw: "743020047575476813", pendingFtRaw: "59654073282058744" } } } }] } }
const POINTS_2CHAINS = { data: { chains: [
  { chainData: { id: 146, name: "Sonic" }, isAllChains: false, userMetrics: { totalPoints: 45757.02690673988 } },
  { chainData: { id: 1, name: "Ethereum" }, isAllChains: false, userMetrics: { totalPoints: 616132.7877936237 } },
  { chainData: { id: 56, name: "BNB Smart Chain" }, isAllChains: false, userMetrics: { totalPoints: 0 } },
  { chainData: null, isAllChains: true, userMetrics: { totalPoints: 661889.8147003637 } }] } }
ok("rewards breakdown: a smaller wallet's old sftUSD yield vs a larger wallet's new Lend rewards", () => {
  const s = M.parseRewards(SMALL_REWARDS), l = M.parseRewards(LARGE_REWARDS)
  assert(Math.abs(s.totalFt - 95.386787178560501) < 1e-9 && s.lendFt === 0 && Math.abs(s.sftClaimed - s.totalFt) < 1e-12)
  assert(Math.abs(l.totalFt - (0.060167126473248989 + 0.743020047575476813 + 0.059654073282058744)) < 1e-12, l.totalFt)
  assert.equal(l.sftFt, 0); assert.equal(M.fmtFt(l.totalFt), "0.86"); assert.equal(M.fmtFt(s.totalFt), "95.4")
  assert.equal(M.earnedByChain(s), "Sonic 95.4"); assert.equal(M.earnedByChain(l), "Ethereum 0.06, Sonic 0.80")
})
ok("points: all-chains total plus each chain, largest first", () => {
  const p = M.parsePoints(POINTS_2CHAINS)
  assert(Math.abs(p.total - 661889.8147003637) < 1e-6); assert.deepEqual(p.chains.map(c => c.name), ["Ethereum", "Sonic"])
})
ok("FT earned and points rows say what they cover, with the breakdown in the submenu", () => {
  const w = world(), orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (/account\/dashboard/.test(urls[i]) ? JSON.stringify(SMALL_REWARDS) : /points\?walletAddress/.test(urls[i]) ? JSON.stringify(POINTS_2CHAINS) : b))
  const out = M.main(w.io, args({ wallet: DEAD }), NOW)
  assert.deepEqual(validate(out), [])
  for (const s of ["--FT earned   95.4 FT  all time", "--  sftUSD yield     95.4 FT  (claimed 95.4, pending 0)", "--  Lend FT rewards  0 FT", "--  By chain: Sonic 95.4",
    "--Points      662K  all chains", "--  Ethereum  616K", "--  Sonic     45.8K", "one chain at a time", "Account    0x0000…dead  HF 1.90  95.4 FT  662K pts"])
    assert(out.includes(s), "missing: " + s + "\n" + out)
})
ok("every dropdown line links to a real flyingtulip.com page", () => {
  const w = world(), out = M.main(w.io, args({ wallet: DEAD }), NOW), lines = out.split("\n").slice(1).filter(l => !/^-+$/.test(l) && !/^(--)?(Settings|Advanced) \|/.test(l))
  for (const l of lines) assert(/ (href|shell|refresh)=/.test(l.replace(/^[^|]*\|/, " ")), "no link: " + l)
  const href = l => (l.match(/href=(\S+)/) || [])[1]
  const find = s => lines.find(l => l.includes(s))
  assert.equal(href(find("FT price")), "https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=1&marketType=spot")
  assert.equal(href(find("Fees 24h")), "https://flyingtulip.com/statistics/")
  assert.equal(href(find("Health ")), "https://flyingtulip.com/lend/dashboard/")
  assert.equal(href(find("PnL ")), "https://flyingtulip.com/trade/portfolio/")
  assert.equal(href(find("FT earned")), "https://flyingtulip.com/rewards/")
  assert.equal(href(find("Points ")), "https://flyingtulip.com/rewards/leaderboard/")
  assert.equal(href(find("ftPUT ")), "https://flyingtulip.com/allocation/positions/")
  assert.equal(href(find("Open flyingtulip.com")), "https://flyingtulip.com/")
  const pos = lines.find(l => /^--\S+ (long|short)/.test(l)); assert(/href=https:\/\/flyingtulip\.com\/trade\/\?symbol=\S+&chainId=\d+&marketType=spot/.test(pos), pos)
  const imgs = lines.filter(l => l.includes("image=")); assert(imgs.length >= 2 && imgs.every(l => /href=https:\/\/flyingtulip\.com\//.test(l)))
})
ok("no debt anywhere shows infinity", () => {
  const w = world(); const orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (/mm\/lend\?user=[^&]*$/.test(urls[i]) ? JSON.stringify({ data: { chains: [{ chainId: 146, userMetrics: { totalDebtUsd: 0, healthFactor: 0 } }] } }) : b))
  const out = M.main(w.io, args({ wallet: DEAD }), NOW)
  assert(/HF ∞/.test(out.split("\n")[0])); assert(out.includes("∞  no debt")); assert.equal(w.notes.length, 0)
})
ok("invalid wallet is flagged, not fetched", () => {
  const w = world(), out = M.main(w.io, args({ wallet: "0x123" }), NOW)
  assert(out.includes("Not a valid address")); assert(!w.calls.flat().some(u => /user=/.test(u))); assert.deepEqual(validate(out), [])
})
ok("notifications: warn once, critical on the next crossing, nothing inside the cooldown", () => {
  const w = world({ hf: 1.38 }); let out = M.main(w.io, args({ wallet: DEAD }), NOW)
  assert.equal(w.notes.length, 1); assert(/low/.test(w.notes[0].t) && w.notes[0].u === "normal" && /1\.38/.test(w.notes[0].b))
  assert(out.split("\n")[0].includes("color=" + "#d98a00"))
  M.main(w.io, args({ wallet: DEAD }), NOW + 60e3); assert.equal(w.notes.length, 1, "same level must not repeat")
  const w2 = world({ hf: 1.28 }); w2.files = w.files; Object.assign(w2.io, { readFile: p => (p in w.files ? w.files[p] : null), writeFile: (p, t) => { w.files[p] = t } })
  out = M.main(w2.io, args({ wallet: DEAD }), NOW + 120e3)
  assert.equal(w2.notes.length, 1); assert.equal(w2.notes[0].u, "critical"); assert(out.split("\n")[0].includes("#e5484d"))
})
ok("notifications off: no osascript notification, state still kept", () => {
  const w = world({ hf: 1.2 }); M.main(w.io, args({ wallet: DEAD, notify: "false" }), NOW); assert.equal(w.notes.length, 0)
})
ok("api failure falls back to the last good values and flags them stale", () => {
  const w = world(); M.main(w.io, args({ wallet: DEAD }), NOW)
  const w2 = world({ fail: ["/mm/", "/fees/", "/tickers", "/account/", "/points", "/tge/"] })
  Object.assign(w2.io, { readFile: p => (p in w.files ? w.files[p] : null), writeFile: (p, t) => { w.files[p] = t } })
  const out = M.main(w2.io, args({ wallet: DEAD }), NOW + 10 * 60e3)
  assert(out.split("\n")[0].includes("⚠")); assert(out.includes("HF 1.90")); assert(out.includes("data up to 10m old")); assert.deepEqual(validate(out), [])
  assert.equal(w2.notes.length, 0, "stale data must not raise alerts")
})
ok("everything down and nothing cached: FT offline, still valid", () => {
  const w = world({ fail: ["api.flyingtulip.com"] }), out = M.main(w.io, args({ wallet: DEAD }), NOW)
  assert(out.startsWith("FT offline")); assert.deepEqual(validate(out), [])
})
ok("slow sources are cached for 10 minutes", () => {
  const w = world(); M.main(w.io, args({}), NOW); w.calls.length = 0
  const o = w.io.readFile; M.main(w.io, args({}), NOW + 60e3)
  assert(!w.calls.flat().some(u => /period=1m|klines/.test(u))); M.main(w.io, args({}), NOW + 11 * 60e3)
  assert(w.calls.flat().some(u => /period=1m/.test(u)))
})
ok("a changed wallet drops the old wallet's cache and alert state", () => {
  const w = world({ hf: 1.2 }); M.main(w.io, args({ wallet: DEAD }), NOW); assert.equal(w.notes.length, 1)
  M.main(w.io, args({ wallet: "0x" + "1".repeat(40) }), NOW + 60e3); assert.equal(w.notes.length, 2)   // fresh state: alerts again
})
ok("price falls back to Sonic when the configured chain has no FT-ftUSD market", () => {
  const w = world(), orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (urls[i].endsWith("tickers?chainId=1") ? JSON.stringify({ data: { tickers: [] } }) : urls[i].endsWith("tickers?chainId=146") ? fs.readFileSync(path.join(__dirname, "fixtures/tickers.json"), "utf8") : b))
  assert(/^\$0\.\d{4}/.test(M.main(w.io, args({}), NOW)))
})
ok("pipes and newlines from API text cannot break the menu", () => {
  const w = world(), orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (/positions.*chainId=146/.test(urls[i]) ? JSON.stringify([{ chainId: 146, network: "So|nic\nX", symbol: "a|b-c", sizeCurrency: "a|b\n", side: "long", size: "1", markPrice: "1", pnlAmount: "1" }]) : b))
  assert.deepEqual(validate(M.main(w.io, args({ wallet: DEAD }), NOW)), [])
})
ok("Set wallet prompt: saves lowercase, rejects junk, empty clears, plugin setting wins", () => {
  let w = world({ prompt: " " + DEAD + " " }); M.main(w.io, args({ cmd: "wallet" }), NOW); assert.equal(w.files["/w/wallet"], DEAD.toLowerCase())
  let out = M.main(w.io, args({}), NOW); assert(out.includes("Account    0x0000"))
  out = M.main(w.io, args({ wallet: "0x" + "2".repeat(40) }), NOW); assert(out.includes("0x2222…2222"))
  w = world({ prompt: "junk" }); M.main(w.io, args({ cmd: "wallet" }), NOW); assert(!("/w/wallet" in w.files)); assert(w.notes[0].alert)
  w = world({ prompt: "" }); w.files["/w/wallet"] = DEAD; M.main(w.io, args({ cmd: "wallet" }), NOW); assert.equal(w.files["/w/wallet"], "")
  w = world({ prompt: null }); w.files["/w/wallet"] = DEAD; M.main(w.io, args({ cmd: "wallet" }), NOW); assert.equal(w.files["/w/wallet"], DEAD)
})
ok("thresholds: critical is clamped to warn, junk falls back to defaults", () => {
  assert.equal(M.buildConfig({ hfWarn: "1.2", hfCritical: "1.5" }).alert.critical, 1.2)
  const d = M.buildConfig({ hfWarn: "abc", hfCritical: "", priceChain: "99", notify: "FALSE", cooldownMin: "x" })
  assert.equal(d.alert.warn, 1.4); assert.equal(d.alert.critical, 1.3); assert.equal(d.priceChain, 1); assert.equal(d.notify, false); assert.equal(d.alert.cooldownMs, 30 * 60000)
})

ok("positions endpoint answering null (its reply for a wallet with none) means none open, not unavailable", () => {
  const w = world(), orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (/positions/.test(urls[i]) ? "null" : b))
  const out = M.main(w.io, args({ wallet: DEAD }), NOW); assert(/^Positions  none open/m.test(out), out)
})
ok("a null body from any other endpoint is a failure, not an empty answer (lend keeps its last value)", () => {
  const w = world(); M.main(w.io, args({ wallet: DEAD }), NOW)
  const w2 = world(); Object.assign(w2.io, { readFile: p => (p in w.files ? w.files[p] : null), writeFile: (p, t) => { w.files[p] = t } }); const orig = w2.io.fetchAll
  w2.io.fetchAll = urls => orig(urls).map((b, i) => (/mm\/lend/.test(urls[i]) ? "null" : b))
  const out = M.main(w2.io, args({ wallet: DEAD }), NOW + 60e3)
  assert(out.split("\n")[0].includes("HF 1.90"), out.split("\n")[0]); assert(!out.includes("∞  no debt"))
})
// ---- several wallets ----
const W1 = "0x" + "1".repeat(40), W2 = "0x" + "2".repeat(40), W3 = "0x" + "3".repeat(40)
const sh = w => w.slice(0, 6) + "…" + w.slice(-4)
const share = (w, w2) => Object.assign(w2.io, { readFile: p => (p in w.files ? w.files[p] : null), writeFile: (p, t) => { w.files[p] = t } })
const lendCalls = (w, addr) => w.calls.flat().filter(u => u.includes("/mm/lend?user=" + addr) && !u.includes("chainId=143")).length
ok("wallet list parsing: commas, spaces, duplicates, junk", () => {
  const p = M.parseWallets(" " + W1 + ", " + W2.toUpperCase().replace("0X", "0x") + ";" + W1 + "\n0x12 ")
  assert.deepEqual(p.list, [W1, W2]); assert.deepEqual(p.bad, ["0x12"])
})
ok("two wallets: title names the shown one with the switch sign, one minute later the next one", () => {
  const w = world(); let out = M.main(w.io, args({ wallet: W1 + ", " + W2 }), NOW)
  assert.deepEqual(validate(out), [])
  assert(out.split("\n")[0].includes(sh(W1) + " ⇄"), out.split("\n")[0])
  assert(/^Next wallet ⇄ \| .*param1=next/m.test(out), "next-wallet action")
  assert(out.includes("Showing " + sh(W1) + "  (1 of 2)"))
  assert(w.calls.flat().some(u => u.includes("walletAddress=" + W1)) && !w.calls.flat().some(u => u.includes("walletAddress=" + W2)))
  assert.equal(lendCalls(w, W2), 1, "hidden wallet's health is read too")
  out = M.main(w.io, args({ wallet: W1 + ", " + W2 }), NOW + 20e3); assert(out.split("\n")[0].includes(sh(W1)), "a manual refresh does not rotate")
  out = M.main(w.io, args({ wallet: W1 + ", " + W2 }), NOW + 60e3); assert(out.split("\n")[0].includes(sh(W2)))
  out = M.main(w.io, args({ wallet: W1 + ", " + W2 }), NOW + 120e3); assert(out.split("\n")[0].includes(sh(W1)))
})
ok("Next wallet and a click on a wallet in the list switch at once", () => {
  const w = world(), a3 = W1 + "," + W2 + "," + W3
  M.main(w.io, args({ wallet: a3 }), NOW)
  let out = M.main(w.io, args({ wallet: a3, cmd: "next" }), NOW + 5e3); assert(out.split("\n")[0].includes(sh(W2)))
  out = M.main(w.io, args({ wallet: a3, cmd: "show", arg: W1 }), NOW + 9e3); assert(out.split("\n")[0].includes(sh(W1)))
  assert(new RegExp("^--● " + sh(W1) + "  \\(shown\\) \\|.*param1=show param2=" + W1, "m").test(out), "list marks the shown wallet")
  assert(new RegExp("^--○ " + sh(W3) + " \\|.*param2=" + W3, "m").test(out))
})
ok("a hidden wallet going low: shown in the same run, named in the alert, kept while low; a peek comes back", () => {
  let hf2 = 1.9
  const w = world({ hfBy: { [W2]: () => hf2 } }), A = args({ wallet: W1 + ", " + W2 })
  M.main(w.io, A, NOW); assert.equal(w.notes.length, 0)
  hf2 = 1.36
  let out = M.main(w.io, A, NOW + 20e3)                    // debt: read every run, no rotation yet
  assert(out.split("\n")[0].includes(sh(W2)), "jumped to the low wallet"); assert(out.split("\n")[0].includes("HF 1.36"))
  assert.equal(w.notes.length, 1); assert(w.notes[0].b.startsWith(sh(W2) + ": Sonic HF 1.36"), w.notes[0].b)
  out = M.main(w.io, A, NOW + 80e3); assert(out.split("\n")[0].includes(sh(W2)), "stays while low"); assert.equal(w.notes.length, 1)
  out = M.main(w.io, Object.assign({}, A, { cmd: "next" }), NOW + 90e3); assert(out.split("\n")[0].includes(sh(W1)), "peek")
  out = M.main(w.io, A, NOW + 150e3); assert(out.split("\n")[0].includes(sh(W2)), "back to the low wallet")
  hf2 = 2.5; M.main(w.io, A, NOW + 160e3); out = M.main(w.io, A, NOW + 220e3); assert(out.split("\n")[0].includes(sh(W1)), "rotation resumes")
})
ok("hidden wallets without debt are read every 10 minutes, not every minute", () => {
  const w = world(), orig = w.io.fetchAll
  w.io.fetchAll = urls => orig(urls).map((b, i) => (urls[i].includes("/mm/lend?user=" + W2) && !urls[i].includes("143") ? JSON.stringify({ data: { chains: [{ chainId: 146, userMetrics: { totalDebtUsd: 0, healthFactor: 0 } }] } }) : b))
  const A = args({ wallet: W1 + "," + W2 })
  M.main(w.io, A, NOW); M.main(w.io, A, NOW + 20e3); M.main(w.io, A, NOW + 40e3)
  assert.equal(lendCalls(w, W2), 1)
})
ok("Add a wallet, Edit wallets, Remove: saved in the wallet file, one per line", () => {
  let w = world({ prompt: W2 }); w.files["/w/wallet"] = W1
  M.main(w.io, args({ cmd: "add" }), NOW); assert.equal(w.files["/w/wallet"], W1 + "\n" + W2)
  let out = M.main(w.io, args({}), NOW); assert(out.includes("(1 of 2)")); assert(/^--Add a wallet… \| .*param1=add/m.test(out)); assert(/^--Remove 0x1111…1111 \| .*param1=remove param2=0x1/m.test(out))
  M.main(w.io, args({ cmd: "remove", arg: W1 }), NOW); assert.equal(w.files["/w/wallet"], W2)
  w = world({ prompt: W3 + ", " + W1 }); M.main(w.io, args({ cmd: "wallet" }), NOW); assert.equal(w.files["/w/wallet"], W3 + "\n" + W1)
  w = world({ prompt: W3 + ", junk" }); M.main(w.io, args({ cmd: "wallet" }), NOW); assert(!("/w/wallet" in w.files)); assert(w.notes[0].alert.includes("junk"))
})
ok("wallets from VAR_WALLET: the menu says so instead of offering add/edit/remove that would not apply", () => {
  const w = world(), out = M.main(w.io, args({ wallet: W1 + "," + W2 }), NOW)
  assert(!/param1=(add|wallet|remove)/.test(out)); assert(out.includes("come from the plugin settings (VAR_WALLET)"))
  assert(/param1=show param2=/.test(out) && /param1=next/.test(out), "showing and switching still work")
})
ok("an upgrade from 1.0.x keeps the wallet's alert state (no second notification)", () => {
  const w = world({ hf: 1.38 })
  w.files["/s/state.json"] = JSON.stringify({ v: 1, wallet: DEAD.toLowerCase(), cache: {}, alert: { level: 1, last: { 1: NOW - 60e3 } } })
  M.main(w.io, args({ wallet: DEAD }), NOW); assert.equal(w.notes.length, 0)
})
ok("dropdown: three submenus (Market, Account, Positions) and nothing else long at the top level", () => {
  const w = world(), out = M.main(w.io, args({ wallet: DEAD }), NOW), top = out.split("\n").filter(l => !l.startsWith("-"))
  assert(top.some(l => l.startsWith("Market ")) && top.some(l => l.startsWith("Account ")) && top.some(l => l.startsWith("Positions ")))
  assert(top.length <= 10, top.length + " top-level lines:\n" + top.join("\n"))
})

// ---- anonymous usage stats ----
const ev = w => w.posts.map(a => ({ args: a, body: JSON.parse(a[a.indexOf("-d") + 1]) }))
const named = (w, n) => ev(w).filter(e => e.body.name === n)
const S = o => args(Object.assign({ analytics: "true" }, o))
ok("usage stats: one pageview a day with platform-level values only, browser-like user agent, Plausible's API", () => {
  const w = world(); M.main(w.io, S({ wallet: W1 + "," + W2 }), NOW)
  const pv = named(w, "pageview"); assert.equal(pv.length, 1)
  assert.deepEqual(pv[0].body, { name: "pageview", url: "app://widget/macos", domain: "widget",
    props: { platform: "macos", version: M.WIDGET_VERSION, os: "macOS 15", host: "xbar", walletsConfigured: "2" } })
  const a = pv[0].args
  assert.equal(a[0], "/usr/bin/curl"); assert(a.includes("https://plausible.io/api/event")); assert.equal(a[a.indexOf("-m") + 1], "10")
  assert(/^Mozilla\/5\.0 \(Macintosh; Intel Mac OS X 10_15_7\) FlyingTulipWidget\/\d/.test(a[a.indexOf("-A") + 1]))
  M.main(w.io, S({ wallet: W1 + "," + W2 }), NOW + 3600e3); assert.equal(named(w, "pageview").length, 1, "once a day")
  M.main(w.io, S({ wallet: W1 + "," + W2 }), NOW + 25 * 3600e3); assert.equal(named(w, "pageview").length, 2)
  for (const e of ev(w)) assert(!/0x[0-9a-f]{40}/i.test(JSON.stringify(e.args)), "address sent: " + JSON.stringify(e.body))
})
ok("usage stats: every link runs the plugin with its element id; the click is counted (address removed), then the page opens", () => {
  const w = world(), out = M.main(w.io, S({ wallet: DEAD }), NOW)
  assert.deepEqual(validate(out), []); assert(!/ href=/.test(out.split("\n").slice(1).join("\n")), "no plain href while stats are on")
  const ids = [...out.matchAll(/param1=open param2=([a-z0-9-]+) param3=(\S+)/g)].map(m => m[1])
  for (const id of ["header-title", "header-open-site", "market-ft-price", "market-fees", "market-fees-chart", "market-price-chart", "market-header",
    "account-hf", "account-hf-sonic", "account-pnl", "account-ft-earned", "account-points", "account-ftput", "account-header", "positions-row", "positions-header", "footer-disclaimer"])
    assert(ids.includes(id), "missing element " + id)
  M.main(w.io, S({ cmd: "open", arg: "account-pnl", arg2: "https://flyingtulip.com/trade/portfolio/?a=" + DEAD }), NOW)
  const lc = named(w, "Link click"); assert.equal(lc.length, 1)
  assert.deepEqual(lc[0].body.props, { platform: "macos", version: M.WIDGET_VERSION, element: "account-pnl", url: "https://flyingtulip.com/trade/portfolio/?a=:address" })
  assert.deepEqual(w.opened, ["https://flyingtulip.com/trade/portfolio/?a=" + DEAD], "the real page still opens")
  M.main(w.io, S({ cmd: "open", arg: "x", arg2: "https://evil.example/" }), NOW); assert.equal(w.opened.length, 1, "only flyingtulip.com")
})
ok("usage stats: switch, refresh, settings, wallet added and removed, HF alert, fetch errors once an hour, 30 per hour cap", () => {
  const w = world({ hf: 1.28, prompt: W2 }), A = o => S(Object.assign({}, o))
  M.main(w.io, A({ cmd: "add" }), NOW); M.main(w.io, A({}), NOW); M.main(w.io, A({ cmd: "next" }), NOW + 1e3)
  M.main(w.io, A({ cmd: "refresh" }), NOW + 2e3); M.main(w.io, A({ cmd: "remove", arg: W2 }), NOW + 3e3)
  for (const n of ["Settings open", "Wallet added", "Wallet switch", "Refresh", "Wallet removed"]) assert.equal(named(w, n).length, 1, n)
  assert.deepEqual(named(w, "HF alert shown")[0].body.props.level, "danger")
  const w2 = world({ fail: ["/points?walletAddress"] })
  M.main(w2.io, S({ wallet: DEAD }), NOW); M.main(w2.io, S({ wallet: DEAD }), NOW + 60e3)
  assert.equal(named(w2, "Fetch error").length, 1); assert.equal(named(w2, "Fetch error")[0].body.props.endpoint, "points")
  M.main(w2.io, S({ wallet: DEAD }), NOW + 3700e3); assert.equal(named(w2, "Fetch error").length, 2)
  const w3 = world(); for (let i = 0; i < 40; i++) M.main(w3.io, S({ cmd: "open", arg: "header-title", arg2: "https://flyingtulip.com/" }), NOW + i)
  assert.equal(named(w3, "Link click").length, 30); assert.equal(w3.opened.length, 40, "pages open regardless of the cap")
})
ok("usage stats off (VAR_ANALYTICS=false, or the Advanced switch): nothing is sent, links are plain", () => {
  for (const mk of [() => ({ w: world({ prompt: W2 }), a: o => args(o) }), () => { const w = world({ prompt: W2 }); M.main(w.io, S({ cmd: "stats" }), NOW); return { w, a: o => S(o) } }]) {
    const { w, a } = mk()
    let out = M.main(w.io, a({ wallet: DEAD }), NOW)
    assert(out.includes("href=https://flyingtulip.com/statistics/"))
    M.main(w.io, a({ cmd: "open", arg: "header-title", arg2: "https://flyingtulip.com/" }), NOW); M.main(w.io, a({ cmd: "add" }), NOW)
    M.main(w.io, a({ cmd: "next" }), NOW); M.main(w.io, a({ cmd: "refresh" }), NOW)
    assert.equal(w.posts.length, 0); assert.equal(w.opened.length, 1)
  }
  const w = world(); M.main(w.io, S({ cmd: "stats" }), NOW); let out = M.main(w.io, S({}), NOW)
  assert(/^----Anonymous usage stats: off \(click to turn on\) \|.*param1=stats/m.test(out), "Settings > Advanced shows the switch")
  M.main(w.io, S({ cmd: "stats" }), NOW); out = M.main(w.io, S({}), NOW + 1)
  assert(/^----Anonymous usage stats: on \(click to turn off\)/m.test(out)); assert.equal(named(w, "pageview").length, 1)
})
// ---- the plugin file itself ----
ok("plugin file: executable, bash shebang, required xbar metadata, refresh in filename, bash -n", () => {
  const { PLUGIN } = require("./load"), src = fs.readFileSync(PLUGIN, "utf8")
  assert(/^#!\/usr\/bin\/env bash\n/.test(src)); assert(fs.statSync(PLUGIN).mode & 0o111); assert(/\.1m\.sh$/.test(PLUGIN))
  for (const t of ["xbar.title", "xbar.version", "xbar.author", "xbar.author.github", "xbar.desc", "xbar.dependencies", "xbar.abouturl"])
    assert(new RegExp("<" + t + ">[^<]+</" + t + ">").test(src), t)
  const vars = [...src.matchAll(/<xbar\.var>(string|number|boolean|select)\((VAR_[A-Z_]+)=("[^"]*"|[^)]*)\): .+<\/xbar\.var>/g)]
  assert.equal(vars.length, 7); assert(src.includes("<swiftbar.environment>"))
  for (const v of vars) assert(src.includes("${" + v[2] + ":-"), v[2] + " is not passed to the script")
  cp.execFileSync("bash", ["-n", PLUGIN])
  assert(!/dev\.|opbalance|api\.galaxy|0x[0-9a-fA-F]{40}/.test(src.replace(/\$\{[^}]*\}/g, "")), "scrub")
})
console.log("\n" + passed + " passed")

if (process.env.LIVE) {
  const curlIO = {
    fetchAll: urls => urls.map(u => { const r = cp.spawnSync("curl", ["-fsS", "-m", "15", u], { encoding: "utf8", maxBuffer: 1 << 28 }); return r.status === 0 ? r.stdout : null }),
    readFile: () => null, writeFile: () => {}, notify: (t, b) => console.error("NOTIFY", t, b), prompt: () => null, alert: () => {}
  }
  const out = M.main(curlIO, args({ wallet: process.env.WALLET || "" }), Date.now())
  const errs = validate(out); console.log(out.replace(/image=\S{40,}/g, "image=<base64>")); console.log("\nformat errors:", errs)
  if (errs.length) process.exit(1)
}
