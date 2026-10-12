/// Live (or final) score of one fixture.
class LiveScore {
  final int home;
  final int away;

  /// Match clock as reported, e.g. `72'`, `HT`, `FT`, `AET`.
  final String clock;
  final bool live;
  final bool finished;

  const LiveScore({
    required this.home,
    required this.away,
    required this.clock,
    required this.live,
    required this.finished,
  });

  bool get halfTime => live && clock.toUpperCase() == 'HT';

  /// Short text for the card's status line.
  String get statusLabel {
    if (live) return halfTime ? 'Half-time' : clock;
    final c = clock.toUpperCase();
    return c.isEmpty || c == 'FT' ? 'Full-time' : clock;
  }

  String get scoreText => '$home - $away';

  @override
  bool operator ==(Object other) =>
      other is LiveScore &&
      other.home == home &&
      other.away == away &&
      other.clock == clock &&
      other.live == live &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(home, away, clock, live, finished);
}
