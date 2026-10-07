/// What a notification points at. Built from the FCM `data` payload.
///
///   type: kickoff | highlights | movies   (what kind of content)
///   url:  the highlight / movie link       (highlights, movies)
///   home, away, kickoffMs                  (a single match)
///
/// With no item details (several new items at once) the app only opens the
/// matching section.
class PushTarget {
  /// `kickoff` (matches), `highlights` or `movies`.
  final String kind;
  final String url;
  final String home;
  final String away;
  final int? kickoffMs;

  const PushTarget({
    required this.kind,
    this.url = '',
    this.home = '',
    this.away = '',
    this.kickoffMs,
  });

  /// Bottom-tab index: 0 Live, 1 Highlights, 3 Movies.
  int get tab => kind == 'highlights' ? 1 : (kind == 'movies' ? 3 : 0);

  /// True when the notification names one specific item to open.
  bool get hasItem => kind == 'kickoff'
      ? home.isNotEmpty && away.isNotEmpty
      : url.isNotEmpty;

  bool matchesFixture(String h, String a, int kickoffEpochMs) {
    if (h.trim().toLowerCase() != home.toLowerCase() ||
        a.trim().toLowerCase() != away.toLowerCase()) {
      return false;
    }
    final k = kickoffMs;
    return k == null || (kickoffEpochMs - k).abs() < 120000;
  }

  static PushTarget? fromData(Map<String, dynamic> data) {
    String s(String k) => (data[k] ?? '').toString().trim();
    var kind = (s('type').isNotEmpty ? s('type') : s('tab')).toLowerCase();
    if (kind == 'live') kind = 'kickoff';
    if (kind != 'kickoff' && kind != 'highlights' && kind != 'movies') {
      return null;
    }
    return PushTarget(
      kind: kind,
      url: s('url'),
      home: s('home'),
      away: s('away'),
      kickoffMs: int.tryParse(s('kickoffMs')),
    );
  }
}
