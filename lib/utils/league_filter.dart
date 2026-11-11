import '../models/fixture.dart';

/// League / national-team filter used by the AI Predict match list.
///
/// The app's own fixtures and ESPN's list name the same competition in
/// different ways ("English Premier League", "Premier League",
/// "UEFA Nations League - League A"). [LeagueFilter.canonical] folds those
/// into one name so a single chip shows every match of that competition.
class LeagueFilter {
  LeagueFilter._();

  /// Special (non-league) filters.
  static const String all = '__all';
  static const String national = '__national';
  static const String women = '__women';

  /// Shown first, in this order, when they have upcoming matches.
  static const List<String> top = [
    'Premier League',
    'LaLiga',
    'Serie A',
    'Bundesliga',
    'Ligue 1',
    'UEFA Champions League',
    'UEFA Europa League',
    'UEFA Conference League',
    'Championship',
    'Eredivisie',
    'Primeira Liga',
    'Super Lig',
    'Scottish Premiership',
    'Belgian Pro League',
    'MLS',
    'Liga MX',
    'Brasileirao',
    'Argentine Primera',
    'Saudi Pro League',
    'Copa Libertadores',
    'FA Cup',
    'EFL Cup',
    'Copa del Rey',
    'Coppa Italia',
    'DFB-Pokal',
    'Coupe de France',
  ];

  // (pattern on the lower-cased, accent-free name, canonical name)
  static final List<(RegExp, String)> _aliases = [
    (RegExp(r'^(?:english )?premier league$'), 'Premier League'),
    (RegExp(r'^(?:spanish )?la ?liga(?: ea sports| santander| primera division)?$|^primera division$'), 'LaLiga'),
    (RegExp(r'^(?:italian )?serie a$'), 'Serie A'),
    (RegExp(r'^(?:german )?bundesliga$'), 'Bundesliga'),
    (RegExp(r'^(?:french )?ligue 1(?: uber eats| mcdonalds)?$'), 'Ligue 1'),
    (RegExp(r'^(?:english )?(?:efl )?championship$'), 'Championship'),
    (RegExp(r'^(?:dutch )?eredivisie$'), 'Eredivisie'),
    (RegExp(r'^(?:portuguese )?primeira liga$|^liga portugal'), 'Primeira Liga'),
    (RegExp(r'^(?:turkish )?(?:super lig|trendyol super lig)$'), 'Super Lig'),
    (RegExp(r'^(?:scottish )?(?:premiership|premier league)$|^scottish premiership$'), 'Scottish Premiership'),
    (RegExp(r'^(?:belgian )?(?:pro league|first division a)$|^belgian pro league$'), 'Belgian Pro League'),
    (RegExp(r'^(?:major league soccer|mls)$'), 'MLS'),
    (RegExp(r'^(?:mexican )?liga mx'), 'Liga MX'),
    (RegExp(r'^(?:brazilian )?(?:serie a|brasileirao|campeonato brasileiro)'), 'Brasileirao'),
    (RegExp(r'^(?:argentine )?(?:primera|liga profesional)'), 'Argentine Primera'),
    (RegExp(r'^(?:saudi )?(?:pro league|professional league|roshn)'), 'Saudi Pro League'),
    (RegExp(r'^(?:uefa )?champions league$'), 'UEFA Champions League'),
    (RegExp(r'^(?:uefa )?europa league$'), 'UEFA Europa League'),
    (RegExp(r'^(?:uefa )?(?:europa )?conference league$'), 'UEFA Conference League'),
    (RegExp(r'^(?:conmebol )?(?:copa )?libertadores'), 'Copa Libertadores'),
    (RegExp(r'^(?:english )?fa cup$'), 'FA Cup'),
    (RegExp(r'^(?:english )?(?:efl|carabao|league) cup$'), 'EFL Cup'),
    (RegExp(r'^(?:spanish )?copa del rey$'), 'Copa del Rey'),
    (RegExp(r'^(?:italian )?coppa italia$'), 'Coppa Italia'),
    (RegExp(r'^(?:german )?dfb[- ]pokal$'), 'DFB-Pokal'),
    (RegExp(r'^(?:french )?coupe de france$'), 'Coupe de France'),
  ];

  static String _plain(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãä]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ş', 's')
      .replaceAll('ı', 'i')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// One display name per competition.
  static String canonical(String league) {
    var name = league.trim();
    if (name.isEmpty) return 'Other leagues';
    final p = _plain(name);
    for (final (re, canon) in _aliases) {
      if (re.hasMatch(p)) return canon;
    }
    // "UEFA Nations League - League A" and "UEFA Nations League" are one chip.
    if (p.contains('nations league') && p.contains('uefa')) {
      return 'UEFA Nations League';
    }
    final dash = name.indexOf(RegExp(r'\s[-–—]\s'));
    if (dash > 3) name = name.substring(0, dash).trim();
    return name;
  }

  static final RegExp _nationalRe = RegExp(
    r'nations league|world cup|euro(?:pean)? champ|\beuro 20|qualif|friendl|international|africa cup|afcon|copa am[eé]rica|gold cup|asian cup|concacaf nations',
    caseSensitive: false,
  );
  static final RegExp _clubRe = RegExp(
    r'champions league|europa league|conference league|\bclub\b|libertadores|sudamericana|cup winners|\bu-?\d\d\b|youth|\bunder',
    caseSensitive: false,
  );

  static bool isSpecial(String f) => f == all || f == national || f == women;

  /// True when the competition is played between countries.
  static bool isNationalLeague(String league) =>
      _nationalRe.hasMatch(league) && !_clubRe.hasMatch(league);

  static bool isNational(Fixture f) => isNationalLeague(f.league);

  /// Does [f] belong under the [filter] chip?
  static bool matches(Fixture f, String filter) {
    switch (filter) {
      case all:
        return true;
      case national:
        return isNational(f);
      case women:
        return f.isWomen;
      default:
        return canonical(f.league) == filter;
    }
  }

  /// League names present in [fixtures] with their match counts, ordered for
  /// the chip row: the big leagues first, then national-team competitions,
  /// then everything else A to Z.
  static List<MapEntry<String, int>> leaguesOf(Iterable<Fixture> fixtures) {
    final counts = <String, int>{};
    for (final f in fixtures) {
      final c = canonical(f.league);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    int rank(String name) {
      final i = top.indexOf(name);
      if (i >= 0) return i;
      if (isNationalLeague(name)) return 1000;
      return 2000;
    }

    final list = counts.entries.toList()
      ..sort((a, b) {
        final ra = rank(a.key), rb = rank(b.key);
        if (ra != rb) return ra.compareTo(rb);
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    return list;
  }
}
