import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/fixture.dart';
import '../models/live_score.dart';
import 'remote_config.dart';

/// One match as reported by the score feed.
class ScoreEvent {
  final List<String> homeNames;
  final List<String> awayNames;
  final int home;
  final int away;
  final String state; // pre | in | post
  final String clock;
  final DateTime? date;
  const ScoreEvent({
    required this.homeNames,
    required this.awayNames,
    required this.home,
    required this.away,
    required this.state,
    required this.clock,
    required this.date,
  });
}

/// Real live scores for the fixture cards.
///
/// Every match you post in fixtures.json is looked up (by team names and
/// kick-off time) in a free public football scoreboard feed, ESPN's
/// `soccer/all/scoreboard`. No key, no account. The feed address, polling
/// speed and an on/off switch are in app_config.json ("scores").
class ScoreService {
  ScoreService._();
  static final ScoreService instance = ScoreService._();

  /// Fixture id -> latest score. Only matches that were found appear here.
  final ValueNotifier<Map<String, LiveScore>> scores =
      ValueNotifier<Map<String, LiveScore>>(const {});

  bool _busy = false;

  LiveScore? scoreFor(String fixtureId) => scores.value[fixtureId];

  // ------------------------------------------------------------- polling

  /// Matches worth asking about: started in the last 12 hours or starting in
  /// the next 30 minutes (live, just finished, or about to kick off).
  static bool isTarget(Fixture f, DateTime now) {
    final d = f.kickoff.difference(now);
    return d <= const Duration(minutes: 30) && d >= const Duration(hours: -12);
  }

  /// Looks the given fixtures up once. Safe to call often: it never runs two
  /// lookups at the same time and keeps the old scores if the feed fails.
  Future<void> refresh(List<Fixture> fixtures, {DateTime? now}) async {
    final cfg = RemoteConfig.instance;
    if (!cfg.scoresEnabled || _busy) return;
    final n = now ?? DateTime.now();
    final targets = fixtures.where((f) => isTarget(f, n)).toList();
    if (targets.isEmpty) return;
    _busy = true;
    try {
      final base = cfg.scoresUrl;
      final events = <ScoreEvent>[];
      for (final d in _dates(targets)) {
        events.addAll(await _fetch(base, d) ?? const []);
      }
      final found = match(targets, events);

      // Matches the "all" feed did not list: try the league named in the
      // fixture's optional "scoreLeague" (e.g. "eng.1").
      if (base.contains('/all/')) {
        for (final f in targets) {
          final lg = f.scoreLeague.trim();
          if (found.containsKey(f.id) || lg.isEmpty) continue;
          final url = base.replaceFirst('/all/', '/$lg/');
          final more = <ScoreEvent>[];
          for (final d in _dates([f])) {
            more.addAll(await _fetch(url, d) ?? const []);
          }
          found.addAll(match([f], more));
        }
      }

      if (found.isEmpty) return;
      final next = {...scores.value, ...found};
      if (!mapEquals(next, scores.value)) scores.value = next;
    } catch (_) {
      // Keep whatever we already show.
    } finally {
      _busy = false;
    }
  }

