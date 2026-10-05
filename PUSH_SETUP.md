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
* Or open drawer > Notifications > *Copy device token* and send to that token.
* Fixtures that start in the next 5 minutes trigger a real reminder within a
  minute of deploying the function.

## Files added / changed

* `lib/services/push_service.dart`, `lib/widgets/notification_settings.dart`
* `lib/main.dart`, `lib/app.dart`, `lib/screens/shell_screen.dart`, `lib/widgets/app_drawer.dart`
* `tool/patch_android_push.py`, `tool/patch_main_activity.py`, `.github/workflows/build.yml`
* `scripts/notify_content.mjs`, `.github/workflows/notify-content.yml`
