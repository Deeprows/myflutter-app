import '../config.dart';

enum MatchPhase { live, upcoming, ended }

class Fixture {
  final String id;
  final String home;
  final String away;
  final String homeFlag;
  final String awayFlag;
  final String league;
  final DateTime kickoff;
  final int durationMin;
  final String url;
  final String altUrl;

  const Fixture({
    required this.id,
    required this.home,
    required this.away,
    required this.kickoff,
    this.homeFlag = '',
    this.awayFlag = '',
    this.league = '',
    this.durationMin = AppConfig.defaultMatchMinutes,
    this.url = '',
    this.altUrl = '',
  });

  String get title => '$home vs $away';
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
      homeFlag: s('homeFlag'),
      awayFlag: s('awayFlag'),
      league: s('league'),
      kickoff: kickoff,
      durationMin:
          int.tryParse(s('duration')) ?? AppConfig.defaultMatchMinutes,
      url: s('url'),
      altUrl: s('altUrl'),
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
