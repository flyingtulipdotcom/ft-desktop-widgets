#!/usr/bin/env bash

# Flying Tulip in the macOS menu bar: FT market price, 24h application fees and, for the wallets you set,
# health factor with liquidation alerts, PnL, FT earned, points, ftPUT gain and positions.
# Public API only (https://api.flyingtulip.com), no keys. Works in xbar and SwiftBar.
#
# Metadata (xbar):
#  <xbar.title>Flying Tulip</xbar.title>
#  <xbar.version>v1.1.0</xbar.version>
#  <xbar.author>Flying Tulip</xbar.author>
#  <xbar.author.github>flyingtulipdotcom</xbar.author.github>
#  <xbar.desc>FT market price, 24h application fees and, for optional wallets (shown in turn), health factor with liquidation alerts, PnL, FT earned, points, ftPUT gain and positions. Public API only.</xbar.desc>
#  <xbar.dependencies>bash,curl,osascript</xbar.dependencies>
#  <xbar.abouturl>https://github.com/flyingtulipdotcom/ft-desktop-widgets</xbar.abouturl>
#
# Settings (shown in the plugin settings window of xbar and SwiftBar):
#  <xbar.var>string(VAR_WALLET=""): Public wallet addresses to track (0x...), comma separated. Leave empty to set them from the menu.</xbar.var>
#  <xbar.var>string(VAR_HF_WARN="1.40"): Warning notification at or below this health factor.</xbar.var>
#  <xbar.var>string(VAR_HF_CRITICAL="1.30"): Critical notification at or below this health factor (liquidation starts below 1.25).</xbar.var>
#  <xbar.var>boolean(VAR_NOTIFICATIONS=true): Show a macOS notification when health factor crosses a threshold.</xbar.var>
#  <xbar.var>number(VAR_NOTIFY_COOLDOWN_MIN=30): Minimum minutes between two notifications of the same level.</xbar.var>
#  <xbar.var>select(VAR_PRICE_CHAIN="1"): Chain whose FT-ftUSD market price is shown. [1, 146]</xbar.var>
#
# Metadata (SwiftBar):
#  <swiftbar.environment>[VAR_WALLET:, VAR_HF_WARN:1.40, VAR_HF_CRITICAL:1.30, VAR_NOTIFICATIONS:true, VAR_NOTIFY_COOLDOWN_MIN:30, VAR_PRICE_CHAIN:1]</swiftbar.environment>
#  <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#  <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
#
# Not financial advice. Figures can be delayed, incomplete or wrong. MIT licensed. The Flying Tulip name and
# logo are trademarks of Flying Tulip and are not covered by the MIT license.
#
# How it works: stock macOS has bash 3.2, curl and osascript, but no jq, node or (without the Command Line
# Tools) python. The data logic is JavaScript run by osascript (JXA, always present); this wrapper only hands it
# the settings. It makes no network call besides curl to api.flyingtulip.com.

export LANG="${LANG:-en_US.UTF-8}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

CACHE_DIR="${SWIFTBAR_PLUGIN_CACHE_PATH:-$HOME/Library/Caches/com.flyingtulip.menubar}"
WALLET_FILE="$HOME/Library/Application Support/FlyingTulip/menubar-wallet"
SELF="$0"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac

IFS= read -r -d '' FT_JS <<'FT_JS_END' || true
// ---- Flying Tulip menu bar: JXA core. Pure logic + render; I/O lives in jxaIO() --------------------

var API = "https://api.flyingtulip.com";
var SITE = "https://flyingtulip.com/";
var STATS_URL = SITE + "statistics/";
// Public flyingtulip.com pages every dropdown line links to.
var PAGES = {
  fees: SITE + "statistics/",
  health: SITE + "lend/dashboard/",
  portfolio: SITE + "trade/portfolio/",
  rewards: SITE + "rewards/",
  points: SITE + "rewards/leaderboard/",
  put: SITE + "allocation/positions/"
};
// Spot market page for a symbol such as "FT-ftUSD" on a chain id.
function marketUrl(symbol, chainId) {
  var c = Number(chainId), q = "symbol=" + encodeURIComponent(String(symbol || "FT-ftUSD"));
  if (isFinite(c) && c > 0) q += "&chainId=" + Math.floor(c);
  return SITE + "trade/?" + q + "&marketType=spot";
}
var DEFAULT_LIQ_HF = 1.25;
var HF_CHAINS = { 146: "Sonic", 1: "Ethereum", 56: "BNB", 143: "Monad" };
var HF_CHAIN_IDS = [146, 1, 56, 143];
var SLOW_TTL = 600;          // seconds: chart series and leaderboard rank
var STALE_AFTER = 180;       // seconds: a source older than this is shown as stale
var C_TULIP = "#7559ff", C_GREEN = "#1fa84a", C_RED = "#e5484d", C_AMBER = "#d98a00", C_FAINT = "#8a8a93";
var LOGO_B64 = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAACXBIWXMAABYlAAAWJQFJUiTwAAAE7klEQVR42s2YS2wUdRzHP///PHa729nSLuURDVqDEkmKggoJooaDARMCB7yVcMF4MSEarp6I4aAh6gkkcpHHgSiJgSCvRFAgEV9QQhNegkhp+oDSdndnd2b+/5+HlvIwhF1oi7/TZDKT+cx3vr/H/BTDoUFZEDKp5iW57Iw1Wqfe1Eo1g9KMaYgVkd7ElH8eKv3zdanSewAUIBqwahgGCzRNbnjpi0w632ZspKN4EGMrIDK2PErhaB/fa8DRvi2Vb+zoGzj9IXAT0ApEgZo0tfGVA5lU/rX+wkWpxEOiUEoppRiHEBERRFJeoBrrZ6pS5cav3f2/LwG5pQCaG1q3ZzPT23r722NBPK3c27cyPjH8nlYSFCpubpzjFUtdO3oHzqxysqkpbzfUt3x6q/CXtTZytHLV+IHc//UcwOooKdgg89ScJCmecJqCWZ8prWYXwy609vREwdwFpYwJSfuTtKszWe246Tcq8SCMk1+qpFKVeBDHrVuktdJ5YyMUSk20Ord9qlDK2Ait1GQN6DFP7UdLPQDt1qasHv2yIhZ5wIsopVAj9XQ4wW3Vz3CrT1RFHIfEcRmlNb6fwXV8rDX3XKe1gzERlaiEWIvnpfHcNFKlHdxqlYniIrNfWMqsma9z5eqfnL90lKFCD+l0blQBpTRhOEB9/RRaX1zGszPmcu7icTrO78f3slUpVSWQIo4rtMxYwPIlHzBYgN6+y+w5+AmnznxHKhUAUKkMMbf1XZYt+Zgp+RZyAXwbJZw++z0pv74qq+oaMpM4DikUDWEYMTnfwnttW5k/r40oKhJFRebPa2PNqq0051sIyxGFoiGOw5oqiq7V1Fo7aO0QRYbEwIqlG8gF08gF01ixdAPGQBSZ0etUjcOC+6hZqrVDHBuaGht47pmFADQ1NlAoDsPcb/ZxB7qjmpBvmjF6/LjhPn5FU5TLQ/d08QkEUvfPWkQR/N35BzB8/F//1gZZk+PiJBwtcMYkBFmHU2f303m9nc7r7Zw6u58g62BMMtKlhDgJxwdIK4funnMYoxAgqHfpOH+S3XvX4TgujuOye+86Os6fJKh3EcAYRXfPObRyxhbIWovvZ7h05TidXRcIsg4Hj2xh46bF9Ny8iBWDFUPPzYts3LSYg0e2EGQdOrsucOnKMXw/g7V2LD0kaO1SKvez7/B63l+9jWymieVLN5CfNJUTv20HYOGrq7hxq5tsponEwL7D6ymVb5FO5apusFWbWsRSl87R3rGHbbvW0rbyS5oaFb03En48/hUgzJ2zkua8x81+YduutbR37KEunataHQD1dPMiKZV7qMQDIzPuw6t1WB5g+tTZLFqwmlNnfuDC5aMAPN/yFi+3vsOxX76hq7uDunRDVcqIGFJeA5n0lNqBbhs8ikvESWV0vBjOwjJxXMZzU/heBiumSvXvAD1SYbRi8Lw6fD9zzwDmuWl8rw4RqRpmzCr18MT48HM190jA8gR/OO4p+2C1FelztI8gMha96FF6oSDiaB8r0qdNEh5LeTkeOLFPzB+HpLwcJgmP6UJ4bbOjU+J5gYgkE6ySQiQRzwvE0SkphNc262Kl51Cp3LuzMZjpgEqsJCMdWo0rCChGnpU0BjOdUrl3Z7HSc+h/uY65a2HV+nkm3bzK2IqO4qGJWlht7xs4/dFdC6sns9IztvLTYPHq1vtXev8CgGJ39mZpH2oAAAAASUVORK5CYII=";

// ---- numbers and formatting --------------------------------------------------------------------

