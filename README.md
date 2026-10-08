# Deeprowss (Flutter)

Football and TV Android app with four sections:

* **Live** – fixture cards (UPCOMING / LIVE / ENDED, flags, kick-off time, live countdown) in the same style as the Deeprowss website. Filter by status, pull to refresh, tap a card to watch.
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
* `assets/data/*.json` – fixtures, highlights, movies and TV channels all live in the repo and ship inside the app. Edit them and build a new APK to update. `lib/config.dart` has optional `fixturesUrl` / `highlightsUrl` / `moviesUrl` / `tvUrl` remote feeds, all empty by default; when empty, any cache from an old remote feed is cleared so the bundled data always shows.

## Build

```
flutter create . --platforms=android
flutter pub get
flutter run
```

After `flutter create`, run `python3 tool/patch_android_manifest.py` once. It adds INTERNET, notification and foreground-service permissions (needed for background downloads), cleartext `http://` support, the app label, and disables WorkManager's default initializer so `flutter_downloader` can start its own. The included GitHub workflow does this automatically and uploads the APK.

Background downloads use [`flutter_downloader`](https://pub.dev/packages/flutter_downloader) (Android WorkManager). On Android 13+ the app asks for notification permission the first time you download.


## TMDB movies and series

Every title is keyed by its TMDB id (settings are in `lib/config.dart`):

| What | Link |
| --- | --- |
| Movie player | `https://vsembed.su/embed/movie/<tmdb id>` |
| Series player | `https://vsembed.su/embed/tv/<tmdb id>` |
| Backup player (Switch button) | `https://web.nxsha.app/embed/movie/<id>` / `https://web.nxsha.app/embed/tv/<id>/1/1` |
| Movie download | `https://web.nxsha.app/dl/movie/<tmdb id>` |
| Series download | `https://web.nxsha.app/dl/tv/<tmdb id>` |

* **Add a title by id only** in `assets/data/movies.json`; the app fetches the
  name, poster, rating and genres from TMDB and builds the links:
  `{ "tmdbId": 9319989, "type": "movie" }` or `{ "tmdbId": 1396, "type": "tv" }`.
  Add `"date": "2026-10-08"` to place it in the newest-first order.
* **Trending** TMDB movies and series are listed after your own titles
  (`AppConfig.tmdbTrending`).
* **Movie page**: slim Reload / Switch / Rotate buttons, then TMDB details
  (overview, runtime, release date, director, cast). Titles without a TMDB id are
  matched through the id in their link or by exact title and year.
* **Categories**: picking Drama, Action, etc. also lists that category's popular
  TMDB titles (`AppConfig.tmdbCategories`); pull down to refresh them.
* **Search** in the Movies tab also searches all of TMDB (`AppConfig.tmdbSearch`).
* The v3 API key is `AppConfig.tmdbApiKey`; override it at build time with
  `--dart-define=TMDB_API_KEY=...`.
