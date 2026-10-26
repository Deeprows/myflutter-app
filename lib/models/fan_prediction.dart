/// Shared display/scoring rules for the supported 90-minute markets.
String fanPredictionLabel(Map<String, dynamic> p) {
  final s = '${p['selection'] ?? ''}';
  return switch (p['market'] ?? 'score') {
    'result' => {'1': 'Home win', 'X': 'Draw', '2': 'Away win'}[s] ?? s,
    'double_chance' =>
      {
            '1X': 'Home or draw',
            'X2': 'Away or draw',
            '12': 'Either team wins',
          }[s] ??
          s,
    'btts' => s == 'yes' ? 'Both teams score: Yes' : 'Both teams score: No',
    'totals' =>
      s.replaceFirst('over_', 'Over ').replaceFirst('under_', 'Under ') +
          ' goals',
    _ => '${p['home']} – ${p['away']}',
  };
}

bool fanPredictionPush(Map<String, dynamic> p) {
  if (p['market'] != 'totals' ||
      p['result_home'] is! num ||
      p['result_away'] is! num)
    return false;
  final line = double.tryParse('${p['selection']}'.split('_').last);
  return line != null &&
      (p['result_home'] as num) + (p['result_away'] as num) == line;
}

int? fanPredictionScore(Map<String, dynamic> p) {
  final rh = p['result_home'], ra = p['result_away'];
  if (rh is! num || ra is! num || fanPredictionPush(p)) return null;
  final outcome = rh > ra
      ? '1'
      : rh < ra
      ? '2'
      : 'X';
  final s = '${p['selection'] ?? ''}';
  switch (p['market'] ?? 'score') {
    case 'result':
      return s == outcome ? 1 : 0;
    case 'double_chance':
      return s.contains(outcome) ? 1 : 0;
    case 'btts':
      return ((rh > 0 && ra > 0) == (s == 'yes')) ? 1 : 0;
    case 'totals':
      final line = double.tryParse(s.split('_').last);
      if (line == null) return 0;
      return (s.startsWith('over_') ? rh + ra > line : rh + ra < line) ? 1 : 0;
    default:
      final h = (p['home'] as num).toInt(), a = (p['away'] as num).toInt();
      if (h == rh && a == ra) return 3;
      return (h - a).sign == (rh - ra).sign ? 1 : 0;
  }
}
