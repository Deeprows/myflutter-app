// Run:  node functions/kickoff.test.js
import assert from "node:assert/strict";
import {
  parseKickoff, normalizeFixtures, dueGroups, buildMessage, claimKey,
} from "./kickoff.js";

const KICK = Date.parse("2026-10-05T19:45:00+01:00");
const min = 60000;

// parsing (same rules as the Flutter app)
assert.equal(parseKickoff("2026-10-05T19:45:00+01:00"), KICK);
assert.equal(parseKickoff("2026-10-05T18:45:00Z"), KICK);
assert.equal(parseKickoff("2026-10-05T19:45:00"), KICK);        // no offset => +01:00
assert.equal(parseKickoff("2026-10-05 19:45"), KICK);
assert.equal(parseKickoff("2026-10-05"), null);                  // no time of day
assert.equal(parseKickoff("garbage"), null);
assert.equal(parseKickoff(""), null);

// normalising
const fx = normalizeFixtures({ fixtures: [
  { id: "1", home: "France", away: "Belgium", kickoff: "2026-10-05T19:45:00+01:00" },
  { id: "2", home: "Italy", away: "Türkiye", kickoff: "2026-10-05T19:45:00+01:00", league: "Nations League" },
  { home: "", away: "X", kickoff: "2026-10-05T19:45:00+01:00" },
  { id: "9", home: "A", away: "B", kickoff: "nope" },
]});
assert.equal(fx.length, 2);

// windows
assert.equal(dueGroups(fx, KICK - 6 * min).length, 0);           // too early
let g = dueGroups(fx, KICK - 5 * min);
assert.equal(g.length, 1); assert.equal(g[0].phase, "reminder"); assert.equal(g[0].matches.length, 2);
g = dueGroups(fx, KICK - 4 * min - 30000);
assert.equal(g[0].phase, "reminder");
assert.equal(dueGroups(fx, KICK).at(0).phase, "kickoff");        // exactly at kick-off
assert.equal(dueGroups(fx, KICK + 9 * min).at(0).phase, "kickoff");
assert.equal(dueGroups(fx, KICK + 11 * min).length, 0);          // too late

// message wording
let m = buildMessage(dueGroups(fx, KICK - 5 * min)[0], KICK - 5 * min);
assert.equal(m.topic, "kickoff");
assert.equal(m.notification.title, "⏰ 2 matches kick off in 5 minutes");
assert.equal(m.android.notification.channelId, "kickoff");
assert.equal(m.data.tab, "live");

const single = normalizeFixtures([{ id: "2", home: "Italy", away: "Türkiye", league: "Nations League", kickoff: "2026-10-05T19:45:00+01:00" }]);
m = buildMessage(dueGroups(single, KICK - 4 * min - 59000)[0], KICK - 4 * min - 59000);
assert.equal(m.notification.title, "⏰ Kick-off in 5 minutes");
assert.equal(m.notification.body, "Italy vs Türkiye • Nations League");
m = buildMessage(dueGroups(single, KICK)[0], KICK);
assert.equal(m.notification.title, "⚽ Kick-off! Match is live");

// many matches
const many = normalizeFixtures(Array.from({ length: 6 }, (_, i) => ({
  id: String(i), home: `H${i}`, away: `A${i}`, kickoff: "2026-10-05T19:45:00+01:00" })));
m = buildMessage(dueGroups(many, KICK)[0], KICK);
assert.equal(m.notification.title, "⚽ 6 matches are live now");
assert.equal(m.notification.body, "H0 vs A0, H1 vs A1, H2 vs A2 +3 more");

// idempotency keys are Firestore-safe and distinct per phase
const k1 = claimKey("reminder", many[0]), k2 = claimKey("kickoff", many[0]);
assert.notEqual(k1, k2); assert.ok(!/[/.]/.test(k1));
console.log("kickoff.js: all tests passed");
