// node test/lint.js : static checks for the skin (INI structure, cross references, Lua syntax, scrub).
const fs = require("fs"), path = require("path"), cp = require("child_process")
const root = path.join(__dirname, "..", "Skins", "FlyingTulip")
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

// every download measure maps to a key the Lua parses, with a unique file, and no key is orphaned
const files = {}, keys = new Set()
for (const [n, s] of Object.entries(data.sections)) {
  ok(s.Measure === "WebParser" && s.Download === "1", n + " must be a Download=1 WebParser")
  ok(/^https:\/\/api\.flyingtulip\.com\//.test(s.URL), n + " URL must be the public API over https: " + s.URL)
  ok(!/key|token|secret|apikey/i.test(s.URL), n + " URL looks like it carries a credential")
  ok(!(s.DownloadFile in files), "duplicate DownloadFile " + s.DownloadFile); files[s.DownloadFile] = n
  const k = (s.FinishAction.match(/OnData\('(\w+)'\)/) || [])[1]
  ok(k, n + " FinishAction does not call OnData"); keys.add(k)
  ok(new RegExp("\\b" + k + " = \"" + s.DownloadFile.replace(".", "\\.") + "\"").test(lua), "Lua FILES[" + k + "] != " + s.DownloadFile)
  ok(/OnError\('(\w+)'\)/.test(s.OnConnectErrAction || ""), n + " has no OnConnectErrAction")
  if (s.URL.includes("#Wallet#")) ok(s.Group === "Account" && s.Disabled === "1", n + " uses the wallet so it must start disabled in group Account")
  else if (n !== "MeasureRank") ok(s.Group === "Data", n + " should be in group Data")
}
const filesBlock = lua.match(/local FILES = \{([\s\S]*?)\n\}/)[1]
for (const m of filesBlock.matchAll(/(\w+) = "/g)) ok(keys.has(m[1]), "Lua FILES key " + m[1] + " has no download measure")
ok(main.sections.MeasureInput && main.sections.MeasureInput.Plugin === "InputText", "InputText measure missing")
ok(/OnLoaded\(\)/.test(main.sections.Rainmeter.OnRefreshAction), "OnRefreshAction must call OnLoaded")
ok(/Settings\.inc/.test(JSON.stringify(main.sections.Variables)), "Settings.inc not included")

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
// the PowerShell toast script: static sanity (no PowerShell on this machine)
const ps = fs.readFileSync(path.join(root, "@Resources", "Notify.ps1"), "utf8")
const open = (ps.match(/[{(]/g) || []).length, close = (ps.match(/[})]/g) || []).length
ok(open === close, "Notify.ps1 brackets unbalanced")
ok(/ToastNotificationManager/.test(ps) && !/Invoke-Expression|iex |DownloadString/i.test(ps), "Notify.ps1 shape")

if (errs.length) { console.error(errs.join("\n")); process.exit(1) }
console.log("lint ok: " + Object.keys(main.sections).length + " Main.ini sections, " + Object.keys(data.sections).length + " download measures, " + all.length + " files scanned")
