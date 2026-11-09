import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/fixture.dart';
import 'auth_service.dart';

/// One saved AI Predict analysis. It stays for [AiHistory.lifetime] unless the user keeps it.
class AiHistoryEntry {
  final String key;
  final Fixture fixture;
  final Map<String, dynamic> data;
  final DateTime savedAt;
  final bool kept;

  const AiHistoryEntry({
    required this.key,
    required this.fixture,
    required this.data,
    required this.savedAt,
    this.kept = false,
  });

  DateTime get expiresAt => savedAt.add(AiHistory.lifetime);
  bool get expired => !kept && DateTime.now().isAfter(expiresAt);

  /// Time left before an unkept analysis is cleared.
  Duration get remaining => expiresAt.difference(DateTime.now());

  AiHistoryEntry copyWith({bool? kept}) => AiHistoryEntry(
    key: key,
    fixture: fixture,
    data: data,
    savedAt: savedAt,
    kept: kept ?? this.kept,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'fixture': {
      'id': fixture.id,
      'home': fixture.home,
      'away': fixture.away,
      'homeLogo': fixture.homeLogo,
      'awayLogo': fixture.awayLogo,
      'league': fixture.league,
      'kickoff': fixture.kickoff.toUtc().toIso8601String(),
      'scoreLeague': fixture.scoreLeague,
    },
    'data': data,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'kept': kept,
  };

  static AiHistoryEntry? fromJson(Object? raw) {
    try {
      if (raw is! Map) return null;
      final f = raw['fixture'];
      final d = raw['data'];
      if (f is! Map || d is! Map) return null;
      final kickoff = DateTime.parse('${f['kickoff']}').toLocal();
      return AiHistoryEntry(
        key: '${raw['key']}',
        fixture: Fixture(
          id: '${f['id']}',
          home: '${f['home']}',
          away: '${f['away']}',
          homeLogo: '${f['homeLogo'] ?? ''}',
          awayLogo: '${f['awayLogo'] ?? ''}',
          league: '${f['league'] ?? ''}',
          kickoff: kickoff,
          scoreLeague: '${f['scoreLeague'] ?? ''}',
        ),
        data: Map<String, dynamic>.from(d),
        savedAt: DateTime.parse('${raw['savedAt']}').toLocal(),
        kept: raw['kept'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Saves opened analyses on the device so the user can come back to one without analysing it again.
/// Unkept entries clear after 24 hours; kept ones stay until the user removes them.
class AiHistory {
  static const lifetime = Duration(hours: 24);
  static const _maxUnkept = 15;
  static const _maxKept = 40;

  static String get _prefsKey =>
      'ai_predict_history_v1_${AuthService.instance.user?.id ?? 'guest'}';

  /// Newest first, with expired entries already dropped (and the drop saved).
  static Future<List<AiHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_prefsKey);
    var list = <AiHistoryEntry>[];
    if (text != null && text.isNotEmpty) {
      try {
        final raw = jsonDecode(text);
        if (raw is List) {
          list = [for (final e in raw) ?AiHistoryEntry.fromJson(e)];
        }
      } catch (_) {}
    }
    final live = list.where((e) => !e.expired).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (live.length != list.length) await _write(prefs, live);
    return live;
  }

  /// Adds or replaces the analysis for [key]. A new run restarts the 24 hours but keeps the "kept" choice.
  static Future<List<AiHistoryEntry>> save(
    Fixture fixture,
    String key,
    Map<String, dynamic> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final wasKept = list.any((e) => e.key == key && e.kept);
    list.removeWhere((e) => e.key == key);
    list.insert(
      0,
      AiHistoryEntry(
        key: key,
        fixture: fixture,
        data: data,
        savedAt: DateTime.now(),
        kept: wasKept,
      ),
    );
    final out = <AiHistoryEntry>[];
    var kept = 0, unkept = 0;
    for (final e in list) {
      if (e.kept ? kept++ < _maxKept : unkept++ < _maxUnkept) out.add(e);
    }
    await _write(prefs, out);
    return out;
  }

  static Future<List<AiHistoryEntry>> setKept(String key, bool kept) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final e in await load()) e.key == key ? e.copyWith(kept: kept) : e,
    ];
    await _write(prefs, list);
    return list;
  }

  static Future<List<AiHistoryEntry>> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (await load()).where((e) => e.key != key).toList();
    await _write(prefs, list);
    return list;
  }

  static Future<void> _write(
    SharedPreferences prefs,
    List<AiHistoryEntry> list,
  ) => prefs.setString(
    _prefsKey,
    jsonEncode([for (final e in list) e.toJson()]),
  );
}
