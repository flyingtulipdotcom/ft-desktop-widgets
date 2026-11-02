import { chromium } from "playwright-core";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const browser = await chromium.launch({ executablePath: process.env.FT_CHROME || undefined, args: ["--no-sandbox"] });
try {
  const page = await browser.newPage();
  await page.setContent('<div id="host" style="width:400px;height:300px"></div>');
  await page.addScriptTag({ path: path.join(here, "out/adaptivecards.js") });
  const result = await page.evaluate(() => {
    const card = new AdaptiveCards.AdaptiveCard();
    card.version = new AdaptiveCards.Version(1, 6);
    const carousel = new AdaptiveCards.Carousel();
    for (const text of ["First card", "Second card"]) {
      const child = new AdaptiveCards.CarouselPage();
      const label = new AdaptiveCards.TextBlock();
      label.text = text;
      child.addItem(label);
      carousel.addPage(child);
    }
    card.addItem(carousel);
    document.querySelector("#host").append(card.render());
    card.updateLayout();
    const slider = document.querySelector(".swiper").swiper;
    if (!slider) throw new Error("Carousel did not initialize Swiper");
    slider.slideTo(1, 0);
    const original = Array.prototype.indexOf;
    let polluted;
    try {
      Array.prototype.indexOf = () => -1;
      slider.constructor.extendDefaults(JSON.parse('{"__proto__":{"ftSecurityProbe":"polluted"}}'));
      polluted = Object.prototype.ftSecurityProbe;
    } finally {
      Array.prototype.indexOf = original;
      delete Object.prototype.ftSecurityProbe;
    }
    return { text: document.querySelector("#host").textContent, activeIndex: slider.activeIndex, polluted };
  });
  assert.match(result.text, /First card/);
  assert.match(result.text, /Second card/);
  assert.equal(result.activeIndex, 1);
  assert.equal(result.polluted, undefined, "loaded renderer permits prototype pollution");
  console.log("Card, carousel navigation and loaded-bundle prototype-pollution checks passed");
} finally {
  await browser.close();
}
