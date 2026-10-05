// Sends a push notification when a commit adds NEW highlights or movies.
//
//   node scripts/notify_content.mjs            (needs FIREBASE_SERVICE_ACCOUNT)
//   DRY_RUN=1 node scripts/notify_content.mjs  (prints what it would send)
//
// It compares assets/data/{highlights,movies}.json with the previous commit
// (BEFORE_SHA, or HEAD^) and notifies only for items whose url is new, so
// editing or reordering existing items never triggers a notification.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const DRY = process.env.DRY_RUN === "1";
const BEFORE = /^0*$/.test(process.env.BEFORE_SHA || "") ? "HEAD^" : process.env.BEFORE_SHA;

const KINDS = [
  { file: "assets/data/highlights.json", topic: "highlights" },
  { file: "assets/data/movies.json", topic: "movies" },
];

function toList(text) {
  const d = JSON.parse(text);
  if (Array.isArray(d)) return d;
  for (const k of ["highlights", "movies", "items"]) if (Array.isArray(d?.[k])) return d[k];
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

export function newItems(prev, curr) {
  const seen = new Set(prev.map((i) => str(i?.url)));
  const added = new Set();
  return curr.filter((i) => {
    const u = str(i?.url);
    if (!u || !str(i?.name) || seen.has(u) || added.has(u)) return false;
    added.add(u);
    return true;
  });
}

export function buildMessage(topic, items) {
  const n = items.length;
  const first = items[0];
  const names = items.slice(0, 2).map((i) => str(i.name));
  let title, body, imageUrl;
  if (topic === "highlights") {
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
    data: { type: topic, tab: topic },
    android: { priority: "normal", notification: { channelId: "content" } },
  };
}

async function main() {
  const messages = [];
  for (const { file, topic } of KINDS) {
    let curr;
    try { curr = toList(readFileSync(file, "utf8")); } catch { continue; }
    const prev = previousList(file);
    if (!prev) { console.log(`${file}: no previous version, skipping`); continue; }
    const added = newItems(prev, curr);
    console.log(`${file}: ${added.length} new item(s)`);
    if (added.length) messages.push(buildMessage(topic, added));
  }
  if (!messages.length) { console.log("Nothing to notify."); return; }

  if (DRY) { console.log(JSON.stringify(messages, null, 2)); return; }

  const { initializeApp, cert } = await import("firebase-admin/app");
  const { getMessaging } = await import("firebase-admin/messaging");
  initializeApp({ credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });

  for (const m of messages) {
    try {
      console.log("sent", m.topic, await getMessaging().send(m));
    } catch (e) {
      if (m.notification.imageUrl) { // bad poster url: retry as plain text
        delete m.notification.imageUrl;
        console.log("sent (no image)", m.topic, await getMessaging().send(m));
      } else throw e;
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error("Failed to send notifications:", e); process.exit(1); });
}
