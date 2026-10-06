// Sends one test notification. Run it from GitHub: Actions > "Send test push"
// > Run workflow. Proves the whole chain (service account > Firebase > phone).
//   TOPIC=kickoff TITLE="Test" BODY="Hello" node scripts/send_test_push.mjs
import { initializeApp, cert } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";

const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) { console.error("FIREBASE_SERVICE_ACCOUNT secret is missing in this repository"); process.exit(1); }

const topic = (process.env.TOPIC || "kickoff").trim();
const tab = { kickoff: "live", highlights: "highlights", movies: "movies" }[topic] || "live";

try {
  initializeApp({ credential: cert(JSON.parse(raw)) });
  const id = await getMessaging().send({
    topic,
    notification: {
      title: process.env.TITLE || "✅ Test notification",
      body: process.env.BODY || "Push notifications are working.",
    },
    data: { type: topic, tab },
    android: {
      priority: "high",
      notification: { channelId: topic === "kickoff" ? "kickoff" : "content" },
    },
  });
  console.log(`Sent to topic "${topic}":`, id);
} catch (e) {
  console.error("FAILED:", e.code || "", e.message);
  process.exit(1);
}
