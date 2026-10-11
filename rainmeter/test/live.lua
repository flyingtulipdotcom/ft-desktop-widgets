-- lua5.1 test/live.lua [0xA,0xB,...]
-- Runs the skin against the live public API (curl) through the same Rainmeter stand-in as run.lua, then prints what
-- every meter would show, for each wallet in turn (the switch icon is clicked between them). Nothing is written to
-- the repo: the skin is copied to a temp folder first.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local RM = require("rainmeter")
local wallets = arg[1] or ""
local TMP = os.tmpname(); os.remove(TMP)
os.execute("mkdir -p '" .. TMP .. "' && cp -r '" .. here .. "/../Skins/FlyingTulip' '" .. TMP .. "/FlyingTulip'")
local dir = TMP .. "/FlyingTulip"
local f = assert(io.open(dir .. "/@Resources/Settings.inc", "rb")); local s = f:read("*a"); f:close()
s = s:gsub("\nWallets=[^\r\n]*", "\nWallets=" .. wallets)
f = assert(io.open(dir .. "/@Resources/Settings.inc", "wb")); f:write(s); f:close()

local fetched = {}
local function http(url)
  assert(url:match("^https://api%.flyingtulip%.com/[%w%-%._~/%?&=#]*$"), "unexpected URL " .. url)
  local p = io.popen("curl -s -m 30 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) FlyingTulipRainmeter/1.2.0' -H 'Accept: application/json' '" .. url .. "'")
  local body = p:read("*a"); p:close()
  fetched[#fetched + 1] = string.format("%7d bytes  %s", #body, url)
  if body == "" then return nil end
  return body
end

local sk = RM.load(dir, { http = http }):start()
local METERS = { "MeterStatus", "MeterSub", "MeterSwitch", "MeterBanner", "MeterPriceVal", "MeterFeesVal", "MeterFeesChartLabel",
  "MeterPriceChartLabel", "MeterAccountHint", "MeterHfVal", "MeterHfC1", "MeterHfC2", "MeterPnlVal", "MeterEarnLbl", "MeterEarnVal",
  "MeterEarnD1", "MeterEarnD2", "MeterEarnD3", "MeterPointsLbl", "MeterPointsVal", "MeterPointsD1", "MeterPointsD2", "MeterPutVal",
  "MeterPosHead", "MeterPos1", "MeterPos2", "MeterPos3", "MeterPos4" }
local count = select(2, wallets:gsub("0x%x+", ""))
for round = 1, math.max(1, count) do
  if round > 1 then sk:exec(sk:option("MeterSwitch", "LeftMouseUpAction")) end
  for _ = 1, 12 do sk:deliver(); sk:tick() end
  sk:deliver()
  print(string.format("\n---- wallet %d of %d", round, math.max(1, count)))
  for _, m in ipairs(METERS) do
    local t = sk:text(m)
    if t and t ~= "" then print(string.format("%-22s %s", m, t)) end
  end
end
print("")
for _, l in ipairs(fetched) do print(l) end
local errs = sk:errors()
print("\n" .. (#errs == 0 and "no script errors" or table.concat(errs, "\n")))
os.execute("rm -rf '" .. TMP .. "'")
if #errs > 0 then os.exit(1) end
