
 // Sends a push when a NEW movie reaches the top of the daily trending list.
 //
 //   node scripts/notify_trending.mjs
 //   DRY_RUN=1 node scripts/notify_trending.mjs
 //   FORCE=1 node scripts/notify_trending.mjs
 //
 // The last announced movie IDs are kept in state/trending_last.json.
 // The workflow commits this file to prevent duplicate notifications.

import {
  readFileSync,
  writeFileSync,
  mkdirSync,
} from "node:fs";

import {
  initializeApp,
  cert,
} from "firebase-admin/app";

import {
  getMessaging,
} from "firebase-admin/messaging";

const DRY = process.env.DRY_RUN === "1";
const FORCE = process.env.FORCE === "1";

const STATE = "state/trending_last.json";
const KEEP = 60;

// API credentials are provided securely through GitHub Secrets.
const key = (process.env.TMDB_API_KEY || "").trim();

if (!key) {
  console.error("TMDB_API_KEY secret is missing");
  process.exit(1);
}

const isV4 = key.startsWith("eyJ") && key.length > 80;

const url = new URL(
  "https://api.themoviedb.org/3/trending/movie/day"
);

if (!isV4) {
  url.searchParams.set("api_key", key);
}

const res = await fetch(url, {
  headers: isV4
    ? { Authorization: `Bearer ${key}` }
    : {},
});

if (!res.ok) {
  console.error(
    `TMDB request failed: HTTP ${res.status}`
  );
  process.exit(1);
}

const results = (await res.json()).results || [];

let seen = [];
let firstRun = false;

try {
  seen =
    JSON.parse(readFileSync(STATE, "utf8")).announced || [];
} catch {
  firstRun = true;
}
if (seen.length === 0) firstRun = true;

// Find a new movie among the top five trending movies.
const top = results
  .slice(0, 5)
  .filter((m) => m.title && m.poster_path);

const fresh = top.filter(
  (m) => !seen.includes(m.id)
);

// Force allows manually testing a notification.
const pick = FORCE
  ? top[0]
  : fresh[0];

// Save announced movie IDs to prevent duplicates.
function save(ids) {
  mkdirSync("state", {
    recursive: true,
  });

  writeFileSync(
    STATE,
    JSON.stringify(
      {
        announced: ids.slice(0, KEEP),
      },
      null,
      2
    ) + "\n"
  );
}

// First scheduled run records trending movies
// without sending an initial notification.
if (firstRun && !FORCE) {
  console.log(
    "First run: recording the current trending list without notifying."
  );

  if (!DRY) {
    save(top.map((m) => m.id));
  }

  process.exit(0);
}

if (!pick) {
  console.log(
    "No new trending movie. Nothing to send."
  );

  process.exit(0);
}

// Prepare movie information.
const year = (pick.release_date || "").slice(0, 4);

const rating = pick.vote_average
  ? ` • ⭐ ${pick.vote_average.toFixed(1)}`
  : "";

// Firebase Cloud Messaging notification.
//
// IMPORTANT:
// movieId identifies the exact movie that should open
// when the notification is tapped.
//
// tmdbId is retained for compatibility with older receivers.

const message = {
  topic: "trending",

  notification: {
    title: "🔥 Trending now",

    body:
      `${pick.title}` +
      `${year ? ` (${year})` : ""}` +
      `${rating}`,

    imageUrl:
      `https://image.tmdb.org/t/p/w500${pick.poster_path}`,
  },

  data: {
    type: "trending_movie",

    movieId: String(pick.id),

    tmdbId: String(pick.id),

    mediaType: "movie",

    title: pick.title,
  },

  android: {
    priority: "high",

    notification: {
      channelId: "trending",
    },
  },
};

// Preview the notification without sending it.
if (DRY) {
  console.log(
    "DRY RUN, would send:",
    JSON.stringify(message, null, 2)
  );

  process.exit(0);
}

// Read Firebase service account credentials.
const raw = process.env.FIREBASE_SERVICE_ACCOUNT;

if (!raw) {
  console.error(
    "FIREBASE_SERVICE_ACCOUNT secret is missing in this repository"
  );

  process.exit(1);
}

try {
  // Initialize Firebase Admin.
  initializeApp({
    credential: cert(JSON.parse(raw)),
  });

  // Send the Trending Now notification.
  const id = await getMessaging().send(message);

  console.log(
    `Sent "${pick.title}" to topic "trending":`,
    id
  );

  // Record the announced movie.
  save(
    [
      pick.id,
      ...top.map((m) => m.id),
      ...seen,
    ].filter(
      (v, i, a) => a.indexOf(v) === i
    )
  );
} catch (e) {
  console.error(
    "FAILED:",
    e.code || "",
    e.message
  );

  process.exit(1);
}
