// Bundle package sources so Swiper resolves through the patched lockfile.
// The published Adaptive Cards dist embeds its own older Swiper copy.
import * as AdaptiveCards from "adaptivecards/lib/adaptivecards.js";
globalThis.AdaptiveCards = AdaptiveCards;