function num(v) {
  if (v === null || v === undefined || v === "") return NaN;
  var n = Number(v);
  return isFinite(n) ? n : NaN;
}
function isAddress(a) { return /^0x[0-9a-fA-F]{40}$/.test(String(a || "")); }
function normalizeWallet(s) {
  var t = String(s || "").trim();
  return isAddress(t) ? t.toLowerCase() : "";
}
function fmtUsd(v) {
  if (!isFinite(v)) return "—";
  var a = Math.abs(v);
  if (a >= 1e6) return "$" + (a / 1e6).toFixed(2) + "M";
  if (a >= 1e4) return "$" + (a / 1e3).toFixed(1) + "k";
  if (a >= 1e3) return "$" + (a / 1e3).toFixed(2) + "k";
  return "$" + a.toFixed(a >= 100 ? 0 : 2);
}
function fmtSignedUsd(v) {
  if (!isFinite(v)) return "—";
  if (Math.abs(v) < 0.005) return "$0.00";
  return (v < 0 ? "-" : "+") + fmtUsd(v);
}
function fmtPrice(p) {
  if (!isFinite(p)) return "—";
  return "$" + p.toFixed(p >= 1 ? 2 : 4);
}
function fmtHf(hf) {
  if (hf === null || hf === undefined || !isFinite(hf)) return "∞";
  return hf >= 100 ? ">100" : hf.toFixed(2);
}
function fmtPct(v) {
  if (!isFinite(v)) return "—";
  return (v >= 0 ? "+" : "") + (Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(1)) + "%";
}
function fmtFt(v) {
  if (!isFinite(v)) return "—";
  if (v < 0.01) return v <= 0 ? "0" : "<0.01";
  if (v < 10) return v.toFixed(2);
  if (v < 1000) return v.toFixed(1);
  if (v < 1e6) return (v / 1e3).toFixed(v < 1e4 ? 2 : 1) + "K";
  return (v / 1e6).toFixed(2) + "M";
}
function fmtPoints(v) {
  if (!isFinite(v)) return "—";
  var a = Math.abs(v);
  if (a >= 1e9) return (a / 1e9).toFixed(2) + "B";
  if (a >= 1e6) return (a / 1e6).toFixed(a >= 1e8 ? 0 : 1) + "M";
  if (a >= 1e3) return (a / 1e3).toFixed(a >= 1e5 ? 0 : 1) + "K";
  return a.toFixed(0);
}
function fmtSize(v) {
  if (!isFinite(v)) return "—";
  var a = Math.abs(v);
  if (a >= 1e6) return (a / 1e6).toFixed(2) + "M";
  if (a >= 1e4) return (a / 1e3).toFixed(1) + "K";
  if (a >= 100) return a.toFixed(0);
  if (a >= 1) return a.toFixed(2);
  return a.toFixed(4);
}
function thousands(n) { return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
function shortAddr(a) { a = String(a || ""); return a.length > 12 ? a.slice(0, 6) + "…" + a.slice(-4) : a; }
function pad2(n) { return (n < 10 ? "0" : "") + n; }

// ---- parsers (tolerate missing fields; return null on unusable payloads) ----------------------

function parseFees(body) {
  var d = body && body.data;
  if (!d || !d.totals) return null;
  var period = num(d.totals.period_usd);
  if (!isFinite(period)) return null;
  var products = [];
  var bp = d.byProduct || {};
  for (var k in bp) {
    var v = num(bp[k] && bp[k].period_usd);
    if (isFinite(v)) products.push({ name: k, usd: v });
  }
  products.sort(function (a, b) { return b.usd - a.usd; });
  return { period24h: period, lifetime: num(d.totals.lifetime_usd), products: products };
}

function parsePrice(body) {
  var ts = body && body.data && body.data.tickers;
  if (!ts) return null;
  for (var i = 0; i < ts.length; i++) {
    if (ts[i].display_symbol === "FT-ftUSD") {
      var p = num(ts[i].price);
      if (!isFinite(p)) return null;
      return { price: p, changePct24h: num(ts[i].price_change_pct_24h), sampledAt: ts[i].sampled_at || "" };
    }
  }
  return null;
}

function parseLend(body) {
  var d = body && (body.data || body);
  var chains = d && d.chains;
  if (!chains) return [];
  var out = [];
  for (var i = 0; i < chains.length; i++) {
    var c = chains[i];
    var m = c.userMetrics || {};
    var debt = num(m.totalDebtUsd);
    var hf = num(m.healthFactor);
    var hasDebt = isFinite(debt) && debt > 0.01;
    out.push({
      chainId: Number(c.chainId),
      name: HF_CHAINS[Number(c.chainId)] || c.chainName || String(c.chainId),
      hf: hasDebt && isFinite(hf) ? hf : null,
      debtUsd: isFinite(debt) ? debt : 0,
      equityUsd: num(m.equityUsd),
      liqHf: isFinite(num(c.hfLiquidationThreshold)) ? num(c.hfLiquidationThreshold) : DEFAULT_LIQ_HF
    });
  }
  return out;
}

function parseSummary(body) {
  var arr = Array.isArray(body) ? body : (body && body.data) || [];
  if (!Array.isArray(arr) || !arr.length) return null;
  var pnl = num(arr[0].unrealizedPnl);
  return { chainId: Number(arr[0].chainId), pnlUsd: isFinite(pnl) ? pnl : 0 };
}

function mergeChains(lists) {
  var byId = {};
  for (var i = 0; i < lists.length; i++)
    for (var j = 0; j < lists[i].length; j++) byId[lists[i][j].chainId] = lists[i][j];
  var out = [];
  for (var id in byId) out.push(byId[id]);
  out.sort(function (a, b) { return HF_CHAIN_IDS.indexOf(a.chainId) - HF_CHAIN_IDS.indexOf(b.chainId); });
  return out;
}

function lowestHf(chains) {
  var best = null;
  for (var i = 0; i < chains.length; i++) {
    if (chains[i].hf === null) continue;
    if (best === null || chains[i].hf < best.hf) best = chains[i];
  }
  return best;
}

// Exact decimal shift of an integer string (display precision only).
function rawUnits(s, dec) {
  if (s === null || s === undefined || !/^\d+$/.test(String(s))) return NaN;
  var str = String(s);
  if (str.length <= 15) return Number(str) / Math.pow(10, dec);
  var cut = str.length - dec;
  if (cut <= 0) return Number("0." + new Array(-cut + 1).join("0") + str);
  return Number(str.slice(0, cut) + "." + str.slice(cut));
}
function rawFt(s) { return rawUnits(s, 18); }

// /account/dashboard?view=rewards -> FT earned, all time and all chains: sftUSD yield (claimed + pending) plus
// Lend FT rewards (received + pending). It is what the wallet's sftUSD staking and Lend supply have paid over time,
// so it does not follow the wallet's current size. NaN total when any piece is unknown or a section errored.
function parseRewards(body) {
  var d = body && body.success !== false && body.data;
  if (!d || !d.chains) return null;
  var errs = d.sectionErrors || {};
  var stakingFailed = !!errs.staking, lendFailed = !!errs.lend;
  var known = !stakingFailed && !lendFailed;
  var r = { totalFt: NaN, claimableFt: 0, sftClaimed: 0, sftPending: 0, lendReceived: 0, lendPending: 0, chains: [] };
  for (var i = 0; i < d.chains.length; i++) {
    var c = d.chains[i], st = c.staking, lm = c.lend && c.lend.userMetrics;
    var pendingSft = st ? rawFt(st.pending_yield_ft) : (stakingFailed ? NaN : 0);
    var claimedSft = st ? ((st.claimed_yield_indexed_through_block && !st.claimed_yield_stale) ? rawFt(st.claimed_yield_ft) : NaN)
                        : (stakingFailed ? NaN : 0);
    var rec = lendFailed ? NaN : 0, pen = lendFailed ? NaN : 0;
    if (c.lend) {
      var fr = lm && lm.ftRewards;
      if (lm && lm.ftRewardsError) rec = pen = NaN;
      else if (fr) { rec = rawFt(fr.receivedFtRaw); pen = rawFt(fr.pendingFtRaw); }
      else if (!lm) rec = pen = NaN;
      else rec = pen = 0;
    }
    if (isFinite(pendingSft)) r.claimableFt += pendingSft;
    if (!isFinite(pendingSft) || !isFinite(claimedSft) || !isFinite(rec) || !isFinite(pen)) { known = false; continue; }
    r.sftClaimed += claimedSft; r.sftPending += pendingSft; r.lendReceived += rec; r.lendPending += pen;
    var id = Number(c.chainId);
    r.chains.push({ chainId: id, name: HF_CHAINS[id] || String(c.chainId), sft: claimedSft + pendingSft, lend: rec + pen });
  }
  r.sftFt = r.sftClaimed + r.sftPending; r.lendFt = r.lendReceived + r.lendPending;
  r.totalFt = known ? r.sftFt + r.lendFt : NaN;
  return r;
}
// Chains that earned something, as "Sonic 95.4, Ethereum 0.06".
function earnedByChain(r) {
  var out = [];
  for (var i = 0; r && r.chains && i < r.chains.length; i++)
    if (r.chains[i].sft + r.chains[i].lend >= 0.005) out.push(r.chains[i].name + " " + fmtFt(r.chains[i].sft + r.chains[i].lend));
  return out.join(", ");
}

// /tge/ftPUT/user/<wallet>: cost basis = sum(current_capital * strike), FT held = current_ft + withdrawn_ft.
// null when the wallet has no PUTs.
function parsePuts(body) {
  var d = body && body.data;
  var ps = d && d.positions;
  if (!ps || !ps.length) return null;
  var cost = 0, ftHeld = 0, rows = [];
  for (var i = 0; i < ps.length; i++) {
    var p = ps[i];
    var dec = Number(p.token_decimals);
    if (!isFinite(dec)) dec = (p.tokenData && Number(p.tokenData.decimals)) || 18;
    var strike = rawUnits(p.strike, 8);
    var cap = rawUnits(p.current_capital, dec);
    var ftC = rawUnits(p.current_ft, 18), ftW = rawUnits(p.withdrawn_ft, 18);
    if (!isFinite(strike) || !isFinite(cap) || !isFinite(ftC)) continue;
    if (!isFinite(ftW)) ftW = 0;
    cost += cap * strike; ftHeld += ftC + ftW;
    rows.push({ nft: String(p.nft_id), symbol: p.token_symbol || (p.tokenData && p.tokenData.symbol) || "?",
      costUsd: cap * strike, ft: ftC + ftW });
  }
  if (!rows.length) return null;
  return { count: rows.length, costUsd: cost, ftHeld: ftHeld, rows: rows };
}

// gain = FT held x FT MARKET price - cost basis (never NAV)
function putGain(puts, ftPrice) {
  if (!puts || !isFinite(ftPrice)) return null;
  var value = puts.ftHeld * ftPrice, gain = value - puts.costUsd;
  return { valueUsd: value, gainUsd: gain, gainPct: puts.costUsd > 0 ? gain / puts.costUsd * 100 : NaN };
}

// /points?walletAddress= -> the all-chains total (what the leaderboard ranks) plus each chain's share, largest first.
// flyingtulip.com/rewards shows ONE chain at a time in its big number, with the all-networks total under it.
function parsePoints(body) {
  var chains = body && body.data && body.data.chains;
  if (!chains) return null;
  var total = NaN, per = [];
  for (var i = 0; i < chains.length; i++) {
    var c = chains[i], v = c.userMetrics ? num(c.userMetrics.totalPoints) : NaN;
    if (c.isAllChains) { total = v; continue; }
    if (!(v > 0)) continue;
    var id = c.chainData ? Number(c.chainData.id) : NaN;
    per.push({ chainId: id, name: HF_CHAINS[id] || (c.chainData && c.chainData.name) || "?", points: v });
  }
  if (!isFinite(total)) return null;
  per.sort(function (a, b) { return b.points - a.points; });
  return { total: total, chains: per };
}

// Leaderboard page -> {found, rank, dir, total}. dir -1: wallet is on an earlier page, +1 later.
function rankInPage(body, wallet, myPoints) {
  var lb = body && body.data && body.data.leaderboard;
  var total = body && body.data && body.data.pagination ? Number(body.data.pagination.total) : 0;
  if (!lb || !lb.length) return { found: false, rank: 0, dir: 0, total: total, empty: true };
  var w = String(wallet).toLowerCase();
  for (var i = 0; i < lb.length; i++)
    if (String(lb[i].userWallet).toLowerCase() === w) return { found: true, rank: Number(lb[i].rank), dir: 0, total: total };
  var first = num(lb[0].totalPoints), last = num(lb[lb.length - 1].totalPoints);
  return { found: false, rank: 0, dir: myPoints > first ? -1 : (myPoints < last ? 1 : 0), total: total };
}

function parsePositions(body) {
  var arr = Array.isArray(body) ? body : (body && body.data) || [];
  if (!Array.isArray(arr)) return [];
  var out = [];
  for (var i = 0; i < arr.length; i++) {
    var p = arr[i];
    var size = num(p.size), mark = num(p.markPrice);
    if (!isFinite(size) || size <= 0) continue;
    out.push({
      network: p.network || HF_CHAINS[Number(p.chainId)] || String(p.chainId),
      chainId: Number(p.chainId), market: String(p.symbol || ""),
      symbol: String(p.sizeCurrency || String(p.symbol || "").split("-")[0] || "?"),
      side: String(p.side || "").toLowerCase() === "short" ? "short" : "long",
      size: size, mark: mark, pnlUsd: num(p.pnlAmount), pnlPct: num(p.pnlPct),
      leverage: num(p.blendedLeverage) || num(p.leverage),
      valueUsd: isFinite(mark) ? size * mark : NaN
    });
  }
  return out;
}
function sortPositions(rows) {
  return rows.slice().sort(function (a, b) {
    return (isFinite(b.valueUsd) ? b.valueUsd : 0) - (isFinite(a.valueUsd) ? a.valueUsd : 0);
  });
}

function parseFeesSeries(body) {
  var s = body && body.data && body.data.series;
  if (!s || !s.length) return null;
  var out = [];
  for (var i = 0; i < s.length; i++) {
    var v = num(s[i].total_usd);
    if (isFinite(v)) out.push({ date: String(s[i].date), total: v });
  }
  return out.length ? out : null;
}

// market closes (never NAV)
function parseKlines(body) {
  if (!Array.isArray(body) || !body.length) return null;
  var out = [];
  for (var i = 0; i < body.length; i++) {
    var c = num(body[i].close);
    if (isFinite(c)) out.push({ date: new Date(Number(body[i].time)).toISOString().slice(0, 10), close: c });
  }
  return out.length ? out : null;
}

// Day-over-day % across FINISHED days (the last bucket is the partial current day).
function feesDayOverDay(series, nowMs) {
  if (!series || series.length < 4) return NaN;
  var today = new Date(nowMs).toISOString().slice(0, 10);
  var rows = series[series.length - 1].date.slice(0, 10) === today ? series.slice(0, -1) : series;
  if (rows.length < 2) return NaN;
  var last = rows[rows.length - 1].total, prev = rows[rows.length - 2].total;
  return prev > 0 ? (last - prev) / prev * 100 : NaN;
}

// ---- liquidation alerts ------------------------------------------------------------------------

// level: 0 ok, 1 warning, 2 critical. A level only clears once HF is back above its threshold + hysteresis.
function levelFor(hf, cfg, prevLevel) {
  var hyst = cfg.hyst === undefined ? 0.05 : cfg.hyst;
  var lvl = 0;
  if (hf <= cfg.critical) lvl = 2;
  else if (hf <= cfg.warn) lvl = 1;
  if (prevLevel === 2 && lvl < 2 && hf <= cfg.critical + hyst) lvl = 2;
  if (prevLevel >= 1 && lvl < 1 && hf <= cfg.warn + hyst) lvl = 1;
  return lvl;
}

// state: {level, last:{1:ms,2:ms}}. Notifies once per upward crossing, never twice for the same level
// within cooldownMs. hfEntry=null (no debt) resets to level 0.
function decideNotify(state, hfEntry, cfg, nowMs) {
  var last = state.last || {};
  var st = { level: state.level || 0, last: {
    1: last[1] == null ? -1e18 : last[1], 2: last[2] == null ? -1e18 : last[2] } };
  if (!hfEntry) { st.level = 0; return { state: st, notify: null }; }
  var lvl = levelFor(hfEntry.hf, cfg, st.level);
  var notify = null;
  if (lvl > st.level && nowMs - st.last[lvl] >= cfg.cooldownMs) {
    notify = { level: lvl, hf: hfEntry.hf, chain: hfEntry.name, liqHf: hfEntry.liqHf };
    st.last[lvl] = nowMs;
  }
  st.level = lvl;
  return { state: st, notify: notify };
}

// n.wallet (short address), when set, names the wallet so a toast says which one of several it is about.
function notifyText(n) {
  var hf = n.hf.toFixed(2), who = n.wallet ? n.wallet + ": " : "";
  if (n.level === 2)
    return { urgency: "critical", title: "FT account near liquidation",
      body: who + n.chain + " HF " + hf + " (liquidation below " + n.liqHf.toFixed(2) + "). Add collateral or repay now." };
  return { urgency: "normal", title: "FT account health low",
    body: who + n.chain + " HF " + hf + " (liquidation below " + n.liqHf.toFixed(2) + ")." };
}

function parseThreshold(v, fallback) {
  var n = num(v);
  return isFinite(n) && n > 1 ? n : fallback;
}

// ---- tiny dependency-free PNG (4-bit palette, stored deflate) ------------------------------------

var CRC_TABLE = null;
function crc32(bytes, start, end) {
  if (!CRC_TABLE) {
    CRC_TABLE = [];
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      CRC_TABLE[n] = c >>> 0;
    }
  }
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function adler32(bytes) {
  var a = 1, b = 0;
  for (var i = 0; i < bytes.length; i++) { a = (a + bytes[i]) % 65521; b = (b + a) % 65521; }
  return ((b << 16) | a) >>> 0;
}
function be32(n) { return [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]; }
function pngChunk(type, data) {
  var out = new Uint8Array(12 + data.length);
  out.set(be32(data.length), 0);
  for (var i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
  out.set(data, 8);
  out.set(be32(crc32(out, 4, 8 + data.length)), 8 + data.length);
  return out;
}

function Raster(w, h) { this.w = w; this.h = h; this.p = new Uint8Array(w * h); }
Raster.prototype.set = function (x, y, c) {
  x = Math.round(x); y = Math.round(y);
  if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.p[y * this.w + x] = c;
};
Raster.prototype.rect = function (x0, y0, x1, y1, c) {
  for (var y = Math.round(y0); y < Math.round(y1); y++)
    for (var x = Math.round(x0); x < Math.round(x1); x++) this.set(x, y, c);
};
Raster.prototype.line = function (x0, y0, x1, y1, c, th) {
  x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
  var dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  var err = dx + dy, h = Math.floor(th / 2);
  for (;;) {
    this.rect(x0 - h, y0 - h, x0 - h + th, y0 - h + th, c);
    if (x0 === x1 && y0 === y1) break;
    var e2 = 2 * err;
    if (e2 >= dy) { err += dy; x0 += sx; }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
};

// palette: [[r,g,b], ...] up to 16 entries. 144 dpi so a 2x image is shown at 1x point size.
function encodePng(r, palette) {
  var rowBytes = Math.ceil(r.w / 2), raw = new Uint8Array((rowBytes + 1) * r.h);
  for (var y = 0; y < r.h; y++) {
    var o = y * (rowBytes + 1);
    raw[o] = 0;
    for (var x = 0; x < r.w; x += 2) {
      var hi = r.p[y * r.w + x], lo = x + 1 < r.w ? r.p[y * r.w + x + 1] : 0;
      raw[o + 1 + (x >> 1)] = (hi << 4) | lo;
    }
  }
  var blocks = Math.max(1, Math.ceil(raw.length / 65535));
  var z = new Uint8Array(2 + raw.length + blocks * 5 + 4), zp = 0;
  z[zp++] = 0x78; z[zp++] = 0x01;
  for (var b = 0; b < blocks; b++) {
    var start = b * 65535, len = Math.min(65535, raw.length - start);
    z[zp++] = b === blocks - 1 ? 1 : 0;
    z[zp++] = len & 255; z[zp++] = len >> 8; z[zp++] = (~len) & 255; z[zp++] = ((~len) >> 8) & 255;
    z.set(raw.subarray(start, start + len), zp); zp += len;
  }
  z.set(be32(adler32(raw)), zp);
  var ihdr = new Uint8Array(13);
  ihdr.set(be32(r.w), 0); ihdr.set(be32(r.h), 4); ihdr[8] = 4; ihdr[9] = 3;
  var plte = new Uint8Array(palette.length * 3);
  for (var i = 0; i < palette.length; i++) plte.set(palette[i], i * 3);
  var phys = new Uint8Array(9);
  phys.set(be32(5669), 0); phys.set(be32(5669), 4); phys[8] = 1;
  var parts = [new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk("IHDR", ihdr), pngChunk("PLTE", plte),
    pngChunk("pHYs", phys), pngChunk("IDAT", z), pngChunk("IEND", new Uint8Array(0))];
  var total = 0, j;
  for (j = 0; j < parts.length; j++) total += parts[j].length;
  var out = new Uint8Array(total), p = 0;
  for (j = 0; j < parts.length; j++) { out.set(parts[j], p); p += parts[j].length; }
  return out;
}

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function base64(bytes) {
  var s = "";
  for (var i = 0; i < bytes.length; i += 3) {
    var a = bytes[i], b = i + 1 < bytes.length ? bytes[i + 1] : 0, c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    s += B64[a >> 2] + B64[((a & 3) << 4) | (b >> 4)] +
      (i + 1 < bytes.length ? B64[((b & 15) << 2) | (c >> 6)] : "=") + (i + 2 < bytes.length ? B64[c & 63] : "=");
  }
  return s;
}

// 0 bg, 1 tulip, 2 tulip400, 3 tulip300, 4 area, 5 grid, 6 green, 7 red
var CHART_PALETTE = [[14, 14, 17], [117, 89, 255], [147, 133, 255], [183, 177, 255], [35, 28, 82], [42, 42, 50], [15, 215, 39], [239, 68, 68]];
var CW = 340, CH = 76, CPAD = 7;   // 2x pixels, shown at 170x38 points

function barChartPng(values) {
  var r = new Raster(CW, CH), n = values.length, i;
  r.rect(0, 0, CW, CH, 0);
  var max = 0;
  for (i = 0; i < n; i++) max = Math.max(max, values[i]);
  if (!(max > 0)) max = 1;
  var aw = CW - 2 * CPAD, ah = CH - 2 * CPAD, step = aw / n, bw = Math.max(2, Math.floor(step) - 2);
  r.rect(CPAD, CH - CPAD, CW - CPAD, CH - CPAD + 1, 5);
  for (i = 0; i < n; i++) {
    var h = Math.max(2, Math.round(values[i] / max * ah)), x = CPAD + i * step;
    r.rect(x, CH - CPAD - h, x + bw, CH - CPAD, i === n - 1 ? 3 : 1);   // last bar = today so far
  }
  return base64(encodePng(r, CHART_PALETTE));
}

function lineChartPng(values) {
  var r = new Raster(CW, CH), n = values.length, i;
  r.rect(0, 0, CW, CH, 0);
  var min = Infinity, max = -Infinity;
  for (i = 0; i < n; i++) { min = Math.min(min, values[i]); max = Math.max(max, values[i]); }
  if (max - min < 1e-12) { max += 1; min -= 1; }
  var span = max - min; min -= span * 0.08; max += span * 0.08;
  var aw = CW - 2 * CPAD, ah = CH - 2 * CPAD;
  function X(k) { return CPAD + k * (aw - 1) / Math.max(1, n - 1); }
  function Y(v) { return CPAD + (1 - (v - min) / (max - min)) * (ah - 1); }
  for (var g = 0; g < 3; g++) {
    var gy = CPAD + g * (ah - 1) / 2;
    for (var gx = CPAD; gx < CW - CPAD; gx += 6) r.rect(gx, gy, gx + 3, gy + 1, 5);
  }
  for (i = 1; i < n; i++) {
    var xa = Math.round(X(i - 1)), xb = Math.round(X(i));
    for (var x = xa; x <= xb; x++) {
      var t = xb === xa ? 0 : (x - xa) / (xb - xa);
      var y = Y(values[i - 1] + (values[i] - values[i - 1]) * t);
      r.rect(x, y, x + 1, CH - CPAD, 4);
    }
  }
  for (i = 1; i < n; i++) r.line(X(i - 1), Y(values[i - 1]), X(i), Y(values[i]), 3, 3);
  var up = values[n - 1] >= values[0];
  r.rect(X(n - 1) - 4, Y(values[n - 1]) - 4, X(n - 1) + 4, Y(values[n - 1]) + 4, up ? 6 : 7);
  return base64(encodePng(r, CHART_PALETTE));
}

// ---- data loading with per-source cache and last-good fallback ---------------------------------

var FAIL = undefined;   // parse() result meaning "this fetch failed"; null means "ok, nothing there"

function sourceSpecs(cfg, w) {
  var enc = encodeURIComponent, pc = cfg.priceChain, specs = [
    { key: "price", ttl: 0, urls: [API + "/mm/spot/tickers?chainId=" + pc],
      parse: function (b) { var p = parsePrice(b[0]); return p || FAIL; } },
    { key: "fees", ttl: 0, urls: [API + "/fees/application?period=1d&granularity=day"],
      parse: function (b) { var f = parseFees(b[0]); return f || FAIL; } },
    { key: "feesSeries", ttl: SLOW_TTL, urls: [API + "/fees/application?period=1m&granularity=day"],
      parse: function (b) { var s = parseFeesSeries(b[0]); return s || FAIL; } },
    { key: "klines", ttl: SLOW_TTL,
      urls: [API + "/mm/spot/market/klines?symbol=FT-ftUSD&chainId=" + pc + "&interval=1d&limit=30"],
      parse: function (b) { var k = parseKlines(b[0]); return k || FAIL; } }
  ];
  if (!w) return specs;
  var a = enc(w), summaryIds = [146, 1, 56, 143], posIds = [146, 1, 56];
  specs.push(lendSpec(w, 0));
  specs.push({ key: "pnl", ttl: 0,
    urls: summaryIds.map(function (id) { return API + "/mm/spot/account/summary?address=" + a + "&chainId=" + id; }),
    parse: function (b) {
      var total = 0, ok = 0;
      for (var i = 0; i < b.length; i++) { var s = parseSummary(b[i]); if (s) { total += s.pnlUsd; ok++; } }
      return ok ? { totalUsd: total } : FAIL;
    } });
  specs.push({ key: "rewards", ttl: 0, urls: [API + "/account/dashboard?address=" + a + "&view=rewards"],
    parse: function (b) { var r = parseRewards(b[0]); return r || FAIL; } });
  specs.push({ key: "points", ttl: 0, urls: [API + "/points?walletAddress=" + a],
    parse: function (b) { var p = parsePoints(b[0]); return p || FAIL; } });
  specs.push({ key: "positions", ttl: 0, nullOk: true,
    urls: posIds.map(function (id) { return API + "/mm/spot/account/positions?address=" + a + "&chainId=" + id; }),
    parse: function (b) {
      var all = [], ok = 0;
      for (var i = 0; i < b.length; i++) if (b[i]) { all = all.concat(b[i] === JSON_NULL ? [] : parsePositions(b[i])); ok++; }
      return ok ? sortPositions(all) : FAIL;
    } });
  specs.push({ key: "puts", ttl: 0, urls: [API + "/tge/ftPUT/user/" + a],
    parse: function (b) { return b[0] ? parsePuts(b[0]) : FAIL; } });
  return specs;
}

// /mm/lend for one wallet (all chains, plus Monad which is asked for separately).
function lendSpec(w, ttl) {
  var a = encodeURIComponent(w);
  return { key: "lend", ttl: ttl,
    urls: [API + "/mm/lend?user=" + a, API + "/mm/lend?user=" + a + "&chainId=143"],
    parse: function (b) {
      if (!b[0]) return FAIL;
      return mergeChains([parseLend(b[0]), parseLend(b[1])]);
    } };
}

// The JSON literal null is an answer, not a failure: the positions endpoint sends it for a wallet with none.
var JSON_NULL = {};
function parseJson(text) {
  if (text === null || text === undefined) return null;
  var t = String(text).replace(/^\s+|\s+$/g, "");
  if (!t) return null;
  if (t === "null") return JSON_NULL;
  try { return JSON.parse(t); } catch (e) { return null; }
}

// Returns {data: {key: value|undefined}, age: {key: seconds since the shown value was fetched}, fetched: {id: bool}}.
// A spec with a store keeps its value there instead of in cache (another wallet's), and is left out of data/age;
// its id is key@wallet.
function loadSources(io, specs, cache, nowMs) {
  var need = [], urls = [], i, j;
  for (i = 0; i < specs.length; i++) {
    var c = (specs[i].store || cache)[specs[i].key];
    if (specs[i].ttl > 0 && c && nowMs - c.t < specs[i].ttl * 1000) continue;
    need.push(specs[i]);
    for (j = 0; j < specs[i].urls.length; j++) urls.push(specs[i].urls[j]);
  }
  var bodies = urls.length ? io.fetchAll(urls) : [], pos = 0;
  var fetched = {};
  for (i = 0; i < need.length; i++) {
    var bs = [];
    for (j = 0; j < need[i].urls.length; j++) {
      var pj = parseJson(bodies[pos++]);
      bs.push(pj === JSON_NULL && !need[i].nullOk ? null : pj);   // only positions answer "none" with null
    }
    var v = FAIL;
    try { v = need[i].parse(bs); } catch (e) { v = FAIL; }
    if (v !== FAIL) { (need[i].store || cache)[need[i].key] = { t: nowMs, v: v }; fetched[need[i].id || need[i].key] = true; }
  }
  var data = {}, age = {};
  for (i = 0; i < specs.length; i++) {
    if (specs[i].store) continue;
    var e = cache[specs[i].key];
    if (e) { data[specs[i].key] = e.v; age[specs[i].key] = Math.round((nowMs - e.t) / 1000); }
  }
  return { data: data, age: age, fetched: fetched };
}

// Leaderboard is sorted by points (500 per page): binary-search the page, then find the wallet.
function findRank(io, wallet, myPoints) {
  var lo = 1, hi = 14, steps = 0, page = Math.floor((lo + hi) / 2);
  while (steps++ < 8) {
    var b = parseJson(io.fetchAll([API + "/points/leaderboard?page=" + page + "&limit=500"])[0]);
    if (!b || b === JSON_NULL) return FAIL;
    var r = rankInPage(b, wallet, myPoints);
    if (r.found) return { rank: r.rank, total: r.total };
    if (r.total > 0) hi = Math.min(hi, Math.max(1, Math.ceil(r.total / 500)));
    if (r.empty) hi = Math.min(hi, page - 1);   // page past the end of the board
    else if (r.dir === -1) hi = page - 1;
    else if (r.dir === 1) lo = page + 1;
    else return null;
    if (lo > hi) return null;
    page = Math.floor((lo + hi) / 2);
  }
  return null;
}

// ---- state (cache + alert state) -----------------------------------------------------------------

function stateReplacer(k, v) { return (typeof v === "number" && !isFinite(v)) ? "__nan__" : v; }
function stateReviver(k, v) { return v === "__nan__" ? NaN : v; }
// v2: {v, cache (market sources), wallets: {addr: {cache, alert}}, cur (wallet shown), shownAt}.
// A 1.0.x state (v1: one wallet's cache and alert mixed with the market sources) is carried over.
var MARKET_KEYS = { price: 1, fees: 1, feesSeries: 1, klines: 1 };
function loadState(io, path) {
  var txt = io.readFile(path), s = null;
  txt = txt ? txt.replace(/\r/g, "\n") : txt;
  try { s = txt ? JSON.parse(txt, stateReviver) : null; } catch (e) { s = null; }
  if (s && s.v === 1 && s.cache && typeof s.cache === "object") {
    var mc = {}, wc = {};
    for (var k in s.cache) (MARKET_KEYS[k] ? mc : wc)[k] = s.cache[k];
    var ws = {};
    if (s.wallet) ws[s.wallet] = { cache: wc, alert: s.alert || { level: 0, last: {} } };
    s = { v: 2, cache: mc, wallets: ws, cur: s.wallet || "", shownAt: 0 };
  }
  if (!s || s.v !== 2 || typeof s.cache !== "object" || !s.cache || typeof s.wallets !== "object" || !s.wallets)
    s = { v: 2, cache: {}, wallets: {}, cur: "", shownAt: 0 };
  return s;
}
function walletSlot(st, w) {
  var x = st.wallets[w];
  if (!x || typeof x !== "object") x = st.wallets[w] = { cache: {}, alert: { level: 0, last: {} } };
  if (!x.cache) x.cache = {};
  if (!x.alert) x.alert = { level: 0, last: {} };
  return x;
}
function saveState(io, path, s) { io.writeFile(path, JSON.stringify(s, stateReplacer)); }

// ---- rendering -----------------------------------------------------------------------------------

function clean(t) { return String(t).replace(/[|\r\n]+/g, " "); }
function line(text, params) {
  var out = clean(text), ps = params || {};
  var parts = [];
  for (var k in ps) {
    if (ps[k] === undefined || ps[k] === null) continue;
    var v = String(ps[k]);
    parts.push(k + "=" + (/[\s"]/.test(v) ? '"' + v.replace(/"/g, "'") + '"' : v));
  }
  return parts.length ? out + " | " + parts.join(" ") : out;
}
// Give every line from index `from` on a link to `url`, unless it already has a link or an action.
function linkFrom(L, from, url) {
  for (var i = from; i < L.length; i++) {
    if (L[i] === "---" || /(^| )(href|shell|bash|refresh)=/.test(L[i].replace(/^[^|]*\|/, " "))) continue;
    L[i] += (L[i].indexOf(" | ") < 0 ? " | " : " ") + "href=" + url;
  }
}
function padR(s, n) { s = String(s); while (s.length < n) s += " "; return s; }
function mono(extra) {
  var o = { font: "Menlo", size: 12 };
  for (var k in (extra || {})) o[k] = extra[k];
  return o;
}
function row(label, value, extra) { return line(padR(label, 12) + value, mono(extra)); }
function head(text, url) { return line(text, { color: C_FAINT, size: 10, href: url || SITE }); }
function deltaColor(v) { return !isFinite(v) || Math.abs(v) < 0.005 ? undefined : (v > 0 ? C_GREEN : C_RED); }
function ageText(sec) { return sec < 90 ? sec + "s" : (sec < 5400 ? Math.round(sec / 60) + "m" : Math.round(sec / 3600) + "h"); }

function buildView(d, cfg, nowMs) {
  var v = { hfLevel: 0, lowest: null, hasWallet: !!cfg.wallet, walletBad: !cfg.wallet && cfg.badWallets && cfg.badWallets.length > 0 };
  if (d.lend) v.lowest = lowestHf(d.lend);
  if (v.lowest) v.hfLevel = levelFor(v.lowest.hf, cfg.alert, 0);
  return v;
}

// Title: price, fees, the shown wallet's HF and, with several wallets, which one is shown plus the switch sign.
function titleLine(d, age, cfg, v) {
  var parts = [], p = d.price;
  parts.push(p ? fmtPrice(p.price) : "FT —");
  if (d.fees) parts.push("fees " + fmtUsd(d.fees.period24h));
  if (cfg.wallet && d.lend) parts.push("HF " + (v.lowest ? fmtHf(v.lowest.hf) : "∞"));
  if (cfg.wallet && cfg.wallets.length > 1) parts.push(shortAddr(cfg.wallet) + " ⇄");
  var stale = (age.price !== undefined && age.price > STALE_AFTER) || (age.fees !== undefined && age.fees > STALE_AFTER) ||
    (cfg.wallet && age.lend !== undefined && age.lend > STALE_AFTER);
  var txt = parts.join("  ") + (stale ? " ⚠" : "");
  var color = v.hfLevel === 2 ? C_RED : (v.hfLevel === 1 ? C_AMBER : undefined);
  return line(txt, { image: LOGO_B64, color: color, size: 13 });
}

// Lines of a section moved one level down, under its header line: a submenu.
function submenu(L, header, lines) {
  L.push(header);
  for (var i = 0; i < lines.length; i++) L.push(lines[i] === "---" ? "-----" : "--" + lines[i]);
}

// The dropdown has three submenus (Market, Account, Positions) instead of one long list, plus the wallet switch.
function render(d, age, cfg, nowMs, selfPath) {
  var v = buildView(d, cfg, nowMs), L = [], n = cfg.wallets ? cfg.wallets.length : 0;
  var act = function (p1, p2, extra) {
    var o = { shell: selfPath, param1: p1 };
    if (p2) o.param2 = p2;
    o.terminal = false; o.refresh = true;
    for (var k in (extra || {})) o[k] = extra[k];
    return o;
  };
  if (!d.price && !d.fees && !d.lend) {
    L.push(line("FT offline", { image: LOGO_B64, color: C_FAINT }));
  } else L.push(titleLine(d, age, cfg, v));
  L.push("---");
  L.push(line("Flying Tulip", { color: C_TULIP, size: 14, href: SITE }));
  L.push(line("Open flyingtulip.com", { href: SITE }));
  L.push(line("Refresh now", { refresh: true }));
  if (n > 1 && selfPath) {
    L.push("---");
    L.push(line("Showing " + shortAddr(cfg.wallet) + "  (" + (cfg.wallets.indexOf(cfg.wallet) + 1) + " of " + n + ")", { size: 11, color: C_FAINT, href: PAGES.portfolio }));
    L.push(line("Next wallet ⇄", act("next")));
  }
  L.push("---");

  // ---- Market
  var mkt = marketUrl("FT-ftUSD", cfg.priceChain), M = [], mk0 = 0, ch = d.price ? d.price.changePct24h : NaN;
  if (d.price) {
    M.push(row("FT price", fmtPrice(d.price.price) + (isFinite(ch) ? "  " + fmtPct(ch) + " 24h" : ""), { color: deltaColor(ch) }));
    M.push(line("FT-ftUSD market price (the traded mark, not the NAV used for accounting)", { size: 11 }));
    if (d.price.sampledAt) M.push(line("sampled " + d.price.sampledAt, { size: 11, color: C_FAINT }));
  } else M.push(row("FT price", "— unavailable"));
  linkFrom(M, mk0, mkt);
  M.push("---");
  mk0 = M.length;
  if (d.fees) {
    var dod = feesDayOverDay(d.feesSeries, nowMs);
    M.push(row("Fees 24h", fmtUsd(d.fees.period24h) + (isFinite(dod) ? "  " + fmtPct(dod) + " d/d" : ""), { color: deltaColor(dod) }));
    M.push(line("Flying Tulip application fees, last 24 hours" + (isFinite(d.fees.lifetime) ? ", lifetime " + fmtUsd(d.fees.lifetime) : ""), { size: 11 }));
    for (var i = 0; i < d.fees.products.length; i++)
      M.push(line("  " + d.fees.products[i].name + "  " + fmtUsd(d.fees.products[i].usd), { size: 11, font: "Menlo" }));
  } else M.push(row("Fees 24h", "— unavailable"));
  if (d.feesSeries && d.feesSeries.length > 1) {
    var fv = d.feesSeries.map(function (x) { return x.total; });
    M.push(line("Fees, last " + fv.length + " days (today so far in light purple)", { size: 10, color: C_FAINT }));
    M.push(line(" ", { image: barChartPng(fv), href: PAGES.fees }));
  }
  linkFrom(M, mk0, PAGES.fees);
  mk0 = M.length;
  if (d.klines && d.klines.length > 1) {
    var kv = d.klines.map(function (x) { return x.close; });
    M.push(line("FT market price, last " + kv.length + " days", { size: 10, color: C_FAINT }));
    M.push(line(" ", { image: lineChartPng(kv), href: mkt }));
  }
  linkFrom(M, mk0, mkt);
  submenu(L, line("Market     " + (d.price ? fmtPrice(d.price.price) + (isFinite(ch) ? " " + fmtPct(ch) : "") : "—") +
    (d.fees ? "  ·  fees " + fmtUsd(d.fees.period24h) : ""), mono({ href: mkt })), M);

  // ---- Account (the wallet shown)
  var A = [], ac0 = 0, sum = [];
  if (v.walletBad) {
    A.push(line("Not a valid address: " + String(cfg.badWallets[0]).slice(0, 24) + " (0x + 40 hex characters)", { color: C_RED, href: SITE }));
  } else if (v.hasWallet) {
    if (d.lend) {
      if (v.lowest) {
        var lvc = v.hfLevel === 2 ? C_RED : (v.hfLevel === 1 ? C_AMBER : C_GREEN);
        A.push(row("Health", fmtHf(v.lowest.hf) + "  " + v.lowest.name + " (lowest)", { color: lvc }));
      } else A.push(row("Health", "∞  no debt", { color: C_GREEN }));
      for (var c = 0; c < d.lend.length; c++) {
        var ce = d.lend[c];
        if (ce.hf === null && !(ce.debtUsd > 0) && !(ce.equityUsd > 0)) continue;
        A.push(line("  " + padR(ce.name, 9) + (ce.hf === null ? "no debt" : "HF " + fmtHf(ce.hf) + "  debt " + fmtUsd(ce.debtUsd)) +
          (isFinite(ce.equityUsd) ? "  equity " + fmtUsd(ce.equityUsd) : ""), { size: 11, font: "Menlo" }));
      }
      A.push(line("Liquidation below HF " + (v.lowest ? v.lowest.liqHf : DEFAULT_LIQ_HF).toFixed(2) + ". Alerts at " +
        cfg.alert.warn.toFixed(2) + " (warning) and " + cfg.alert.critical.toFixed(2) + " (critical)", { size: 11, color: C_FAINT }));
      sum.push("HF " + (v.lowest ? fmtHf(v.lowest.hf) : "∞"));
    } else A.push(row("Health", "— unavailable"));
    linkFrom(A, ac0, PAGES.health);
    A.push("---");
    ac0 = A.length;
    if (d.pnl) A.push(row("PnL", fmtSignedUsd(d.pnl.totalUsd) + "  unrealized", { color: deltaColor(d.pnl.totalUsd) }));
    else A.push(row("PnL", "— unavailable"));
    linkFrom(A, ac0, PAGES.portfolio);
    ac0 = A.length;
    if (d.rewards) {
      var rw = d.rewards;
      A.push(row("FT earned", fmtFt(rw.totalFt) + " FT  all time"));
      if (isFinite(rw.sftFt)) {
        A.push(line("  sftUSD yield     " + fmtFt(rw.sftFt) + " FT  (claimed " + fmtFt(rw.sftClaimed) + ", pending " + fmtFt(rw.sftPending) + ")", { size: 11, font: "Menlo" }));
        A.push(line("  Lend FT rewards  " + fmtFt(rw.lendFt) + " FT  (received " + fmtFt(rw.lendReceived) + ", pending " + fmtFt(rw.lendPending) + ")", { size: 11, font: "Menlo" }));
        var bc = earnedByChain(rw);
        if (bc) A.push(line("  By chain: " + bc, { size: 11 }));
      }
      if (rw.claimableFt > 0) A.push(line("  " + fmtFt(rw.claimableFt) + " FT claimable (sftUSD yield)", { size: 11 }));
      A.push(line("All time and all chains: what this wallet's sftUSD staking and Lend supply paid out,", { size: 11, color: C_FAINT }));
      A.push(line("so it does not follow the wallet's current size. FT held in ftPUTs is not counted.", { size: 11, color: C_FAINT }));
      sum.push(fmtFt(rw.totalFt) + " FT");
    } else A.push(row("FT earned", "— unavailable"));
    linkFrom(A, ac0, PAGES.rewards);
    ac0 = A.length;
    if (d.points) {
      var rk = d.rank, pc = d.points.chains || [];
      A.push(row("Points", fmtPoints(d.points.total) + "  all chains" + (rk ? "  rank #" + thousands(rk.rank) + " of " + thousands(rk.total) : "")));
      for (var pi = 0; pi < pc.length; pi++) A.push(line("  " + padR(pc[pi].name, 10) + fmtPoints(pc[pi].points), { size: 11, font: "Menlo" }));
      A.push(line("flyingtulip.com/rewards shows one chain at a time, the all-networks total is under it", { size: 11, color: C_FAINT }));
      sum.push(fmtPoints(d.points.total) + " pts");
    } else A.push(row("Points", "— unavailable"));
    linkFrom(A, ac0, PAGES.points);
    ac0 = A.length;
    if (d.puts) {
      var pg = putGain(d.puts, d.price ? d.price.price : NaN);
      if (pg) A.push(row("ftPUT", fmtPct(pg.gainPct) + "  " + fmtSignedUsd(pg.gainUsd), { color: deltaColor(pg.gainUsd) }));
      else A.push(row("ftPUT", d.puts.count + " position" + (d.puts.count === 1 ? "" : "s")));
      A.push(line("Gain = FT held x FT market price - cost basis", { size: 11, color: C_FAINT }));
      for (var q = 0; q < d.puts.rows.length; q++)
        A.push(line("  #" + d.puts.rows[q].nft + "  " + d.puts.rows[q].symbol + "  cost " + fmtUsd(d.puts.rows[q].costUsd) +
          "  " + fmtFt(d.puts.rows[q].ft) + " FT", { size: 11, font: "Menlo" }));
    }
    linkFrom(A, ac0, PAGES.put);
  } else {
    A.push(line("Add a wallet to see health factor, PnL, FT earned, points, ftPUT and positions", { size: 12, href: SITE }));
  }
  // the wallet list: show any of them, add, edit, remove
  if (selfPath) {
    A.push("---");
    for (var wi = 0; wi < n; wi++) {
      var w = cfg.wallets[wi];
      A.push(line((w === cfg.wallet ? "● " : "○ ") + shortAddr(w) + (w === cfg.wallet ? "  (shown)" : ""), act("show", w, { font: "Menlo", size: 12 })));
    }
    if (cfg.fromSettings) {
      A.push(line("These wallets come from the plugin settings (VAR_WALLET).", { size: 11, color: C_FAINT, href: PAGES.portfolio }));
      A.push(line("Change them there, or empty it to manage them from this menu.", { size: 11, color: C_FAINT, href: PAGES.portfolio }));
    } else {
      A.push(line("Add a wallet…", act("add")));
      if (n > 0) A.push(line("Edit wallets…", act("wallet")));
      if (cfg.wallet) A.push(line("Remove " + shortAddr(cfg.wallet), act("remove", cfg.wallet)));
    }
  }
  var acHead = v.hasWallet ? "Account    " + shortAddr(cfg.wallet) + (sum.length ? "  " + sum.join("  ") : "") : "Account    add a wallet";
  submenu(L, line(acHead, mono({ href: PAGES.portfolio, color: v.hfLevel === 2 ? C_RED : (v.hfLevel === 1 ? C_AMBER : undefined) })), A);

  // ---- Positions (the wallet shown)
  var P = [], posHead = "Positions  —";
  if (v.hasWallet && d.positions) {
    if (d.positions.length) {
      posHead = "Positions  " + d.positions.length + " open";
      for (var k = 0; k < d.positions.length && k < 20; k++) {
        var ps = d.positions[k];
        var lev = isFinite(ps.leverage) && ps.leverage > 0 ? " " + ps.leverage.toFixed(ps.leverage >= 10 ? 0 : 1) + "x" : "";
        P.push(line(padR(ps.symbol + " " + ps.side + lev, 14) + padR(ps.network, 10) + "mark " + fmtPrice(ps.mark) +
          "  " + fmtSignedUsd(ps.pnlUsd), { size: 11, font: "Menlo", color: deltaColor(ps.pnlUsd), href: marketUrl(ps.market || (ps.symbol + "-ftUSD"), ps.chainId) }));
      }
      if (d.positions.length > 20) P.push(line("+" + (d.positions.length - 20) + " more on flyingtulip.com", { size: 11, href: PAGES.portfolio }));
    } else { posHead = "Positions  none open"; P.push(line("No open positions", { size: 11, href: PAGES.portfolio })); }
  } else P.push(line(v.hasWallet ? "Unavailable right now" : "Add a wallet to see its open positions", { size: 11, href: PAGES.portfolio }));
  submenu(L, line(posHead, mono({ href: PAGES.portfolio })), P);
  L.push("---");

  // footer
  var ft0 = L.length, t = new Date(nowMs);
  L.push(line("Updated " + pad2(t.getHours()) + ":" + pad2(t.getMinutes()) + (cfg.wallet && !cfg.notify ? "  (notifications off)" : ""), { size: 10, color: C_FAINT }));
  var oldest = 0, k2;
  for (k2 in age) if (!(d.__fetched && d.__fetched[k2]) && age[k2] > STALE_AFTER) oldest = Math.max(oldest, age[k2]);
  if (oldest > 0) L.push(line("Some sources are showing data up to " + ageText(oldest) + " old", { size: 10, color: C_AMBER }));
  if (selfPath && !cfg.fromSettings) L.push(line(n ? "Wallets…" : "Add a wallet…", act(n ? "wallet" : "add", null, { size: 12 })));
  L.push(line("Public API only, no keys. Not financial advice.", { size: 10, color: C_FAINT, href: "https://flyingtulip.com" }));
  linkFrom(L, ft0, SITE);
  return L.join("\n");
}

// ---- main ------------------------------------------------------------------------------------------

// Wallet list: "0xA, 0xB" (commas, spaces, semicolons or new lines) -> {list (lowercase, no duplicates), bad}.
function parseWallets(text) {
  var list = [], bad = [], parts = String(text || "").split(/[\s,;]+/);
  for (var i = 0; i < parts.length; i++) {
    if (!parts[i]) continue;
    var w = normalizeWallet(parts[i]);
    if (!w) bad.push(parts[i]);
    else if (list.indexOf(w) < 0) list.push(w);
  }
  return { list: list, bad: bad };
}

function buildConfig(a) {
  var warn = parseThreshold(a.hfWarn, 1.40), crit = parseThreshold(a.hfCritical, 1.30);
  if (crit > warn) crit = warn;
  var raw = String(a.wallet || "").trim();
  var cd = num(a.cooldownMin);
  var pc = Number(a.priceChain);
  var pw = parseWallets(raw);
  return {
    walletRaw: raw, wallets: pw.list, badWallets: pw.bad, wallet: pw.list[0] || "",
    alert: { warn: warn, critical: crit, cooldownMs: (isFinite(cd) && cd >= 1 ? cd : 30) * 60000 },
    notify: !/^(false|0|no|off)$/i.test(String(a.notify === undefined ? "true" : a.notify).trim()),
    priceChain: pc === 146 ? 146 : 1,
    stateDir: a.stateDir || "", walletFile: a.walletFile || "", self: a.self || ""
  };
}

// "Wallets…" edits the whole list (comma separated), "Add a wallet…" appends, "Remove 0x…" drops one. The list is
// saved one address per line in the wallet file (a 1.0.x file with one address is the same format).
function savedWallets(io, cfg) { return parseWallets(io.readFile(cfg.walletFile) || "").list; }
function writeWallets(io, cfg, list) { io.writeFile(cfg.walletFile, list.join("\n")); }
function runWalletPrompt(io, cfg, mode, arg) {
  var cur = savedWallets(io, cfg);
  if (mode === "remove") {
    writeWallets(io, cfg, cur.filter(function (w) { return w !== normalizeWallet(arg); }));
    return "";
  }
  var input = mode === "add"
    ? io.prompt("", "Public wallet address to add (0x...).")
    : io.prompt(cur.join(", "), "Public wallet addresses to track (0x...), comma separated. Leave empty to clear.");
  if (input === null) return "";
  var p = parseWallets(input);
  if (p.bad.length) { io.alert("Not a valid address: " + String(p.bad[0]).slice(0, 24) + ". Use 0x followed by 40 hex characters."); return ""; }
  var list = mode === "add" ? cur.concat(p.list.filter(function (w) { return cur.indexOf(w) < 0; })) : p.list;
  writeWallets(io, cfg, list);
  return "";
}

var ROTATE_MS = 50000;   // the plugin runs every minute: each run past this shows the next wallet

// The wallet whose health factor is at or below the warning line (the lowest one when several are), else "".
function pinnedWallet(st, wallets) {
  var best = "", bestHf = Infinity;
  for (var i = 0; i < wallets.length; i++) {
    var x = st.wallets[wallets[i]];
    if (!x || !x.alert || !(x.alert.level >= 1)) continue;
    var lo = x.cache.lend ? lowestHf(x.cache.lend.v || []) : null;
    if (lo && lo.hf < bestHf) { best = wallets[i]; bestHf = lo.hf; }
  }
  return best;
}
function hasDebt(list) {
  for (var i = 0; list && i < list.length; i++) if (list[i].debtUsd > 0.01) return true;
  return false;
}

// Alerts for one wallet, from a lend read made this run only. Returns true when its level went up.
function alertWallet(io, cfg, st, w, nowMs) {
  var slot = walletSlot(st, w), prev = slot.alert.level || 0, lend = slot.cache.lend ? slot.cache.lend.v : null;
  var dn = decideNotify(slot.alert, lend ? lowestHf(lend) : null, { warn: cfg.alert.warn, critical: cfg.alert.critical, cooldownMs: cfg.alert.cooldownMs }, nowMs);
  slot.alert = dn.state;
  if (dn.notify && cfg.notify) {
    if (cfg.wallets.length > 1) dn.notify.wallet = shortAddr(w);
    var nt = notifyText(dn.notify); io.notify(nt.title, nt.body, nt.urgency);
  }
  return dn.state.level > prev;
}

function main(io, a, nowMs) {
  var cfg = buildConfig(a);
  if (a.cmd === "wallet" || a.cmd === "add" || a.cmd === "remove") return runWalletPrompt(io, cfg, a.cmd, a.arg);
  // wallets from the plugin settings win; otherwise the ones saved from the menu
  cfg.fromSettings = cfg.wallets.length > 0 || cfg.badWallets.length > 0;
  if (!cfg.fromSettings && cfg.walletFile) {
    cfg.wallets = savedWallets(io, cfg); cfg.wallet = cfg.wallets[0] || "";
  }
  var statePath = cfg.stateDir + "/state.json";
  var st = loadState(io, statePath);
  for (var w0 in st.wallets) if (cfg.wallets.indexOf(w0) < 0) delete st.wallets[w0];   // removed wallets

  // which wallet to show: a manual pick, else every minute the next one, except while one is low (it stays)
  var n = cfg.wallets.length, cur = cfg.wallets.indexOf(st.cur) >= 0 ? st.cur : (cfg.wallets[0] || "");
  var next = function (w) { return cfg.wallets[(cfg.wallets.indexOf(w) + 1) % n]; };
  if (n && a.cmd === "next") { cur = next(cur); st.shownAt = nowMs; }
  else if (n && a.cmd === "show" && cfg.wallets.indexOf(normalizeWallet(a.arg)) >= 0) { cur = normalizeWallet(a.arg); st.shownAt = nowMs; }
  else if (!st.shownAt) st.shownAt = nowMs;   // first run: start on the first wallet
  else if (n > 1 && nowMs - st.shownAt >= ROTATE_MS) { cur = pinnedWallet(st, cfg.wallets) || next(cur); st.shownAt = nowMs; }

  // fetch: market, the shown wallet in full, and /mm/lend of the hidden wallets when due (every run while they have
  // debt, every 10 minutes otherwise)
  var specsFor = function (shown) {
    var specs = sourceSpecs(cfg, shown);
    if (shown) {
      var slot = walletSlot(st, shown);
      for (var i = 4; i < specs.length; i++) specs[i].store = slot.cache;   // the first 4 are the market sources
      for (var j = 0; j < cfg.wallets.length; j++) {
        var w = cfg.wallets[j]; if (w === shown) continue;
        var ws = walletSlot(st, w), sp = lendSpec(w, hasDebt(ws.cache.lend && ws.cache.lend.v) ? 0 : SLOW_TTL);
        sp.store = ws.cache; sp.id = "lend@" + w; specs.push(sp);
      }
    }
    return specs;
  };
  var res = loadSources(io, specsFor(cur), st.cache, nowMs);
  // alerts: the shown wallet and every hidden wallet read this run; one that just turned low is shown at once
  var jump = "";
  if (cur && res.fetched.lend) alertWallet(io, cfg, st, cur, nowMs);
  for (var k = 0; k < n; k++) {
    var hw = cfg.wallets[k];
    if (hw !== cur && res.fetched["lend@" + hw] && alertWallet(io, cfg, st, hw, nowMs) && !jump) jump = hw;
  }
  if (jump) {
    cur = jump; st.shownAt = nowMs;
    var r2 = loadSources(io, specsFor(cur).slice(4).filter(function (s) { return !s.id; }), st.cache, nowMs);
    for (var f in r2.fetched) res.fetched[f] = true;
  }
  st.cur = cur;
  cfg.wallet = cur;

  // the shown wallet's values (each kept in its own cache) next to the market ones
  var d = {}, age = {}, mk;
  for (mk in res.data) if (MARKET_KEYS[mk]) { d[mk] = res.data[mk]; age[mk] = res.age[mk]; }
  if (cur) {
    var c = walletSlot(st, cur).cache;
    for (var key in c) if (key !== "rank") { d[key] = c[key].v; age[key] = Math.round((nowMs - c[key].t) / 1000); }
  }
  // price chain fallback: Sonic ticker when the configured chain has no FT-ftUSD market
  if (!res.fetched.price && cfg.priceChain !== 146 && !d.price) {
    var alt = parseJson(io.fetchAll([API + "/mm/spot/tickers?chainId=146"])[0]), ap = parsePrice(alt);
    if (ap) { st.cache.price = { t: nowMs, v: ap }; d.price = ap; age.price = 0; res.fetched.price = true; }
  }
  if (cur && d.points) {
    var cc = walletSlot(st, cur).cache, rc = cc.rank;
    if (!rc || nowMs - rc.t >= SLOW_TTL * 1000) {
      var rv = findRank(io, cur, d.points.total);
      if (rv !== FAIL) cc.rank = { t: nowMs, v: rv };
    }
    d.rank = cc.rank ? cc.rank.v : null;
  }
  d.__fetched = res.fetched;
  try { saveState(io, statePath, st); } catch (e) { /* cache is optional */ }
  return render(d, age, cfg, nowMs, cfg.self);
}

// ---- osascript (JXA) I/O: no ObjC bridge, only StandardAdditions + curl ------------------------------

function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function jxaIO() {
  var app = Application.currentApplication();
  app.includeStandardAdditions = true;
  // doShellScript turns \n into \r in its result; JSON parsing and the trims below tolerate that.
  function sh(cmd) { return app.doShellScript(cmd); }
  return {
    // Parallel curl, one temp file per URL. A failed request (HTTP error, timeout) yields an empty body.
    fetchAll: function (urls) {
      var cmd = 'd=$(mktemp -d "${TMPDIR:-/tmp}/ftw.XXXXXX") || exit 1; ', i;
      for (i = 0; i < urls.length; i++)
        cmd += "(/usr/bin/curl -fsS -m 12 -H 'Accept: application/json' " + shq(urls[i]) + ' > "$d/' + i + '" 2>/dev/null) & ';
      cmd += "wait; ";
      for (i = 0; i < urls.length; i++) cmd += 'cat "$d/' + i + '"; printf "\\n@@FT@@\\n"; ';
      cmd += 'rm -rf "$d"';
      var out;
      try { out = sh(cmd); } catch (e) { return urls.map(function () { return null; }); }
      var segs = out.split("@@FT@@");
      return urls.map(function (u, j) { return segs[j] === undefined ? null : segs[j]; });
    },
    readFile: function (p) {
      try { return sh("cat " + shq(p) + " 2>/dev/null"); } catch (e) { return null; }
    },
    writeFile: function (p, text) {
      var dir = p.replace(/\/[^\/]*$/, "");
      sh("mkdir -p " + shq(dir) + " && printf %s " + shq(text) + " > " + shq(p));
    },
    notify: function (title, body, urgency) {
      app.displayNotification(body, { withTitle: title, subtitle: "Flying Tulip", soundName: urgency === "critical" ? "Basso" : "Glass" });
    },
    prompt: function (cur, msg) {
      try {
        try { app.activate(); } catch (e) { /* the dialog still shows */ }
        var r = app.displayDialog(msg || "Public wallet addresses to track (0x...), comma separated. Leave empty to clear.", {
          defaultAnswer: cur, withTitle: "Flying Tulip", buttons: ["Cancel", "Save"], defaultButton: "Save", cancelButton: "Cancel" });
        return r.textReturned;
      } catch (e) { return null; }
    },
    alert: function (msg) { try { app.displayAlert("Flying Tulip", { message: msg }); } catch (e) { /* dismissed */ } }
  };
}

function run(argv) {
  var a = {
    cmd: argv[0] || "run", wallet: argv[1] || "", hfWarn: argv[2], hfCritical: argv[3], notify: argv[4],
    cooldownMin: argv[5], priceChain: argv[6], stateDir: argv[7], walletFile: argv[8], self: argv[9], arg: argv[10] || ""
  };
  try { return main(jxaIO(), a, Date.now()); }
  catch (e) { return line("FT ⚠", { image: LOGO_B64, color: C_AMBER }) + "\n---\n" + line("Plugin error: " + e, { color: C_RED }) + "\n" + line("Open flyingtulip.com", { href: SITE }); }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    main: main, buildConfig: buildConfig, parseWallets: parseWallets, pinnedWallet: pinnedWallet, render: render, loadSources: loadSources, sourceSpecs: sourceSpecs, findRank: findRank,
    parseFees: parseFees, parsePrice: parsePrice, parseLend: parseLend, parseSummary: parseSummary, mergeChains: mergeChains,
    lowestHf: lowestHf, parseRewards: parseRewards, earnedByChain: earnedByChain, parsePuts: parsePuts, putGain: putGain, parsePoints: parsePoints,
    rankInPage: rankInPage, parsePositions: parsePositions, parseFeesSeries: parseFeesSeries, parseKlines: parseKlines,
    feesDayOverDay: feesDayOverDay, levelFor: levelFor, decideNotify: decideNotify, notifyText: notifyText,
    parseThreshold: parseThreshold, fmtUsd: fmtUsd, fmtSignedUsd: fmtSignedUsd, fmtPrice: fmtPrice, fmtHf: fmtHf, fmtPct: fmtPct,
    fmtFt: fmtFt, fmtPoints: fmtPoints, fmtSize: fmtSize, normalizeWallet: normalizeWallet, rawUnits: rawUnits,
    barChartPng: barChartPng, lineChartPng: lineChartPng, base64: base64, crc32: crc32, line: line, shq: shq, LOGO_B64: LOGO_B64
  };
}
FT_JS_END

exec /usr/bin/osascript -l JavaScript -e "$FT_JS" \
  "${1:-run}" \
  "${VAR_WALLET:-}" \
  "${VAR_HF_WARN:-1.40}" \
  "${VAR_HF_CRITICAL:-1.30}" \
  "${VAR_NOTIFICATIONS:-true}" \
  "${VAR_NOTIFY_COOLDOWN_MIN:-30}" \
  "${VAR_PRICE_CHAIN:-1}" \
  "$CACHE_DIR" \
  "$WALLET_FILE" \
  "$SELF" \
  "${2:-}" 2>&1
