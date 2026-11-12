import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/static_strings.dart';
import '../l10n/translations.dart';
import 'locale_service.dart';

/// Shows the app's fixed texts in the phone's language.
///
/// 1. The hand-written table ([kTranslations]) is used first.
/// 2. Anything else that is a known fixed UI text ([kStaticUiStrings]) is
///    translated once with Google's public web translation endpoint (the same
///    one used for "Translate post"), saved on the phone per language, and
///    works offline afterwards. Only the fixed text is sent, never account
///    data, posts or names.
/// While a translation is on its way the English text is shown.
class UiTranslator {
  UiTranslator._();

  /// Goes up when new translations have arrived.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static final Map<String, Map<String, String>> _mem = {};
  static final Map<String, int> _failedAt = {}; // "lang\nsrc" -> ms
  static final Set<String> _queued = {};
  static final List<String> _queue = [];
  static int _running = 0;
  static int _streak = 0; // consecutive failures (offline?)
  static int _pausedUntil = 0;
  static bool _arrived = false;
  static Timer? _notify;
  static Timer? _save;
  static Timer? _resume;
  static final Set<String> _loadedLangs = {};

  static const _retryMs = 10 * 60 * 1000;
  static final _placeholder = RegExp(r'\{\w+\}');

  /// Language code the UI texts are wanted in ('en' = nothing to do).
  static String get _lang => AppLocale.uiLang;

  static bool _eligible(String s) =>
      s.length >= 3 && s.length <= 200 && kStaticUiStrings.contains(s);

  /// Loads the saved translations of [lang] (call once at start and when the
  /// language changes).
  static Future<void> prepare(String lang) async {
    if (lang == 'en' || _loadedLangs.contains(lang)) return;
    _loadedLangs.add(lang);
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('ui_tr_v1_$lang');
      if (raw == null) return;
      final d = jsonDecode(raw);
      if (d is Map) {
        final map = _mem.putIfAbsent(lang, () => {});
        d.forEach((k, v) {
          if (k is String && v is String) map[k] = v;
        });
      }
    } catch (_) {}
  }

  /// The text in the phone's language (English if not translated yet).
  static String text(String s) {
    final lang = _lang;
    if (lang == 'en') return s;
    final t = kTranslations[lang]?[s];
    if (t != null) return t;
    return lookup(s);
  }

  /// Saved or freshly fetched translation; starts a fetch when needed.
  static String lookup(String s) {
    final lang = _lang;
    if (lang == 'en' || !_eligible(s)) return s;
    final hit = _mem[lang]?[s];
    if (hit != null) return hit;
    _enqueue(lang, s);
    return s;
  }

  /// True while [s] could still get a translation.
  static bool isPending(String s) {
    final lang = _lang;
    if (lang == 'en' || !_eligible(s)) return false;
    if (kTranslations[lang]?[s] != null) return false;
    if (_mem[lang]?[s] != null) return false;
    final f = _failedAt['$lang\n$s'];
    if (f != null &&
        DateTime.now().millisecondsSinceEpoch - f < _retryMs) {
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------- fetching

  static void _enqueue(String lang, String s) {
    final key = '$lang\n$s';
    final f = _failedAt[key];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (f != null && now - f < _retryMs) return;
    if (!_queued.add(key)) return;
    _queue.add(key);
    scheduleMicrotask(_pump);
  }

  static void _pump() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _pausedUntil) {
      // Offline or blocked: try again later (one timer only).
      _resume ??= Timer(Duration(milliseconds: _pausedUntil - now + 50), () {
        _resume = null;
        _pump();
      });
      return;
    }
    while (_running < 3 && _queue.isNotEmpty) {
      final key = _queue.removeLast(); // newest (on screen) first
      _running++;
      unawaited(_fetch(key).whenComplete(() {
        _running--;
        _queued.remove(key);
        if (_queue.isNotEmpty) {
          _pump();
        } else if (_running == 0 && _arrived) {
          _arrived = false;
          // Texts that are not drawn through Text (hints, tooltips) are
          // refreshed once when everything has arrived.
          Timer(const Duration(milliseconds: 600), AppLocale.refreshAll);
        }
      }));
    }
  }

  static Future<void> _fetch(String key) async {
    final i = key.indexOf('\n');
    final lang = key.substring(0, i);
    final src = key.substring(i + 1);
    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'en',
        'tl': AppLocale.gtxCode(lang),
        'dt': 't',
        'q': src,
      });
      final r = await http.get(uri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Deeprowss/1.0',
      }).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is! List || d.isEmpty || d[0] is! List) throw Exception('shape');
      final out = (d[0] as List)
          .whereType<List>()
          .map((p) => p.isNotEmpty ? '${p[0] ?? ''}' : '')
          .join()
          .trim();
      if (out.isEmpty || out.length > src.length * 6 + 24) {
        throw Exception('odd');
      }
      // Placeholders like {n} must survive the translation.
      for (final m in _placeholder.allMatches(src)) {
        if (!out.contains(m.group(0)!)) throw Exception('placeholder');
      }
      _mem.putIfAbsent(lang, () => {})[src] = out;
      _streak = 0;
      _arrived = true;
      _bump();
      _saveSoon(lang);
    } catch (_) {
      _failedAt[key] = DateTime.now().millisecondsSinceEpoch;
      _streak++;
      if (_streak >= 6) {
        // Probably offline: stop hammering for a few minutes.
        _streak = 0;
        _pausedUntil = DateTime.now().millisecondsSinceEpoch + 3 * 60 * 1000;
      }
    }
  }

  static void _bump() {
    _notify ??= Timer(const Duration(milliseconds: 250), () {
      _notify = null;
      version.value++;
    });
  }

  static void _saveSoon(String lang) {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('ui_tr_v1_$lang', jsonEncode(_mem[lang] ?? {}));
      } catch (_) {}
    });
  }
}
