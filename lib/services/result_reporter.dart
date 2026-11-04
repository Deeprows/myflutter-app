import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/fixture.dart';
import '../models/live_score.dart';
import 'auth_service.dart';
import 'fan_zone_service.dart';

/// Connects predictions to the Live screen: when a match shows a plain
/// full-time score there, the app tells the Fan Zone server. Once enough
/// different people's apps report the same score, the server settles every
/// prediction for that match and the points reach the Ranks table.
class ResultReporter {
  ResultReporter._();
  static final ResultReporter instance = ResultReporter._();

  static const _key = 'reported_results';
  bool _busy = false;

  /// [scores] is the Live screen's score map (fixture id -> score).
  Future<void> submit(
    Iterable<Fixture> fixtures,
    Map<String, LiveScore> scores,
  ) async {
    if (_busy || !AuthService.instance.signedIn) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = (prefs.getStringList(_key) ?? <String>[]).toSet();
      var changed = false;
      for (final f in fixtures) {
        final s = scores[f.id];
        if (s == null || !s.finished) continue;
        // Extra time and penalties are not the 90-minute score: leave those
        // to the server's own check.
        final clock = s.clock.toUpperCase();
        if (clock.isNotEmpty && clock != 'FT' && clock != 'FULL-TIME') continue;
        if (DateTime.now().isBefore(f.kickoff.add(const Duration(minutes: 100)))) {
          continue;
        }
        final key = FanZoneService.matchKey(f);
        final mark = '$key|${s.home}-${s.away}';
        if (done.contains(mark)) continue;
        try {
          final r = await FanZoneService.call(
            'result-report',
            body: {'key': key, 'home': s.home, 'away': s.away},
          );
          // "too_early" is retried later; everything else is final.
          if ('${r['status']}' != 'too_early') {
            done.add(mark);
            changed = true;
          }
        } catch (_) {
          // Try again on the next refresh.
        }
      }
      if (changed) {
        final list = done.toList();
        await prefs.setStringList(
          _key,
          list.length > 300 ? list.sublist(list.length - 300) : list,
        );
      }
    } finally {
      _busy = false;
    }
  }
}
