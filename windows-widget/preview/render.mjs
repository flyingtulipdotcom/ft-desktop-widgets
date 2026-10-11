// Renders the widget's real Adaptive Card templates, bound to the data JSON the provider builds from the live public API,
// with the official Adaptive Cards JavaScript renderer in headless Chromium, and takes a PNG of each tab and size,
// light and dark. This is NOT the Windows Widgets Board (Windows Server runners do not have one): it is the same card
// drawn with a host config that stands in for the Windows 11 widget host. The accent colour is the one place it differs
// on purpose: the board uses the user's Windows accent colour, the preview shows the Flying Tulip purple.
//
// Usage: node render.mjs <dataDir> <outDir>
// Env:   FT_CHROME  path of a Chromium/Chrome executable (default: Playwright's own)
import { chromium } from "playwright-core";
import * as ACData from "adaptivecards-templating";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.resolve(process.argv[2] ?? "out/data");
const outDir = path.resolve(process.argv[3] ?? "out/shots");
fs.mkdirSync(outDir, { recursive: true });

// Widget sizes on the board (CSS pixels, approximate) and the host padding around the card.
const SIZES = { small: [176, 176], medium: [352, 176], large: [352, 360] };
const PAD = 10;

const palette = {
  dark: {
    bg: "#202020", page: "#101010", fg: "#e4e4e7", sub: "#71717a", accent: "#9385ff", good: "#0fd727", attention: "#ef4444", warning: "#f5a524",
    sep: "rgba(255,255,255,0.10)", btnBorder: "rgba(255,255,255,0.18)", btnFg: "#a1a1aa", posBg: "rgba(117,89,255,0.24)", posBorder: "#7559ff",
    posFg: "#d4d0ff", frameBorder: "rgba(255,255,255,0.08)", empBg: "#0FFFFFFF", empBorder: "#1AFFFFFF",
  },
  light: {
    bg: "#f6f6f6", page: "#dcdcdc", fg: "#1b1b1f", sub: "#6b6b76", accent: "#5a3fe0", good: "#0e8a1e", attention: "#c42b1c", warning: "#9d5d00",
    sep: "rgba(0,0,0,0.10)", btnBorder: "rgba(0,0,0,0.22)", btnFg: "#52525b", posBg: "rgba(117,89,255,0.16)", posBorder: "#7559ff",
    posFg: "#4630c8", frameBorder: "rgba(0,0,0,0.10)", empBg: "#0A000000", empBorder: "#17000000",
  },
};

function hostConfig(p) {
  const colors = {
    default: { default: p.fg, subtle: p.sub }, dark: { default: p.fg, subtle: p.sub }, light: { default: p.fg, subtle: p.sub },
    accent: { default: p.accent, subtle: p.accent }, good: { default: p.good, subtle: p.good },
    warning: { default: p.warning, subtle: p.warning }, attention: { default: p.attention, subtle: p.attention },
  };
  return {
    fontFamily: '"Segoe UI Variable Text","Segoe UI","Noto Sans","DejaVu Sans",sans-serif',
    fontSizes: { small: 11, default: 13, medium: 15, large: 18, extraLarge: 22 },
    fontWeights: { lighter: 300, default: 400, bolder: 600 },
    lineHeights: { small: 13, default: 16, medium: 19, large: 22, extraLarge: 26 },
    spacing: { small: 4, default: 6, medium: 8, large: 12, extraLarge: 16, padding: 6 },
    separator: { lineThickness: 1, lineColor: p.sep },
    supportsInteractivity: true,
    actions: {
      maxActions: 8, spacing: "default", buttonSpacing: 6, showCard: { actionMode: "inline", inlineTopMargin: 8 },
      actionsOrientation: "horizontal", actionAlignment: "left",
    },
    imageSizes: { small: 28, medium: 52, large: 100 },
    containerStyles: {
      default: { backgroundColor: "#00000000", foregroundColors: colors },
      emphasis: { backgroundColor: p.empBg, borderColor: p.empBorder, borderThickness: 1, foregroundColors: colors },
    },
  };
}

