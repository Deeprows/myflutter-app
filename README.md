# Footbolive (Flutter)

Football and TV Android app with four sections:

* **Live** – fixture cards (UPCOMING / LIVE / ENDED, flags, kick-off time, live countdown) in the same style as the Footbolive website. Filter by status, pull to refresh, tap a card to watch.
* **Highlights** – searchable grid of match replays, grouped by day, with competition filters.

* **TV** – 155 live channels (Sports, Movies, Music, News) with search and category filters.
* **Downloads** – button in the Movies header (with a badge for running downloads). Files that a download page redirects to, or any page via the browser menu **Download this link**, are handed to the Android background downloader: they keep going when the app is minimised or closed, show a progress notification, and are saved to the phone's Downloads folder. The list supports pause / resume / retry, open and delete.
* **Movies** – poster grid with search and genre filters; tap a title for details, **Play** or **Download** (opens the download page in a clean in-app browser window; if the page redirects to a file such as .mkv or .apk, it is downloaded in-app).

## Player

Every stream opens in a WebView-based player (`webview_flutter`):

| Link type | How it plays |
| --- | --- |
| `.m3u8` (HLS) | built-in HTML5 page with hls.js, native fallback |
| `.mp4`, `.webm`, `.mov`, `.mkv`… | built-in HTML5 `<video>` |
| `.mpd` (DASH) | built-in page with dash.js |
| wrapper links such as `player.html#https://…/x.m3u8` or `?url=…` | inner stream is extracted and played directly |
| any embed / iframe page (filemoon, YouTube, Dailymotion, …) | loaded as a normal page |

Extras: fullscreen from inside the page, rotate button, backup-stream switch, copy link, screen stays awake, ad redirects/pop-ups are blocked, and an **Add link** button on the Live header lets you paste any URL to play.

## Editing content

* `assets/data/fixtures.json` – fixtures (`home`, `away`, flags, `kickoff` with offset, `duration` in minutes, `url`, optional `altUrl`, optional `league`).
* `assets/data/highlights.json` – highlights (`name`, `url`, `date`).
* `assets/data/tv.json` – channels (`name`, `url`, `category`: sports / movies / music / news).
* `assets/data/movies.json` – movies and series (`name`, `url`, optional `downloadUrl`, `date`, `rating`, `genre`, `image`).
* `lib/config.dart` – set `fixturesUrl` to a hosted JSON with the same shape to update fixtures without a new APK. `highlightsUrl` and `moviesUrl` already point to the website feeds (`tvUrl` can be set the same way); the bundled file is the offline fallback.

## Build

```
flutter create . --platforms=android
flutter pub get
flutter run
```

After `flutter create`, run `python3 tool/patch_android_manifest.py` once. It adds INTERNET, notification and foreground-service permissions (needed for background downloads), cleartext `http://` support, the app label, and disables WorkManager's default initializer so `flutter_downloader` can start its own. The included GitHub workflow does this automatically and uploads the APK.

Background downloads use [`flutter_downloader`](https://pub.dev/packages/flutter_downloader) (Android WorkManager). On Android 13+ the app asks for notification permission the first time you download.
