/// Central place for the things you are most likely to edit.
class AppConfig {
  static const appName = 'Footbolive';
  static const appVersion = '1.0';

  /// Drawer menu links. Leave a value empty to make its menu item show a
  /// "not set up yet" message instead of opening anything.
  static const websiteUrl = '';
  static const joinUrl = ''; // Telegram / WhatsApp / Discord invite link
  static const updateUrl = ''; // release page or direct apk link

  /// Optional remote notice (plain text, or JSON {"title":"","message":""}).
  static const noticeUrl = '';

  /// Score pages opened in the in-app browser.
  static const footballScoreUrl = 'https://www.livescore.com/en/football/';
  static const cricketScoreUrl =
      'https://www.cricbuzz.com/cricket-match/live-scores';

  /// Origin used as the base URL of the built-in HLS / MP4 / DASH player page.
  /// Some stream hosts only allow requests coming from your own site, so this
  /// mirrors the site the streams were originally played on.
  static const playerOrigin = 'https://deeprowss.com/';

  /// Optional remote JSON feed for the fixtures list (same shape as
  /// assets/data/fixtures.json). Leave empty to use only the bundled file.
  static const fixturesUrl = 'https://github.com/Deeprows/myflutter-app/blob/main/assets/data/fixtures.json';

  /// Remote JSON feed for highlights (same shape as assets/data/highlights.json).
  /// The bundled copy is used as an offline fallback.
  static const highlightsUrl =
      'https://deeprowss.com/content/highlights/highlights.json';

  /// Remote JSON feed for movies / series (same shape as
  /// assets/data/movies.json). The bundled copy is the offline fallback.
  static const moviesUrl =
      'https://deeprowss.com/content/movies/movies.json';

  /// Optional remote JSON feed for TV channels (same shape as
  /// assets/data/tv.json). Leave empty to use only the bundled file.
  static const tvUrl = '';

  /// Used when a fixture has no explicit duration (minutes).
  static const defaultMatchMinutes = 96;

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
}