function pageHtml(p, size) {
  const [w, h] = size;
  return `<!doctype html><meta charset="utf-8"><style>
    html,body{margin:0;background:${p.page};font-family:"Segoe UI Variable Text","Segoe UI","Noto Sans","DejaVu Sans",sans-serif}
    #shot{display:inline-block;padding:14px;background:${p.page}}
    #frame{width:${w}px;height:${h}px;box-sizing:border-box;padding:${PAD}px;background:${p.bg};border:1px solid ${p.frameBorder};border-radius:8px;overflow:hidden;position:relative;color:${p.fg}}
    #cap{margin-top:8px;font-size:11px;color:${p.sub};max-width:${w}px}
    /* Fluent-like boxes and buttons (the real host draws its own) */
    .ac-container[style*="background-color: rgba"]{border-radius:8px}
    .ac-pushButton{border-radius:6px;background:transparent;border:1px solid ${p.btnBorder};color:${p.btnFg};padding:1px 8px;font-size:11px;line-height:15px;font-family:inherit;cursor:pointer;white-space:nowrap;flex-shrink:0}
    .ac-pushButton.style-positive{background:${p.posBg};border-color:${p.posBorder};color:${p.posFg};font-weight:600}
    .ac-actionSet{flex-wrap:nowrap}
    .ac-actionSet > button{flex-shrink:0 !important}
    .ac-actionSet > div{width:5px !important}
    .ac-input{background:transparent;color:${p.fg};border:1px solid ${p.btnBorder};border-radius:4px;font-family:inherit}
    .ac-textBlock{margin:0}
  </style><div id="shot"><div id="frame"><div id="host"></div></div><div id="cap"></div></div>`;
}

const names = fs.readdirSync(dataDir).filter((f) => f.endsWith(".template.json")).map((f) => f.replace(".template.json", ""));
const browser = await chromium.launch({ executablePath: process.env.FT_CHROME || undefined, args: ["--no-sandbox"] });
const acJs = path.join(here, "node_modules/adaptivecards/dist/adaptivecards.js");
const report = [];
let failed = false;

for (const theme of ["dark", "light"]) {
  const p = palette[theme];
  for (const name of names) {
    const sizeKey = name === "small" ? "small" : name.endsWith("-medium") ? "medium" : "large";
    const size = SIZES[sizeKey];
    const template = fs.readFileSync(path.join(dataDir, name + ".template.json"), "utf8");
    const data = fs.readFileSync(path.join(dataDir, name + ".data.json"), "utf8");
    const card = new ACData.Template(JSON.parse(template)).expand({ $root: JSON.parse(data), $host: { widgetSize: sizeKey } });
    const page = await browser.newPage({ viewport: { width: 520, height: 700 }, deviceScaleFactor: 2 });
    await page.setContent(pageHtml(p, size));
    await page.addScriptTag({ path: acJs });
    const label = name === "customize" ? "customize" : name === "small" ? "small" : name.replace("-", " · ");
    const caption = `Adaptive Card preview (Windows 11 host config) · ${label} · ${theme} · live public data`;
    const res = await page.evaluate(({ card, hc, caption }) => {
      const errors = [];
      const ac = new AdaptiveCards.AdaptiveCard();
      ac.hostConfig = new AdaptiveCards.HostConfig(hc);
      ac.onParseError = (e) => errors.push(e.message);
      ac.parse(card);
      document.getElementById("host").appendChild(ac.render());
      document.getElementById("cap").textContent = caption;
      return { errors, unresolved: (JSON.stringify(card).match(/\$\{[^}]*\}/g) || []).slice(0, 5) };
    }, { card, hc: hostConfig(p), caption });
    await page.waitForTimeout(200);
    // measured after the images have loaded: their height follows their width
    const m = await page.evaluate((pad) => {
      const el = document.querySelector("#host > div");
      const imgs = [...document.querySelectorAll("img")];
      return { height: el.scrollHeight, overflow: el.scrollHeight - (document.getElementById("frame").clientHeight - 2 * pad),
        imgs: imgs.length, broken: imgs.filter((i) => !i.complete || i.naturalWidth === 0).length };
    }, PAD);
    const box = await page.locator("#shot").boundingBox();
    await page.screenshot({ path: path.join(outDir, `${name}-${theme}.png`), clip: { x: box.x, y: box.y, width: box.width, height: box.height } });
    await page.close();
    const clipped = m.overflow > 2;
    report.push(`${name}-${theme}: content ${m.height}px in ${size[1] - 2 * PAD}px${clipped ? "  CLIPPED by " + m.overflow + "px" : ""}, images ${m.imgs} (broken ${m.broken})` +
      (res.errors.length ? ", errors: " + res.errors.join("; ") : "") + (res.unresolved.length ? ", unresolved: " + res.unresolved.join(" ") : ""));
    if (res.errors.length || res.unresolved.length || m.broken || clipped) failed = true;
  }
}
await browser.close();
fs.writeFileSync(path.join(outDir, "report.txt"), report.join("\n") + "\n");
console.log(report.join("\n"));
if (failed) { console.error("preview: card parse errors, unresolved bindings, broken images or clipped content"); process.exit(1); }
