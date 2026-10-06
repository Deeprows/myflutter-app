// Sends the live-football push notifications (5 minutes before kick-off and
// at kick-off) straight from GitHub Actions, using assets/data/fixtures.json
// from the checkout (no caching delay). Needs FIREBASE_SERVICE_ACCOUNT.
//
// The workflow starts every 15 minutes. If a match is coming up, this script
// stays alive and checks every 20 seconds, so alerts are on time to the
// minute. If nothing is coming up it exits immediately (no Actions minutes
// wasted).
//
//   DRY_RUN=1 node scripts/kickoff_reminders.mjs   -> prints, sends nothing
//
// It shares the Firestore "kickoff_sent" markers with the Cloud Function, so
// using both together never sends a match twice.
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import {
  normalizeFixtures,
  dueGroups,
  claimKey,
  buildMessage,
} from "../functions/kickoff.js";

const DRY = process.env.DRY_RUN === "1";
const FILE = process.env.FIXTURES_FILE || "assets/data/fixtures.json";
const LOOP_MINUTES = Number(process.env.LOOP_MINUTES || 55);
const POLL_MS = Number(process.env.POLL_SECONDS || 20) * 1000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let messaging = null;
let db = null;
let FieldValue = null;
let Timestamp = null;

async function setupFirebase() {
  if (DRY) return;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing in this repository");
  const { initializeApp, cert } = await import("firebase-admin/app");
  initializeApp({ credential: cert(JSON.parse(raw)) });
  messaging = (await import("firebase-admin/messaging")).getMessaging();
  const fs = await import("firebase-admin/firestore");
  db = fs.getFirestore();
  FieldValue = fs.FieldValue;
  Timestamp = fs.Timestamp;
}

const sentHere = new Set(); // dedupe inside this run, even if Firestore is down

/** true = we own this notification; false = someone already sent it. */
async function claim(key) {
  if (sentHere.has(key)) return false;
  sentHere.add(key);
  if (DRY || !db) return true;
  try {
    await db.collection("kickoff_sent").doc(key).create({
      sentAt: FieldValue.serverTimestamp(),
      expireAt: Timestamp.fromMillis(Date.now() + 3 * 24 * 60 * 60 * 1000),
      by: "github-actions",
    });
    return true;
  } catch (e) {
    if (e.code === 6 || /already exists/i.test(String(e.message))) return false;
    // Firestore unavailable: better to risk a duplicate than miss the alert.
    console.warn("Firestore dedupe unavailable, sending anyway:", e.message);
    return true;
  }
}

async function release(key) {
  if (DRY || !db) return;
  try { await db.collection("kickoff_sent").doc(key).delete(); } catch {}
}

let lastFetch = 0;

/** Newest fixtures.json: pulled from GitHub every minute so a match you add
 *  while this job is already running is picked up (not only at start-up). */
function readFixtures(strict = false) {
  let text = null;
  if (!DRY && Date.now() - lastFetch > 60000) {
    lastFetch = Date.now();
    try {
      execFileSync("git", ["fetch", "--quiet", "--depth=1", "origin", "main"], { stdio: "ignore", timeout: 20000 });
      text = execFileSync("git", ["show", `FETCH_HEAD:${FILE}`], { stdio: ["ignore", "pipe", "ignore"] }).toString();
    } catch { text = null; }
  }
  try {
    return normalizeFixtures(JSON.parse(text ?? readFileSync(FILE, "utf8")));
  } catch (e) {
    console.error(`::error file=${FILE}::${FILE} cannot be read as JSON: ${e.message}`);
    if (strict) process.exit(1);
    return [];
  }
}

async function tick(fixtures) {
  const now = Date.now();
  for (const group of dueGroups(fixtures, now)) {
    const fresh = [];
    const keys = [];
    for (const m of group.matches) {
      const key = claimKey(group.phase, m);
      if (await claim(key)) { fresh.push(m); keys.push(key); }
    }
    if (!fresh.length) continue;
    const message = buildMessage({ ...group, matches: fresh }, now);
    if (DRY) {
      console.log("[dry-run]", JSON.stringify(message));
      continue;
    }
    try {
      const id = await messaging.send(message);
      console.log(`Sent ${group.phase}: ${message.notification.body} (${id})`);
    } catch (e) {
      await Promise.all(keys.map(release));
      throw e;
    }
  }
}

async function main() {
  const end = Date.now() + LOOP_MINUTES * 60000;
  let fixtures = readFixtures(true);
  const upcoming = fixtures.filter((f) => f.kickoffMs > Date.now() - 90000).sort((a, b) => a.kickoffMs - b.kickoffMs)[0];
  console.log(`${fixtures.length} valid fixture(s) in ${FILE}.` + (upcoming
    ? ` Next: ${upcoming.home} vs ${upcoming.away} in ${Math.round((upcoming.kickoffMs - Date.now()) / 60000)} min.`
    : " None upcoming."));

  const relevant = (list, now) =>
    list.filter((f) => f.kickoffMs > now - 90000 && f.kickoffMs < end + 5 * 60000);

  if (!relevant(fixtures, Date.now()).length) {
    console.log("No fixture kicks off soon. Nothing to do.");
    return;
  }
  await setupFirebase();

  for (;;) {
    await tick(fixtures);
    if (Date.now() >= end) break;
    await sleep(POLL_MS);
    fixtures = readFixtures();
    if (!relevant(fixtures, Date.now()).length) break;
  }
  console.log("Done.");
}

main().catch((e) => { console.error("Kick-off notifier failed:", e); process.exit(1); });
