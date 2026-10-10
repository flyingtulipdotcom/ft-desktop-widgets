#!/usr/bin/env node
// Linux stand-in for `osascript -l JavaScript -e <script> [args...]`, used to run the real plugin file end to end.
// It mimics the parts of JXA the plugin uses (Application.currentApplication, doShellScript with \n -> \r,
// displayNotification/displayDialog) inside a bare vm context, so any use of node-only globals fails here too.
const vm = require("vm"), cp = require("child_process")
const a = process.argv.slice(2)
if (a[0] !== "-l" || a[1] !== "JavaScript" || a[2] !== "-e") { console.error("shim: unsupported osascript usage: " + a.slice(0, 3)); process.exit(2) }
const script = a[3], argv = a.slice(4), log = process.env.SHIM_LOG
const note = s => { if (log) require("fs").appendFileSync(log, s + "\n") }
const app = {
  includeStandardAdditions: false,
  doShellScript(cmd) {
    const r = cp.spawnSync("/bin/sh", ["-c", cmd], { encoding: "utf8", maxBuffer: 1 << 28 })
    if (r.status !== 0) throw new Error("shell exited " + r.status + ": " + r.stderr)
    return r.stdout.replace(/\n/g, "\r").replace(/\r$/, "")
  },
  displayNotification(body, o) { note("NOTIFY " + JSON.stringify([o.withTitle, o.subtitle, body, o.soundName])) },
  displayDialog(msg, o) { note("DIALOG " + msg); if (process.env.SHIM_DIALOG === "cancel") throw new Error("User canceled. (-128)"); return { textReturned: process.env.SHIM_DIALOG || "", buttonReturned: "Save" } },
  displayAlert(t, o) { note("ALERT " + o.message) },
  activate() {}
}
const ctx = vm.createContext({ Application: { currentApplication: () => app } })
vm.runInContext(script, ctx)
const out = ctx.run(argv)
if (out !== undefined) process.stdout.write(out + "\n")
