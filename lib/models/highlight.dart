import '../utils/posted_at.dart';

class Highlight {
  final String name;
  final String url;
  final DateTime? date;
  final String home;
  final String away;
  final String? competition;

  const Highlight({
    required this.name,
    required this.url,
    required this.date,
    required this.home,
    required this.away,
    required this.competition,
  });

  String get title => away.isEmpty ? home : '$home vs $away';

  static Highlight? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    final url = (raw['url'] ?? '').toString().trim();
    if (name.isEmpty || url.isEmpty) return null;
    final date = parsePostedAt(
        (raw['date'] ?? '').toString(), (raw['time'] ?? '').toString());

    var t = name
        .replaceAll(RegExp(r'\s*highlights?\s*$', caseSensitive: false), '')
        .trim();
    String? comp;
    final m = RegExp(r'^(.+?\bvs\b.+?)\s*-\s*([^-]+)$', caseSensitive: false)
        .firstMatch(t);
    if (m != null) {
      t = m.group(1)!.trim();
      comp = _normalizeCompetition(m.group(2)!.trim());
    }
    final parts = t.split(RegExp(r'\s+vs\s+', caseSensitive: false));
    return Highlight(
      name: name,
      url: url,
      date: date,
      home: parts.first.trim(),
      away: parts.length > 1 ? parts.sublist(1).join(' vs ').trim() : '',
      competition: comp,
    );
  }

  static String _normalizeCompetition(String c) {
    final l = c.toLowerCase();
    if (l == 'epl' || l.contains('premier league')) return 'Premier League';
    if (l.contains('la liga') || l == 'laliga') return 'La Liga';
    if (l.contains('efl')) return 'EFL Cup';
    return c;
  }
}

/// "Manchester United" -> "MU", "Arsenal" -> "ARS".
String initialsOf(String name) {
  final letters = RegExp(r'[A-Za-z\u00C0-\u00FF]');
  final words =
      name.split(RegExp(r'\s+')).where((w) => letters.hasMatch(w)).toList();
  if (words.isEmpty) return '?';
  String clean(String w) =>
      w.replaceAll(RegExp(r'[^A-Za-z\u00C0-\u00FF]'), '');
  if (words.length == 1) {
    final w = clean(words.first);
    return w.substring(0, w.length < 3 ? w.length : 3).toUpperCase();
  }
  return (clean(words[0])[0] + clean(words[1])[0]).toUpperCase();
}
