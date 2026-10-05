/* =========================================================
   KICK-OFF NOTIFICATION LOGIC (pure functions, no Firebase)
   Used by the scheduled function in index.js and unit-tested
   in kickoff.test.js.
   ========================================================= */

export const REMIND_MINUTES = 5;      // "kick-off in 5 minutes"
export const KICKOFF_GRACE_MIN = 10;  // still announce a start up to 10 min late

/**
 * Same rule as the Flutter app (Fixture.tryParse): a time with no offset is
 * read as Nigeria time (+01:00) so it can't shift between servers.
 * Returns epoch milliseconds, or null when the value is unusable.
 */
export function parseKickoff(raw) {
  let k = String(raw ?? "").trim();
  if (!k) return null;
  if (!/[T ]/.test(k)) return null; // date only: no time of day to notify at
  k = k.replace(" ", "T");
  if (!/(Z|[+-]\d{2}:?\d{2})$/i.test(k)) k = `${k}+01:00`;
  const ms = Date.parse(k);
  return Number.isNaN(ms) ? null : ms;
}

/** Accepts [..] or {fixtures|matches|items: [..]} like the app's feed. */
export function normalizeFixtures(data) {
  let list = [];
  if (Array.isArray(data)) list = data;
  else if (data && typeof data === "object") {
    for (const key of ["fixtures", "matches", "items"]) {
      if (Array.isArray(data[key])) { list = data[key]; break; }
    }
  }
  const out = [];
  for (const raw of list) {
    if (!raw || typeof raw !== "object") continue;
    const home = String(raw.home ?? "").trim();
    const away = String(raw.away ?? "").trim();
    const kickoffMs = parseKickoff(raw.kickoff);
    if (!home || !away || kickoffMs === null) continue;
    const id = String(raw.id ?? "").trim() || `${home}-${away}-${raw.kickoff}`;
    out.push({
      id,
      home,
      away,
      league: String(raw.league ?? "").trim(),
      kickoffMs,
    });
  }
  return out;
}

/**
 * Which fixtures need a notification right now?
 * Returns [{ phase: "reminder" | "kickoff", kickoffMs, matches: [...] }],
 * grouped by kick-off time so 6 matches at 19:45 become ONE notification.
 */
export function dueGroups(fixtures, nowMs) {
  const groups = new Map();
  for (const f of fixtures) {
    const toKick = f.kickoffMs - nowMs;
    let phase = null;
    if (toKick > 0 && toKick <= REMIND_MINUTES * 60000) phase = "reminder";
    else if (toKick <= 0 && toKick > -KICKOFF_GRACE_MIN * 60000) phase = "kickoff";
    if (!phase) continue;
    const key = `${phase}:${f.kickoffMs}`;
    if (!groups.has(key)) groups.set(key, { phase, kickoffMs: f.kickoffMs, matches: [] });
    groups.get(key).matches.push(f);
  }
  return [...groups.values()];
}

/** Firestore document id used to make sure a match is announced only once. */
export function claimKey(phase, match) {
  return `${phase}_${match.kickoffMs}_${match.id}`.replace(/[^\w-]/g, "_").slice(0, 400);
}

/** FCM message for one group of matches. */
export function buildMessage(group, nowMs, topic = "kickoff") {
  const { phase, kickoffMs, matches } = group;
  const n = matches.length;
  const names = matches.map((m) => `${m.home} vs ${m.away}`);
  const mins = Math.max(1, Math.ceil((kickoffMs - nowMs) / 60000));

  let title;
  let body;
  if (phase === "reminder") {
    title = n === 1
      ? `⏰ Kick-off in ${mins} minute${mins === 1 ? "" : "s"}`
      : `⏰ ${n} matches kick off in ${mins} minute${mins === 1 ? "" : "s"}`;
  } else {
    title = n === 1 ? "⚽ Kick-off! Match is live" : `⚽ ${n} matches are live now`;
  }
  if (n === 1) {
    body = matches[0].league ? `${names[0]} • ${matches[0].league}` : names[0];
  } else {
    body = names.slice(0, 3).join(", ") + (n > 3 ? ` +${n - 3} more` : "");
  }

  return {
    topic,
    notification: { title, body },
    data: {
      type: "kickoff",
      tab: "live",
      phase,
      matchIds: matches.map((m) => m.id).join(",").slice(0, 500),
    },
    android: {
      priority: "high",
      ttl: phase === "reminder" ? 5 * 60 * 1000 : 15 * 60 * 1000,
      notification: {
        channelId: "kickoff",
        tag: `kickoff-${phase}-${kickoffMs}`,
      },
    },
  };
}
