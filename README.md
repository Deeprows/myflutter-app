# Kick-off push server (add to the Footbolive repo)

Copy these into the **Footbolive** repo root, replacing existing files:

* `functions/index.js`   (your existing functions are kept; `kickoffReminders` is added)
* `functions/kickoff.js`, `functions/kickoff.test.js`
* `functions/package.json` (adds `firebase-functions`, which `index.js` already imported)
* `firebase.json`, `.firebaserc` (only if you don't already have them)

Then:

```bash
cd functions && npm install && npm test      # logic tests
cd .. && firebase deploy --only functions:kickoffReminders
# when asked for FIXTURES_URL, enter the raw URL of the app's fixtures.json, e.g.
# https://raw.githubusercontent.com/<user>/<repo>/main/assets/data/fixtures.json
```

Requires the Blaze plan (Cloud Scheduler); your existing v2 functions already need it.

Behaviour: runs every minute, sends to FCM topic `kickoff` when a match is
within 5 minutes of kick-off and again when it starts (up to 10 min late if a
run was missed). Matches sharing a kick-off time are merged into one
notification. Each (phase, match) is recorded in Firestore `kickoff_sent` so
it is never sent twice. Optional: add a Firestore TTL policy on `expireAt`.

GitHub's raw URLs are cached for about 5 minutes, so a fixture you just added
may be picked up a few minutes later.
