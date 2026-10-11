#!/usr/bin/env node
// Builds dist/FlyingTulip-<version>.rmskin from RMSKIN.ini + Skins/.
//   node tools/build_rmskin.js
// A .rmskin is a zip (RMSKIN.ini at the root, skins under Skins/) followed by Rainmeter's 16 byte footer:
// int64 LE size of the zip, one flag byte, and the ASCII key "RMSKIN" + NUL. Needs the `zip` command.
const fs = require("fs"), path = require("path"), cp = require("child_process")
const root = path.join(__dirname, "..")
const ini = fs.readFileSync(path.join(root, "RMSKIN.ini"), "utf8")
const version = (ini.match(/^Version=(.+)$/m) || [])[1]
if (!version) throw new Error("RMSKIN.ini has no Version")
const dist = path.join(root, "dist"), zipPath = path.join(dist, "FlyingTulip-" + version + ".zip"), out = path.join(dist, "FlyingTulip-" + version + ".rmskin")
fs.mkdirSync(dist, { recursive: true })
for (const f of [zipPath, out]) fs.rmSync(f, { force: true })
// never ship downloaded data, alert state or a user's wallet
const stage = fs.mkdtempSync(path.join(require("os").tmpdir(), "rmskin-"))
fs.cpSync(path.join(root, "Skins"), path.join(stage, "Skins"), { recursive: true })
fs.copyFileSync(path.join(root, "RMSKIN.ini"), path.join(stage, "RMSKIN.ini"))
fs.rmSync(path.join(stage, "Skins", "FlyingTulip", "DownloadFile"), { recursive: true, force: true })
for (const f of ["State.txt", "Notify.txt", "UsageStats.txt"]) fs.rmSync(path.join(stage, "Skins", "FlyingTulip", "@Resources", f), { force: true })
const settings = path.join(stage, "Skins", "FlyingTulip", "@Resources", "Settings.inc")
if (/^Wallets?=\S/m.test(fs.readFileSync(settings, "utf8"))) throw new Error("Settings.inc has a wallet set; refusing to package it")
cp.execFileSync("zip", ["-q", "-r", "-X", zipPath, "RMSKIN.ini", "Skins"], { cwd: stage })
const zip = fs.readFileSync(zipPath)
const footer = Buffer.alloc(16)
footer.writeBigInt64LE(BigInt(zip.length), 0)
footer[8] = 0
footer.write("RMSKIN\0", 9, "latin1")
fs.writeFileSync(out, Buffer.concat([zip, footer]))
fs.rmSync(zipPath); fs.rmSync(stage, { recursive: true, force: true })
console.log("built " + path.relative(process.cwd(), out) + " (" + (zip.length + 16) + " bytes)")
