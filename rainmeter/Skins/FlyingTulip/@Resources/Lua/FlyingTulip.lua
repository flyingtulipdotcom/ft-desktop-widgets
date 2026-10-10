-- Flying Tulip skin logic (Lua 5.1, as embedded in Rainmeter).
-- Each WebParser measure keeps one JSON body in memory (RegExp (?s)^(.*)$); its FinishAction calls OnData(key),
-- which reads it with SKIN:GetMeasure(name):GetStringValue().
-- Public API only: https://api.flyingtulip.com. No keys, no RPC.
--
-- SKIN does not exist while this file runs. Rainmeter runs the chunk first and only then puts SKIN and SELF into
-- the script's environment, before calling Initialize(). Everything that touches SKIN runs from Initialize() on.
-- (v1.0.0 captured SKIN at load time, got nil, and every callback failed: the skin stayed on "loading...".)
--
-- The file must stay plain ASCII without a UTF-16 BOM. Rainmeter then treats the script as ANSI: strings to and
-- from the skin go through the system code page, so non-ASCII glyphs are written as [\NNNN] character references.

local API = "https://api.flyingtulip.com"
local SITE = "https://flyingtulip.com/"
local PORTFOLIO_URL = SITE .. "trade/portfolio/"
-- Spot market page for a symbol such as "FT-ftUSD" on a chain id.
local function marketUrl(symbol, chainId)
  local q = "symbol=" .. tostring(symbol or "FT-ftUSD"):gsub("[^%w%-_.~]", function(c) return string.format("%%%02X", c:byte()) end)
  if tonumber(chainId) and tonumber(chainId) > 0 then q = q .. "&chainId=" .. string.format("%d", tonumber(chainId)) end
  return SITE .. "trade/?" .. q .. "&marketType=spot"
end
local DEFAULT_LIQ_HF = 1.25
local HF_CHAINS = { [146] = "Sonic", [1] = "Ethereum", [56] = "BNB", [143] = "Monad" }
local HF_ORDER = { 146, 1, 56, 143 }
local RANK_TTL = 600

-- colours (r,g,b,a)
local C_TEXT, C_SUB, C_FAINT = "228,228,231,255", "161,161,170,255", "113,113,122,255"
local C_TULIP, C_TULIP300 = "117,89,255,255", "183,177,255,255"
local C_GREEN, C_RED, C_AMBER = "15,215,39,255", "239,68,68,255", "245,165,36,255"
local C_BORDER = "76,76,82,128"

local M = {}

-- ---------------------------------------------------------------- JSON (decoder only)
local function skipws(s, i)
  local _, e = s:find("^[ \n\r\t]*", i)
  return e + 1
end

local ESC = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local parseValue

-- index just past the string that opens at a (a is the opening quote)
local function stringEnd(s, a)
  local j = a + 1
  while true do
    local q = s:find('["\\]', j)
    if not q then error("unterminated string") end
    if s:byte(q) == 92 then j = q + 2 else return q + 1 end
  end
end

-- index just past the value at i, without building it (the 500 KB /mm/lend body is mostly chart series)
local function skipValue(s, i)
  i = skipws(s, i)
  local c = s:byte(i)
  if c == 34 then return stringEnd(s, i) end
  if c == 123 or c == 91 then
    local depth, j = 0, i
    while true do
      local a = s:find('[][{}"]', j)
      if not a then error("unterminated container") end
      local b = s:byte(a)
      if b == 34 then j = stringEnd(s, a)
      elseif b == 123 or b == 91 then depth = depth + 1; j = a + 1
      else
        depth = depth - 1; j = a + 1
        if depth == 0 then return j end
      end
    end
  end
  local _, e = s:find("^[%w%.%+%-]+", i)
  if not e then error("unexpected character at " .. i) end
  return e + 1
end

local SKIP -- object keys whose values the current decode drops (set by jsonDecode)

