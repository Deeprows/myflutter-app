import '../config.dart';

enum MatchPhase { live, upcoming, ended }

class Fixture {
  final String id;
  final String home;
  final String away;
  final String homeLogo;
  final String awayLogo;
  final String league;
  final DateTime kickoff;
  final int durationMin;
  final String url;
  final String altUrl;

  /// Extra backup streams (3rd, 4th). With [url] and [altUrl] a match can
  /// have up to 4 sources the player switches between (1/4 ... 4/4).
  final List<String> moreUrls;

  /// Optional ESPN league code (e.g. `eng.1`) used to find the live score if
  /// the general feed does not list this match.
  final String scoreLeague;

  /// `women` for a women's match, `men` for a men's match, empty when unknown
  /// (treated as men's unless the names/league say otherwise).
  final String gender;

  const Fixture({
    required this.id,
    required this.home,
    required this.away,
    required this.kickoff,
    this.homeLogo = '',
    this.awayLogo = '',
    this.league = '',
    this.durationMin = AppConfig.defaultMatchMinutes,
    this.url = '',
    this.altUrl = '',
    this.moreUrls = const [],
    this.scoreLeague = '',
    this.gender = '',
  });

  String get title => '$home vs $away';

  static final RegExp _womenRe = RegExp(
    r"\b(?:women|womens|woman|ladies|feminin\w*|femenin\w*|femminile|frauen|dames|nwsl|wsl)\b|\(\s*w\s*\)|\sW$",
    caseSensitive: false,
  );

  /// True for women's matches: the server's tag first, then the names/league.
  bool get isWomen {
    if (gender == 'women') return true;
    if (gender == 'men') return false;
    return _womenRe.hasMatch(home) ||
        _womenRe.hasMatch(away) ||
        _womenRe.hasMatch(league);
  }

  /// Men's matches (the default) show the plain title; only women's matches get
  /// a "(women)" tag, so a men's and a women's match between clubs with the same
  /// name can never be confused. `isWomen` still tells the AI which side it is.
  String get genderTitle => isWomen ? '$title (women)' : title;
  DateTime get endTime => kickoff.add(Duration(minutes: durationMin));
  bool get hasStream => url.trim().isNotEmpty;
  bool get hasAlt =>
      altUrl.trim().isNotEmpty && altUrl.trim() != url.trim();

  MatchPhase phaseAt(DateTime now) {
    if (now.isBefore(kickoff)) return MatchPhase.upcoming;
    if (now.isBefore(endTime)) return MatchPhase.live;
    return MatchPhase.ended;
  }

  static Fixture? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    String s(String k) => (raw[k] ?? '').toString().trim();
    // Kick-off times in the data carry their own offset (e.g. +01:00 for
    // Nigeria) so every phone converts them to its own timezone. A time with
    // no offset is read as Nigeria time (WAT, +01:00) rather than as the
    // phone's local time, so it can't shift between users.
    var k = s('kickoff');
    final hasZone =
        RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(k);
    if (!hasZone && (k.contains('T') || k.contains(' '))) k = '$k+01:00';
    final kickoff = DateTime.tryParse(k);
    if (kickoff == null || s('home').isEmpty || s('away').isEmpty) return null;
    return Fixture(
      id: s('id').isNotEmpty
          ? s('id')
          : '${s('home')}-${s('away')}-${s('kickoff')}',
      home: s('home'),
      away: s('away'),
      homeLogo: s('homeLogo'),
      awayLogo: s('awayLogo'),
      league: s('league'),
      kickoff: kickoff,
      durationMin:
          int.tryParse(s('duration')) ?? AppConfig.defaultMatchMinutes,
      url: s('url').isNotEmpty
          ? s('url')
          : (raw['urls'] is List && (raw['urls'] as List).isNotEmpty
                ? '${(raw['urls'] as List)[0]}'.trim()
                : ''),
      altUrl: s('altUrl').isNotEmpty
          ? s('altUrl')
          : (raw['urls'] is List && (raw['urls'] as List).length > 1
                ? '${(raw['urls'] as List)[1]}'.trim()
                : ''),
      moreUrls: [
        if (raw['urls'] is List)
          for (final u in (raw['urls'] as List).skip(2)) '$u'.trim(),
        s('altUrl2'),
        s('altUrl3'),
      ].where((u) => u.isNotEmpty).toList(),
      scoreLeague: s('scoreLeague'),
    );
  }
}

/// Live first, then upcoming (soonest first), then ended (most recent first).
List<Fixture> sortFixtures(List<Fixture> input, DateTime now) {
  final list = [...input];
  list.sort((a, b) {
    final pa = a.phaseAt(now), pb = b.phaseAt(now);
    if (pa != pb) return pa.index.compareTo(pb.index);
    return pa == MatchPhase.ended
        ? b.kickoff.compareTo(a.kickoff)
        : a.kickoff.compareTo(b.kickoff);
  });
  return list;
}
