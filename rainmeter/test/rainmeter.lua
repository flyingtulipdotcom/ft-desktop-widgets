-- A small Rainmeter stand-in for the offline tests (lua5.1). It follows Rainmeter 4.5's own code, not our skin's
-- assumptions, wherever the skin depends on it:
--   * Script measures: the file runs in its own environment (globals fall through to _G); SKIN and SELF are put
--     into that environment only AFTER the chunk has run, then Initialize() is called (LuaScript.cpp,
--     MeasureScript.cpp). An error is logged and the measure carries on, exactly as Rainmeter does.
--   * WebParser: only the real option names are read (FinishAction, OnConnectErrorAction, OnRegExpErrorAction,
--     OnDownloadErrorAction, ...). Fetch mode: the RegExp result becomes the string value, then FinishAction runs.
--     Download mode (Download=1, no RegExp): the body is written to DownloadFile\<name> and the string value is
--     that path. UpdateRate counts measure updates; a fetch in flight blocks the next one; !CommandMeasure
--     <measure> "Update" resets the counter and drops the fetch in flight (MeasureWebParser.cpp).
--   * Bangs from Lua: SKIN:Bang('!X', a, b) replaces #variables# in each argument, SKIN:Bang('[...]') runs an
--     action string. !SetOption with an empty value deletes the option. Character references [\NNNN] in
--     meter text are resolved when the meter is read.
--   * InputText: ExecuteBatch opens the box; typing runs CommandN with $UserInput$ replaced; dismissing runs
--     OnDismissAction.
-- Not modelled: drawing, real HTTP (the test supplies an http(url) function), timing beyond one update per tick.
local R = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function writeFile(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end

-- INI: ordered sections, case-insensitive keys (kept with their original spelling for lookups by the test)
local function parseIni(text, into, order)
  local cur
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local ln = trim(raw:gsub("\r$", ""))
    if ln ~= "" and ln:sub(1, 1) ~= ";" then
      local sec = ln:match("^%[([^%]]+)%]$")
      if sec then
        cur = into[sec:lower()]
        if not cur then cur = { _name = sec, _opts = {} }; into[sec:lower()] = cur; order[#order + 1] = cur end
      elseif cur then
        local k, v = ln:match("^([^=]+)=(.*)$")
        if k then cur._opts[trim(k):lower()] = v end
      end
    end
  end
end

function R.load(skinDir, opt)
  opt = opt or {}
  local sk = { dir = skinDir, res = skinDir .. "/@Resources/", log = {}, bangs = {}, runs = {}, refreshed = 0,
    sections = {}, order = {}, vars = {}, setopts = {}, http = opt.http, pending = {}, input = nil }
  local main = assert(readFile(skinDir .. "/Main.ini"), "no Main.ini")
  -- @Include lines inside [Variables] pull files in at that point (good enough: our includes are whole files)
  local expanded = main:gsub("\n@Include%d*=([^\r\n]+)", function(path)
    local p = path:gsub("#@#", skinDir .. "/@Resources/"):gsub("\\", "/")
    return "\n" .. assert(readFile(p), "include " .. p)
  end)
  parseIni(expanded, sk.sections, sk.order)
  local v = sk.sections["variables"]
  if v then for k, x in pairs(v._opts) do sk.vars[k] = x end end
  for k, x in pairs(opt.vars or {}) do sk.vars[k:lower()] = x end
  sk.vars["@"] = sk.res
  setmetatable(sk, { __index = R })
  sk:init()
  return sk
end

function R:logf(level, msg) self.log[#self.log + 1] = level .. ": " .. msg end

function R:replaceVars(s)
  return (tostring(s):gsub("#([%w@_]+)#", function(name)
    local x = self.vars[name:lower()]
    if x == nil then return nil end
    return x
  end))
end

function R:option(sec, key)
  local o = self.setopts[sec:lower() .. "~" .. key:lower()]
  if o ~= nil then return o ~= false and o or nil end
  local s = self.sections[sec:lower()]
  local val = s and s._opts[key:lower()]
  if val == nil and s and s._opts.meterstyle then
    local st = self.sections[s._opts.meterstyle:lower()]
    val = st and st._opts[key:lower()]
  end
  return val
end

-- a meter's Text as Rainmeter would draw it: variables and character references resolved
function R:text(meter)
  local t = self:option(meter, "Text")
  if t == nil then return nil end
  t = self:replaceVars(t)
  return (t:gsub("%[\\([xX]?)(%x+)%]", function(x, n)
    local cp = tonumber(n, x ~= "" and 16 or 10)
    if cp == 8734 then return "<INF>" end
    return "<U+" .. string.format("%04X", cp) .. ">"
  end))
end

-- ---------------------------------------------------------------- measures
local function webparserOptions(sk, m)
  local o = function(k) return sk:option(m.name, k) end
  m.url = sk:replaceVars(o("URL") or "")
  m.regexp = o("RegExp") or ""
  m.stringIndex = tonumber(o("StringIndex") or "0") or 0
  m.updateRate = tonumber(sk:replaceVars(o("UpdateRate") or "600")) or 600
  m.download = o("Download") == "1"
  m.downloadFile = o("DownloadFile") or ""
  m.finish = o("FinishAction") or ""
  m.onConnectErr = o("OnConnectErrorAction") or ""
  m.onRegExpErr = o("OnRegExpErrorAction") or ""
  m.onDownloadErr = o("OnDownloadErrorAction") or ""
end

function R:init()
  self.measures, self.measureList = {}, {}
  for _, s in ipairs(self.order) do
    local kind = s._opts.measure
    if kind then
      local m = { name = s._name, kind = kind:lower(), disabled = s._opts.disabled == "1", group = s._opts.group or "",
        dynamic = s._opts.dynamicvariables == "1", counter = 0, value = "" }
      self.measures[s._name:lower()] = m
      self.measureList[#self.measureList + 1] = m
      if m.kind == "webparser" then webparserOptions(self, m) end
      if m.kind == "script" then self:initScript(m, s._opts.scriptfile) end
    end
  end
end

function R:skinObject()
  local sk = self
  local SK = {}
  function SK:GetVariable(name, def) local x = sk.vars[tostring(name):lower()]; if x == nil then return def end; return x end
  function SK:ReplaceVariables(s) return sk:replaceVars(s) end
  function SK:MakePathAbsolute(p) return sk.dir .. "/" .. tostring(p):gsub("\\", "/") end
  function SK:GetMeasure(name)
    local m = sk.measures[tostring(name):lower()]
    if not m then return nil end
    return { GetStringValue = function() return m.value end, GetName = function() return m.name end }
  end
  function SK:Bang(name, ...)
    if select("#", ...) == 0 then return sk:exec(sk:replaceVars(name)) end
    local args = {}
    for i = 1, select("#", ...) do args[i] = sk:replaceVars(tostring(select(i, ...))) end
    sk:bang(name, args)
  end
  return SK
end

function R:initScript(m, file)
  self.script = m
  local path = self.dir .. "/" .. tostring(file):gsub("#@#", "@Resources/"):gsub("\\", "/")
  local chunk, err = loadfile(path)
  if not chunk then self:logf("Error", "Script: " .. err); return end
  local env = setmetatable({}, { __index = _G })
  setfenv(chunk, env)
  local ok, e = pcall(chunk)                                   -- 1. run the file (SKIN does not exist yet)
  if not ok then self:logf("Error", "Script: " .. tostring(e)); return end
  env.SKIN = self:skinObject()                                 -- 2. then SKIN and SELF
  env.SELF = { GetName = function() return m.name end, GetOption = function(_, k, d) return self:option(m.name, k) or d end }
  m.env = env
  if type(env.Initialize) == "function" then                   -- 3. then Initialize()
    local ok2, e2 = pcall(env.Initialize)
    if not ok2 then self:logf("Error", "Script Initialize() failed: " .. tostring(e2)) end
  end
end

function R:runLua(code)
  local m = self.script
  if not (m and m.env) then self:logf("Error", "Script: not initialized"); return end
  local f, err = loadstring(code)
  if not f then self:logf("Error", "Script: " .. err); return end
  setfenv(f, m.env)
  local ok, e = pcall(f)
  if not ok then self:logf("Error", "Script: " .. tostring(e)) end
end

-- ---------------------------------------------------------------- bangs
local function tokenize(s)
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c:match("%s") then i = i + 1
    elseif c == '"' then
      local j = s:find('"', i + 1, true) or (#s + 1)
      out[#out + 1] = s:sub(i + 1, j - 1); i = j + 1
    else
      local j = s:find("%s", i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1); i = j
    end
  end
  return out
end

-- runs an action string: [!Bang a "b c"][!Other] or a bare !Bang, or ["program" args]
function R:exec(action)
  action = trim(action or "")
  if action == "" then return end
  if action:sub(1, 1) ~= "[" then return self:execOne(action) end
  local i = 1
  while i <= #action do
    local a = action:find("[", i, true)
    if not a then break end
    -- find the matching ] outside quotes
    local depth, j, inq = 0, a, false
    while j <= #action do
      local c = action:sub(j, j)
      if c == '"' then inq = not inq
      elseif not inq and c == "[" then depth = depth + 1
      elseif not inq and c == "]" then depth = depth - 1; if depth == 0 then break end end
      j = j + 1
    end
    self:execOne(action:sub(a + 1, j - 1))
    i = j + 1
  end
end

function R:execOne(cmd)
  cmd = trim(cmd)
  if cmd:sub(1, 1) ~= "!" then self.runs[#self.runs + 1] = cmd; self.bangs[#self.bangs + 1] = { name = cmd, args = {} }; return end
  local name, rest = cmd:match("^(!%S+)%s*(.*)$")
  self:bang(name, tokenize(rest))
end

function R:bang(name, a)
  self.bangs[#self.bangs + 1] = { name = name, args = a }
  local n = name:lower()
  if n == "!setoption" then
    local key = a[1]:lower() .. "~" .. a[2]:lower()
    if a[3] == nil or a[3] == "" then self.setopts[key] = false else self.setopts[key] = a[3] end
    local m = self.measures[a[1]:lower()]
    if m and m.kind == "webparser" then webparserOptions(self, m) end
  elseif n == "!setvariable" then self.vars[a[1]:lower()] = a[2] or ""
  elseif n == "!enablemeasure" then local m = self.measures[a[1]:lower()]; if m then m.disabled = false end
  elseif n == "!disablemeasure" then local m = self.measures[a[1]:lower()]; if m then m.disabled = true end
  elseif n == "!enablemeasuregroup" or n == "!disablemeasuregroup" then
    for _, m in ipairs(self.measureList) do if m.group:lower() == a[1]:lower() then m.disabled = (n == "!disablemeasuregroup") end end
  elseif n == "!updatemeasure" then local m = self.measures[a[1]:lower()]; if m then self:updateMeasure(m) end
  elseif n == "!commandmeasure" then
    local m = self.measures[a[1]:lower()]
    if not m then self:logf("Error", "!CommandMeasure: no measure " .. tostring(a[1])); return end
    if m.kind == "script" then self:runLua(a[2])
    elseif m.kind == "webparser" and a[2]:lower() == "update" then m.counter = 0; m.inflight = nil
    elseif m.kind == "plugin" and (self:option(m.name, "Plugin") or ""):lower() == "inputtext" then
      if a[2]:lower():match("^executebatch") then self.input = { measure = m } end
    end
  elseif n == "!writekeyvalue" then
    local file = (a[4] or ""):gsub("\\", "/")
    local txt = readFile(file) or ""
    local sec, key, val = a[1], a[2], a[3]
    local out, insec, done = {}, false, false
    for line in (txt .. (txt:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
      local s = line:match("^%[([^%]]+)%]")
      if s then insec = s:lower() == sec:lower() end
      if insec and not done and line:match("^" .. key .. "=") then line = key .. "=" .. val; done = true end
      out[#out + 1] = line
    end
    if not done then out[#out + 1] = "[" .. sec .. "]"; out[#out + 1] = key .. "=" .. val end
    writeFile(file, table.concat(out, "\n") .. "\n")
  elseif n == "!refresh" then self.refreshed = self.refreshed + 1
  elseif n == "!log" then self:logf(a[2] or "Notice", a[1] or "")
  end
end

-- ---------------------------------------------------------------- update loop
function R:updateMeasure(m)
  if m.disabled then return end
  if m.kind == "webparser" then
    if m.dynamic then webparserOptions(self, m) end
    if m.url ~= "" and not m.url:find("[", 1, true) and not m.inflight then
      if m.counter == 0 then m.inflight = { url = m.url }; self.pending[#self.pending + 1] = m end
      m.counter = m.counter + 1
      if m.counter >= m.updateRate then m.counter = 0 end
    end
  elseif m.kind == "script" and m.env and type(m.env.Update) == "function" then
    local ok, e = pcall(m.env.Update)
    if not ok then self:logf("Error", "Script Update() failed: " .. tostring(e)) end
  end
end

-- one skin update (Update=1000): every enabled measure in file order
function R:tick(n)
  for _ = 1, n or 1 do
    for _, m in ipairs(self.measureList) do self:updateMeasure(m) end
  end
end

-- completes every fetch in flight with self.http(url): string body, or nil for a connection error
function R:deliver()
  local queue = self.pending
  self.pending = {}
  for _, m in ipairs(queue) do
    local req = m.inflight
    if req then
      m.inflight = nil
      local body = self.http and self.http(req.url)
      if body == nil then
        self:exec(self:replaceVars(m.onConnectErr))
      elseif m.download and m.regexp == "" then
        local name = m.downloadFile ~= "" and m.downloadFile or "index"
        os.execute("mkdir -p '" .. self.dir .. "/DownloadFile'")
        local p = self.dir .. "/DownloadFile/" .. name:gsub("\\", "/")
        writeFile(p, body)
        m.value = p
        self:exec(self:replaceVars(m.finish))
      else
        local re = m.regexp
        assert(re == "(?s)^(.*)$" or re == "(?siU)^(.*)$", "mock WebParser only knows the whole-body RegExp, got " .. re)
        assert(m.stringIndex == 0 or m.stringIndex == 1, "StringIndex " .. m.stringIndex)
        m.value = body                                         -- index 0 (whole match) and 1 (the group) are both the body
        self:exec(self:replaceVars(m.finish))
      end
    end
  end
end

-- the skin load sequence: measures initialised (done in load), first update, then OnRefreshAction
function R:start()
  self:tick()
  self:exec(self:replaceVars(self:option("Rainmeter", "OnRefreshAction") or ""))
  return self
end

-- InputText: the user types into the open box and presses Enter, or dismisses it
function R:typeInput(text)
  assert(self.input, "no input box is open")
  local m = self.input.measure
  self.input = nil
  for i = 1, 20 do
    local c = self:option(m.name, "Command" .. i)
    if not c then break end
    self:exec(self:replaceVars(c):gsub("%$[Uu][Ss][Ee][Rr][Ii][Nn][Pp][Uu][Tt]%$", function() return text end))
  end
end
function R:dismissInput()
  assert(self.input, "no input box is open")
  local m = self.input.measure
  self.input = nil
  self:exec(self:replaceVars(self:option(m.name, "OnDismissAction") or ""))
end

function R:errors()
  local out = {}
  for _, l in ipairs(self.log) do if l:find("^Error") then out[#out + 1] = l end end
  return out
end

function R:bangsNamed(n)
  local out = {}
  for _, b in ipairs(self.bangs) do if b.name:lower() == n:lower() then out[#out + 1] = b end end
  return out
end

return R