local function parseString(s, i)
  local out, j = {}, i + 1
  while true do
    local a, b = s:find('["\\]', j)
    if not a then error("unterminated string") end
    out[#out + 1] = s:sub(j, a - 1)
    if s:sub(a, a) == '"' then return table.concat(out), a + 1 end
    local c = s:sub(a + 1, a + 1)
    if c == "u" then
      local hex = s:sub(a + 2, a + 5)
      if not hex:match("^%x%x%x%x$") then error("bad unicode escape") end
      local cp = tonumber(hex, 16)
      j = a + 6
      if cp >= 0xD800 and cp < 0xDC00 and s:sub(j, j + 1) == "\\u" then
        local lo = tonumber(s:sub(j + 2, j + 5), 16)
        if lo and lo >= 0xDC00 and lo < 0xE000 then
          cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
          j = j + 6
        end
      end
      out[#out + 1] = utf8char(cp)
    else
      if not ESC[c] then error("bad escape") end
      out[#out + 1] = ESC[c]
      j = a + 2
    end
  end
end

function parseValue(s, i)
  i = skipws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = skipws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      i = skipws(s, i)
      if s:sub(i, i) ~= '"' then error("object key expected at " .. i) end
      local k
      k, i = parseString(s, i)
      i = skipws(s, i)
      if s:sub(i, i) ~= ":" then error("colon expected at " .. i) end
      if SKIP and SKIP[k] then
        i = skipValue(s, i + 1)
      else
        local v
        v, i = parseValue(s, i + 1)
        obj[k] = v
      end
      i = skipws(s, i)
      local d = s:sub(i, i)
      if d == "}" then return obj, i + 1 end
      if d ~= "," then error("comma expected at " .. i) end
      i = i + 1
    end
  elseif c == "[" then
    local arr, n = {}, 0
    i = skipws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local v
      v, i = parseValue(s, i)
      n = n + 1
      arr[n] = v
      i = skipws(s, i)
      local d = s:sub(i, i)
      if d == "]" then return arr, i + 1 end
      if d ~= "," then error("comma expected at " .. i) end
      i = i + 1
    end
  elseif c == '"' then
    return parseString(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return nil, i + 4
  end
  local a, b = s:find("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
  if not a then error("unexpected character at " .. i) end
  return tonumber(s:sub(a, b)), b + 1
end

-- skip: optional set of object keys (at any depth) whose values are dropped unparsed
local function jsonDecode(s, skip)
  if type(s) ~= "string" or s == "" then return nil end
  SKIP = skip
  local ok, v = pcall(function()
    local val, i = parseValue(s, 1)
    i = skipws(s, i)
    if i <= #s then error("trailing data") end
    return val
  end)
  SKIP = nil
  if ok then return v end
  return nil
end
M.jsonDecode = jsonDecode

-- ---------------------------------------------------------------- numbers and formatting
local function num(v)
  if v == nil or v == "" then return nil end
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end
local function isAddress(a) return type(a) == "string" and a:match("^0x%x+$") ~= nil and #a == 42 end
local function normalizeWallet(s)
  local t = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if isAddress(t) then return t:lower() end
  return ""
end
local function fmtUsd(v)
  if not v then return "-" end
  local a = math.abs(v)
  if a >= 1e6 then return string.format("$%.2fM", a / 1e6) end
  if a >= 1e4 then return string.format("$%.1fk", a / 1e3) end
  if a >= 1e3 then return string.format("$%.2fk", a / 1e3) end
  return string.format(a >= 100 and "$%.0f" or "$%.2f", a)
end
local function fmtSignedUsd(v)
  if not v then return "-" end
  if math.abs(v) < 0.005 then return "$0.00" end
  return (v < 0 and "-" or "+") .. fmtUsd(v)
end
local function fmtPrice(p)
  if not p then return "-" end
  return string.format(p >= 1 and "$%.2f" or "$%.4f", p)
end
-- U+221E. A placeholder byte that setText turns into the character reference [\8734] after cleaning: the ANSI
-- script cannot carry the UTF-8 bytes (Rainmeter would show them as mojibake).
local INF = "\001"
local INF_REF = "[\\8734]"
local function fmtHf(hf)
  if not hf then return INF end
  if hf >= 100 then return ">100" end
  return string.format("%.2f", hf)
end
local function fmtPct(v)
  if not v then return "-" end
  return string.format(math.abs(v) >= 100 and "%+.0f%%" or "%+.1f%%", v)
end
local function fmtFt(v)
  if not v then return "-" end
  if v < 0.01 then return v <= 0 and "0" or "<0.01" end
  if v < 10 then return string.format("%.2f", v) end
  if v < 1000 then return string.format("%.1f", v) end
  if v < 1e6 then return string.format(v < 1e4 and "%.2fK" or "%.1fK", v / 1e3) end
  return string.format("%.2fM", v / 1e6)
end
local function fmtPoints(v)
  if not v then return "-" end
  local a = math.abs(v)
  if a >= 1e9 then return string.format("%.2fB", a / 1e9) end
  if a >= 1e6 then return string.format(a >= 1e8 and "%.0fM" or "%.1fM", a / 1e6) end
  if a >= 1e3 then return string.format(a >= 1e5 and "%.0fK" or "%.1fK", a / 1e3) end
  return string.format("%.0f", a)
end
local function thousands(n)
  local s = string.format("%d", math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local function shortAddr(a)
  if #a > 12 then return a:sub(1, 6) .. ".." .. a:sub(-4) end
  return a
end

-- exact decimal shift of an integer string (display precision only)
local function rawUnits(s, dec)
  if s == nil then return nil end
  s = tostring(s)
  if not s:match("^%d+$") then return nil end
  if #s <= 15 then return tonumber(s) / 10 ^ dec end
  local cut = #s - dec
  if cut <= 0 then return tonumber("0." .. string.rep("0", -cut) .. s) end
  return tonumber(s:sub(1, cut) .. "." .. s:sub(cut + 1))
end

-- ---------------------------------------------------------------- parsers
local function parseFees(body)
  local d = body and body.data
  if not d or not d.totals then return nil end
  local period = num(d.totals.period_usd)
  if not period then return nil end
  local products = {}
  for k, v in pairs(d.byProduct or {}) do
    local u = num(type(v) == "table" and v.period_usd)
    if u then products[#products + 1] = { name = k, usd = u } end
  end
  table.sort(products, function(a, b) return a.usd > b.usd end)
  return { period24h = period, lifetime = num(d.totals.lifetime_usd), products = products }
end

local function parsePrice(body)
  local ts = body and body.data and body.data.tickers
  if not ts then return nil end
  for i = 1, #ts do
    if ts[i].display_symbol == "FT-ftUSD" then
      local p = num(ts[i].price)
      if not p then return nil end
      return { price = p, changePct24h = num(ts[i].price_change_pct_24h), sampledAt = ts[i].sampled_at or "" }
    end
  end
  return nil
end

local function parseLend(body)
  local d = body and (body.data or body)
  local chains = d and d.chains
  local out = {}
  if not chains then return out end
  for i = 1, #chains do
    local c = chains[i]
    local m = c.userMetrics or {}
    local debt, hf = num(m.totalDebtUsd), num(m.healthFactor)
    local hasDebt = debt ~= nil and debt > 0.01
    local id = tonumber(c.chainId)
    out[#out + 1] = {
      chainId = id, name = HF_CHAINS[id] or c.chainName or tostring(c.chainId),
      hf = (hasDebt and hf) or nil, debtUsd = debt or 0, equityUsd = num(m.equityUsd),
      liqHf = num(c.hfLiquidationThreshold) or DEFAULT_LIQ_HF }
  end
  return out
end

local function parseSummary(body)
  local arr = body
  if type(arr) == "table" and arr.data then arr = arr.data end
  if type(arr) ~= "table" or not arr[1] then return nil end
  return { chainId = tonumber(arr[1].chainId), pnlUsd = num(arr[1].unrealizedPnl) or 0 }
end

local function mergeChains(lists)
  local byId = {}
  for _, list in ipairs(lists) do
    for _, c in ipairs(list) do byId[c.chainId] = c end
  end
  local out = {}
  for _, id in ipairs(HF_ORDER) do if byId[id] then out[#out + 1] = byId[id]; byId[id] = nil end end
  for _, c in pairs(byId) do out[#out + 1] = c end
  return out
end

local function lowestHf(chains)
  local best
  for _, c in ipairs(chains or {}) do
    if c.hf and (not best or c.hf < best.hf) then best = c end
  end
  return best
end

-- Total FT earned: sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending), all chains.
-- total is nil when any piece is unknown or a section errored.
local function parseRewards(body)
  local d = body and body.success ~= false and body.data
  if not d or not d.chains then return nil end
  local errs = d.sectionErrors or {}
  local known = not errs.staking and not errs.lend
  local total, claimable = 0, 0
  for _, c in ipairs(d.chains) do
    local st, lm = c.staking, c.lend and c.lend.userMetrics
    local pending, claimed
    if st then
      pending = rawUnits(st.pending_yield_ft, 18)
      if st.claimed_yield_indexed_through_block and not st.claimed_yield_stale then claimed = rawUnits(st.claimed_yield_ft, 18) end
    else
      if errs.staking then pending, claimed = nil, nil else pending, claimed = 0, 0 end
    end
    local sft = (pending and claimed) and (pending + claimed) or nil
    local lend = 0
    if errs.lend then lend = nil end
    if c.lend then
      local fr = lm and lm.ftRewards
      if lm and lm.ftRewardsError then lend = nil
      elseif fr then
        local r, p = rawUnits(fr.receivedFtRaw, 18), rawUnits(fr.pendingFtRaw, 18)
        lend = (r and p) and (r + p) or nil
      elseif not lm then lend = nil
      else lend = 0 end
    end
    if pending then claimable = claimable + pending end
    if sft == nil or lend == nil then known = false else total = total + sft + lend end
  end
  return { totalFt = known and total or nil, claimableFt = claimable }
end

-- ftPUT: cost basis = sum(current_capital * strike), FT held = current_ft + withdrawn_ft. nil with no PUTs.
local function parsePuts(body)
  local ps = body and body.data and body.data.positions
  if not ps or #ps == 0 then return nil end
  local cost, held, n = 0, 0, 0
  for _, p in ipairs(ps) do
    local dec = tonumber(p.token_decimals) or (p.tokenData and tonumber(p.tokenData.decimals)) or 18
    local strike, cap = rawUnits(p.strike, 8), rawUnits(p.current_capital, dec)
    local ftC, ftW = rawUnits(p.current_ft, 18), rawUnits(p.withdrawn_ft, 18)
    if strike and cap and ftC then
      cost = cost + cap * strike
      held = held + ftC + (ftW or 0)
      n = n + 1
    end
  end
  if n == 0 then return nil end
  return { count = n, costUsd = cost, ftHeld = held }
end

-- gain = FT held x FT MARKET price - cost basis (never NAV)
local function putGain(puts, ftPrice)
  if not puts or not ftPrice then return nil end
  local gain = puts.ftHeld * ftPrice - puts.costUsd
  return { gainUsd = gain, gainPct = puts.costUsd > 0 and gain / puts.costUsd * 100 or nil }
end

local function parsePoints(body)
  local chains = body and body.data and body.data.chains
  if not chains then return nil end
  for _, c in ipairs(chains) do
    if c.isAllChains and c.userMetrics then
      local t = num(c.userMetrics.totalPoints)
      if t then return { total = t } end
    end
  end
  return nil
end

local function rankInPage(body, wallet, myPoints)
  local d = body and body.data
  local lb = d and d.leaderboard
  local total = (d and d.pagination and tonumber(d.pagination.total)) or 0
  if not lb or #lb == 0 then return { found = false, dir = 0, total = total, empty = true } end
  local w = wallet:lower()
  for _, r in ipairs(lb) do
    if tostring(r.userWallet):lower() == w then return { found = true, rank = tonumber(r.rank), total = total } end
  end
  local first, last = num(lb[1].totalPoints) or 0, num(lb[#lb].totalPoints) or 0
  return { found = false, dir = myPoints > first and -1 or (myPoints < last and 1 or 0), total = total }
end

local function parsePositions(body)
  local arr = body
  if type(arr) == "table" and arr.data then arr = arr.data end
  local out = {}
  if type(arr) ~= "table" then return out end
  for _, p in ipairs(arr) do
    local size, mark = num(p.size), num(p.markPrice)
    if size and size > 0 then
      local sym = p.sizeCurrency or tostring(p.symbol or "?"):match("^[^-]+") or "?"
      out[#out + 1] = { symbol = tostring(sym), side = (tostring(p.side or ""):lower() == "short") and "short" or "long",
        size = size, mark = mark, pnlUsd = num(p.pnlAmount), pnlPct = num(p.pnlPct),
        leverage = num(p.blendedLeverage) or num(p.leverage), valueUsd = mark and size * mark or 0,
        network = p.network or HF_CHAINS[tonumber(p.chainId)] or tostring(p.chainId),
        chainId = tonumber(p.chainId), market = tostring(p.symbol or "") }
    end
  end
  return out
end

local function parseFeesSeries(body)
  local s = body and body.data and body.data.series
  if not s or #s == 0 then return nil end
  local out = {}
  for _, r in ipairs(s) do
    local v = num(r.total_usd)
    if v then out[#out + 1] = { date = tostring(r.date), total = v } end
  end
  return #out > 0 and out or nil
end

local function parseKlines(body)
  if type(body) ~= "table" or #body == 0 then return nil end
  local out = {}
  for _, k in ipairs(body) do
    local c = num(k.close)
    if c then out[#out + 1] = { close = c } end
  end
  return #out > 0 and out or nil
end

-- day-over-day % across finished days (the last bucket is the partial current day)
local function feesDayOverDay(series, nowSec)
  if not series or #series < 4 then return nil end
  local today = os.date("!%Y-%m-%d", nowSec)
  local n = #series
  if series[n].date:sub(1, 10) == today then n = n - 1 end
  if n < 2 then return nil end
  local last, prev = series[n].total, series[n - 1].total
  if prev > 0 then return (last - prev) / prev * 100 end
  return nil
end

-- ---------------------------------------------------------------- alerts
local function levelFor(hf, cfg, prev)
  local hyst = cfg.hyst or 0.05
  local lvl = 0
  if hf <= cfg.critical then lvl = 2 elseif hf <= cfg.warn then lvl = 1 end
  if prev == 2 and lvl < 2 and hf <= cfg.critical + hyst then lvl = 2 end
  if prev >= 1 and lvl < 1 and hf <= cfg.warn + hyst then lvl = 1 end
  return lvl
end

-- state: {level, last1, last2}. Notifies once per upward crossing, never twice for a level inside the cooldown.
local function decideNotify(state, entry, cfg, nowSec)
  local st = { level = state.level or 0, last1 = state.last1 or -1e18, last2 = state.last2 or -1e18 }
  if not entry then st.level = 0; return st, nil end
  local lvl = levelFor(entry.hf, cfg, st.level)
  local notify
  local key = lvl == 2 and "last2" or "last1"
  if lvl > st.level and nowSec - st[key] >= cfg.cooldownSec then
    notify = { level = lvl, hf = entry.hf, chain = entry.name, liqHf = entry.liqHf }
    st[key] = nowSec
  end
  st.level = lvl
  return st, notify
end

local function notifyText(n)
  local hf = string.format("%.2f", n.hf)
  if n.level == 2 then
    return "FT account near liquidation",
      string.format("%s HF %s (liquidation below %.2f). Add collateral or repay now.", n.chain, hf, n.liqHf), "critical"
  end
  return "FT account health low", string.format("%s HF %s (liquidation below %.2f).", n.chain, hf, n.liqHf), "normal"
end

local function threshold(v, fallback)
  local n = num(v)
  if n and n > 1 then return n end
  return fallback
end

-- ---------------------------------------------------------------- skin state and rendering
local S, cfg, alertState
local SK -- the SKIN object, set by Initialize() (it does not exist yet while this chunk runs)
local io_ = io

-- data key -> WebParser measure (Data.inc) holding that endpoint's JSON body
local MEASURES = {
  price = "MeasurePrice", fees = "MeasureFees", feesSeries = "MeasureFeesSeries", klines = "MeasureKlines",
  lend = "MeasureLend", lend143 = "MeasureLend143", sum146 = "MeasureSum146", sum1 = "MeasureSum1", sum56 = "MeasureSum56",
  sum143 = "MeasureSum143", rewards = "MeasureRewards", points = "MeasurePoints", pos146 = "MeasurePos146",
  pos1 = "MeasurePos1", pos56 = "MeasurePos56", puts = "MeasurePuts", rank = "MeasureRank"
}
-- the parts of /mm/lend the skin never reads: dropped unparsed, which keeps the 500 KB body cheap to decode
local LEND_SKIP = { series = true, assets = true, userTransactions = true, marketsSummary = true,
  circuitBreakerParams = true, chainData = true, globalMetrics = true }
local LEND_IDLE_RATE = 600 -- WebParser updates (seconds at Update=1000) between /mm/lend fetches while nothing is borrowed

local function resource(rel) return SK:ReplaceVariables("#@#" .. rel) end

local function readFile(path)
  local f = io_.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function writeFile(path, text)
  local f = io_.open(path, "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

local function set(meter, option, value) SK:Bang("!SetOption", meter, option, value) end
-- API text must not be interpreted as Rainmeter variables/measure references
local function clean(t) return ((tostring(t):gsub("[#%[%]\r\n]", " "):gsub("\001", INF_REF))) end
local function setText(meter, text, color)
  set(meter, "Text", clean(text))
  if color then set(meter, "FontColor", color) end
end
local function link(meter, url) set(meter, "LeftMouseUpAction", '["' .. url .. '"]') end
local function dim(color) return (color:gsub(",%d+$", ",120")) end

local function now() return os.time() end

local function buildConfig()
  local warn, crit = threshold(SK:GetVariable("HfWarn"), 1.40), threshold(SK:GetVariable("HfCritical"), 1.30)
  if crit > warn then crit = warn end
  local cd = num(SK:GetVariable("NotifyCooldownMin"))
  local ref = num(SK:GetVariable("RefreshSeconds")) or 60
  local raw = tostring(SK:GetVariable("Wallet") or "")
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  return {
    walletRaw = raw, wallet = normalizeWallet(raw), warn = warn, critical = crit,
    cooldownSec = ((cd and cd >= 1) and cd or 30) * 60,
    notify = tostring(SK:GetVariable("Notifications") or "1") ~= "0",
    priceChain = (tonumber(SK:GetVariable("PriceChainId")) == 146) and 146 or 1,
    refresh = math.max(15, ref)
  }
end

local function loadAlertState()
  alertState = { level = 0, last1 = -1e18, last2 = -1e18 }
  local txt = readFile(resource("State.txt"))
  if not txt then return end
  local kv = {}
  for k, v in txt:gmatch("(%w+)=([^\r\n]*)") do kv[k] = v end
  if kv.wallet == cfg.wallet then
    alertState.level = tonumber(kv.level) or 0
    alertState.last1 = tonumber(kv.last1) or -1e18
    alertState.last2 = tonumber(kv.last2) or -1e18
  end
end
local function saveAlertState()
  writeFile(resource("State.txt"), string.format("wallet=%s\nlevel=%d\nlast1=%d\nlast2=%d\n", cfg.wallet, alertState.level,
    alertState.last1 > -1e17 and alertState.last1 or 0, alertState.last2 > -1e17 and alertState.last2 or 0))
end

local function lendList()
  if not S.lend then return nil end
  return mergeChains({ S.lend, S.lend143 or {} })
end

local function pnlTotal()
  local total, ok = 0, false
  for _, k in ipairs({ "sum146", "sum1", "sum56", "sum143" }) do
    if S[k] then total = total + S[k].pnlUsd; ok = true end
  end
  return ok and total or nil
end

local function allPositions()
  local any, all = false, {}
  for _, k in ipairs({ "pos146", "pos1", "pos56" }) do
    if S[k] then any = true; for _, p in ipairs(S[k]) do all[#all + 1] = p end end
  end
  if not any then return nil end
  table.sort(all, function(a, b) return a.valueUsd > b.valueUsd end)
  return all
end

local function stale(key)
  local t = S.ts[key]
  local every = (key == "lend" and S.lendRate) or cfg.refresh
  return t ~= nil and now() - t > 3 * every
end

local function deltaColor(v)
  if not v or math.abs(v) < 0.005 then return C_TEXT end
  return v > 0 and C_GREEN or C_RED
end

-- chart shapes -------------------------------------------------------------------------------------
local CHART_W, CHART_H = 312, 48

local function renderBars(meter, values)
  set(meter, "Shape", string.format("Rectangle 0,0,%d,%d,6 | Fill Color 20,18,32,255 | StrokeWidth 0", CHART_W, CHART_H))
  local n, max = #values, 0
  for _, v in ipairs(values) do if v > max then max = v end end
  if max <= 0 then max = 1 end
  local pad, step = 6, (CHART_W - 12) / n
  local bw = math.max(2, math.floor(step) - 2)
  for i, v in ipairs(values) do
    local h = math.max(2, math.floor(v / max * (CHART_H - 12) + 0.5))
    local x = pad + (i - 1) * step
    local color = (i == n) and "183,177,255,255" or "117,89,255,255"   -- last bar = today so far
    set(meter, "Shape" .. (i + 1), string.format("Rectangle %.1f,%d,%d,%d | Fill Color %s | StrokeWidth 0", x, CHART_H - 6 - h, bw, h, color))
  end
  for i = n + 2, 40 do set(meter, "Shape" .. i, "") end
end

local function renderLine(meter, values)
  local n, min, max = #values, math.huge, -math.huge
  for _, v in ipairs(values) do if v < min then min = v end; if v > max then max = v end end
  if max - min < 1e-12 then max = max + 1; min = min - 1 end
  local span = max - min
  min, max = min - span * 0.08, max + span * 0.08
  local pad = 6
  local function X(i) return pad + (i - 1) * (CHART_W - 2 * pad) / math.max(1, n - 1) end
  local function Y(v) return pad + (1 - (v - min) / (max - min)) * (CHART_H - 2 * pad) end
  local line, area = {}, {}
  for i, v in ipairs(values) do
    local seg = string.format("%.1f,%.1f", X(i), Y(v))
    line[#line + 1] = (i == 1) and seg or ("LineTo " .. seg)
    area[#area + 1] = (i == 1) and string.format("%.1f,%d | LineTo %s", X(1), CHART_H - pad, seg) or ("LineTo " .. seg)
  end
  area[#area + 1] = string.format("LineTo %.1f,%d | ClosePath 1", X(n), CHART_H - pad)
  set(meter, "Shape", string.format("Rectangle 0,0,%d,%d,6 | Fill Color 20,18,32,255 | StrokeWidth 0", CHART_W, CHART_H))
  set(meter, "AreaPath", table.concat(area, " | "))
  set(meter, "Shape2", "Path AreaPath | Fill Color 117,89,255,60 | StrokeWidth 0")
  set(meter, "LinePath", table.concat(line, " | "))
  set(meter, "Shape3", "Path LinePath | Fill Color 0,0,0,0 | StrokeWidth 2 | Stroke Color 183,177,255,255")
  local up = values[n] >= values[1]
  set(meter, "Shape4", string.format("Ellipse %.1f,%.1f,3,3 | Fill Color %s | StrokeWidth 0", X(n), Y(values[n]), up and C_GREEN or C_RED))
end

-- ---------------------------------------------------------------- render
local POS_ROWS = 4

function M.render()
  if not S then return end
  local t = now()
  local lowest = lendList() and lowestHf(lendList())
  local level = lowest and levelFor(lowest.hf, { warn = cfg.warn, critical = cfg.critical }, 0) or 0
  local liq = lowest and lowest.liqHf or DEFAULT_LIQ_HF

  -- header
  setText("MeterSub", cfg.wallet ~= "" and shortAddr(cfg.wallet) or "Market, fees and your account", C_FAINT)
  local anyData = S.price or S.fees
  local ts = 0
  for _, v in pairs(S.ts) do if v > ts then ts = v end end
  if not anyData then
    local failed = S.err.price or S.err.fees or t - S.startedAt > 20
    setText("MeterStatus", failed and "offline" or "loading...", C_FAINT)
  elseif stale("price") or stale("fees") or (cfg.wallet ~= "" and stale("lend")) then
    setText("MeterStatus", "stale " .. os.date("%H:%M", ts), C_AMBER)
  else
    setText("MeterStatus", "updated " .. os.date("%H:%M", ts), C_FAINT)
  end

  -- warning state: panel border and banner
  if level == 2 then
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,550,12 | Fill Color 14,14,17,240 | StrokeWidth 2 | Stroke Color %s", C_RED))
    setText("MeterBanner", string.format("HF %.2f: near liquidation (below %.2f)", lowest.hf, liq), C_RED)
  elseif level == 1 then
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,550,12 | Fill Color 14,14,17,240 | StrokeWidth 2 | Stroke Color %s", C_AMBER))
    setText("MeterBanner", string.format("HF %.2f: health factor is low (liquidation below %.2f)", lowest.hf, liq), C_AMBER)
  else
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,550,12 | Fill Color 14,14,17,240 | StrokeWidth 1 | Stroke Color %s", C_BORDER))
    setText("MeterBanner", "", C_AMBER)
  end

  -- market: the FT price meters open the FT-ftUSD spot page on the chain being shown
  local mkt = marketUrl("FT-ftUSD", cfg.priceChain)
  for _, m in ipairs({ "MeterMarketHead", "MeterPriceLbl", "MeterPriceVal", "MeterPriceChartLabel", "MeterPriceChart" }) do link(m, mkt) end
  if S.price then
    local ch = S.price.changePct24h
    local c = stale("price") and dim(deltaColor(ch)) or deltaColor(ch)
    setText("MeterPriceVal", fmtPrice(S.price.price) .. (ch and ("  " .. fmtPct(ch) .. " 24h") or ""), c)
  else setText("MeterPriceVal", "unavailable", C_FAINT) end
  if S.fees then
    local dod = feesDayOverDay(S.feesSeries, t)
    local c = stale("fees") and dim(deltaColor(dod)) or deltaColor(dod)
    setText("MeterFeesVal", fmtUsd(S.fees.period24h) .. (dod and ("  " .. fmtPct(dod) .. " d/d") or ""), c)
  else setText("MeterFeesVal", "unavailable", C_FAINT) end

  if S.feesSeries and #S.feesSeries > 1 then
    local v = {}
    for i, r in ipairs(S.feesSeries) do v[i] = r.total end
    renderBars("MeterFeesChart", v)
    setText("MeterFeesChartLabel", string.format("Fees, last %d days (today so far in light purple)", #v), C_FAINT)
  end
  if S.klines and #S.klines > 1 then
    local v = {}
    for i, r in ipairs(S.klines) do v[i] = r.close end
    renderLine("MeterPriceChart", v)
    setText("MeterPriceChartLabel", string.format("FT market price, last %d days", #v), C_FAINT)
  end

  -- account
  local hasWallet = cfg.wallet ~= ""
  local function acct(meter, text, color) setText(meter, hasWallet and text or "", color or C_TEXT) end
  if not hasWallet then
    setText("MeterAccountHint", cfg.walletRaw ~= "" and "Wallet is not a valid address (0x + 40 hex characters)"
      or "Add your wallet to see health factor, PnL, FT earned, points, ftPUT and positions. Click 'Set wallet'.",
      cfg.walletRaw ~= "" and C_RED or C_SUB)
    for _, m in ipairs({ "MeterHfVal", "MeterPnlVal", "MeterEarnVal", "MeterPointsVal", "MeterPutVal", "MeterPosHead" }) do setText(m, "") end
    for i = 1, POS_ROWS do setText("MeterPos" .. i, "") end
    for _, m in ipairs({ "MeterHfLbl", "MeterPnlLbl", "MeterEarnLbl", "MeterPointsLbl", "MeterPutLbl" }) do setText(m, "") end
  else
    setText("MeterAccountHint", "")
    local lbl = { MeterHfLbl = "Health factor", MeterPnlLbl = "PnL (unrealized)", MeterEarnLbl = "FT earned", MeterPointsLbl = "Points", MeterPutLbl = "ftPUT gain" }
    for m, v in pairs(lbl) do setText(m, v, C_FAINT) end
    local l = lendList()
    if l then
      if lowest then
        local c = level == 2 and C_RED or (level == 1 and C_AMBER or C_GREEN)
        setText("MeterHfVal", fmtHf(lowest.hf) .. "  " .. lowest.name, stale("lend") and dim(c) or c)
      else setText("MeterHfVal", INF .. "  no debt", C_GREEN) end
    else setText("MeterHfVal", "unavailable", C_FAINT) end
    local pnl = pnlTotal()
    if pnl then setText("MeterPnlVal", fmtSignedUsd(pnl), deltaColor(pnl)) else setText("MeterPnlVal", "unavailable", C_FAINT) end
    if S.rewards then
      setText("MeterEarnVal", fmtFt(S.rewards.totalFt) .. " FT", C_TEXT)
    else setText("MeterEarnVal", "unavailable", C_FAINT) end
    if S.points then
      local r = S.rank
      setText("MeterPointsVal", fmtPoints(S.points.total) .. (r and ("  rank " .. thousands(r.rank) .. " of " .. thousands(r.total)) or ""), C_TEXT)
    else setText("MeterPointsVal", "unavailable", C_FAINT) end
    if S.puts then
      local g = putGain(S.puts, S.price and S.price.price)
      if g and g.gainPct then setText("MeterPutVal", fmtPct(g.gainPct) .. "  " .. fmtSignedUsd(g.gainUsd), deltaColor(g.gainUsd))
      else setText("MeterPutVal", S.puts.count .. " position" .. (S.puts.count == 1 and "" or "s"), C_TEXT) end
    else setText("MeterPutVal", "none", C_FAINT) end
    local pos = allPositions()
    if pos then
      setText("MeterPosHead", #pos > 0 and ("Positions: " .. #pos .. " open") or "Positions: none open", C_FAINT)
      for i = 1, POS_ROWS do
        local p = pos[i]
        if p then
          local lev = (p.leverage and p.leverage > 0) and string.format(p.leverage >= 10 and " %.0fx" or " %.1fx", p.leverage) or ""
          setText("MeterPos" .. i, string.format("%s %s%s  %s  %s", p.symbol, p.side, lev, p.network, fmtSignedUsd(p.pnlUsd)), deltaColor(p.pnlUsd))
          link("MeterPos" .. i, marketUrl(p.market, p.chainId))
        else setText("MeterPos" .. i, ""); link("MeterPos" .. i, PORTFOLIO_URL) end
      end
      if #pos > POS_ROWS then setText("MeterPos" .. POS_ROWS, string.format("+%d more (see portfolio)", #pos - POS_ROWS + 1), C_FAINT); link("MeterPos" .. POS_ROWS, PORTFOLIO_URL) end
    else
      setText("MeterPosHead", "Positions: unavailable", C_FAINT)
      for i = 1, POS_ROWS do setText("MeterPos" .. i, "") end
    end
  end
  SK:Bang("!UpdateMeter", "*")
  SK:Bang("!Redraw")
end

-- ---------------------------------------------------------------- notifications
local function notifyDesktop(title, body, level)
  if not cfg.notify then return end
  -- text goes through a file so no quoting can break the command line
  if not writeFile(resource("Notify.txt"), title .. "\n" .. body .. "\n" .. level .. "\n") then return end
  -- #@# is expanded by Rainmeter itself, so the paths stay Unicode-safe on the command line
  SK:Bang('["powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#Notify.ps1" "#@#Notify.txt"]')
end

local function evaluateAlerts()
  local l = lendList()
  if not l or cfg.wallet == "" then return end
  local st, n = decideNotify(alertState, lowestHf(l), { warn = cfg.warn, critical = cfg.critical, cooldownSec = cfg.cooldownSec }, now())
  alertState = st
  saveAlertState()
  if n then
    local title, body, level = notifyText(n)
    notifyDesktop(title, body, level)
  end
end

-- ---------------------------------------------------------------- rank search (leaderboard is sorted by points)
local rank = { active = false }

-- One fetch per page: set the page, enable the measure, reset its UpdateRate counter ("Update" also drops a fetch
-- still in flight for the previous page) and update it now, which re-reads the URL (DynamicVariables=1) and fetches.
local function rankProbe()
  SK:Bang("!SetVariable", "RankPage", tostring(rank.page))
  SK:Bang("!EnableMeasure", "MeasureRank")
  SK:Bang("!CommandMeasure", "MeasureRank", "Update")
  SK:Bang("!UpdateMeasure", "MeasureRank")
end

local function rankStop()
  rank.active = false
  SK:Bang("!DisableMeasure", "MeasureRank")
end

local function rankStart()
  if not S.points or cfg.wallet == "" or rank.active then return end
  if S.rankAt and now() - S.rankAt < RANK_TTL and S.rank then return end
  rank = { active = true, lo = 1, hi = 14, steps = 0 }
  rank.page = math.floor((rank.lo + rank.hi) / 2)
  rankProbe()
end

local function rankStep(body)
  -- an answer for another page (a late response from an earlier probe) is not this step's answer
  local pg = body and body.data and body.data.pagination and tonumber(body.data.pagination.page)
  if pg and pg ~= rank.page then return false end
  local r = rankInPage(body, cfg.wallet, S.points.total)
  if r.found then
    S.rank = { rank = r.rank, total = r.total }
    S.rankAt = now()
    rankStop()
    return true
  end
  if r.total > 0 then rank.hi = math.min(rank.hi, math.max(1, math.ceil(r.total / 500))) end
  if r.empty then rank.hi = math.min(rank.hi, rank.page - 1)
  elseif r.dir == -1 then rank.hi = rank.page - 1
  elseif r.dir == 1 then rank.lo = rank.page + 1
  else rankStop(); return false end
  rank.steps = rank.steps + 1
  if rank.lo > rank.hi or rank.steps > 8 then rankStop(); return false end
  rank.page = math.floor((rank.lo + rank.hi) / 2)
  rankProbe()
  return false
end

-- ---------------------------------------------------------------- data callbacks
-- the JSON body the key's WebParser measure captured (its string value once FinishAction fires)
local JSON_NULL = {} -- the body was the JSON literal null (the positions endpoint's answer for "no positions")
local function load(key)
  local m = MEASURES[key] and SK:GetMeasure(MEASURES[key])
  if not m then return nil end
  local txt = m:GetStringValue()
  if type(txt) == "string" and txt:match("^%s*null%s*$") then return JSON_NULL end
  return jsonDecode(txt, key:sub(1, 4) == "lend" and LEND_SKIP or nil)
end

-- /mm/lend is the heavy call: every RefreshSeconds while anything is borrowed (health factor alerts), every
-- LEND_IDLE_RATE seconds otherwise. UpdateRate counts measure updates, one per second at Update=1000.
local function tuneLendRate()
  if not S.lend then return end -- decide on the all-chains answer, never on Monad alone
  local debt = false
  for _, c in ipairs(lendList() or {}) do if c.debtUsd and c.debtUsd > 0.01 then debt = true end end
  local rate = debt and cfg.refresh or math.max(cfg.refresh, LEND_IDLE_RATE)
  if rate ~= S.lendRate then
    S.lendRate = rate
    for _, m in ipairs({ "MeasureLend", "MeasureLend143" }) do SK:Bang("!SetOption", m, "UpdateRate", tostring(rate)) end
  end
end

-- parse(body) -> value or nil (nil = unusable, keep the last good value)
local PARSE = {
  price = parsePrice, fees = parseFees, feesSeries = parseFeesSeries, klines = parseKlines,
  lend = parseLend, lend143 = parseLend, sum146 = parseSummary, sum1 = parseSummary, sum56 = parseSummary,
  sum143 = parseSummary, rewards = parseRewards, points = parsePoints, pos146 = parsePositions, pos1 = parsePositions,
  pos56 = parsePositions, puts = function(b) return parsePuts(b) end
}

function M.ingest(key, body)
  if key == "rank" then
    if rank.active and S.points then rankStep(body) end
    M.render()
    return
  end
  local parse = PARSE[key]
  if body == JSON_NULL then body = (key:sub(1, 3) == "pos") and {} or nil end
  if not parse or body == nil then return end
  local v = parse(body)
  if key == "puts" then
    S.puts = v                                          -- nil is a valid answer: the wallet has no PUTs
  elseif v == nil then
    return                                              -- unusable payload: keep the last good value, it dims when stale
  else
    S[key] = v
  end
  S.ts[key] = now()
  S.err[key] = nil
  if key == "lend" or key == "lend143" then evaluateAlerts(); tuneLendRate() end
  if key == "points" then rankStart() end
  M.render()
end

-- Every entry point Rainmeter calls goes through guard(): a Lua error is logged (Manage > Log) and shown in the
-- status corner instead of silently leaving the skin on "loading...".
local function guard(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return err end
  local msg = "FlyingTulip " .. name .. " failed: " .. tostring(err)
  if not (SK and pcall(function() SK:Bang("!Log", clean(msg), "Error") end)) then print(msg) end
  if SK then
    pcall(function()
      SK:Bang("!SetOption", "MeterStatus", "Text", "script error, see log")
      SK:Bang("!SetOption", "MeterStatus", "FontColor", C_RED)
      SK:Bang("!UpdateMeter", "MeterStatus")
      SK:Bang("!Redraw")
    end)
  end
end
M.guard = guard

function OnData(key)
  guard("OnData(" .. tostring(key) .. ")", function()
    if not S then return end
    M.ingest(key, load(key))
  end)
end

function OnError(key)
  -- keep the last value; it is dimmed and flagged stale once older than 3 refresh intervals
  guard("OnError(" .. tostring(key) .. ")", function()
    if not S then return end
    S.err[key] = now()
    if key == "rank" and rank.active then rankStop() end
    M.render()
  end)
end

-- InputText's OnDismissAction (Escape or a click elsewhere): put the banner back
function Render() guard("Render", M.render) end

-- ---------------------------------------------------------------- wallet input
function SetWallet(text)
  guard("SetWallet", function()
    local t = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if t ~= "" and normalizeWallet(t) == "" then
      SK:Bang("!SetOption", "MeterBanner", "Text", "Not a valid address (0x + 40 hex characters)")
      SK:Bang("!SetOption", "MeterBanner", "FontColor", C_RED)
      SK:Bang("!UpdateMeter", "MeterBanner")
      SK:Bang("!Redraw")
      return
    end
    -- the file path is left as #@# for Rainmeter to expand, so a non-ASCII profile path still works
    SK:Bang("!WriteKeyValue", "Variables", "Wallet", t == "" and "" or normalizeWallet(t), "#@#Settings.inc")
    os.remove(resource("State.txt"))
    SK:Bang("!Refresh")
  end)
end

-- ---------------------------------------------------------------- skin lifecycle
function Initialize()
  guard("Initialize", function()
    SK = SKIN
    cfg = buildConfig()
    S = { ts = {}, err = {}, startedAt = now(), lendRate = cfg.refresh }
    rank = { active = false }
    loadAlertState()
  end)
end

-- called by the skin's OnRefreshAction once every meter and measure exists
function OnLoaded()
  guard("OnLoaded", function()
    if cfg.wallet ~= "" then
      SK:Bang("!EnableMeasureGroup", "Account")
    else
      SK:Bang("!DisableMeasureGroup", "Account")
    end
    M.render()
  end)
end

local ticks = 0
function Update()
  ticks = ticks + 1
  if S and ticks % 30 == 0 then guard("Update", M.render) end -- ages the "updated" label and dims stale values
  return 0
end

-- exposed for the offline tests (Rainmeter itself only calls the globals above)
M._parse = { fees = parseFees, price = parsePrice, lend = parseLend, summary = parseSummary, rewards = parseRewards,
  puts = parsePuts, points = parsePoints, positions = parsePositions, feesSeries = parseFeesSeries, klines = parseKlines,
  rankInPage = rankInPage }
M._fmt = { usd = fmtUsd, signed = fmtSignedUsd, price = fmtPrice, hf = fmtHf, pct = fmtPct, ft = fmtFt, points = fmtPoints,
  thousands = thousands, wallet = normalizeWallet, rawUnits = rawUnits }
M._alert = { levelFor = levelFor, decideNotify = decideNotify, notifyText = notifyText, threshold = threshold }
M._lowestHf, M._mergeChains, M._putGain, M._feesDayOverDay = lowestHf, mergeChains, putGain, feesDayOverDay
FT_TEST = M
