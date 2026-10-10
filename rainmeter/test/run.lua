-- lua5.1 test/run.lua   (Rainmeter embeds Lua 5.1)
-- Loads the real skin script with a mock SKIN object and feeds it WebParser-style download files.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local FIX = here .. "/fixtures"
local TMP = os.tmpname(); os.remove(TMP); os.execute("mkdir -p " .. TMP .. "/DownloadFile " .. TMP .. "/res")
local DEAD = "0x000000000000000000000000000000000000dEaD"

local passed = 0
local function ok(name, fn) fn(); passed = passed + 1; print("ok  " .. name) end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end
local function has(s, sub, msg) if not tostring(s):find(sub, 1, true) then error((msg or "") .. " missing [" .. sub .. "] in [" .. tostring(s) .. "]", 2) end end

local function readFile(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local function writeFile(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end

-- ---------------------------------------------------------------- mock SKIN
local vars, opts, bangs, clock
local function resetSkin(v)
  vars = { Wallet = "", HfWarn = "1.40", HfCritical = "1.30", NotifyCooldownMin = "30", Notifications = "1", PriceChainId = "1", RefreshSeconds = "60" }
  for k, x in pairs(v or {}) do vars[k] = x end
  opts, bangs = {}, {}
  os.execute("rm -f " .. TMP .. "/res/* " .. TMP .. "/DownloadFile/*")
end
SKIN = {
  GetVariable = function(_, n) return vars[n] end,
  MakePathAbsolute = function(_, p) return TMP .. "/" .. p:gsub("\\", "/") end,
  ReplaceVariables = function(_, s) return (s:gsub("#@#", TMP .. "/res/")) end,
  Bang = function(_, name, ...)
    local a = { ... }
    bangs[#bangs + 1] = { name = name, args = a }
    if name == "!SetOption" then opts[a[1]] = opts[a[1]] or {}; opts[a[1]][a[2]] = a[3] end
    if name == "!WriteKeyValue" then vars[a[2]] = a[3]; writeFile(a[4], "[" .. a[1] .. "]\n" .. a[2] .. "=" .. a[3] .. "\n") end
  end
}
local realTime = os.time
os.time = function(...) if select("#", ...) > 0 then return realTime(...) end return clock end
local function bangNamed(n) local out = {}; for _, b in ipairs(bangs) do if b.name == n then out[#out + 1] = b end end; return out end
local function text(m) return opts[m] and opts[m].Text end

dofile(here .. "/../Skins/FlyingTulip/@Resources/Lua/FlyingTulip.lua")
local T = FT_TEST

local function put(key_file, body) writeFile(TMP .. "/DownloadFile/" .. key_file, body) end
local function putFixture(file) put(file, readFile(FIX .. "/" .. file)) end
local function boot(v, t0)
  resetSkin(v); clock = t0 or 1790000000
  Initialize(); OnLoaded()
end
local function loadMarket()
  for k, f in pairs({ price = "tickers.json", fees = "fees.json", feesSeries = "fees_series.json", klines = "klines.json" }) do
    local target = ({ price = "price.json", fees = "fees.json", feesSeries = "fees_series.json", klines = "klines.json" })[k]
    put(target, readFile(FIX .. "/" .. f)); OnData(k)
  end
end
local function lendJson(hf)
  return string.format([[{"data":{"chains":[{"chainId":146,"hfLiquidationThreshold":1.25,"userMetrics":{"totalDebtUsd":1000,"healthFactor":%s,"equityUsd":500}},
    {"chainId":1,"userMetrics":{"totalDebtUsd":0,"healthFactor":0,"equityUsd":25}}]}}]], tostring(hf))
end
local function leaderboard(page, myRank, myPts)
  local rows = {}
  for r = (page - 1) * 500 + 1, math.min(page * 500, 2000) do
    local w = (r == myRank) and DEAD or string.format("0x%040d", r)
    rows[#rows + 1] = string.format('{"rank":%d,"userWallet":"%s","totalPoints":%d}', r, w, (r == myRank) and myPts or (1000000 - r * 100))
  end
  return '{"data":{"pagination":{"total":2000},"leaderboard":[' .. table.concat(rows, ",") .. "]}}"
end

-- ---------------------------------------------------------------- JSON decoder
ok("json: scalars, nesting, escapes, unicode, big input", function()
  local j = T.jsonDecode('{"a":[1,2.5,-3e2,true,false,null,"x\\n\\"y\\u00e9\\ud83d\\ude00"],"b":{"c":{}},"d":"0.150151694355331498"}')
  eq(j.a[1], 1); eq(j.a[2], 2.5); eq(j.a[3], -300); eq(j.a[4], true); eq(j.a[5], false); eq(j.a[7], 'x\n"y\195\169\240\159\152\128')
  eq(type(j.b.c), "table"); eq(j.d, "0.150151694355331498")
  eq(T.jsonDecode("{"), nil); eq(T.jsonDecode('{"a":1} x'), nil); eq(T.jsonDecode(""), nil); eq(T.jsonDecode("[1,]"), nil)
  local big = {}
  for i = 1, 20000 do big[#big + 1] = '{"i":' .. i .. ',"s":"row ' .. i .. '"}' end
  local d = T.jsonDecode("[" .. table.concat(big, ",") .. "]"); eq(#d, 20000); eq(d[20000].s, "row 20000")
end)
ok("json: the recorded API fixtures decode", function()
  for _, f in ipairs({ "tickers.json", "fees.json", "fees_series.json", "klines.json" }) do assert(T.jsonDecode(readFile(FIX .. "/" .. f)), f) end
end)

-- ---------------------------------------------------------------- formatting and parsers
ok("formatters match the other widgets", function()
  eq(T._fmt.hf(nil), "\226\136\158"); eq(T._fmt.hf(150), ">100"); eq(T._fmt.hf(1.2345), "1.23")
  eq(T._fmt.usd(1152.98), "$1.15k"); eq(T._fmt.signed(-5), "-$5.00"); eq(T._fmt.price(0.15015), "$0.1502")
  eq(T._fmt.ft(470.83), "470.8"); eq(T._fmt.points(1234567), "1.2M"); eq(T._fmt.pct(-3.456), "-3.5%"); eq(T._fmt.thousands(1234567), "1,234,567")
  eq(T._fmt.wallet(" " .. DEAD .. " "), DEAD:lower()); eq(T._fmt.wallet("0x123"), "")
end)
ok("price is the FT-ftUSD market mark", function()
  local p = T._parse.price(T.jsonDecode(readFile(FIX .. "/tickers.json"))); assert(p and p.price > 0 and p.price < 10)
  eq(T._parse.price({ data = { tickers = { { display_symbol = "WBTC-ftUSD", price = "1" } } } }), nil)
end)
ok("fees, series, klines", function()
  local f = T._parse.fees(T.jsonDecode(readFile(FIX .. "/fees.json"))); assert(f.period24h >= 0 and #f.products > 0)
  eq(#T._parse.feesSeries(T.jsonDecode(readFile(FIX .. "/fees_series.json"))), 31); eq(#T._parse.klines(T.jsonDecode(readFile(FIX .. "/klines.json"))), 30)
end)
ok("rawUnits and ftPUT gain use FT market price", function()
  assert(math.abs(T._fmt.rawUnits("9996014600000000000000", 18) - 9996.0146) < 1e-9)
  local puts = T._parse.puts(T.jsonDecode('{"data":{"positions":[{"nft_id":"1","token_symbol":"USDT","token_decimals":6,"strike":"99960146","current_capital":"1000000000","current_ft":"9996014600000000000000","withdrawn_ft":"0"}]}}'))
  eq(puts.count, 1); assert(math.abs(puts.costUsd - 999.60146) < 1e-6)
  local g = T._putGain(puts, 0.15); assert(math.abs(g.gainUsd - (9996.0146 * 0.15 - 999.60146)) < 1e-6)
  eq(T._parse.puts(T.jsonDecode('{"data":{"positions":null}}')), nil)
end)
ok("rewards: total FT, unknown when a section errored", function()
  local r = T._parse.rewards(T.jsonDecode('{"success":true,"data":{"chains":[{"chainId":146,"staking":{"pending_yield_ft":"3000000000000000000","claimed_yield_ft":"100000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false},"lend":{"userMetrics":{"ftRewards":{"receivedFtRaw":"50000000000000000000","pendingFtRaw":"0"}}}}]}}'))
  assert(math.abs(r.totalFt - 153) < 1e-9); assert(math.abs(r.claimableFt - 3) < 1e-9)
  eq(T._parse.rewards(T.jsonDecode('{"success":true,"data":{"sectionErrors":{"lend":true},"chains":[{"chainId":146}]}}')).totalFt, nil)
end)
ok("lend: no debt is infinity, lowest across chains", function()
  local l = T._mergeChains({ T._parse.lend(T.jsonDecode(lendJson(1.8))), T._parse.lend(T.jsonDecode('{"data":{"chains":[{"chainId":56,"userMetrics":{"totalDebtUsd":50,"healthFactor":1.33}}]}}')) })
  eq(#l, 3); eq(T._lowestHf(l).name, "BNB"); eq(T._lowestHf({ l[2] }), nil)
end)
ok("alert state machine: once per crossing, hysteresis, cooldown", function()
  local cfg = { warn = 1.4, critical = 1.3, cooldownSec = 1800 }
  local function e(hf) return { hf = hf, name = "Sonic", liqHf = 1.25 } end
  local st, n = { level = 0 }, nil
  st, n = T._alert.decideNotify(st, e(2), cfg, 0); assert(not n)
  st, n = T._alert.decideNotify(st, e(1.39), cfg, 1); assert(n and n.level == 1)
  st, n = T._alert.decideNotify(st, e(1.38), cfg, 2); assert(not n)
  st, n = T._alert.decideNotify(st, e(1.29), cfg, 3); assert(n and n.level == 2)
  st, n = T._alert.decideNotify(st, e(1.33), cfg, 4); assert(not n and st.level == 2)
  st, n = T._alert.decideNotify(st, e(1.6), cfg, 5); assert(not n and st.level == 0)
  st, n = T._alert.decideNotify(st, e(1.39), cfg, 6); assert(not n, "inside cooldown")
  st, n = T._alert.decideNotify(st, e(1.2), cfg, 1900); assert(n and n.level == 2)
  st, n = T._alert.decideNotify(st, nil, cfg, 1901); eq(st.level, 0)
  eq(T._alert.threshold("abc", 1.4), 1.4); eq(T._alert.threshold("1.5", 1.4), 1.5)
end)

-- ---------------------------------------------------------------- skin behaviour
ok("no wallet: market rows, hint, account measures disabled, no account text", function()
  boot({})
  assert(#bangs > 0); eq(bangNamed("!DisableMeasureGroup")[1].args[1], "Account")
  loadMarket()
  has(text("MeterPriceVal"), "$0.1"); has(text("MeterFeesVal"), "$"); has(text("MeterFeesChartLabel"), "31 days"); has(text("MeterPriceChartLabel"), "30 days")
  has(opts.MeterFeesChart.Shape2, "Rectangle"); has(opts.MeterPriceChart.Shape3, "Path LinePath"); has(opts.MeterPriceChart.LinePath, "LineTo")
  has(text("MeterAccountHint"), "Add your wallet"); eq(text("MeterHfVal"), ""); has(text("MeterStatus"), "updated")
  eq(#bangs and #bangNamed("!EnableMeasureGroup"), 0)
end)
ok("wallet: account measures enabled, every row rendered", function()
  boot({ Wallet = DEAD })
  eq(bangNamed("!EnableMeasureGroup")[1].args[1], "Account"); loadMarket()
  put("lend.json", lendJson(1.9)); OnData("lend"); put("lend143.json", '{"data":{"chains":[]}}'); OnData("lend143")
  put("sum146.json", '[{"chainId":146,"unrealizedPnl":"12.5"}]'); OnData("sum146"); put("sum1.json", '[{"chainId":1,"unrealizedPnl":"-2"}]'); OnData("sum1")
  put("rewards.json", '{"success":true,"data":{"chains":[{"chainId":146,"staking":{"pending_yield_ft":"3000000000000000000","claimed_yield_ft":"100000000000000000000","claimed_yield_indexed_through_block":5,"claimed_yield_stale":false}}]}}'); OnData("rewards")
  put("pos146.json", '[{"chainId":146,"network":"Sonic","symbol":"wS-ftUSD","sizeCurrency":"wS","side":"long","size":"1000","markPrice":"0.05","pnlAmount":"5","blendedLeverage":"3"}]'); OnData("pos146")
  put("puts.json", '{"data":{"positions":[{"nft_id":"7","token_symbol":"USDT","token_decimals":6,"strike":"99960146","current_capital":"1000000000","current_ft":"9996014600000000000000","withdrawn_ft":"0"}]}}'); OnData("puts")
  put("points.json", '{"data":{"chains":[{"isAllChains":true,"userMetrics":{"totalPoints":922000}}]}}'); OnData("points")
  has(text("MeterHfVal"), "1.90"); has(text("MeterHfVal"), "Sonic"); eq(opts.MeterHfVal.FontColor, "15,215,39,255")
  has(text("MeterPnlVal"), "+$10.50"); has(text("MeterEarnVal"), "103.0 FT"); local px = T._parse.price(T.jsonDecode(readFile(FIX .. "/tickers.json"))).price
  has(text("MeterPutVal"), T._fmt.pct((9996.0146 * px - 999.60146) / 999.60146 * 100), "ftPUT uses the market price"); has(text("MeterPosHead"), "1 open")
  has(text("MeterPos1"), "wS long 3.0x"); has(text("MeterPointsVal"), "922K"); eq(text("MeterAccountHint"), "")
  has(text("MeterSub"), "0x0000"); eq(#bangNamed("!EnableMeasure"), 1, "rank search started"); eq(bangNamed("!SetVariable")[1].args[2], "7")
end)
ok("price and position meters link to their trade pages", function()
  boot({ Wallet = DEAD, PriceChainId = "146" }); loadMarket()
  put("pos146.json", '[{"chainId":146,"network":"Sonic","symbol":"wS-ftUSD","sizeCurrency":"wS","side":"long","size":"1000","markPrice":"0.05","pnlAmount":"5","blendedLeverage":"3"}]'); OnData("pos146")
  eq(opts.MeterPriceVal.LeftMouseUpAction, '["https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=146&marketType=spot"]')
  eq(opts.MeterPriceChart.LeftMouseUpAction, opts.MeterPriceVal.LeftMouseUpAction)
  eq(opts.MeterPos1.LeftMouseUpAction, '["https://flyingtulip.com/trade/?symbol=wS-ftUSD&chainId=146&marketType=spot"]')
  eq(opts.MeterPos2.LeftMouseUpAction, '["https://flyingtulip.com/trade/portfolio/"]')
end)
ok("rank search walks the leaderboard like the other widgets", function()
  boot({ Wallet = DEAD }); put("points.json", '{"data":{"chains":[{"isAllChains":true,"userMetrics":{"totalPoints":1922000}}]}}'); OnData("points")
  local pages = {}
  for i = 1, 6 do
    local v = bangNamed("!SetVariable"); local page = tonumber(v[#v].args[2]); pages[#pages + 1] = page
    put("rank.json", leaderboard(page, 777, 922000)); OnData("rank")
    if text("MeterPointsVal") and text("MeterPointsVal"):find("rank") then break end
  end
  has(text("MeterPointsVal"), "rank 777 of 2,000"); eq(pages[1], 7); eq(pages[2], 2)
  assert(#bangNamed("!DisableMeasure") > 0, "rank measure disabled again")
end)
ok("warning state: border, banner and a toast, once", function()
  boot({ Wallet = DEAD }); loadMarket()
  put("lend.json", lendJson(1.38)); OnData("lend")
  has(opts.MeterBackground.Shape, "245,165,36"); has(text("MeterBanner"), "HF 1.38"); eq(opts.MeterHfVal.FontColor, "245,165,36,255")
  local note = readFile(TMP .. "/res/Notify.txt"); has(note, "FT account health low"); has(note, "normal")
  local ps = bangNamed("")[1]; local run
  for _, b in ipairs(bangs) do if b.name:find("powershell.exe", 1, true) then run = b end end
  assert(run, "powershell command issued"); has(run.name, "Notify.ps1")
  local before = 0; for _, b in ipairs(bangs) do if b.name:find("powershell", 1, true) then before = before + 1 end end
  clock = clock + 60; OnData("lend"); local after = 0; for _, b in ipairs(bangs) do if b.name:find("powershell", 1, true) then after = after + 1 end end
  eq(after, before, "no repeat")
  clock = clock + 60; put("lend.json", lendJson(1.28)); OnData("lend")
  has(opts.MeterBackground.Shape, "239,68,68"); has(readFile(TMP .. "/res/Notify.txt"), "critical")
end)
ok("notifications off: visual warning only", function()
  boot({ Wallet = DEAD, Notifications = "0" }); put("lend.json", lendJson(1.2)); OnData("lend")
  has(opts.MeterBackground.Shape, "239,68,68"); local f = io.open(TMP .. "/res/Notify.txt", "rb"); eq(f, nil)
end)
ok("alert state survives a skin refresh (no second toast inside the cooldown)", function()
  boot({ Wallet = DEAD }); put("lend.json", lendJson(1.38)); OnData("lend")
  local state = readFile(TMP .. "/res/State.txt"); os.remove(TMP .. "/res/Notify.txt")
  bangs = {}; Initialize(); OnLoaded(); clock = clock + 120; put("lend.json", lendJson(1.37)); OnData("lend")
  eq(io.open(TMP .. "/res/Notify.txt", "rb"), nil); has(state, "level=1")
end)
ok("a bad payload keeps the last good value; stale values are flagged", function()
  boot({ Wallet = DEAD }); loadMarket(); local price = text("MeterPriceVal")
  put("price.json", "<html>502</html>"); OnData("price"); eq(text("MeterPriceVal"), price)
  clock = clock + 60 * 5; OnData("fees"); has(text("MeterStatus"), "stale")
end)
ok("nothing arrives: loading, then offline", function()
  boot({}); has(text("MeterStatus"), "loading"); clock = clock + 30
  for i = 1, 30 do Update() end; has(text("MeterStatus"), "offline")
end)
ok("invalid wallet is flagged and never queried", function()
  boot({ Wallet = "0x123" }); eq(bangNamed("!DisableMeasureGroup")[1].args[1], "Account"); has(text("MeterAccountHint"), "not a valid address")
end)
ok("API text cannot inject Rainmeter variables", function()
  boot({ Wallet = DEAD })
  put("pos146.json", '[{"chainId":146,"network":"So#nic[X]","symbol":"a#b-c","sizeCurrency":"a#[MeasureX]","side":"long","size":"1","markPrice":"1","pnlAmount":"1"}]'); OnData("pos146")
  assert(not text("MeterPos1"):find("[#%[%]]"), text("MeterPos1"))
end)
ok("SetWallet: validates, writes Settings.inc, clears wallet downloads, refreshes", function()
  boot({ Wallet = DEAD }); put("lend.json", lendJson(2)); OnData("lend")
  SetWallet("junk"); has(text("MeterBanner"), "Not a valid address"); eq(#bangNamed("!Refresh"), 0)
  SetWallet(" 0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD ")
  has(readFile(TMP .. "/res/Settings.inc"), "Wallet=0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"); eq(#bangNamed("!Refresh"), 1)
  eq(io.open(TMP .. "/DownloadFile/lend.json", "rb"), nil)
  SetWallet(""); has(readFile(TMP .. "/res/Settings.inc"), "Wallet=\n")
end)

os.execute("rm -rf " .. TMP)
print("\n" .. passed .. " passed")