  static Set<String> _dates(List<Fixture> targets) {
    String ymd(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final out = <String>{};
    for (final f in targets) {
      final k = f.kickoff.toUtc();
      out.add(ymd(k));
      out.add(ymd(k.subtract(const Duration(days: 1))));
    }
    return out;
  }

  static Future<List<ScoreEvent>?> _fetch(String url, String date) async {
    try {
      final u = Uri.parse(url);
      final r = await http
          .get(u.replace(queryParameters: {...u.queryParameters, 'dates': date}))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return parseEvents(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- parsing

  /// Reads the scoreboard JSON (`{"events": [...]}`) into [ScoreEvent]s.
  /// Matches that have not started, were postponed or cancelled are skipped.
  static List<ScoreEvent> parseEvents(dynamic json) {
    final out = <ScoreEvent>[];
    final events = json is Map ? json['events'] : null;
    if (events is! List) return out;
    for (final e in events) {
      try {
        if (e is! Map) continue;
        final comps = e['competitions'];
        if (comps is! List || comps.isEmpty || comps.first is! Map) continue;
        final comp = comps.first as Map;
        final list = comp['competitors'];
        if (list is! List) continue;
        Map? home, away;
        for (final c in list) {
          if (c is! Map) continue;
          if (c['homeAway'] == 'home') home = c;
          if (c['homeAway'] == 'away') away = c;
        }
        if (home == null || away == null) continue;

        final status = (comp['status'] ?? e['status']) as Map?;
        final type = status?['type'] as Map?;
        final state = (type?['state'] ?? '').toString();
        final name = (type?['name'] ?? '').toString().toUpperCase();
        if (state != 'in' && state != 'post') continue;
        if (RegExp(r'POSTPON|CANCEL|ABANDON|FORFEIT|SUSPEND|DELAY')
            .hasMatch(name)) {
          continue;
        }

        String clock;
        if (state == 'in') {
          final dc = (status?['displayClock'] ?? '').toString().trim();
          final sd = (type?['shortDetail'] ?? '').toString().trim();
          clock = name.contains('HALF') && !name.contains('FIRST') &&
                  !name.contains('SECOND')
              ? 'HT'
              : (dc.isNotEmpty && dc != "0'" ? dc : sd);
        } else {
          final sd = (type?['shortDetail'] ?? '').toString().trim();
          clock = sd.isEmpty ? 'FT' : sd;
        }

        List<String> names(Map c) {
          final t = c['team'];
          if (t is! Map) return const [];
          return [
            for (final k in [
              'displayName',
              'shortDisplayName',
              'name',
              'location',
              'abbreviation'
            ])
              if ((t[k] ?? '').toString().trim().isNotEmpty)
                t[k].toString().trim()
          ];
        }

        out.add(ScoreEvent(
          homeNames: names(home),
          awayNames: names(away),
          home: int.tryParse((home['score'] ?? '').toString()) ?? 0,
          away: int.tryParse((away['score'] ?? '').toString()) ?? 0,
          state: state,
          clock: clock,
          date: DateTime.tryParse((e['date'] ?? comp['date'] ?? '').toString()),
        ));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // ------------------------------------------------------------ matching

  /// Fixture id -> score for every fixture found in [events]. Both teams must
  /// match by name and the kick-off must be within 8 hours; if the feed lists
  /// the teams the other way round the score is flipped.
  static Map<String, LiveScore> match(
      List<Fixture> fixtures, List<ScoreEvent> events) {
    final out = <String, LiveScore>{};
    for (final f in fixtures) {
      ScoreEvent? best;
      var bestFlip = false;
      Duration? bestGap;
      for (final e in events) {
        final straight =
            _teamMatches(f.home, e.homeNames) && _teamMatches(f.away, e.awayNames);
        final flipped = !straight &&
            _teamMatches(f.home, e.awayNames) &&
            _teamMatches(f.away, e.homeNames);
        if (!straight && !flipped) continue;
        final gap = e.date == null
            ? Duration.zero
            : e.date!.difference(f.kickoff).abs();
        if (gap > const Duration(hours: 8)) continue;
        if (bestGap == null || gap < bestGap) {
          best = e;
          bestFlip = flipped;
          bestGap = gap;
        }
      }
      if (best == null) continue;
      out[f.id] = LiveScore(
        home: bestFlip ? best.away : best.home,
        away: bestFlip ? best.home : best.away,
        clock: best.clock,
        live: best.state == 'in',
        finished: best.state == 'post',
      );
    }
    return out;
  }

  static const _stop = {
    'fc', 'cf', 'afc', 'sc', 'ac', 'as', 'ssc', 'cd', 'ud', 'fk', 'sk', 'bk',
    'club', 'the', 'sv',
  };
  static const _alias = {
    'man': 'manchester',
    'utd': 'united',
    'spurs': 'tottenham',
    'wolves': 'wolverhampton',
    'atleti': 'atletico',
    'intl': 'international',
    'st': 'saint',
    'nottm': 'nottingham',
    'notts': 'nottingham',
  };
  // Reserve / women's / youth sides must not match the senior team.
  static const _squad = {
    'w', 'women', 'u17', 'u18', 'u19', 'u20', 'u21', 'u23', 'ii', 'b',
    'reserves',
  };
  static const _plain = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i',
    'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ø': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ß': 'ss',
    'š': 's', 'ž': 'z', 'č': 'c', 'ć': 'c', 'ł': 'l', 'ğ': 'g', 'ı': 'i',
    'ş': 's',
  };

  @visibleForTesting
  static List<String> tokens(String name) {
    var s = name.toLowerCase();
    _plain.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (s.isEmpty) return const [];
    final out = <String>[];
    for (final t in s.split(' ')) {
      if (t.isEmpty || _stop.contains(t)) continue;
      out.add(_alias[t] ?? t);
    }
    return out;
  }

  static bool _tokenMatch(String a, String b) =>
      a == b ||
      (a.length >= 3 && b.startsWith(a)) ||
      (b.length >= 3 && a.startsWith(b));

  static bool _teamMatches(String fixtureName, List<String> candidates) {
    final ft = tokens(fixtureName);
    if (ft.isEmpty) return false;
    for (final c in candidates) {
      final ct = tokens(c);
      if (ct.isEmpty) continue;
      if (ft.join(' ') == ct.join(' ')) return true;
      final shorter = ft.length <= ct.length ? ft : ct;
      final longer = ft.length <= ct.length ? ct : ft;
      final ok = shorter.every((s) => longer.any((l) => _tokenMatch(s, l)));
      if (!ok) continue;
      final extra = longer.where((l) => !shorter.any((s) => _tokenMatch(s, l)));
      if (extra.any(_squad.contains)) continue;
      return true;
    }
    return false;
  }
}
