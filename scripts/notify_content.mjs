// Sends a push notification when a commit adds NEW highlights or movies.
//
//   node scripts/notify_content.mjs            (needs FIREBASE_SERVICE_ACCOUNT)
//   DRY_RUN=1 node scripts/notify_content.mjs  (prints what it would send)
//   FORCE_LATEST=1 ...   re-sends the newest highlight / movie / upcoming match
//                        (used by "Run workflow > resend_latest" to test)
//
// It compares assets/data/{highlights,movies}.json with the previous commit
// (BEFORE_SHA, or HEAD^) and notifies only for items whose url is new, so
// editing or reordering existing items never triggers a notification.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const DRY = process.env.DRY_RUN === "1";
const FORCE = process.env.FORCE_LATEST === "1";
const BEFORE = /^0*$/.test(process.env.BEFORE_SHA || "") ? "HEAD^" : process.env.BEFORE_SHA;

const KINDS = [
  { file: "assets/data/highlights.json", topic: "highlights" },
  { file: "assets/data/movies.json", topic: "movies" },
  // New matches go to the same topic as the kick-off alerts ("Live match alerts").
  { file: "assets/data/fixtures.json", topic: "kickoff" },
];

function toList(text) {
  const d = JSON.parse(text);
  if (Array.isArray(d)) return d;
  for (const k of ["fixtures", "matches", "highlights", "movies", "items"]) if (Array.isArray(d?.[k])) return d[k];
  return [];
}

function previousList(file) {
  try {
    const out = execFileSync("git", ["show", `${BEFORE}:${file}`], {
      stdio: ["ignore", "pipe", "ignore"],
    }).toString();
    return toList(out);
  } catch {
    return null; // file did not exist / unreadable: do not announce the whole catalogue
  }
}

const str = (v) => String(v ?? "").trim();

// A fixture is "the same" when teams and kick-off match (ids get reused).
export function keyOf(topic, i) {
  return topic === "kickoff"
    ? `${str(i?.home)}|${str(i?.away)}|${str(i?.kickoff)}`.toLowerCase()
    : str(i?.url);
}

function valid(topic, i, nowMs) {
  if (topic !== "kickoff") return !!str(i?.name) && !!str(i?.url);
  if (!str(i?.home) || !str(i?.away)) return false;
  const t = Date.parse(kickoffIso(i.kickoff));
  // Skip matches that already finished (old data being tidied up).
  return Number.isNaN(t) || t > nowMs - 3 * 3600000;
}

function kickoffIso(raw) {
  let k = str(raw).replace(" ", "T");
  if (k && !/(Z|[+-]\d{2}:?\d{2})$/i.test(k)) k += "+01:00"; // same rule as the app
  return k;
}

export function newItems(prev, curr, topic = "highlights", nowMs = Date.now()) {
  const seen = new Set(prev.map((i) => keyOf(topic, i)));
  const added = new Set();
  return curr.filter((i) => {
    const k = keyOf(topic, i);
    if (!k || k === "||" || seen.has(k) || added.has(k) || !valid(topic, i, nowMs)) return false;
    added.add(k);
    return true;
  });
}

function whenText(raw) {
  const t = Date.parse(kickoffIso(raw));
  if (Number.isNaN(t)) return "";
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "short", day: "numeric", month: "short",
    hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Africa/Lagos",
  }).format(t).replace(/\b(am|pm)\b/i, (m) => m.toUpperCase()) + " WAT";
}

