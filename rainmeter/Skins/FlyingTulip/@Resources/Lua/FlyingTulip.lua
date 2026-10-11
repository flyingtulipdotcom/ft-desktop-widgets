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

-- FT earned, all time and all chains: sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending).
-- It is what the wallet's sftUSD staking and Lend supply have paid over time, so it does not follow the wallet's
-- current size. totalFt is nil when any piece is unknown or a section errored. The parts are kept for the tooltip.
local function parseRewards(body)
  local d = body and body.success ~= false and body.data
  if not d or not d.chains then return nil end
  local errs = d.sectionErrors or {}
  local known = not errs.staking and not errs.lend
  local r = { totalFt = 0, claimableFt = 0, sftClaimed = 0, sftPending = 0, lendReceived = 0, lendPending = 0, chains = {} }
  for _, c in ipairs(d.chains) do
    local st, lm = c.staking, c.lend and c.lend.userMetrics
    local pending, claimed
    if st then
      pending = rawUnits(st.pending_yield_ft, 18)
      if st.claimed_yield_indexed_through_block and not st.claimed_yield_stale then claimed = rawUnits(st.claimed_yield_ft, 18) end
    else
      if errs.staking then pending, claimed = nil, nil else pending, claimed = 0, 0 end
    end
    local received, lpending = 0, 0
    if errs.lend then received, lpending = nil, nil end
    if c.lend then
      local fr = lm and lm.ftRewards
      if lm and lm.ftRewardsError then received, lpending = nil, nil
      elseif fr then received, lpending = rawUnits(fr.receivedFtRaw, 18), rawUnits(fr.pendingFtRaw, 18)
      elseif not lm then received, lpending = nil, nil
      else received, lpending = 0, 0 end
    end
    if pending then r.claimableFt = r.claimableFt + pending end
    if not (pending and claimed and received and lpending) then known = false
    else
      r.sftClaimed, r.sftPending = r.sftClaimed + claimed, r.sftPending + pending
      r.lendReceived, r.lendPending = r.lendReceived + received, r.lendPending + lpending
      local id = tonumber(c.chainId)
      r.chains[#r.chains + 1] = { chainId = id, name = HF_CHAINS[id] or tostring(c.chainId), sft = claimed + pending, lend = received + lpending }
    end
  end
  r.sftFt, r.lendFt = r.sftClaimed + r.sftPending, r.lendReceived + r.lendPending
  r.totalFt = known and (r.sftFt + r.lendFt) or nil
  return r
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

-- Points: the all-chains total (what the leaderboard ranks) plus each chain's share. flyingtulip.com/rewards
-- shows ONE chain at a time in its big number (Sonic first), with the all-networks total in small print under it.
local function parsePoints(body)
  local chains = body and body.data and body.data.chains
  if not chains then return nil end
  local total, per = nil, {}
  for _, c in ipairs(chains) do
    local v = c.userMetrics and num(c.userMetrics.totalPoints)
    if c.isAllChains then
      if v then total = v end
    elseif v and v > 0 then
      local id = c.chainData and tonumber(c.chainData.id)
      per[#per + 1] = { chainId = id, name = (id and HF_CHAINS[id]) or (c.chainData and c.chainData.name) or "?", points = v }
    end
  end
  if not total then return nil end
  table.sort(per, function(a, b) return a.points > b.points end)
  return { total = total, chains = per }
end

-- tooltip texts (plain ASCII: no # [ ] which Rainmeter would read as variables or measures)
local function earnedTip(r)
  if not r then return "" end
  local by = {}
  for _, c in ipairs(r.chains or {}) do
    if c.sft + c.lend >= 0.005 then by[#by + 1] = c.name .. " " .. fmtFt(c.sft + c.lend) end
  end
  return "All time, all chains. sftUSD yield " .. fmtFt(r.sftFt) .. " FT (claimed " .. fmtFt(r.sftClaimed) .. ", pending " ..
    fmtFt(r.sftPending) .. "). Lend FT rewards " .. fmtFt(r.lendFt) .. " FT (received " .. fmtFt(r.lendReceived) ..
    ", pending " .. fmtFt(r.lendPending) .. ")." .. (#by > 0 and (" By chain: " .. table.concat(by, ", ") .. ".") or "") ..
    " This is what the wallet's sftUSD staking and Lend supply paid over time, so a smaller wallet can show more" ..
    " than a larger one. FT held in ftPUTs is not counted."
end
local function pointsTip(p, r)
  if not p then return "" end
  local by = {}
  for _, c in ipairs(p.chains or {}) do by[#by + 1] = c.name .. " " .. fmtPoints(c.points) end
  return "Total over all chains" .. (#by > 0 and (": " .. table.concat(by, ", ")) or "") .. "." ..
    (r and (" Leaderboard rank " .. thousands(r.rank) .. " of " .. thousands(r.total) .. ", all chains.") or "") ..
    " flyingtulip.com/rewards shows one chain at a time, with the all-networks total under it."
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

-- n.wallet (short address) names the wallet, so with several wallets the toast says which one
local function notifyText(n)
  local hf = string.format("%.2f", n.hf)
  local who = n.wallet and (n.wallet .. ": ") or ""
  if n.level == 2 then
    return "FT account near liquidation",
      string.format("%s%s HF %s (liquidation below %.2f). Add collateral or repay now.", who, n.chain, hf, n.liqHf), "critical"
  end
  return "FT account health low", string.format("%s%s HF %s (liquidation below %.2f).", who, n.chain, hf, n.liqHf), "normal"
end

local function threshold(v, fallback)
  local n = num(v)
  if n and n > 1 then return n end
  return fallback
end

-- ---------------------------------------------------------------- skin state and rendering
local S, cfg
local SK -- the SKIN object, set by Initialize() (it does not exist yet while this chunk runs)
local io_ = io

-- data key -> WebParser measure (Data.inc) holding that endpoint's JSON body
local MEASURES = {
  price = "MeasurePrice", fees = "MeasureFees", feesSeries = "MeasureFeesSeries", klines = "MeasureKlines",
  lend = "MeasureLend", lend143 = "MeasureLend143", sum146 = "MeasureSum146", sum1 = "MeasureSum1", sum56 = "MeasureSum56",
  sum143 = "MeasureSum143", rewards = "MeasureRewards", points = "MeasurePoints", pos146 = "MeasurePos146",
  pos1 = "MeasurePos1", pos56 = "MeasurePos56", puts = "MeasurePuts", rank = "MeasureRank", watch = "MeasureWatch",
  watch143 = "MeasureWatch143"
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
local shownText = {} -- what each meter was last given (the layout skips empty detail lines)
local function setText(meter, text, color)
  shownText[meter] = clean(text)
  set(meter, "Text", clean(text))
  if color then set(meter, "FontColor", color) end
end
-- hover text (an empty value removes the option, so no stale tooltip stays behind)
local function tip(meter, text) set(meter, "ToolTipText", clean(text)) end
local function dim(color) return (color:gsub(",%d+$", ",120")) end

local function now() return os.time() end

-- ---------------------------------------------------------------- anonymous usage stats (Plausible), see the README
-- Only the event name, the platform, the skin version and the few values below (tab, element, url, level, endpoint,
-- a wallet count bucket) are sent, by @Resources\UsageStats.ps1 in a hidden PowerShell, fire and forget. Never a
-- wallet address, balance or position; any 0x address that slips into a value is replaced by ":address" here and
-- again in the script. Nothing is sent while Analytics=0. Each event name is capped at 30 per hour.
local SKIN_VERSION = "1.2.0"
local STAT_CAP = 30
local usage = { hour = -1, counts = {}, errAt = {}, openAt = -1e18, pageAt = -1e18 }
local ADDRESS = "0x" .. string.rep("%x", 40)
local function statValue(v)
  return (tostring(v):gsub(ADDRESS, ":address"):gsub('[#"%[%]\r\n]', ""))
end
local function sendStat(name, props)
  if not (cfg and cfg.analytics) then return false end
  local h = math.floor(now() / 3600)
  if h ~= usage.hour then usage.hour, usage.counts = h, {} end
  local c = usage.counts[name] or 0
  if c >= STAT_CAP then return false end
  usage.counts[name] = c + 1
  local args = { '"' .. statValue(name) .. '"', '"' .. SKIN_VERSION .. '"', '"#PROGRAMPATH#Rainmeter.exe"' }
  for _, kv in ipairs(props or {}) do args[#args + 1] = '"' .. kv[1] .. "=" .. statValue(kv[2]) .. '"' end
  SK:Bang('["powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#UsageStats.ps1" ' ..
    table.concat(args, " ") .. ']')
  return true
end
local function walletsBucket(n) return n >= 3 and "3+" or tostring(n) end
-- the launch pageview (at most once an hour, so refreshing the skin is not a launch) and one a day while it runs
local function pageview()
  if sendStat("pageview", { { "walletsConfigured", walletsBucket(#cfg.wallets) } }) then
    usage.pageAt = now()
    writeFile(resource("UsageStats.txt"), string.format("pageview=%d\n", usage.pageAt))
  end
end
-- a failed or unusable answer, at most once an hour per endpoint
local ENDPOINT = { price = "ticker", fees = "fees", feesSeries = "fees", klines = "klines", lend = "lend", lend143 = "lend",
  watch = "lend", watch143 = "lend", sum146 = "summary", sum1 = "summary", sum56 = "summary", sum143 = "summary",
  rewards = "rewards", points = "points", rank = "leaderboard", pos146 = "positions", pos1 = "positions",
  pos56 = "positions", puts = "ftput" }
local function fetchError(key)
  local ep = ENDPOINT[key]
  if not ep or key == "sum143" or key == "lend143" or key == "watch143" then return end -- Monad is not served everywhere yet
  if now() - (usage.errAt[ep] or -1e18) < 3600 then return end
  usage.errAt[ep] = now()
  sendStat("Fetch error", { { "endpoint", ep } })
end
-- Every element that opens flyingtulip.com calls OpenLink(element, url): the click is counted, then the page opens.
local function link(meter, url, element)
  set(meter, "LeftMouseUpAction", string.format([=[[!CommandMeasure MeasureScript "OpenLink('%s','%s')"]]=], element, url))
end

-- Wallet list: "0xA, 0xB" (commas, spaces, semicolons or new lines). Returns the valid wallets (lowercase, no
-- duplicates, in order) and the entries that are not addresses.
local function parseWallets(text)
  local list, bad, seen = {}, {}, {}
  for item in tostring(text or ""):gmatch("[^,;%s]+") do
    local w = normalizeWallet(item)
    if w == "" then bad[#bad + 1] = item
    elseif not seen[w] then seen[w] = true; list[#list + 1] = w end
  end
  return list, bad
end

-- Wallets survive a reinstall: Settings.inc is the source (Rainmeter keeps its values when a newer .rmskin is
-- installed over the skin), and a copy is kept in Rainmeter's own settings folder, outside the skin folder, so even
-- a removed and re-added skin finds them again.
local function backupPath()
  local p = SK:ReplaceVariables("#SETTINGSPATH#")
  if not p or p == "" or p:find("#", 1, true) then return nil end
  if not p:match("[\\/]$") then p = p .. "\\" end
  return p .. "FlyingTulip-wallets.txt"
end

local function buildConfig()
  local warn, crit = threshold(SK:GetVariable("HfWarn"), 1.40), threshold(SK:GetVariable("HfCritical"), 1.30)
  if crit > warn then crit = warn end
  local cd = num(SK:GetVariable("NotifyCooldownMin"))
  local ref = num(SK:GetVariable("RefreshSeconds")) or 60
  local rot = num(SK:GetVariable("RotateSeconds")) or 60
  -- Wallets is the list; Wallet is the single-wallet setting of 1.0.x, still read (and kept equal to the first wallet)
  local listRaw = tostring(SK:GetVariable("Wallets") or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local oneRaw = tostring(SK:GetVariable("Wallet") or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local list, bad = parseWallets(listRaw .. "," .. oneRaw)
  return {
    wallets = list, badWallets = bad, walletRaw = listRaw .. oneRaw, wallet = list[1] or "",
    warn = warn, critical = crit,
    cooldownSec = ((cd and cd >= 1) and cd or 30) * 60,
    notify = tostring(SK:GetVariable("Notifications") or "1") ~= "0",
    priceChain = (tonumber(SK:GetVariable("PriceChainId")) == 146) and 146 or 1,
    refresh = math.max(15, ref),
    analytics = tostring(SK:GetVariable("Analytics") or "1") ~= "0",
    rotate = math.max(10, rot)
  }
end

-- Per-wallet alert state in State.txt, one line per wallet: 0x...=level,last1,last2
-- (1.0.x wrote wallet=/level=/last1=/last2= lines for its one wallet; that is still read.)
local function loadAlertStates()
  local out = {}
  local txt = readFile(resource("State.txt"))
  if not txt then return out end
  local kv = {}
  for k, v in txt:gmatch("(%w+)=([^\r\n]*)") do
    kv[k] = v
    local lv, l1, l2 = v:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
    if k:match("^0x%x+$") and lv then
      out[k:lower()] = { level = tonumber(lv) or 0, last1 = (tonumber(l1) or 0) ~= 0 and tonumber(l1) or -1e18,
        last2 = (tonumber(l2) or 0) ~= 0 and tonumber(l2) or -1e18 }
    end
  end
  if kv.wallet and kv.level and not out[kv.wallet] then
    out[kv.wallet] = { level = tonumber(kv.level) or 0, last1 = tonumber(kv.last1) or -1e18, last2 = tonumber(kv.last2) or -1e18 }
  end
  return out
end
local function saveAlertStates()
  local lines = {}
  for _, w in ipairs(cfg.wallets) do
    local a = S.w[w] and S.w[w].alert
    if a then
      lines[#lines + 1] = string.format("%s=%d,%d,%d", w, a.level, a.last1 > -1e17 and a.last1 or 0, a.last2 > -1e17 and a.last2 or 0)
    end
  end
  writeFile(resource("State.txt"), table.concat(lines, "\n") .. "\n")
end

local function lendList()
  if not S.lend then return nil end
  return mergeChains({ S.lend, S.lend143 or {} })
end
local function walletIndex(w)
  for i, x in ipairs(cfg.wallets) do if x == w then return i end end
  return 0
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
local CHART_W, CHART_H = 312, 64

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
local POS_ROWS = 10
local PANEL_H = 424
-- Three tabs so nothing needs scrolling: the header (wallet shown, switch, status, cog), the banner and the footer
-- stay visible on every tab.
local TAB_ORDER = { "market", "account", "positions" }
local TAB_LABEL = { market = "MeterTabMarket", account = "MeterTabAccount", positions = "MeterTabPositions" }
local TAB_METERS = {
  market = { "MeterPriceLbl", "MeterPriceVal", "MeterFeesLbl", "MeterFeesVal", "MeterFeesChartLabel", "MeterFeesChart",
    "MeterPriceChartLabel", "MeterPriceChart" },
  account = { "MeterAccountHint", "MeterHfLbl", "MeterHfVal", "MeterHfC1", "MeterHfC2", "MeterHfC3", "MeterHfC4",
    "MeterPnlLbl", "MeterPnlVal", "MeterEarnLbl", "MeterEarnVal", "MeterEarnD1", "MeterEarnD2", "MeterEarnD3",
    "MeterPointsLbl", "MeterPointsVal", "MeterPointsD1", "MeterPointsD2", "MeterPutLbl", "MeterPutVal" },
  positions = { "MeterPosHead", "MeterPos1", "MeterPos2", "MeterPos3", "MeterPos4", "MeterPos5", "MeterPos6", "MeterPos7",
    "MeterPos8", "MeterPos9", "MeterPos10" },
}
local function validTab(t) return t == "market" or t == "account" or t == "positions" end

-- Account tab rows stacked on one grid: every row 20 px (label and value on the same line), every detail line 16 px,
-- a 6 px gap between groups. Empty detail lines take no room, so no group leaves a hole above the next one.
local ACCOUNT_TOP, ROW_H, DETAIL_H, GROUP_GAP = 102, 20, 16, 6
local ACCOUNT_GROUPS = {
  { "MeterHfLbl", "MeterHfVal", { "MeterHfC1", "MeterHfC2", "MeterHfC3", "MeterHfC4" } },
  { "MeterPnlLbl", "MeterPnlVal", {} },
  { "MeterEarnLbl", "MeterEarnVal", { "MeterEarnD1", "MeterEarnD2", "MeterEarnD3" } },
  { "MeterPointsLbl", "MeterPointsVal", { "MeterPointsD1", "MeterPointsD2" } },
  { "MeterPutLbl", "MeterPutVal", {} },
}
local function layoutAccount(hasText)
  local y = ACCOUNT_TOP
  for _, g in ipairs(ACCOUNT_GROUPS) do
    set(g[1], "Y", tostring(y)); set(g[2], "Y", tostring(y - 1))
    y = y + ROW_H
    for _, d in ipairs(g[3]) do
      set(d, "Y", tostring(y - 1))
      if hasText(d) then y = y + DETAIL_H end
    end
    y = y + GROUP_GAP
  end
end

local function renderTabs()
  for _, name in ipairs(TAB_ORDER) do
    local on = S.tab == name
    for _, m in ipairs(TAB_METERS[name]) do set(m, "Hidden", on and "0" or "1") end
    set(TAB_LABEL[name], "FontColor", on and C_TULIP300 or C_FAINT)
  end
end

function M.render()
  if not S then return end
  local t = now()
  local lowest = lendList() and lowestHf(lendList())
  local level = lowest and levelFor(lowest.hf, { warn = cfg.warn, critical = cfg.critical }, 0) or 0
  local liq = lowest and lowest.liqHf or DEFAULT_LIQ_HF
  local n = #cfg.wallets

  -- header: the wallet shown, "i/n" and the switch icon when there are several
  local sub = "Market, fees and your account"
  if cfg.wallet ~= "" then
    sub = shortAddr(cfg.wallet) .. (n > 1 and string.format("  %d/%d", walletIndex(cfg.wallet), n) or "")
  end
  setText("MeterSub", sub, cfg.wallet ~= "" and C_SUB or C_FAINT)
  set("MeterSwitch", "Hidden", n > 1 and "0" or "1")
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

  -- warning state: panel border and banner (for the wallet shown; a low wallet is always the one shown)
  local who = n > 1 and (shortAddr(cfg.wallet) .. " ") or ""
  if level == 2 then
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,%d,12 | Fill Color 14,14,17,240 | StrokeWidth 2 | Stroke Color %s", PANEL_H, C_RED))
    setText("MeterBanner", string.format("%sHF %.2f: near liquidation (below %.2f)", who, lowest.hf, liq), C_RED)
  elseif level == 1 then
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,%d,12 | Fill Color 14,14,17,240 | StrokeWidth 2 | Stroke Color %s", PANEL_H, C_AMBER))
    setText("MeterBanner", string.format("%sHF %.2f: health factor is low (liquidation below %.2f)", who, lowest.hf, liq), C_AMBER)
  else
    set("MeterBackground", "Shape", string.format("Rectangle 0,0,340,%d,12 | Fill Color 14,14,17,240 | StrokeWidth 1 | Stroke Color %s", PANEL_H, C_BORDER))
    setText("MeterBanner", "", C_AMBER)
  end
  renderTabs()

  -- market: the FT price meters open the FT-ftUSD spot page on the chain being shown
  local mkt = marketUrl("FT-ftUSD", cfg.priceChain)
  link("MeterPriceLbl", mkt, "market-ft-price"); link("MeterPriceVal", mkt, "market-ft-price")
  link("MeterPriceChartLabel", mkt, "market-price-chart"); link("MeterPriceChart", mkt, "market-price-chart")
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
  local details = { "MeterHfC1", "MeterHfC2", "MeterHfC3", "MeterHfC4", "MeterEarnD1", "MeterEarnD2", "MeterEarnD3",
    "MeterPointsD1", "MeterPointsD2" }
  if not hasWallet then
    setText("MeterAccountHint", #cfg.badWallets > 0 and ("Not a valid address: " .. tostring(cfg.badWallets[1]):sub(1, 24) .. " (0x + 40 hex characters)")
      or "Add a wallet to see health factor, PnL, FT earned, points, ftPUT and positions: click the cog at the top right, or 'Wallets' below.",
      #cfg.badWallets > 0 and C_RED or C_SUB)
    for _, m in ipairs({ "MeterHfVal", "MeterPnlVal", "MeterEarnVal", "MeterPointsVal", "MeterPutVal" }) do setText(m, "") end
    for _, m in ipairs({ "MeterHfLbl", "MeterPnlLbl", "MeterEarnLbl", "MeterPointsLbl", "MeterPutLbl" }) do setText(m, "") end
    for _, m in ipairs(details) do setText(m, "") end
    for _, m in ipairs({ "MeterEarnLbl", "MeterEarnVal", "MeterPointsLbl", "MeterPointsVal" }) do tip(m, "") end
    setText("MeterPosHead", "Add a wallet to see its open positions.", C_SUB)
    for i = 1, POS_ROWS do setText("MeterPos" .. i, "") end
  else
    setText("MeterAccountHint", "")
    local lbl = { MeterHfLbl = "Health factor", MeterPnlLbl = "PnL (unrealized)", MeterEarnLbl = "FT earned, all time", MeterPointsLbl = "Points, all chains", MeterPutLbl = "ftPUT gain" }
    for m, v in pairs(lbl) do setText(m, v, C_FAINT) end
    for _, m in ipairs(details) do setText(m, "") end
    local l = lendList()
    if l then
      if lowest then
        local c = level == 2 and C_RED or (level == 1 and C_AMBER or C_GREEN)
        setText("MeterHfVal", fmtHf(lowest.hf) .. "  " .. lowest.name, stale("lend") and dim(c) or c)
      else setText("MeterHfVal", INF .. "  no debt", C_GREEN) end
      local row = 0
      for _, c in ipairs(l) do
        if row < 4 and (c.hf or (c.debtUsd or 0) > 0 or (c.equityUsd or 0) > 0) then
          row = row + 1
          local eqText = c.equityUsd and ("  equity " .. fmtUsd(c.equityUsd)) or ""
          link("MeterHfC" .. row, SITE .. "lend/dashboard/", "account-hf-" .. tostring(c.name):lower():gsub("[^%w]+", "-"))
          setText("MeterHfC" .. row, c.hf and string.format("%-9s HF %s  debt %s%s", c.name, fmtHf(c.hf), fmtUsd(c.debtUsd or 0), eqText)
            or string.format("%-9s no debt%s", c.name, eqText), C_SUB)
        end
      end
    else setText("MeterHfVal", "unavailable", C_FAINT) end
    local pnl = pnlTotal()
    if pnl then setText("MeterPnlVal", fmtSignedUsd(pnl), deltaColor(pnl)) else setText("MeterPnlVal", "unavailable", C_FAINT) end
    local rw = S.rewards
    if rw then
      setText("MeterEarnVal", fmtFt(rw.totalFt) .. " FT", C_TEXT)
      if rw.sftFt then
        setText("MeterEarnD1", string.format("sftUSD yield %s FT  (claimed %s, pending %s)", fmtFt(rw.sftFt), fmtFt(rw.sftClaimed), fmtFt(rw.sftPending)), C_SUB)
        setText("MeterEarnD2", string.format("Lend rewards %s FT  (received %s, pending %s)", fmtFt(rw.lendFt), fmtFt(rw.lendReceived), fmtFt(rw.lendPending)), C_SUB)
        local by = {}
        for _, c in ipairs(rw.chains or {}) do if c.sft + c.lend >= 0.005 then by[#by + 1] = c.name .. " " .. fmtFt(c.sft + c.lend) end end
        setText("MeterEarnD3", #by > 0 and ("By chain: " .. table.concat(by, ", ")) or "", C_FAINT)
      end
    else setText("MeterEarnVal", "unavailable", C_FAINT) end
    tip("MeterEarnVal", earnedTip(rw)); tip("MeterEarnLbl", earnedTip(rw))
    if S.points then
      local r = S.rank
      setText("MeterPointsVal", fmtPoints(S.points.total) .. (r and ("  rank " .. thousands(r.rank)) or ""), C_TEXT)
      local by = {}
      for _, c in ipairs(S.points.chains or {}) do by[#by + 1] = c.name .. " " .. fmtPoints(c.points) end
      setText("MeterPointsD1", table.concat(by, ", "), C_SUB)
      setText("MeterPointsD2", r and string.format("Rank %s of %s, all chains", thousands(r.rank), thousands(r.total))
        or "flyingtulip.com shows one chain at a time", C_FAINT)
    else setText("MeterPointsVal", "unavailable", C_FAINT) end
    tip("MeterPointsVal", pointsTip(S.points, S.rank)); tip("MeterPointsLbl", pointsTip(S.points, S.rank))
    if S.puts then
      local g = putGain(S.puts, S.price and S.price.price)
      if g and g.gainPct then setText("MeterPutVal", fmtPct(g.gainPct) .. "  " .. fmtSignedUsd(g.gainUsd), deltaColor(g.gainUsd))
      else setText("MeterPutVal", S.puts.count .. " position" .. (S.puts.count == 1 and "" or "s"), C_TEXT) end
    else setText("MeterPutVal", "none", C_FAINT) end
    layoutAccount(function(m) return (shownText[m] or "") ~= "" end)
    local pos = allPositions()
    if pos then
      setText("MeterPosHead", #pos > 0 and ("Positions of " .. shortAddr(cfg.wallet) .. ": " .. #pos .. " open") or "Positions: none open", C_FAINT)
      for i = 1, POS_ROWS do
        local p = pos[i]
        if p then
          local lev = (p.leverage and p.leverage > 0) and string.format(p.leverage >= 10 and " %.0fx" or " %.1fx", p.leverage) or ""
          setText("MeterPos" .. i, string.format("%s %s%s  %s  %s", p.symbol, p.side, lev, p.network, fmtSignedUsd(p.pnlUsd)), deltaColor(p.pnlUsd))
          link("MeterPos" .. i, marketUrl(p.market, p.chainId), "positions-row")
        else setText("MeterPos" .. i, ""); link("MeterPos" .. i, PORTFOLIO_URL, "positions-row") end
      end
      if #pos > POS_ROWS then setText("MeterPos" .. POS_ROWS, string.format("+%d more (see portfolio)", #pos - POS_ROWS + 1), C_FAINT); link("MeterPos" .. POS_ROWS, PORTFOLIO_URL, "positions-more") end
    else
      setText("MeterPosHead", "Positions: unavailable", C_FAINT)
      for i = 1, POS_ROWS do setText("MeterPos" .. i, "") end
    end
  end
  SK:Bang("!UpdateMeter", "*")
  SK:Bang("!Redraw")
end

-- tab labels: show that tab and remember it in Settings.inc (no refresh needed)
function ShowTab(name)
  M.guard("ShowTab", function()
    if not validTab(name) or not S then return end
    S.tab = name
    SK:Bang("!WriteKeyValue", "Variables", "Tab", name, "#@#Settings.inc")
    sendStat("Tab view", { { "tab", name } })
    M.render()
  end)
end

-- ---------------------------------------------------------------- notifications
local function notifyDesktop(title, body, level)
  if not cfg.notify then return end
  -- text goes through a file so no quoting can break the command line
  if not writeFile(resource("Notify.txt"), title .. "\n" .. body .. "\n" .. level .. "\n") then return end
  -- #@# is expanded by Rainmeter itself, so the paths stay Unicode-safe on the command line
  SK:Bang('["powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#Notify.ps1" "#@#Notify.txt"]')
end

-- ---------------------------------------------------------------- wallets: per-wallet state, rotation, watch
-- The skin shows one wallet at a time (S.cur). Its account values live directly in S (S.lend, S.rewards, ...) so the
-- renderer reads them as before; the other wallets' values are parked in S.w[addr] and swapped in on a switch.
local ACCOUNT_KEYS = { "lend", "lend143", "sum146", "sum1", "sum56", "sum143", "rewards", "points", "pos146", "pos1", "pos56", "puts" }

local function walletState(w)
  local W = S.w[w]
  if not W then
    W = { data = {}, ts = {}, err = {}, alert = { level = 0, last1 = -1e18, last2 = -1e18 } }
    S.w[w] = W
  end
  return W
end
local function stash()
  if S.cur == "" then return end
  local W = walletState(S.cur)
  for _, k in ipairs(ACCOUNT_KEYS) do W.data[k], W.ts[k], W.err[k] = S[k], S.ts[k], S.err[k] end
  W.rank, W.rankAt, W.lendRate = S.rank, S.rankAt, S.lendRate
end
local function unstash(w)
  local W = walletState(w)
  for _, k in ipairs(ACCOUNT_KEYS) do S[k], S.ts[k], S.err[k] = W.data[k], W.ts[k], W.err[k] end
  S.rank, S.rankAt, S.lendRate = W.rank, W.rankAt, W.lendRate or cfg.refresh
end
-- the merged lend chains of any wallet (the shown one reads S, the others their parked values)
local function lendOf(w)
  local lend, l143
  if w == S.cur then lend, l143 = S.lend, S.lend143 else local W = walletState(w); lend, l143 = W.data.lend, W.data.lend143 end
  if not lend then return nil end
  return mergeChains({ lend, l143 or {} })
end
local function hasDebt(list)
  for _, c in ipairs(list or {}) do if c.debtUsd and c.debtUsd > 0.01 then return true end end
  return false
end
-- the wallet whose health factor is at or below the warning threshold (the lowest one when several are), else nil
local function pinnedWallet()
  local best, bestHf
  for _, w in ipairs(cfg.wallets) do
    if walletState(w).alert.level >= 1 then
      local lo = lowestHf(lendOf(w) or {})
      if lo and (not bestHf or lo.hf < bestHf) then best, bestHf = w, lo.hf end
    end
  end
  return best
end

local switchTo -- defined below (alerts switch to a wallet that turns low)

-- Alerts for one wallet, from a fresh /mm/lend read only: once per crossing, per wallet, naming the wallet.
local function evaluateAlertsFor(w, list)
  if not list or w == "" then return end
  local W = walletState(w)
  local prev = W.alert.level
  local st, n = decideNotify(W.alert, lowestHf(list), { warn = cfg.warn, critical = cfg.critical, cooldownSec = cfg.cooldownSec }, now())
  W.alert = st
  saveAlertStates()
  if n then
    n.wallet = shortAddr(w)
    local title, body, level = notifyText(n)
    notifyDesktop(title, body, level)
    sendStat("HF alert shown", { { "level", n.level == 2 and "danger" or "warning" } })
  end
  -- a wallet that just turned low is shown at once, and stays shown while it is low (see Update)
  if st.level > prev and w ~= S.cur then switchTo(w) end
end
local function evaluateAlerts() evaluateAlertsFor(S.cur, lendList()) end

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
  return jsonDecode(txt, (key:sub(1, 4) == "lend" or key:sub(1, 5) == "watch") and LEND_SKIP or nil)
end

local LEND_IGNORE = 10 -- seconds after a switch during which an unforced /mm/lend answer is the previous wallet's
local function lendRateFor(debt) return debt and cfg.refresh or math.max(cfg.refresh, LEND_IDLE_RATE) end

-- /mm/lend is the heavy call: every RefreshSeconds while anything is borrowed (health factor alerts), every
-- LEND_IDLE_RATE seconds otherwise. UpdateRate counts measure updates, one per second at Update=1000.
local function applyLendRate(rate)
  S.lendRate = rate
  for _, m in ipairs({ "MeasureLend", "MeasureLend143" }) do SK:Bang("!SetOption", m, "UpdateRate", tostring(rate)) end
end
local function tuneLendRate()
  if not S.lend then return end -- decide on the all-chains answer, never on Monad alone
  local rate = lendRateFor(hasDebt(lendList()))
  if rate ~= S.lendRate then applyLendRate(rate) end
end

-- Show wallet w: park the current wallet's values, bring w's back, point the account measures at w and fetch.
-- A WebParser answer does not say which wallet it is for, and a fetch started for the previous wallet may still be in
-- flight: "Update" drops it (and refetches for w). /mm/lend is the one exception, to keep the 500 KB read rare: for a
-- wallet without debt whose lend value is fresh it is not refetched, and any lend answer in the next LEND_IGNORE
-- seconds is dropped instead (it can only be the previous wallet's: w's own next read starts a full rate later).
local function forceFetch(measure)
  SK:Bang("!CommandMeasure", measure, "Update")
  SK:Bang("!UpdateMeasure", measure)
end
switchTo = function(w)
  if w == "" or w == S.cur then S.shownAt = now(); return end
  stash()
  if rank.active then rankStop() end
  S.cur, cfg.wallet = w, w
  unstash(w)
  S.shownAt = now()
  SK:Bang("!SetVariable", "CurWallet", w)
  applyLendRate(S.lendRate or cfg.refresh)
  local W = walletState(w)
  local keepLend = not W.debt and S.ts.lend and now() - S.ts.lend < (S.lendRate or cfg.refresh)
  S.lendIgnoreUntil = keepLend and (now() + LEND_IGNORE) or nil
  for _, k in ipairs(ACCOUNT_KEYS) do
    if not (keepLend and (k == "lend" or k == "lend143")) then forceFetch(MEASURES[k]) end
  end
  M.render()
end
local function nextWallet()
  local n = #cfg.wallets
  if n == 0 then return "" end
  return cfg.wallets[walletIndex(S.cur) % n + 1]
end

-- Background health watch for the wallets that are not shown: one /mm/lend read at a time through MeasureWatch,
-- each wallet every RefreshSeconds while it has debt, every 10 minutes otherwise. Only this read and the shown
-- wallet's own reads raise alerts.
local watch = { active = false, last = 0 }
local function watchStop()
  watch.active = false
  SK:Bang("!DisableMeasure", "MeasureWatch")
  SK:Bang("!DisableMeasure", "MeasureWatch143")
end
local function watchStep()
  if cfg.wallet == "" or #cfg.wallets < 2 then return end
  if watch.active then
    if now() - watch.at > 90 then watchStop() end -- no answer: try again later
    return
  end
  local n = #cfg.wallets
  for i = 1, n do
    local idx = (watch.last + i - 1) % n + 1
    local w = cfg.wallets[idx]
    if w ~= S.cur then
      local W = walletState(w)
      local due = (not W.ts.lend or now() - W.ts.lend >= lendRateFor(W.debt)) and (not W.watchErr or now() - W.watchErr >= 60)
      if due then
        watch = { active = true, addr = w, at = now(), last = idx, pending = 2 }
        SK:Bang("!SetVariable", "WatchWallet", w)
        SK:Bang("!EnableMeasure", "MeasureWatch")
        SK:Bang("!EnableMeasure", "MeasureWatch143")
        forceFetch("MeasureWatch")
        forceFetch("MeasureWatch143")
        return
      end
    end
  end
end
-- One answer of a watch read (key watch: all chains, watch143: Monad). Alerts are evaluated once both are in, on the
-- merged chains. An unusable all-chains answer fails the read (retried after a minute); Monad may be absent.
local function watchIngest(key, body)
  if not watch.active then return end
  local v = body and body ~= JSON_NULL and parseLend(body)
  if key == "watch" then watch.main = v or false else watch.m143 = v or {} end
  watch.pending = watch.pending - 1
  if watch.pending > 0 then return end
  local w, main, m143 = watch.addr, watch.main, watch.m143 or {}
  watchStop()
  if not main then walletState(w).watchErr = now(); return end
  if w == S.cur then return end -- shown meanwhile: its own reads (forced at the switch) are the ones to use
  local W = walletState(w)
  W.data.lend, W.data.lend143, W.ts.lend, W.ts.lend143, W.err.lend, W.watchErr = main, m143, now(), now(), nil, nil
  local list = mergeChains({ main, m143 })
  W.debt = hasDebt(list)
  evaluateAlertsFor(w, list)
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
  if key == "watch" or key == "watch143" then watchIngest(key, body); M.render(); return end
  if (key == "lend" or key == "lend143") and S.lendIgnoreUntil and now() < S.lendIgnoreUntil then return end
  local parse = PARSE[key]
  if body == JSON_NULL then body = (key:sub(1, 3) == "pos") and {} or nil end
  if not parse or body == nil then return end
  local v = parse(body)
  if key == "puts" then
    S.puts = v                                          -- nil is a valid answer: the wallet has no PUTs
  elseif v == nil then
    fetchError(key)
    return                                              -- unusable payload: keep the last good value, it dims when stale
  else
    S[key] = v
  end
  S.ts[key] = now()
  S.err[key] = nil
  if key == "lend" or key == "lend143" then
    walletState(S.cur).debt = hasDebt(lendList())
    evaluateAlerts(); tuneLendRate()
  end
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
    if key == "watch" or key == "watch143" then fetchError(key); watchIngest(key, nil); return end
    S.err[key] = now()
    fetchError(key)
    if key == "rank" and rank.active then rankStop() end
    M.render()
  end)
end

-- InputText's OnDismissAction (Escape or a click elsewhere): put the banner back
function Render() guard("Render", M.render) end

-- ---------------------------------------------------------------- wallet list (UI only: the cog, the Wallets button,
-- the right-click menu). Saved to Settings.inc (Wallets, plus Wallet = the first one for 1.0.x) and to the backup.
local function banner(text, color)
  SK:Bang("!SetOption", "MeterBanner", "Text", clean(text))
  SK:Bang("!SetOption", "MeterBanner", "FontColor", color)
  SK:Bang("!UpdateMeter", "MeterBanner")
  SK:Bang("!Redraw")
end
local function writeBackup(list)
  local p = backupPath()
  if p then writeFile(p, table.concat(list, "\n") .. "\n") end
end
local function saveWallets(list)
  local was, now_ = {}, {}
  for _, w in ipairs(cfg.wallets) do was[w] = true end
  for _, w in ipairs(list) do now_[w] = true; if not was[w] then was.added = true end end
  for _, w in ipairs(cfg.wallets) do if not now_[w] then was.removed = true end end
  if was.added then sendStat("Wallet added") end
  if was.removed then sendStat("Wallet removed") end
  -- the file path is left as #@# for Rainmeter to expand, so a non-ASCII profile path still works
  SK:Bang("!WriteKeyValue", "Variables", "Wallets", table.concat(list, ", "), "#@#Settings.inc")
  SK:Bang("!WriteKeyValue", "Variables", "Wallet", list[1] or "", "#@#Settings.inc")
  writeBackup(list)
  SK:Bang("!Refresh")
end
local function badText(bad) return "Not a valid address: " .. tostring(bad[1]):sub(1, 24) .. " (0x + 40 hex characters)" end

-- the whole list from the settings box: add, edit or remove addresses in one line; empty clears every wallet
function SetWallets(text)
  guard("SetWallets", function()
    local list, bad = parseWallets(text)
    if #bad > 0 then banner(badText(bad), C_RED); return end
    saveWallets(list)
  end)
end
SetWallet = SetWallets -- 1.0.x name (an old Main.ini still calls it)

-- "Add wallet...": every address in the text that is not in the list yet goes to the end
function AddWallet(text)
  guard("AddWallet", function()
    local add, bad = parseWallets(text)
    if #bad > 0 then banner(badText(bad), C_RED); return end
    if #add == 0 then Render(); return end
    local list = {}
    for _, w in ipairs(cfg.wallets) do list[#list + 1] = w end
    for _, w in ipairs(add) do if walletIndex(w) == 0 then list[#list + 1] = w end end
    saveWallets(list)
  end)
end

function RemoveShownWallet()
  guard("RemoveShownWallet", function()
    if cfg.wallet == "" then return end
    local list = {}
    for _, w in ipairs(cfg.wallets) do if w ~= cfg.wallet then list[#list + 1] = w end end
    saveWallets(list)
  end)
end

function NextWallet()
  guard("NextWallet", function()
    if #cfg.wallets > 1 then switchTo(nextWallet()); sendStat("Wallet switch") end
  end)
end

-- opens the settings box: batch 1 edits the whole list, batch 2 adds to it
function OpenWallets(batch)
  guard("OpenWallets", function()
    local add = tonumber(batch) == 2
    sendStat("Settings open")
    SK:Bang("!SetVariable", "Wallets", table.concat(cfg.wallets, ", "))
    SK:Bang("!UpdateMeasure", "MeasureInput")
    banner(add and "Paste a wallet (0x...) to add and press Enter"
      or "Wallets, comma separated. Enter saves. Right-click the skin for more", C_TULIP300)
    SK:Bang("!CommandMeasure", "MeasureInput", "ExecuteBatch " .. (add and "2" or "1"))
  end)
end

-- every element that opens flyingtulip.com: count the click (element id, the URL without any address), open the page
function OpenLink(element, url)
  guard("OpenLink", function()
    url = tostring(url or "")
    if not url:match("^https://flyingtulip%.com/") then return end
    sendStat("Link click", { { "element", element }, { "url", url } })
    SK:Bang('["' .. url .. '"]')
  end)
end
-- the mouse came over the skin: counted as opening it, at most once per 30 minutes
function PanelOpen()
  guard("PanelOpen", function()
    if now() - usage.openAt < 1800 then return end
    usage.openAt = now()
    sendStat("Panel open")
  end)
end
function ManualRefresh()
  guard("ManualRefresh", function()
    sendStat("Refresh")
    SK:Bang("!Refresh")
  end)
end
-- Advanced: anonymous usage stats on or off (Settings.inc Analytics=1 or 0)
function ToggleAnalytics()
  guard("ToggleAnalytics", function()
    cfg.analytics = not cfg.analytics
    SK:Bang("!WriteKeyValue", "Variables", "Analytics", cfg.analytics and "1" or "0", "#@#Settings.inc")
    banner(cfg.analytics and "Anonymous usage stats are on" or "Anonymous usage stats are off", C_TULIP300)
  end)
end

-- ---------------------------------------------------------------- skin lifecycle
function Initialize()
  guard("Initialize", function()
    SK = SKIN
    cfg = buildConfig()
    -- nothing in Settings.inc (a fresh install, or a skin folder replaced by hand): take the wallets kept outside it
    if cfg.walletRaw == "" then
      local p = backupPath()
      local saved = p and readFile(p)
      local list = parseWallets(saved or "")
      if #list > 0 then
        SK:Bang("!WriteKeyValue", "Variables", "Wallets", table.concat(list, ", "), "#@#Settings.inc")
        SK:Bang("!WriteKeyValue", "Variables", "Wallet", list[1], "#@#Settings.inc")
        cfg.wallets, cfg.wallet, cfg.walletRaw = list, list[1], table.concat(list, ", ")
      end
    elseif #cfg.wallets > 0 then
      local p = backupPath()
      local want = table.concat(cfg.wallets, "\n") .. "\n"
      if p and readFile(p) ~= want then writeBackup(cfg.wallets) end
    end
    local tab = tostring(SK:GetVariable("Tab") or ""):lower()
    if not validTab(tab) then tab = cfg.wallet ~= "" and "account" or "market" end
    S = { ts = {}, err = {}, startedAt = now(), lendRate = cfg.refresh, w = {}, cur = cfg.wallet, shownAt = now(), tab = tab }
    rank = { active = false }
    watch = { active = false, last = 0 }
    -- the launch pageview, unless one was sent less than an hour ago (a skin refresh is not a launch)
    usage = { hour = -1, counts = {}, errAt = {}, openAt = -1e18, pageAt = -1e18 }
    local up = tonumber((readFile(resource("UsageStats.txt")) or ""):match("pageview=(%d+)") or "")
    if up then usage.pageAt = up end
    if now() - usage.pageAt >= 3600 then pageview() end
    local states = loadAlertStates()
    for _, w in ipairs(cfg.wallets) do
      local a = states[w]
      if a then walletState(w).alert = { level = a.level, last1 = a.last1, last2 = a.last2 } else walletState(w) end
    end
  end)
end

-- called by the skin's OnRefreshAction once every meter and measure exists
function OnLoaded()
  guard("OnLoaded", function()
    SK:Bang("!SetVariable", "Wallets", table.concat(cfg.wallets, ", "))
    if cfg.wallet ~= "" then
      SK:Bang("!SetVariable", "CurWallet", cfg.wallet)
      SK:Bang("!EnableMeasureGroup", "Account")
    else
      SK:Bang("!DisableMeasureGroup", "Account")
    end
    M.render()
  end)
end

-- Once a second (Update=1000): rotate every RotateSeconds through the wallets, except while one is low (it stays
-- shown, and a manual switch away from it comes back at the next rotation), and run the background health watch.
local ticks = 0
function Update()
  ticks = ticks + 1
  if not S then return 0 end
  guard("Update", function()
    if #cfg.wallets > 1 and now() - S.shownAt >= cfg.rotate then
      local pin = pinnedWallet()
      switchTo(pin or nextWallet())
    end
    watchStep()
    if now() - usage.pageAt >= 86400 then pageview() end
    if ticks % 30 == 0 then M.render() end -- ages the "updated" label and dims stale values
  end)
  return 0
end

-- exposed for the offline tests (Rainmeter itself only calls the globals above)
M._parse = { fees = parseFees, price = parsePrice, lend = parseLend, summary = parseSummary, rewards = parseRewards,
  puts = parsePuts, points = parsePoints, positions = parsePositions, feesSeries = parseFeesSeries, klines = parseKlines,
  rankInPage = rankInPage, wallets = parseWallets }
M._fmt = { usd = fmtUsd, signed = fmtSignedUsd, price = fmtPrice, hf = fmtHf, pct = fmtPct, ft = fmtFt, points = fmtPoints,
  thousands = thousands, wallet = normalizeWallet, rawUnits = rawUnits }
M._alert = { levelFor = levelFor, decideNotify = decideNotify, notifyText = notifyText, threshold = threshold }
M._tips = { earned = earnedTip, points = pointsTip }
M._lowestHf, M._mergeChains, M._putGain, M._feesDayOverDay = lowestHf, mergeChains, putGain, feesDayOverDay
M._state = function() return S, cfg end
FT_TEST = M
