/// Central place for the things you are most likely to edit.
class AppConfig {
  static const appName = 'Deeprowss';

  /// Set by the build using `--dart-define=APP_VERSION=...`.
  /// Falls back to `dev` when no build-time version is provided.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

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

  /// ---- IPTV Nexus (static JSON API, no key / auth) ----------------------
  ///
  /// Live channels with health data. The app downloads
  /// `<nexusBase>/api/v1/channels.online.json` (working channels only),
  /// keeps the best working stream per channel and merges the result into
  /// the TV tab after your own `tv.json` channels. Empty = Nexus off.
  static const nexusBase = 'https://dearbulut.github.io/iptv';
  static const nexusOnlinePath = '/api/v1/channels.online.json';

  /// Minimum time between Nexus downloads. Pull-to-refresh ignores it.
  static const nexusRefreshMinutes = 180;

  /// TV tab: play HLS / DASH / direct video links with the native player
  /// (ExoPlayer, real Referer + User-Agent headers, no CORS limits). Embed
  /// pages still use the web player. Set false to use the web player only.
  static const nativeTvPlayer = true;

  /// Hide channels flagged `is_nsfw` by the API.
  static const nexusHideNsfw = true;

  /// Cloudflare feed (traffic monitoring). When set, fixtures, highlights,
  /// movies, TV and the ticker are downloaded from
  /// `<feedBase>/feed/<fixtures|highlights|movies|tv|ticker>.json`
  /// through your Cloudflare Worker (see `cloudflare/README.md`), which fetches
  /// them from GitHub and records anonymous usage. If the Worker is down the
  /// app falls back to the GitHub links above, so keep those set.
  ///
  /// Example: `https://feed.deeprowss.com`.
  /// Empty = download from GitHub only.
  static const feedBase = 'https://deeprowss-feed.deeprows.workers.dev';

  /// Scrolling ticker on the home screen (same shape as
  /// `assets/data/ticker.json`).
  /// Set this to a raw URL to change the ticker text without a new APK.
  static const tickerUrl =
      'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/ticker.json';

  /// ---- Free vs Premium ---------------------------------------------------
  ///
  /// On start the app shows a plans page: FREE (everything, with the
  /// "We Need Your Support" page every [adIntervalMinutes] minutes of use) or
  /// PREMIUM (no ads, paid through Paystack). Needs [feedBase] (the Worker
  /// does the payment work, see SUBSCRIPTIONS.md). false = no plans page and
  /// no ads for anyone.
  static const plansEnabled = true;

  /// true: the plans page shows on every launch for people who are not
  /// premium. false: only on the first launch and after a premium ends.
  static const showPlansEveryStart = true;

  /// Shown only until the Worker answers; the real price lives in the
  /// Worker (`PRICE_NGN`, default 2000) so one change updates every phone.
  static const premiumPriceFallbackNgn = 2000;

  /// WhatsApp chat for people who cannot pay online (manual activation).
  /// Example: `https://wa.me/2348012345678`. Empty = the button tells the
  /// person it is coming soon. The app adds the person's ID to the message.
  static const whatsappUrl = '';
  static const whatsappMessage =
      'Hello, I want to pay for Deeprowss Premium manually.';

  /// ---- "We Need Your Support" ad page (free plan) --------------------------
  ///
  /// Appears after [adIntervalMinutes] minutes of real use (the clock only
  /// runs while the app is open on screen and keeps counting across
  /// launches). Premium people never see it. The person opens
  /// [supportUrl] (your ad / smart link) and the page closes by itself after
  /// [supportViewSeconds].
  /// [supportUrl] empty = no ads at all.
  static const supportUrl =
      'https://www.profitableratecpmnetwork.com/iqv44jk21?key=c2752cc0c9c553ac66e4fb16cdb95f60';
  static const adIntervalMinutes = 15;
  static const supportViewSeconds = 13; // page auto-closes after this long

  /// If the support page cannot load (offline / dead link) nobody is locked
  /// out; the overlay comes back after this many minutes of use.
  static const adRetryMinutes = 3;

  /// The OLD trigger (tap a fixture / highlight / movie card, once every
  /// [supportIntervalHours]) is switched off. Set true to bring it back.
  static const supportOnCardTap = false;
  static const supportIntervalHours = 12;
  static const supportRetryHours =
      1; // if the support page can't load, ask again after

  /// ---- TMDB (themoviedb.org) -------------------------------------------
  ///
  /// The TMDB id is the single key for a title: it is turned into the player
  /// link and the download link below, and TMDB supplies the name, poster,
  /// rating, genres and release date.
  ///
  /// v3 API key. Override at build time with
  /// `--dart-define=TMDB_API_KEY=...` (the GitHub workflow can pass a repo
  /// secret). Leave empty to switch every TMDB feature off.
  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'b83de997ce0ca0406c12cab7f256e43a',
  );

  /// Player (embed) links:  <embedBase>/movie/<tmdb id>  and
  ///                        <embedBase>/tv/<tmdb id>
  static const embedBase = 'https://vsembed.su/embed';

  /// Backup player used by the Switch button on every movie / series page:
  ///   <altEmbedBase>/movie/<tmdb id>
  ///   <altEmbedBase>/tv/<tmdb id>/1/1
  static const altEmbedBase = 'https://web.nxsha.app/embed';

  /// Download links:  <downloadBase>/movie/<tmdb id>  and
  ///                  <downloadBase>/tv/<tmdb id>
  static const downloadBase = 'https://web.nxsha.app/dl';

  /// Adds TMDB's trending movies + series (about 40 titles) after the titles
  /// listed in `movies.json`. Set to false to show only your own list.
  static const tmdbTrending = true;

  /// Picking a category pill (Drama, Action, ...) also lists that category's
  /// popular TMDB movies and series after your own titles.
  static const tmdbCategories = true;

  /// Search box in Movies also searches the whole TMDB catalogue.
  static const tmdbSearch = true;

  /// Used when a fixture has no explicit duration (minutes).
  static const defaultMatchMinutes = 96;

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
}
