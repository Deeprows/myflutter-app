/// Central place for the things you are most likely to edit.
class AppConfig {
  static const appName = 'Deeprowss';

  /// Set by the build using `--dart-define=APP_VERSION=...`.
  /// Falls back to `dev` when no build-time version is provided.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  // -------------------------------------------------------------------------
  // TMDB
  // -------------------------------------------------------------------------

  /// TMDB API base URL.
  static const tmdbBaseUrl = 'https://api.themoviedb.org/3';

  /// TMDB image base URL.
  ///
  /// Poster images will normally use this base URL with a size such as
  /// `w500` followed by the poster path returned by TMDB.
  static const tmdbImageBaseUrl = 'https://image.tmdb.org/t/p/w500';

  /// TMDB Bearer access token.
  ///
  /// IMPORTANT:
  /// Do not put the token directly in this file or commit it to GitHub.
  /// Supply it at build/run time with:
  ///
  /// `--dart-define=TMDB_ACCESS_TOKEN=YOUR_TOKEN`
  static const tmdbAccessToken =
      String.fromEnvironment('TMDB_ACCESS_TOKEN');

  /// Drawer menu links. Leave a value empty to make its menu item show a
  /// "not set up yet" message instead of opening anything.
  static const websiteUrl = '';
  static const joinUrl =
      'https://t.me/deeprows'; // Telegram / WhatsApp / Discord invite link
  static const updateUrl = ''; // release page or direct APK link

  /// Optional remote notice (plain text, or JSON `{"title":"","message":""}`).
  static const noticeUrl = '';

  /// Score pages opened in the in-app browser.
  static const footballScoreUrl =
      'https://www.livescore.com/en/football/';
  static const cricketScoreUrl =
      'https://www.cricbuzz.com/cricket-match/live-scores';

  /// Origin used as the base URL of the built-in HLS / MP4 / DASH player page.
  /// Some stream hosts only allow requests coming from your own site, so this
  /// mirrors the site the streams were originally played on.
  static const playerOrigin = 'https://deeprowss.com/';

  /// All content lives inside this repo (`assets/data/*.json`) and ships with
  /// the app: `fixtures.json`, `highlights.json`, `movies.json` and `tv.json`.
  /// Edit those files and build a new APK to update the content.
  ///
  /// Optional remote feeds (same shape as the matching asset file). Leave a
  /// value empty to use only the bundled file. If you set one, the app fetches
  /// it on launch / pull-to-refresh and falls back to the bundled copy offline.
  static const fixturesUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/fixtures.json';
  static const highlightsUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/highlights.json';
  static const moviesUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/movies.json';
  static const tvUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/tv.json';

  /// Cloudflare feed (traffic monitoring). When set, fixtures, highlights,
  /// movies, TV and the ticker are downloaded from
  /// `<feedBase>/feed/<fixtures|highlights|movies|tv|ticker>.json`
  /// through your Cloudflare Worker (see `cloudflare/README.md`), which fetches
  /// them from GitHub and records anonymous usage. If the Worker is down the
  /// app falls back to the GitHub links above, so keep those set.
  ///
  /// Example: `https://feed.deeprows.com`.
  /// Empty = download from GitHub only.
  static const feedBase = '';

  /// Scrolling ticker on the home screen (same shape as
  /// `assets/data/ticker.json`).
  /// Set this to a raw URL to change the ticker text without a new APK.
  static const tickerUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/ticker.json';

  /// "We Need Your Support" overlay. It appears when a fixture, highlight or
  /// movie card is tapped, at most once every [supportIntervalHours].
  ///
  /// [supportUrl]: the page opened by the CLICK HERE button (your ad / smart
  /// link). LEAVE EMPTY TO TURN THE OVERLAY OFF.
  static const supportUrl =
      'https://www.profitableratecpmnetwork.com/iqv44jk21?key=c2752cc0c9c553ac66e4fb16cdb95f60';
  static const supportIntervalHours = 12;
  static const supportViewSeconds = 13; // page auto-closes after this long
  static const supportRetryHours =
      1; // if the support page can't load, ask again after

  /// Used when a fixture has no explicit duration (minutes).
  static const defaultMatchMinutes = 96;

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
}
