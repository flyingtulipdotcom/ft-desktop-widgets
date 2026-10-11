-- lua5.1 test/run.lua   (Rainmeter embeds Lua 5.1)
-- Loads the skin the way Rainmeter does (test/rainmeter.lua: Main.ini + includes, the script environment, SKIN set
-- only after the chunk runs, WebParser fetch/FinishAction, bangs, InputText) and drives it with recorded payloads.
-- FT_SKIN_DIR=<dir> runs the same tests against another copy of the skin (e.g. the v1.0.0 release).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local RM = require("rainmeter")
local FIX = here .. "/fixtures"
local SRC = os.getenv("FT_SKIN_DIR") or (here .. "/../Skins/FlyingTulip")
local TMP = os.tmpname(); os.remove(TMP); os.execute("mkdir -p " .. TMP)
local DEAD = "0x000000000000000000000000000000000000dEaD"

local passed, failed = 0, 0
local function ok(name, fn)
  local good, err = pcall(fn)
  if good then passed = passed + 1; print("ok    " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end
local function has(s, sub, msg) if not tostring(s):find(sub, 1, true) then error((msg or "") .. " missing [" .. sub .. "] in [" .. tostring(s) .. "]", 2) end end

local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function writeFile(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function fixture(n) return assert(readFile(FIX .. "/" .. n), n) end

-- frozen clock (the script reads os.time through _G)
local clock = 1790000000
local realTime = os.time
os.time = function(...) if select("#", ...) > 0 then return realTime(...) end return clock end

-- ---------------------------------------------------------------- fake API
local function lendJson(hf)
  return string.format([[{"data":{"chains":[{"chainId":146,"hfLiquidationThreshold":1.25,"userMetrics":{"totalDebtUsd":1000,"healthFactor":%s,"equityUsd":500}},
    {"chainId":1,"userMetrics":{"totalDebtUsd":0,"healthFactor":0,"equityUsd":25}}]}}]], tostring(hf))
end
local NO_DEBT = '{"data":{"chains":[{"chainId":146,"hfLiquidationThreshold":1.25,"userMetrics":{"totalDebtUsd":0,"healthFactor":0,"equityUsd":5}}]}}'
local function leaderboard(page, myRank, myPts)
  local rows = {}
  for r = (page - 1) * 500 + 1, math.min(page * 500, 2000) do
    local w = (r == myRank) and DEAD or string.format("0x%040d", r)
    rows[#rows + 1] = string.format('{"rank":%d,"userWallet":"%s","totalPoints":%d}', r, w, (r == myRank) and myPts or (1000000 - r * 100))
  end
  return string.format('{"data":{"pagination":{"page":%d,"limit":500,"total":2000},"leaderboard":[%s]}}', page, table.concat(rows, ","))
end
local ACCOUNT = {
  lend = function() return fixture("lend.json") end,                      -- real shape, Sonic HF 1.90 on $1000 debt
  lend143 = '{"code":200,"success":true,"data":{"chains":[],"stale":true}}',
  sum146 = '[{"chainId":146,"unrealizedPnl":"12.5"}]', sum1 = '[{"chainId":1,"unrealizedPnl":"-2"}]',
  sum56 = '[{"chainId":56,"unrealizedPnl":"0"}]', sum143 = '{"error":"no spot indexer configured for chainId 143","success":false}',
  rewards = '{"success":true,"data":{"chains":[{"chainId":146,"staking":{"pending_yield_ft":"3000000000000000000","claimed_yield_ft":"100000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false}}]}}',
  pos146 = '[{"chainId":146,"network":"Sonic","symbol":"wS-ftUSD","sizeCurrency":"wS","side":"long","size":"1000","markPrice":"0.05","pnlAmount":"5","blendedLeverage":"3"}]',
  pos1 = "[]", pos56 = "[]",
  puts = '{"data":{"positions":[{"nft_id":"7","token_symbol":"USDT","token_decimals":6,"strike":"99960146","current_capital":"1000000000","current_ft":"9996014600000000000000","withdrawn_ft":"0"}]}}',
  points = '{"data":{"chains":[{"isAllChains":true,"userMetrics":{"totalPoints":922000}}]}}',
}
local function keyFor(url)
  if url:find("/mm/spot/tickers", 1, true) then return "price" end
  if url:find("period=1d", 1, true) then return "fees" end
  if url:find("period=1m", 1, true) then return "feesSeries" end
  if url:find("/klines", 1, true) then return "klines" end
  if url:find("/mm/lend", 1, true) then return url:find("chainId=143", 1, true) and "lend143" or "lend" end
  local c = url:match("/account/summary%?.*chainId=(%d+)"); if c then return "sum" .. c end
  c = url:match("/account/positions%?.*chainId=(%d+)"); if c then return "pos" .. c end
  if url:find("/account/dashboard", 1, true) then return "rewards" end
  if url:find("/points/leaderboard", 1, true) then return "rank" end
  if url:find("/points?", 1, true) then return "points" end
  if url:find("/tge/ftPUT/user/", 1, true) then return "puts" end
  error("unexpected URL " .. url)
end
local MARKET = { price = "tickers.json", fees = "fees.json", feesSeries = "fees_series.json", klines = "klines.json" }
-- api(overrides): key -> body string | function(url) | false (connection error)
local function api(over, log)
  return function(url)
    assert(url:find("^https://api%.flyingtulip%.com/"), url)
    assert(not url:find("#", 1, true), "unresolved variable in " .. url)
    local k = keyFor(url)
    if log then log[#log + 1] = k end
    local v = over and over[k]
    if v == nil then v = MARKET[k] and fixture(MARKET[k]) or ACCOUNT[k] end
    if type(v) == "function" then v = v(url) end
    if v == false then return nil end
    return v
  end
end

-- ---------------------------------------------------------------- skin under test
local n = 0
local function freshDir(vars)
  n = n + 1
  local d = TMP .. "/skin" .. n
  os.execute("cp -r '" .. SRC .. "' '" .. d .. "' && rm -rf '" .. d .. "/DownloadFile' '" .. d .. "/@Resources/State.txt' '" .. d .. "/@Resources/Notify.txt'")
  local s = readFile(d .. "/@Resources/Settings.inc")
  for k, v in pairs(vars or {}) do s = s:gsub("\n" .. k .. "=[^\r\n]*", "\n" .. k .. "=" .. v) end
  writeFile(d .. "/@Resources/Settings.inc", s)
  return d
end
local function boot(vars, over, opt)
  local d = (opt and opt.dir) or freshDir(vars)
  local log = {}
  local sk = RM.load(d, { http = api(over, log) })
  sk.fetched = log
  return sk:start()
end
local function settle(sk, rounds) for _ = 1, rounds or 3 do sk:deliver(); sk:tick() end; sk:deliver() end
local function noErrors(sk) local e = sk:errors(); if #e > 0 then error(table.concat(e, "\n      "), 2) end end
local function T(sk) return assert(sk.script and sk.script.env and sk.script.env.FT_TEST, "script did not load") end

-- ---------------------------------------------------------------- the v1.0.0 failure, as Rainmeter runs it
ok("Rainmeter load order: no script error, the market rows replace 'loading...'", function()
  local sk = boot({})
  noErrors(sk)
  settle(sk)
  noErrors(sk)
  has(sk:text("MeterStatus"), "updated"); has(sk:text("MeterPriceVal"), "$0."); has(sk:text("MeterFeesVal"), "$")
  has(sk:text("MeterFeesChartLabel"), "31 days"); has(sk:text("MeterPriceChartLabel"), "30 days")
end)
ok("Set wallet: the button opens the box, Enter saves the wallet and refreshes, the account fills in", function()
  local sk = boot({}); settle(sk)
  sk:exec(sk:option("MeterBtnWallet", "LeftMouseUpAction"))
  assert(sk.input, "input box opened"); has(sk:text("MeterBanner"), "Paste a wallet")
  sk:typeInput("  " .. DEAD .. "  ")
  noErrors(sk)
  eq(sk.refreshed, 1, "skin refreshed")
  has(readFile(sk.dir .. "/@Resources/Settings.inc"), "\nWallet=" .. DEAD:lower() .. "\n")
  local again = boot(nil, nil, { dir = sk.dir }); settle(again)
  noErrors(again)
  has(again:text("MeterSub"), "0x0000"); has(again:text("MeterHfVal"), "1.90  Sonic")
end)
ok("Set wallet from the right-click menu, and Escape puts the banner back", function()
  local sk = boot({}); settle(sk)
  sk:exec(sk:option("Rainmeter", "ContextAction")); assert(sk.input, "input box opened")
  sk:dismissInput(); noErrors(sk); eq(sk:text("MeterBanner"), nil); eq(sk.refreshed, 0)
end)

-- ---------------------------------------------------------------- JSON decoder
ok("json: scalars, nesting, escapes, unicode, big input, skipped keys", function()
  local t = T(boot({}))
  local j = t.jsonDecode('{"a":[1,2.5,-3e2,true,false,null,"x\\n\\"y\\u00e9\\ud83d\\ude00"],"b":{"c":{}},"d":"0.150151694355331498"}')
  eq(j.a[1], 1); eq(j.a[2], 2.5); eq(j.a[3], -300); eq(j.a[4], true); eq(j.a[5], false); eq(j.a[7], 'x\n"y\195\169\240\159\152\128')
  eq(type(j.b.c), "table"); eq(j.d, "0.150151694355331498")
  eq(t.jsonDecode("{"), nil); eq(t.jsonDecode('{"a":1} x'), nil); eq(t.jsonDecode(""), nil); eq(t.jsonDecode(nil), nil); eq(t.jsonDecode("[1,]"), nil)
  local big = {}
  for i = 1, 20000 do big[#big + 1] = '{"i":' .. i .. ',"s":"row ' .. i .. '"}' end
  local d = t.jsonDecode("[" .. table.concat(big, ",") .. "]"); eq(#d, 20000); eq(d[20000].s, "row 20000")
  local s = t.jsonDecode('{"keep":1,"drop":{"x":[1,{"y":"a\\"]}"}],"z":null},"also":2}', { drop = true })
  eq(s.keep, 1); eq(s.drop, nil); eq(s.also, 2)
  eq(t.jsonDecode('{"drop":[1,2', { drop = true }), nil)
end)
ok("json: the recorded API payloads decode", function()
  local t = T(boot({}))
  for _, f in ipairs({ "tickers.json", "fees.json", "fees_series.json", "klines.json", "lend.json" }) do assert(t.jsonDecode(fixture(f)), f) end
end)
ok("a 500 KB /mm/lend body: series and assets are skipped, the health factor survives", function()
  local t = T(boot({}))
  local raw = fixture("lend.json")
  local point = '{"timestamp":1790000000,"value":1.2345678901234567}'
  local pad = string.rep(point .. ",", 3000) .. point
  local big = raw:gsub('"totalDeposited":%[', '"totalDeposited":[' .. pad .. ",")
  assert(#big > 450000, "padded to " .. #big)
  local LEND_SKIP = { series = true, assets = true, userTransactions = true, marketsSummary = true, circuitBreakerParams = true, chainData = true, globalMetrics = true }
  local t0 = os.clock(); local full = t.jsonDecode(big); local tFull = os.clock() - t0
  t0 = os.clock(); local lean = t.jsonDecode(big, LEND_SKIP); local tLean = os.clock() - t0
  assert(full and lean, "both decode")
  local l = t._parse.lend(lean); local c146
  for _, c in ipairs(l) do if c.chainId == 146 then c146 = c end end
  eq(c146.hf, 1.9); eq(c146.liqHf, 1.25); eq(lean.data.chains[1].series, nil)
  print(string.format("      %d bytes: full decode %.0f ms, with skips %.0f ms", #big, tFull * 1000, tLean * 1000))
end)

-- ---------------------------------------------------------------- formatting and parsers
ok("formatters match the other widgets", function()
  local t = T(boot({}))
  eq(t._fmt.hf(150), ">100"); eq(t._fmt.hf(1.2345), "1.23")
  eq(t._fmt.usd(1152.98), "$1.15k"); eq(t._fmt.signed(-5), "-$5.00"); eq(t._fmt.price(0.15015), "$0.1502")
  eq(t._fmt.ft(470.83), "470.8"); eq(t._fmt.points(1234567), "1.2M"); eq(t._fmt.pct(-3.456), "-3.5%"); eq(t._fmt.thousands(1234567), "1,234,567")
  eq(t._fmt.wallet(" " .. DEAD .. " "), DEAD:lower()); eq(t._fmt.wallet("0x123"), "")
end)
ok("price is the FT-ftUSD market mark", function()
  local t = T(boot({}))
  local p = t._parse.price(t.jsonDecode(fixture("tickers.json"))); assert(p and p.price > 0 and p.price < 10)
  eq(t._parse.price({ data = { tickers = { { display_symbol = "WBTC-ftUSD", price = "1" } } } }), nil)
end)
ok("fees, series, klines", function()
  local t = T(boot({}))
  local f = t._parse.fees(t.jsonDecode(fixture("fees.json"))); assert(f.period24h >= 0 and #f.products > 0)
  eq(#t._parse.feesSeries(t.jsonDecode(fixture("fees_series.json"))), 31); eq(#t._parse.klines(t.jsonDecode(fixture("klines.json"))), 30)
end)
ok("rawUnits and ftPUT gain use FT market price", function()
  local t = T(boot({}))
  assert(math.abs(t._fmt.rawUnits("9996014600000000000000", 18) - 9996.0146) < 1e-9)
  local puts = t._parse.puts(t.jsonDecode(ACCOUNT.puts))
  eq(puts.count, 1); assert(math.abs(puts.costUsd - 999.60146) < 1e-6)
  local g = t._putGain(puts, 0.15); assert(math.abs(g.gainUsd - (9996.0146 * 0.15 - 999.60146)) < 1e-6)
  eq(t._parse.puts(t.jsonDecode('{"data":{"positions":null}}')), nil)
end)
ok("rewards: total FT, unknown when a section errored", function()
  local t = T(boot({}))
  local r = t._parse.rewards(t.jsonDecode('{"success":true,"data":{"chains":[{"chainId":146,"staking":{"pending_yield_ft":"3000000000000000000","claimed_yield_ft":"100000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false},"lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"50000000000000000000","pendingFtRaw":"0"}}}}]}}'))
  assert(math.abs(r.totalFt - 153) < 1e-9); assert(math.abs(r.claimableFt - 3) < 1e-9)
  eq(t._parse.rewards(t.jsonDecode('{"success":true,"data":{"sectionErrors":{"lend":true},"chains":[{"chainId":146}]}}')).totalFt, nil)
end)
-- Two real wallet shapes (addresses removed): the smaller one claimed sftUSD yield months ago, the larger one only
-- supplies Lend and earns small rewards whose raw amounts have 17 digits (0.01 to 0.1 FT).
local SMALL_REWARDS = '{"success":true,"data":{"chains":[' ..
  '{"chainId":1,"staking":{"pending_yield_ft":"0","claimed_yield_ft":"0","claimed_yield_indexed_through_block":26165977},"lend":{"userMetrics":{"ftRewards":null,"ftRewardsError":null}}},' ..
  '{"chainId":146,"staking":{"pending_yield_ft":"0","claimed_yield_ft":"95386787178560501045","claimed_yield_indexed_through_block":80722469},"lend":{"userMetrics":{"ftRewards":null}}}]}}'
local LARGE_REWARDS = '{"success":true,"data":{"chains":[' ..
  '{"chainId":1,"staking":{"pending_yield_ft":"0","claimed_yield_ft":"0","claimed_yield_indexed_through_block":26165977},"lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"0","pendingFtRaw":"60167126473248989"}}}},' ..
  '{"chainId":146,"staking":{"pending_yield_ft":"0","claimed_yield_ft":"0","claimed_yield_indexed_through_block":80722469},"lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"743020047575476813","pendingFtRaw":"59654073282058744"}}}}]}}'
local POINTS_2CHAINS = '{"data":{"chains":[' ..
  '{"chainData":{"id":146,"name":"Sonic"},"isAllChains":false,"userMetrics":{"totalPoints":45757.02690673988}},' ..
  '{"chainData":{"id":1,"name":"Ethereum"},"isAllChains":false,"userMetrics":{"totalPoints":616132.7877936237}},' ..
  '{"chainData":{"id":56,"name":"BNB Smart Chain"},"isAllChains":false,"userMetrics":{"totalPoints":0}},' ..
  '{"chainData":null,"isAllChains":true,"userMetrics":{"totalPoints":661889.8147003637}}]}}'
ok("rewards: the breakdown explains a smaller wallet with more FT earned (sftUSD yield) than a larger one (Lend)", function()
  local t = T(boot({}))
  local s = t._parse.rewards(t.jsonDecode(SMALL_REWARDS))
  assert(math.abs(s.totalFt - 95.386787178560501) < 1e-9); assert(math.abs(s.sftClaimed - s.totalFt) < 1e-12); eq(s.lendFt, 0)
  local l = t._parse.rewards(t.jsonDecode(LARGE_REWARDS))
  assert(math.abs(l.totalFt - (0.060167126473248989 + 0.743020047575476813 + 0.059654073282058744)) < 1e-12, l.totalFt)
  assert(math.abs(l.lendPending - 0.119821199755307733) < 1e-12); eq(l.sftFt, 0)
  eq(t._fmt.ft(l.totalFt), "0.86"); eq(t._fmt.ft(s.totalFt), "95.4")
  local tip = t._tips.earned(s)
  has(tip, "sftUSD yield 95.4 FT (claimed 95.4, pending 0)"); has(tip, "Lend FT rewards 0 FT"); has(tip, "By chain: Sonic 95.4.")
  has(t._tips.earned(l), "By chain: Ethereum 0.06, Sonic 0.80.")
end)
ok("points: all-chains total plus each chain, largest first", function()
  local t = T(boot({}))
  local p = t._parse.points(t.jsonDecode(POINTS_2CHAINS))
  assert(math.abs(p.total - 661889.8147003637) < 1e-6); eq(#p.chains, 2); eq(p.chains[1].name, "Ethereum"); eq(p.chains[2].name, "Sonic")
  local tip = t._tips.points(p, { rank = 1715, total = 6789 })
  has(tip, "Total over all chains: Ethereum 616K, Sonic 45.8K."); has(tip, "rank 1,715 of 6,789"); has(tip, "one chain at a time")
end)
ok("FT earned and points rows say what they cover, with the breakdown on hover", function()
  local sk = boot({ Wallet = DEAD }, { rewards = SMALL_REWARDS, points = POINTS_2CHAINS }); settle(sk); noErrors(sk)
  eq(sk:text("MeterEarnLbl"), "FT earned, all time"); eq(sk:text("MeterPointsLbl"), "Points, all chains")
  has(sk:text("MeterEarnVal"), "95.4 FT"); has(sk:option("MeterEarnVal", "ToolTipText"), "sftUSD yield 95.4 FT")
  has(sk:text("MeterPointsVal"), "662K"); has(sk:option("MeterPointsLbl", "ToolTipText"), "Ethereum 616K, Sonic 45.8K")
  eq(sk:option("MeterEarnVal", "ToolTipWidth"), "320")
end)
ok("lend: no debt is infinity, lowest across chains", function()
  local t = T(boot({}))
  local l = t._mergeChains({ t._parse.lend(t.jsonDecode(lendJson(1.8))), t._parse.lend(t.jsonDecode('{"data":{"chains":[{"chainId":56,"userMetrics":{"totalDebtUsd":50,"healthFactor":1.33}}]}}')) })
  eq(#l, 3); eq(t._lowestHf(l).name, "BNB"); eq(t._lowestHf({ l[2] }), nil)
end)
ok("alert state machine: once per crossing, hysteresis, cooldown", function()
  local t = T(boot({}))
  local cfg = { warn = 1.4, critical = 1.3, cooldownSec = 1800 }
  local function e(hf) return { hf = hf, name = "Sonic", liqHf = 1.25 } end
  local st, nt = { level = 0 }, nil
  st, nt = t._alert.decideNotify(st, e(2), cfg, 0); assert(not nt)
  st, nt = t._alert.decideNotify(st, e(1.39), cfg, 1); assert(nt and nt.level == 1)
  st, nt = t._alert.decideNotify(st, e(1.38), cfg, 2); assert(not nt)
  st, nt = t._alert.decideNotify(st, e(1.29), cfg, 3); assert(nt and nt.level == 2)
  st, nt = t._alert.decideNotify(st, e(1.33), cfg, 4); assert(not nt and st.level == 2)
  st, nt = t._alert.decideNotify(st, e(1.6), cfg, 5); assert(not nt and st.level == 0)
  st, nt = t._alert.decideNotify(st, e(1.39), cfg, 6); assert(not nt, "inside cooldown")
  st, nt = t._alert.decideNotify(st, e(1.2), cfg, 1900); assert(nt and nt.level == 2)
  st, nt = t._alert.decideNotify(st, nil, cfg, 1901); eq(st.level, 0)
  eq(t._alert.threshold("abc", 1.4), 1.4); eq(t._alert.threshold("1.5", 1.4), 1.5)
end)

-- ---------------------------------------------------------------- skin behaviour
ok("no wallet: market rows, hint, account measures stay disabled and never fetch", function()
  local sk = boot({}); settle(sk); noErrors(sk)
  has(sk:option("MeterFeesChart", "Shape2"), "Rectangle"); has(sk:option("MeterPriceChart", "Shape3"), "Path LinePath")
  has(sk:option("MeterPriceChart", "LinePath"), "LineTo")
  has(sk:text("MeterAccountHint"), "Add your wallet"); eq(sk:text("MeterHfVal"), nil)
  for _, k in ipairs(sk.fetched) do assert(MARKET[k], "fetched " .. k .. " without a wallet") end
end)
ok("wallet: every account row rendered from the fetched bodies", function()
  local sk = boot({ Wallet = DEAD }); settle(sk); noErrors(sk)
  has(sk:text("MeterHfVal"), "1.90  Sonic"); eq(sk:option("MeterHfVal", "FontColor"), "15,215,39,255")
  has(sk:text("MeterPnlVal"), "+$10.50"); has(sk:text("MeterEarnVal"), "103.0 FT")
  local t = T(sk); local px = t._parse.price(t.jsonDecode(fixture("tickers.json"))).price
  has(sk:text("MeterPutVal"), t._fmt.pct((9996.0146 * px - 999.60146) / 999.60146 * 100), "ftPUT uses the market price")
  has(sk:text("MeterPosHead"), "1 open"); has(sk:text("MeterPos1"), "wS long 3.0x"); has(sk:text("MeterPointsVal"), "922K")
  eq(sk:text("MeterAccountHint"), nil); has(sk:text("MeterSub"), "0x0000")
end)
ok("positions endpoint answering null (its reply for a wallet with none) means none open, not unavailable", function()
  local sk = boot({ Wallet = DEAD }, { pos146 = "null", pos1 = "null", pos56 = "null\n" }); settle(sk); noErrors(sk)
  eq(sk:text("MeterPosHead"), "Positions: none open")
end)
ok("no debt anywhere: the health factor shows the infinity sign and /mm/lend slows to every 10 minutes", function()
  local sk = boot({ Wallet = DEAD }, { lend = NO_DEBT }); settle(sk); noErrors(sk)
  eq(sk:text("MeterHfVal"), "<INF>  no debt")
  eq(sk:option("MeasureLend", "UpdateRate"), "600"); eq(sk.measures.measurelend.updateRate, 600)
  local before = 0; for _, k in ipairs(sk.fetched) do if k == "lend" then before = before + 1 end end
  sk:tick(300); sk:deliver()
  local after = 0; for _, k in ipairs(sk.fetched) do if k == "lend" then after = after + 1 end end
  eq(after, before, "no /mm/lend fetch for 5 minutes"); has(sk:text("MeterStatus"), "updated")
end)
ok("with debt, /mm/lend stays on the refresh interval", function()
  local sk = boot({ Wallet = DEAD }); settle(sk)
  eq(sk.measures.measurelend.updateRate, 60)
  local before = #sk.fetched; sk:tick(61); sk:deliver()
  local lends = 0; for i = before + 1, #sk.fetched do if sk.fetched[i] == "lend" then lends = lends + 1 end end
  eq(lends, 1)
end)
ok("every value the script writes to a meter is plain ASCII", function()
  local sk = boot({ Wallet = DEAD }, { lend = NO_DEBT }); settle(sk)
  for _, b in ipairs(sk:bangsNamed("!SetOption")) do
    for _, a in ipairs(b.args) do assert(not a:find("[\128-\255]"), "non-ASCII in " .. b.args[1] .. "." .. b.args[2]) end
  end
end)
ok("price and position meters link to their trade pages", function()
  local sk = boot({ Wallet = DEAD, PriceChainId = "146" }); settle(sk)
  eq(sk:option("MeterPriceVal", "LeftMouseUpAction"), '["https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=146&marketType=spot"]')
  eq(sk:option("MeterPriceChart", "LeftMouseUpAction"), sk:option("MeterPriceVal", "LeftMouseUpAction"))
  eq(sk:option("MeterPos1", "LeftMouseUpAction"), '["https://flyingtulip.com/trade/?symbol=wS-ftUSD&chainId=146&marketType=spot"]')
  eq(sk:option("MeterPos2", "LeftMouseUpAction"), '["https://flyingtulip.com/trade/portfolio/"]')
end)
ok("rank search: one forced fetch per page, late answers for an old page ignored, measure disabled after", function()
  local pages = {}
  local sk = boot({ Wallet = DEAD }, {
    points = '{"data":{"chains":[{"isAllChains":true,"userMetrics":{"totalPoints":922000}}]}}',
    rank = function(url) local p = tonumber(url:match("page=(%d+)")); pages[#pages + 1] = p; return leaderboard(p, 777, 922000) end })
  settle(sk, 8)
  noErrors(sk)
  has(sk:text("MeterPointsVal"), "922K  rank 777"); eq(pages[1], 7); eq(pages[2], 2)
  has(sk:option("MeterPointsVal", "ToolTipText"), "rank 777 of 2,000, all chains")
  assert(sk.measures.measurerank.disabled, "rank measure disabled again")
  -- a stale page arriving after the search moved on changes nothing
  local before = sk:text("MeterPointsVal"); sk.script.env.OnData("rank"); eq(sk:text("MeterPointsVal"), before)
  -- the measure does not refetch on its own while a search runs: UpdateRate is long, Update is forced per page
  eq(sk.measures.measurerank.updateRate, 3600)
end)
ok("warning state: border, banner and a toast, once", function()
  local hf = 1.38
  local sk = boot({ Wallet = DEAD }, { lend = function() return lendJson(hf) end }); settle(sk); noErrors(sk)
  has(sk:option("MeterBackground", "Shape"), "245,165,36"); has(sk:text("MeterBanner"), "HF 1.38"); eq(sk:option("MeterHfVal", "FontColor"), "245,165,36,255")
  local note = readFile(sk.res .. "Notify.txt"); has(note, "FT account health low"); has(note, "normal")
  eq(#sk.runs >= 1 and sk.runs[#sk.runs]:find("powershell.exe", 1, true) ~= nil, true, "powershell command issued")
  has(sk.runs[#sk.runs], sk.res .. "Notify.ps1")
  local count = function() local c = 0; for _, r in ipairs(sk.runs) do if r:find("powershell", 1, true) then c = c + 1 end end; return c end
  local before = count(); clock = clock + 60; sk:tick(60); sk:deliver(); eq(count(), before, "no repeat")
  hf = 1.28; clock = clock + 60; sk:tick(60); sk:deliver()
  has(sk:option("MeterBackground", "Shape"), "239,68,68"); has(readFile(sk.res .. "Notify.txt"), "critical")
end)
ok("notifications off: visual warning only", function()
  local sk = boot({ Wallet = DEAD, Notifications = "0" }, { lend = lendJson(1.2) }); settle(sk)
  has(sk:option("MeterBackground", "Shape"), "239,68,68"); eq(readFile(sk.res .. "Notify.txt"), nil)
end)
ok("alert state survives a skin refresh (no second toast inside the cooldown)", function()
  local sk = boot({ Wallet = DEAD }, { lend = lendJson(1.38) }); settle(sk)
  has(readFile(sk.res .. "State.txt"), "level=1"); os.remove(sk.res .. "Notify.txt")
  clock = clock + 120
  local again = boot(nil, { lend = lendJson(1.37) }, { dir = sk.dir }); settle(again)
  eq(readFile(again.res .. "Notify.txt"), nil)
end)
ok("a bad payload keeps the last good value; stale values are flagged", function()
  local bad = false
  local sk = boot({}, { price = function() return bad and "<html>502</html>" or fixture("tickers.json") end }); settle(sk)
  local price = sk:text("MeterPriceVal")
  bad = true; sk:tick(60); sk:deliver(); eq(sk:text("MeterPriceVal"), price)
  clock = clock + 60 * 5; sk:tick(60); sk:deliver(); has(sk:text("MeterStatus"), "stale")
end)
ok("nothing arrives: loading, then offline", function()
  local sk = boot({}); has(sk:text("MeterStatus"), "loading"); clock = clock + 30
  sk:tick(30); has(sk:text("MeterStatus"), "offline")
end)
ok("connection errors: offline as soon as WebParser reports them", function()
  local sk = boot({}, { price = false, fees = false, feesSeries = false, klines = false }); sk:deliver(); noErrors(sk)
  has(sk:text("MeterStatus"), "offline")
end)
ok("invalid wallet is flagged and never queried", function()
  local sk = boot({ Wallet = "0x123" }); settle(sk); has(sk:text("MeterAccountHint"), "not a valid address")
  for _, k in ipairs(sk.fetched) do assert(MARKET[k], "fetched " .. k) end
end)
ok("API text cannot inject Rainmeter variables", function()
  local sk = boot({ Wallet = DEAD }, { pos146 = '[{"chainId":146,"network":"So#nic[X]","symbol":"a#b-c","sizeCurrency":"a#[MeasureX]","side":"long","size":"1","markPrice":"1","pnlAmount":"1"}]' })
  settle(sk); local t = sk:option("MeterPos1", "Text"); assert(t and not t:find("[#%[%]]"), t)
end)
ok("SetWallet: validates, writes Settings.inc, refreshes; empty clears the wallet", function()
  local sk = boot({ Wallet = DEAD }); settle(sk)
  sk:exec('[!CommandMeasure MeasureScript "SetWallet(\'junk\')"]'); has(sk:text("MeterBanner"), "Not a valid address"); eq(sk.refreshed, 0)
  sk:exec('[!CommandMeasure MeasureScript "SetWallet(\' 0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD \')"]')
  has(readFile(sk.dir .. "/@Resources/Settings.inc"), "\nWallet=0xabcdefabcdefabcdefabcdefabcdefabcdefabcd\n"); eq(sk.refreshed, 1)
  has(readFile(sk.dir .. "/@Resources/Settings.inc"), "HfWarn=1.40", "other settings kept")
  sk:exec('[!CommandMeasure MeasureScript "SetWallet(\'\')"]'); has(readFile(sk.dir .. "/@Resources/Settings.inc"), "\nWallet=\n")
  noErrors(sk)
end)
ok("a Lua error is logged and shown, not swallowed into 'loading...'", function()
  local sk = boot({}); settle(sk)
  sk.script.env.FT_TEST.render = function() error("boom") end
  sk.script.env.Render()
  has(sk:text("MeterStatus"), "script error"); has(table.concat(sk.log, "\n"), "boom")
end)

os.execute("rm -rf " .. TMP)
print("\n" .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
