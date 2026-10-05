import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineString } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import {
  normalizeFixtures,
  dueGroups,
  claimKey,
  buildMessage
} from "./kickoff.js";

initializeApp();

const TOPIC = "deeprowss";

// Secret used to authorize requests to send notifications
const SEND_SECRET = process.env.SEND_SECRET;


/* =========================================================
   REGISTER FCM TOKEN
   ========================================================= */

export const registerNotificationToken = onRequest(
  {
    region: "us-central1",
    cors: true
  },
  async (req, res) => {

    if (req.method !== "POST") {
      return res.status(405).json({
        success: false,
        error: "Method not allowed"
      });
    }

    try {

      const token =
        typeof req.body?.token === "string"
          ? req.body.token.trim()
          : "";

      if (!token) {
        return res.status(400).json({
          success: false,
          error: "FCM token is required"
        });
      }

      await getMessaging().subscribeToTopic(
        [token],
        TOPIC
      );

      console.log(
        "Subscribed browser to topic:",
        TOPIC
      );

      return res.status(200).json({
        success: true,
        topic: TOPIC
      });

    } catch (error) {

      console.error(
        "FCM topic subscription failed:",
        error
      );

      return res.status(500).json({
        success: false,
        error: "Unable to register notification subscription"
      });

    }

  }
);


/* =========================================================
   SEND NOTIFICATION
   ========================================================= */

export const sendNotification = onRequest(
  {
    region: "us-central1",
    cors: true
  },
  async (req, res) => {

    if (req.method !== "POST") {
      return res.status(405).json({
        success: false,
        error: "Method not allowed"
      });
    }

    // Check secret
    if (
      !SEND_SECRET ||
      req.headers["x-send-secret"] !== SEND_SECRET
    ) {
      return res.status(401).json({
        success: false,
        error: "Unauthorized"
      });
    }

    const {
      title,
      body,
      url
    } = req.body || {};

    if (!title || !body) {
      return res.status(400).json({
        success: false,
        error: "title/body required"
      });
    }

    try {

      await getMessaging().send({
        topic: TOPIC,

        notification: {
          title,
          body
        },

        data: {
          url: url || "./index.html"
        },

        webpush: {
          fcmOptions: {
            link:
              url ||
              "https://deeprows.github.io/Footbolive/"
          }
        }
      });

      console.log(
        "Notification sent to topic:",
        TOPIC
      );

      return res.status(200).json({
        success: true
      });

    } catch (error) {

      console.error(
        "Notification sending failed:",
        error
      );

      return res.status(500).json({
        success: false,
        error: "Unable to send notification"
      });

    }

  }
);


/* =========================================================
   LIVE FOOTBALL: KICK-OFF REMINDERS (FOR THE FLUTTER APP)

   Runs every minute. For every fixture it sends one push to
   the FCM topic "kickoff":
     - when kick-off is 5 minutes away
     - when the match starts
   Several matches with the same kick-off time are merged
   into a single notification.

   FIXTURES_URL = public URL of the app's fixtures.json, e.g.
   https://raw.githubusercontent.com/<user>/<repo>/main/assets/data/fixtures.json
   (asked for on the first "firebase deploy").

   Each (phase, match) is stored in Firestore collection
   "kickoff_sent" so it is never sent twice, even if a run
   is retried or two runs overlap.
   ========================================================= */

const FIXTURES_URL = defineString("FIXTURES_URL");

async function claim(db, key) {
  try {
    await db.collection("kickoff_sent").doc(key).create({
      sentAt: FieldValue.serverTimestamp(),
      // Optional: enable a Firestore TTL policy on "expireAt" to auto-clean.
      expireAt: Timestamp.fromMillis(Date.now() + 3 * 24 * 60 * 60 * 1000)
    });
    return true;
  } catch (error) {
    // 6 = ALREADY_EXISTS -> this one was announced before.
    if (error.code === 6 || /already exists/i.test(String(error.message))) {
      return false;
    }
    throw error;
  }
}

export const kickoffReminders = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 60,
    retryCount: 0
  },
  async () => {

    const url = FIXTURES_URL.value();

    const response = await fetch(url, {
      headers: { "Cache-Control": "no-cache" }
    });

    if (!response.ok) {
      throw new Error(`Fixtures fetch failed: HTTP ${response.status}`);
    }

    const fixtures = normalizeFixtures(await response.json());
    const now = Date.now();
    const groups = dueGroups(fixtures, now);

    if (!groups.length) return;

    const db = getFirestore();

    for (const group of groups) {

      // Keep only matches not announced yet for this phase.
      const fresh = [];
      const claimed = [];

      for (const match of group.matches) {
        const key = claimKey(group.phase, match);
        if (await claim(db, key)) {
          fresh.push(match);
          claimed.push(key);
        }
      }

      if (!fresh.length) continue;

      try {

        const message = buildMessage(
          { ...group, matches: fresh },
          now
        );

        const id = await getMessaging().send(message);

        console.log(
          `Sent ${group.phase} for ${fresh.length} match(es):`,
          message.notification.body,
          id
        );

      } catch (error) {

        // Release the claims so the next run retries.
        await Promise.all(
          claimed.map((key) =>
            db.collection("kickoff_sent").doc(key).delete()
          )
        );

        console.error("Kick-off notification failed:", error);
        throw error;

      }

    }

  }
);
