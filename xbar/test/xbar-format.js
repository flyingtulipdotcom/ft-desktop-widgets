// Validates plugin stdout against the xbar/SwiftBar output format (CONTRIBUTING.md "Plugin API").
const KNOWN = new Set(["key", "href", "color", "font", "size", "shell", "bash", "refresh", "dropdown", "length", "trim", "alternate",
  "templateImage", "image", "emojize", "ansi", "disabled", "terminal", "tooltip", "checked", "sfimage", "sfcolor"])
function validate(out) {
  const errs = [], lines = out.split("\n")
  let sep = -1, inDropdown = false, prevDepth = 0
  lines.forEach((ln, i) => {
    const tag = "line " + (i + 1) + ": "
    if (ln === "---") { if (sep < 0) sep = i; inDropdown = true; prevDepth = 0; return }
    if (ln.trim() === "") { errs.push(tag + "empty line"); return }
    const m = ln.match(/^((?:--)*)(.*)$/s), depth = m[1].length / 2
    if (!inDropdown && depth) errs.push(tag + "submenu marker in the menu bar section")
    if (depth > prevDepth + 1) errs.push(tag + "submenu skips a level")
    prevDepth = depth
    const bar = m[2].indexOf(" | ")
    if (bar < 0) return
    const params = m[2].slice(bar + 3)
    const re = /([A-Za-z0-9]+)=("[^"]*"|\S+)/g
    let rest = params, mm, seen = 0
    while ((mm = re.exec(params))) {
      seen++
      if (!KNOWN.has(mm[1]) && !/^param\d+$/.test(mm[1])) errs.push(tag + "unknown parameter " + mm[1])
      if ((mm[1] === "image" || mm[1] === "templateImage") && !/^[A-Za-z0-9+/=]+$/.test(mm[2])) errs.push(tag + "image is not base64")
    }
    if (!seen) errs.push(tag + "pipe without parameters")
    if (/\|/.test(m[2].slice(0, bar))) errs.push(tag + "stray pipe in title")
  })
  if (sep < 0) errs.push("no --- separator")
  if (sep === 0) errs.push("empty menu bar title")
  return errs
}
module.exports = { validate }
