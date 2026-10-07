# Push notifications (Firebase Cloud Messaging)

The app subscribes to three FCM topics. Users can switch each one on/off in
the drawer: **Notifications**.

| Topic        | Sent when                                         | Sent by                                   |
|--------------|---------------------------------------------------|-------------------------------------------|
| `kickoff`    | 5 minutes before kick-off, and at kick-off        | Cloud Function `kickoffReminders` (every minute) |
| `highlights` | a commit adds a new highlight                     | `.github/workflows/notify-content.yml`    |
| `movies`     | a commit adds a new movie (with poster)           | `.github/workflows/notify-content.yml`    |

Firebase project: `deeprows-4d37c` (same as the Footbolive website).

## One-time setup

1. **Firebase console > Project settings > Your apps > Add app > Android**
   Package name: `com.deeprows.footbolive`. You do not need to download
   `google-services.json`. Copy the **App ID** (`1:227439941748:android:...`)
   and save it in this GitHub repo under *Settings > Secrets and variables >
   Actions > Variables* as `FIREBASE_ANDROID_APP_ID`.
   (If left empty the app falls back to the website's App ID.)
2. **GitHub secret** `FIREBASE_SERVICE_ACCOUNT` in this repo: the same
   service-account JSON the Footbolive repo already uses.
3. **Deploy the kick-off function** from the Footbolive repo (see
   `footbolive-push-server/README.md`).
4. Recommended: set `AppConfig.fixturesUrl` in `lib/config.dart` to the same
   raw `fixtures.json` URL the function reads, so the app list and the
   notifications always agree without rebuilding the APK.

## Test it

* Install the APK, open it once, allow notifications.
* Firebase console > Engage > Messaging > New campaign > Notifications >
  target a **Topic** (`kickoff`, `highlights` or `movies`).
* Or use Actions > Send test push on GitHub.
* Fixtures that start in the next 5 minutes trigger a real reminder within a
  minute of deploying the function.

## Files added / changed

* `lib/services/push_service.dart`, `lib/widgets/notification_settings.dart`
* `lib/main.dart`, `lib/app.dart`, `lib/screens/shell_screen.dart`, `lib/widgets/app_drawer.dart`
* `tool/patch_android_push.py`, `tool/patch_main_activity.py`, `.github/workflows/build.yml`
* `scripts/notify_content.mjs`, `.github/workflows/notify-content.yml`


## If notifications do not arrive (troubleshooting)

1. (Removed from the app menu.) Use the GitHub test push below to check delivery.
   problem: missing App ID, permission not allowed, device token failed (with
   Firebase's error), or a topic that failed to subscribe. Use **Copy status**
   to share it.
2. Test the whole chain from GitHub: **Actions > Send test push > Run
   workflow** (pick a topic). A message should appear on the phone within
   seconds. If the run goes red, the log says why (usually the
   `FIREBASE_SERVICE_ACCOUNT` secret).
3. Status says "Device token: FAILED" with a 403 / "blocked" / "API key"
   message: the website API key is restricted to browsers. Either remove the
   "HTTP referrers" restriction in Google Cloud console > APIs & Services >
   Credentials, or put the Android key (from Firebase > Project settings >
   Your apps > Android app > google-services.json > `current_key`) in a repo
   **variable** named `FIREBASE_ANDROID_API_KEY`, then rebuild.
4. Android app package in Firebase must be exactly `com.deeprows.footbolive`.

## Kick-off alerts without Cloud Functions

`.github/workflows/kickoff-reminders.yml` sends the 5-minute and kick-off
alerts from GitHub (needs only the `FIREBASE_SERVICE_ACCOUNT` secret). It
starts every 15 minutes and, when a match is near, stays alive checking every
20 seconds. Using it together with the Cloud Function is safe (shared
duplicate guard).


## Notifications while the app is open, and opening the exact item

* While the app is open, a notification is now drawn in the phone's status
  bar / tray like any other app (native code in `MainActivity`, patched by
  `tool/patch_main_activity.py`). If notifications are switched off for the
  app, a banner inside the app is shown instead.
* Tapping a notification opens the exact highlight, movie sheet or match
  player (the push carries `url` or `home`/`away`/`kickoffMs`). When several
  items are announced at once it opens the matching section.

## Not arriving when the app is closed?

Some phone makers stop apps in the background and swipe-closing the app
counts as "force stop", which blocks all push messages. In the phone's
settings for the app, allow **Auto-start / Autostart**, set battery to
**Unrestricted / No restrictions**, and lock the app in the recent-apps list.

## Testing the "5 minutes to kick-off" alert (no waiting for a real match)

Actions > **Kick-off reminders** > Run workflow > `test_in_minutes` = `6`.
A real notification "Kick-off in 5 minutes - Test FC vs Demo United" arrives
after about a minute, and "Kick-off! Match is live" after 6 minutes. If both
arrive, the whole chain works and a real match only needs a valid `kickoff`
(with time and zone) in `assets/data/fixtures.json`. If they do not, open the
run log: it states why.

## Order of highlights and movies

Newest first by `date` (and time). Items posted on the same day keep the order
of the file, so put the newest entry at the top. To control the order inside a
day add a time: `"date": "2026-10-06 14:30"` or `"date": "2026-10-06", "time": "14:30"`.
