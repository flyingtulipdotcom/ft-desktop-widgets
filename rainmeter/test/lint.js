// node test/lint.js : static checks for the skin (INI structure, cross references, Lua syntax, scrub).
const fs = require("fs"), path = require("path"), cp = require("child_process")
const root = process.env.FT_SKIN_DIR || path.join(__dirname, "..", "Skins", "FlyingTulip")
const errs = [], ok = (c, m) => { if (!c) errs.push(m) }

function parseIni(file) {
  const sections = {}, order = []
  let cur = null
  fs.readFileSync(file, "utf8").split(/\r?\n/).forEach((raw, i) => {
    const ln = raw.trim()
    if (!ln || ln.startsWith(";")) return
    const m = ln.match(/^\[([^\]]+)\]$/)
    if (m) { ok(!(m[1] in sections), file + ":" + (i + 1) + " duplicate section " + m[1]); cur = sections[m[1]] = sections[m[1]] || {}; order.push(m[1]); return }
    const kv = ln.match(/^([A-Za-z0-9@._]+)\s*=(.*)$/)
    ok(kv, file + ":" + (i + 1) + " not a key=value line: " + ln)
    ok(cur, file + ":" + (i + 1) + " key outside a section")
    if (kv && cur) { ok(!(kv[1] in cur), file + ":" + (i + 1) + " duplicate key " + kv[1]); cur[kv[1]] = kv[2] }
  })
  return { sections, order }
}
const main = parseIni(path.join(root, "Main.ini")), data = parseIni(path.join(root, "@Resources", "Data.inc"))
parseIni(path.join(root, "@Resources", "Settings.inc"))
const lua = fs.readFileSync(path.join(root, "@Resources", "Lua", "FlyingTulip.lua"), "utf8")

// every meter has a type, a known style, and Lua only touches meters that exist
for (const [n, s] of Object.entries(main.sections)) {
  if (!n.startsWith("Meter") && !n.startsWith("Measure")) continue
  ok(s.Meter || s.Measure, n + " has neither Meter= nor Measure=")
  if (s.MeterStyle) ok(s.MeterStyle in main.sections, n + " uses unknown style " + s.MeterStyle)
}
const luaMeters = new Set([...lua.matchAll(/"(Meter[A-Za-z0-9]+)"(?!\s*\.\.)/g)].map(m => m[1]))
for (const m of luaMeters) ok(m in main.sections, "Lua references missing meter " + m)
for (let i = 1; i <= 4; i++) ok("MeterPos" + i in main.sections, "MeterPos" + i + " missing")
const bangTargets = new Set([...JSON.stringify(main).matchAll(/CommandMeasure (Measure[A-Za-z]+)/g)].map(m => m[1]))
for (const m of [...bangTargets, ...[...lua.matchAll(/"(Measure[A-Za-z0-9]+)"/g)].map(x => x[1])])
  ok(m in main.sections || m in data.sections, "bang targets missing measure " + m)

// every text/image/shape meter except the background, buttons, controls (tabs, cog, wallet switch) and the input
// links to a public page; the controls call the script
const CONTROLS = new Set(["MeterCog", "MeterSwitch", "MeterTabMarket", "MeterTabAccount", "MeterTabPositions"])
for (const n of CONTROLS) ok(/^\[!CommandMeasure MeasureScript "\w+\('?\w*'?\)"\]$/.test((main.sections[n] || {}).LeftMouseUpAction || ""), n + " must call the script")
for (const [n, s] of Object.entries(main.sections)) {
  if (!n.startsWith("Meter") || n === "MeterBackground" || n.startsWith("MeterBtn") || n === "MeterInput" || CONTROLS.has(n)) continue
  // through OpenLink(element, url), which counts the click (anonymous usage stats) and opens the page
  ok(/^\[!CommandMeasure MeasureScript "OpenLink\('[a-z0-9-]+','https:\/\/flyingtulip\.com\/[^']*'\)"\]$/.test(s.LeftMouseUpAction || ""), n + " has no flyingtulip.com link through OpenLink")
}

// Option names Rainmeter 4.5 actually reads (MeasureWebParser.cpp, Measure.cpp/Section.cpp, PluginInputText).
// A misspelt action option is silently ignored by Rainmeter, which is how v1.0.0 shipped OnConnectErrAction.
const GENERAL = ["Measure", "Group", "Disabled", "Paused", "DynamicVariables", "UpdateDivider", "OnUpdateAction", "OnChangeAction",
  "Substitute", "RegExpSubstitute", "MinValue", "MaxValue", "AverageSize", "Invert", "IfCondition", "IfTrueAction", "IfFalseAction"]
const WEBPARSER = new Set([...GENERAL, "URL", "RegExp", "StringIndex", "StringIndex2", "UpdateRate", "DecodeCharacterReference",
  "DecodeCodePoints", "Debug", "Debug2File", "Download", "DownloadFile", "ErrorString", "LogSubstringErrors", "CodePage",
  "ProxyServer", "UserAgent", "Flags", "ForceReload", "FinishAction", "OnConnectErrorAction", "OnRegExpErrorAction",
  "OnDownloadErrorAction"].map(s => s.toLowerCase()))
