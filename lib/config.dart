/// Central place for the things you are most likely to edit.
class AppConfig {
  static const appName = 'Deeprowss';
  static const appVersion = '1.0';

  /// Drawer menu links. Leave a value empty to make its menu item show a
  /// "not set up yet" message instead of opening anything.
  static const websiteUrl = '';
  static const joinUrl = 'https://t.me/deeprows'; // Telegram / WhatsApp / Discord invite link
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

  /// All content lives inside this repo (assets/data/*.json) and ships with
  /// the app: fixtures.json, highlights.json, movies.json and tv.json. Edit
  /// those files and build a new APK to update the content.
  ///
  /// Optional remote feeds (same shape as the matching asset file). Leave a
  /// value empty to use only the bundled file. If you set one, the app fetches
  /// it on launch / pull-to-refresh and falls back to the bundled copy offline.
  static const fixturesUrl = '';
  static const highlightsUrl = '';
  static const moviesUrl = '';
  static const tvUrl = '';

  /// Scrolling ticker on the home screen (same shape as assets/data/ticker.json).
  /// Set this to a raw URL to change the ticker text without a new APK.
  static const tickerUrl = '';

  /// Used when a fixture has no explicit duration (minutes).
  static const defaultMatchMinutes = 96;

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
}
