// Extracts the JXA core embedded in the plugin and loads it as a CommonJS module for tests.
const fs = require("fs"), path = require("path"), os = require("os")
const PLUGIN = path.join(__dirname, "..", "Cryptocurrency", "FlyingTulip", "flyingtulip.1m.sh")
function extract() {
  const lines = fs.readFileSync(PLUGIN, "utf8").split("\n")
  const a = lines.findIndex(l => l.includes("<<'FT_JS_END'"))
  const b = lines.findIndex((l, i) => i > a && l === "FT_JS_END")
  if (a < 0 || b < 0) throw new Error("embedded JS markers not found")
  return lines.slice(a + 1, b).join("\n")
}
function load() {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "ftjs-")), "core.js")
  fs.writeFileSync(f, extract())
  return require(f)
}
module.exports = { load, extract, PLUGIN }