const INPUTTEXT = new Set([...GENERAL, "Plugin", "X", "Y", "W", "H", "SolidColor", "FontColor", "FontFace", "FontSize",
  "StringStyle", "StringAlign", "FocusDismiss", "DefaultValue", "Password", "TopMost", "InputLimit", "InputNumber",
  "OnDismissAction"].map(s => s.toLowerCase()))
const known = (set, k) => set.has(k.toLowerCase()) || /^Header\d*$/i.test(k) || (set === INPUTTEXT && /^Command\d+$/.test(k))

// every WebParser measure fetches the public API into memory, maps to a key the Lua knows, and reports errors
const keys = new Set()
const measuresBlock = (lua.match(/local MEASURES = \{([\s\S]*?)\n\}/) || [])[1]
ok(measuresBlock, "Lua MEASURES table missing")
const luaMeasures = Object.fromEntries([...(measuresBlock || "").matchAll(/(\w+) = "(Measure\w+)"/g)].map(m => [m[1], m[2]]))
for (const [n, s] of Object.entries(data.sections)) {
  ok(s.Measure === "WebParser", n + " must be a WebParser measure")
  for (const k of Object.keys(s)) ok(known(WEBPARSER, k), n + ": " + k + " is not a WebParser option Rainmeter reads")
  ok(!("Download" in s) && !("DownloadFile" in s), n + " must not download to disk (fetch into memory)")
  ok(s.RegExp === "(?s)^(.*)$" && s.StringIndex === "1", n + " must capture the whole body: RegExp=(?s)^(.*)$ StringIndex=1")
  ok(/^https:\/\/api\.flyingtulip\.com\//.test(s.URL), n + " URL must be the public API over https: " + s.URL)
  ok(!/key|token|secret|apikey/i.test(s.URL), n + " URL looks like it carries a credential")
  ok(/(^|\|)ForceReload(\||$)/.test(s.Flags || ""), n + " must bypass the WinINet cache (Flags=ForceReload|...)")
  const k = ((s.FinishAction || "").match(/^\[!CommandMeasure MeasureScript "OnData\('(\w+)'\)"\]$/) || [])[1]
  ok(k, n + " FinishAction does not call OnData"); keys.add(k)
  ok(luaMeasures[k] === n, "Lua MEASURES[" + k + "] is " + luaMeasures[k] + ", Data.inc has " + n)
  for (const a of ["OnConnectErrorAction", "OnRegExpErrorAction"])
    ok((s[a] || "") === "[!CommandMeasure MeasureScript \"OnError('" + k + "')\"]", n + " " + a + " must call OnError('" + k + "')")
  ok(!s.URL.includes("#Wallet#") && !s.URL.includes("#Wallets#"), n + " must read the wallet shown (#CurWallet#), not the settings")
  if (s.URL.includes("#CurWallet#")) ok(s.Group === "Account" && s.Disabled === "1" && s.DynamicVariables === "1", n + " uses the wallet shown so it must start disabled in group Account with DynamicVariables=1")
  else if (s.URL.includes("#WatchWallet#")) ok(!s.Group && s.Disabled === "1" && s.DynamicVariables === "1" && Number(s.UpdateRate) >= 600, n + " (background check) must start disabled, outside the groups, with DynamicVariables=1 and a long UpdateRate")
  else if (n !== "MeasureRank") ok(s.Group === "Data", n + " should be in group Data")
  if (s.URL.includes("#RankPage#")) ok(s.DynamicVariables === "1" && Number(s.UpdateRate) >= 600, n + " needs DynamicVariables=1 and a long UpdateRate (pages are forced from Lua)")
}
for (const k of Object.keys(luaMeasures)) ok(keys.has(k), "Lua MEASURES key " + k + " has no WebParser measure")
const input = main.sections.MeasureInput
ok(input && input.Measure === "Plugin" && input.Plugin === "InputText", "InputText measure missing")
if (input) {
  for (const k of Object.keys(input)) ok(known(INPUTTEXT, k), "MeasureInput: " + k + " is not an InputText option")
  ok(/^\[!CommandMeasure MeasureScript "SetWallets\('\$UserInput\$'\)"\]$/.test(input.Command1 || ""), "InputText Command1 must call SetWallets('$UserInput$')")
  ok(/^\[!CommandMeasure MeasureScript "AddWallet\('\$UserInput\$'\)"\] DefaultValue=""$/.test(input.Command2 || ""), "InputText Command2 must call AddWallet('$UserInput$') with an empty box")
  ok(/Render\(\)/.test(input.OnDismissAction || ""), "InputText OnDismissAction must call Render()")
}
for (const where of [main.sections.Rainmeter.ContextAction, main.sections.MeterBtnWallet.LeftMouseUpAction, main.sections.MeterCog.LeftMouseUpAction])
  ok(where === '[!CommandMeasure MeasureScript "OpenWallets(1)"]', "the cog, the Wallets button and the first menu entry open the wallet list: " + where)
ok(/"ExecuteBatch " \.\./.test(lua), "OpenWallets must open the box with ExecuteBatch")
ok(/^Wallets=$/m.test(fs.readFileSync(path.join(root, "@Resources", "Settings.inc"), "utf8")), "Settings.inc must ship with an empty Wallets=")
ok(/OnLoaded\(\)/.test(main.sections.Rainmeter.OnRefreshAction), "OnRefreshAction must call OnLoaded")
ok(/Settings\.inc/.test(JSON.stringify(main.sections.Variables)), "Settings.inc not included")

// SKIN only exists once Initialize() runs (Rainmeter sets it after the chunk): the one read must be inside Initialize
const code = lua.replace(/--.*$/gm, "")
const skinReads = [...code.matchAll(/\bSKIN\b/g)].length
const init = (code.match(/\nfunction Initialize\(\)\n([\s\S]*?)\nend\n/) || [])[1] || ""
ok(skinReads === 1 && /\bSK = SKIN\b/.test(init), "Lua must read SKIN exactly once, as SK = SKIN inside Initialize()")
ok(!/^local SK\s*=/m.test(code), "Lua must not capture SKIN at load time")
// Rainmeter reads a script without a UTF-16 BOM as ANSI: keep it ASCII, write symbols as [\NNNN] references
ok(!/[^\x00-\x7f]/.test(lua), "FlyingTulip.lua must be plain ASCII")

// Lua syntax (Rainmeter embeds 5.1)
for (const f of ["@Resources/Lua/FlyingTulip.lua"]) {
  const r = cp.spawnSync("luac5.1", ["-p", path.join(root, f)], { encoding: "utf8" })
  ok(r.status === 0, f + ": " + r.stderr)
}
// Lua 5.1 has no goto, no \x escapes, no // or bit operators, and string.format has no '*'
ok(!/\bgoto\b|\\x[0-9a-fA-F]{2}|\.\*[a-z]/.test(lua.replace(/--.*$/gm, "").replace(/"[^"\n]*\*a[^"\n]*"/g, "")), "Lua 5.1 incompatibility")

// scrub
const all = []
;(function walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) e.isDirectory() ? walk(path.join(d, e.name)) : all.push(path.join(d, e.name)) })(path.join(__dirname, ".."))
for (const f of all.filter(f => /\.(ini|inc|lua|ps1|md|sh|js|txt)$/.test(f) && !f.includes("/test/"))) {
  const t = fs.readFileSync(f, "utf8")
  ok(!/opbalance|galaxy\.|\.dev\.|staging|localhost|0x(?!0{38}dEaD|0{40}\b)[0-9a-fA-F]{40}/i.test(t), "scrub: " + f)
}
// the usage stats script: Plausible's event API, the "widget" site, a browser-like user agent, never a wallet
const us = fs.readFileSync(path.join(root, "@Resources", "UsageStats.ps1"), "utf8")
ok(/"https:\/\/plausible\.io\/api\/event"/.test(us) && /domain = "widget"/.test(us) && /url = "app:\/\/widget\/windows"/.test(us), "UsageStats.ps1 target")
ok(/\$ua = "Mozilla\/5\.0 \(Windows NT 10\.0; Win64; x64\) FlyingTulipWidget\/" \+ \$Version/.test(us), "UsageStats.ps1 must send a browser-like user agent")
ok(/-TimeoutSec 10/.test(us) && /0x\[0-9a-fA-F\]\{40\}/.test(us), "UsageStats.ps1: short timeout and the address scrub")
ok(/^local SKIN_VERSION = "([^"]+)"$/m.test(lua) && lua.match(/^local SKIN_VERSION = "([^"]+)"$/m)[1] === (fs.readFileSync(path.join(root, "..", "..", "RMSKIN.ini"), "utf8").match(/^Version=(.+)$/m) || [])[1], "SKIN_VERSION must match RMSKIN.ini")
for (const f of [path.join(root, "Main.ini"), path.join(root, "@Resources", "Settings.inc"), path.join(root, "@Resources", "UsageStats.ps1"), path.join(root, "@Resources", "Lua", "FlyingTulip.lua")])
  ok(!/trac[k]/i.test(fs.readFileSync(f, "utf8")), "wording: " + path.basename(f) + " uses calm wording for usage stats")
// the PowerShell toast script: static sanity (no PowerShell on this machine)
const ps = fs.readFileSync(path.join(root, "@Resources", "Notify.ps1"), "utf8")
const open = (ps.match(/[{(]/g) || []).length, close = (ps.match(/[})]/g) || []).length
ok(open === close, "Notify.ps1 brackets unbalanced")
ok(/ToastNotificationManager/.test(ps) && !/Invoke-Expression|iex |DownloadString/i.test(ps), "Notify.ps1 shape")

if (errs.length) { console.error(errs.join("\n")); process.exit(1) }
console.log("lint ok: " + Object.keys(main.sections).length + " Main.ini sections, " + Object.keys(data.sections).length + " WebParser measures, " + all.length + " files scanned")