export function buildMessage(topic, items) {
  const n = items.length;
  const first = items[0];
  const names = items.slice(0, 2).map((i) => str(i.name));
  let title, body, imageUrl;
  if (topic === "kickoff") {
    const label = (m) => `${str(m.home)} vs ${str(m.away)}`;
    title = n === 1 ? "⚽ New match added" : `⚽ ${n} new matches added`;
    body = n === 1
      ? [label(first), whenText(first.kickoff)].filter(Boolean).join(" • ")
      : items.slice(0, 2).map(label).join(", ") + (n > 2 ? ` +${n - 2} more` : "");
  } else if (topic === "highlights") {
    title = n === 1 ? "🎬 New match highlights" : `🎬 ${n} new match highlights`;
    body = n === 1 ? str(first.name) : names.join(", ") + (n > 2 ? ` +${n - 2} more` : "");
  } else {
    title = n === 1 ? "🍿 New movie added" : `🍿 ${n} new movies added`;
    const genre = str(first.genre).split(",").slice(0, 2).join(", ");
    body = n === 1
      ? str(first.name) + (genre ? ` • ${genre}` : "")
      : names.join(", ") + (n > 2 ? ` +${n - 2} more` : "");
    if (n === 1 && /^https:\/\//i.test(str(first.image))) imageUrl = str(first.image);
  }
  return {
    topic,
    notification: { title, body, ...(imageUrl ? { imageUrl } : {}) },
    data: { type: topic, tab: topic === "kickoff" ? "live" : topic },
    android: topic === "kickoff"
      ? { priority: "high", notification: { channelId: "kickoff" } }
      : { priority: "high", notification: { channelId: "content" } },
  };
}

/** Newest item: latest `date` for highlights/movies, next kick-off for matches. */
export function latestItem(topic, list, nowMs = Date.now()) {
  const ok = list.filter((i) => valid(topic, i, nowMs));
  if (!ok.length) return null;
  if (topic === "kickoff") {
    const t = (i) => Date.parse(kickoffIso(i.kickoff));
    return [...ok].sort((a, b) => (t(a) || 9e15) - (t(b) || 9e15))[0];
  }
  return [...ok].sort((a, b) => str(b.date).localeCompare(str(a.date)))[0];
}

async function main() {
  const messages = [];
  let failed = false;
  for (const { file, topic } of KINDS) {
    let curr;
    try {
      curr = toList(readFileSync(file, "utf8"));
    } catch (e) {
      // A broken JSON file must be loud: a red run, not a silent "nothing".
      console.error(`::error file=${file}::${file} cannot be read as JSON: ${e.message}`);
      failed = true;
      continue;
    }

    let added;
    if (FORCE) {
      const one = latestItem(topic, curr);
      added = one ? [one] : [];
      console.log(`${file}: FORCE_LATEST -> ${added.length ? str(one.name || `${one.home} vs ${one.away}`) : "nothing"}`);
    } else {
      const prev = previousList(file);
      if (!prev) { console.log(`${file}: no previous version to compare, skipping`); continue; }
      added = newItems(prev, curr, topic);
      console.log(`${file}: ${curr.length} items now, ${prev.length} before, ${added.length} new`);
      for (const i of added) console.log(`   + ${str(i.name || `${i.home} vs ${i.away}`)}`);
    }
    if (added.length) messages.push(buildMessage(topic, added));
  }

  if (!messages.length) {
    console.log("Nothing to notify.");
    if (failed) process.exit(1);
    return;
  }

  if (DRY) {
    console.log(JSON.stringify(messages, null, 2));
    if (failed) process.exit(1);
    return;
  }

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.error("::error::FIREBASE_SERVICE_ACCOUNT secret is missing in this repository");
    process.exit(1);
  }
  const { initializeApp, cert } = await import("firebase-admin/app");
  const { getMessaging } = await import("firebase-admin/messaging");
  initializeApp({ credential: cert(JSON.parse(raw)) });

  for (const m of messages) {
    try {
      console.log("SENT", m.topic, "-", m.notification.title, "-", m.notification.body, await getMessaging().send(m));
    } catch (e) {
      if (m.notification.imageUrl) { // bad poster url: retry as plain text
        delete m.notification.imageUrl;
        console.log("SENT (no image)", m.topic, await getMessaging().send(m));
      } else throw e;
    }
  }
  if (failed) process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error("Failed to send notifications:", e); process.exit(1); });
}
