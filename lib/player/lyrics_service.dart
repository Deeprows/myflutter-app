import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'media_entry.dart';

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final bool synced;
  final String raw;
  final String source; // 'saved', 'file', 'online'
  const Lyrics(this.lines, this.synced, this.raw, this.source);
  bool get isEmpty => lines.isEmpty;
}

/// Finds lyrics for a song: the ones the person saved, an .lrc file next to
/// the song, or an online search (lrclib.net, free, no key). Understands both
/// plain text and synced .lrc ("[01:23.45] line").
class LyricsService {
  static final _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _tried = <String>{};

  static Lyrics parse(String raw, String source) {
    final synced = <LyricLine>[];
    final plain = <LyricLine>[];
    for (final line in const LineSplitter().convert(raw)) {
      final matches = _stamp.allMatches(line).toList();
      final text = line.replaceAll(_stamp, '').trim();
      if (matches.isNotEmpty) {
        for (final m in matches) {
          final min = int.parse(m.group(1)!);
          final sec = int.parse(m.group(2)!);
          var frac = m.group(3) ?? '0';
          final ms = frac.length == 1
              ? int.parse(frac) * 100
              : frac.length == 2
                  ? int.parse(frac) * 10
                  : int.parse(frac.substring(0, 3));
          synced.add(LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            text,
          ));
        }
      } else if (text.isNotEmpty) {
        // Skip tags such as [ar:Artist] or [ti:Title].
        if (text.startsWith('[') && text.endsWith(']') && text.contains(':')) {
          continue;
        }
        plain.add(LyricLine(Duration.zero, text));
      }
    }
    if (synced.isNotEmpty) {
      synced.sort((a, b) => a.time.compareTo(b.time));
      return Lyrics(synced, true, raw, source);
    }
    return Lyrics(plain, false, raw, source);
  }

  static String _userKey(MediaEntry e) => 'lyr_user_${e.key}';
  static String _netKey(MediaEntry e) => 'lyr_net_${e.key}';

  /// The text of saved/cached lyrics (for the editor), or null.
  static Future<String?> rawFor(MediaEntry e) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_userKey(e)) ?? p.getString(_netKey(e));
  }

  static Future<void> save(MediaEntry e, String raw) async {
    final p = await SharedPreferences.getInstance();
    if (raw.trim().isEmpty) {
      await p.remove(_userKey(e));
    } else {
      await p.setString(_userKey(e), raw);
    }
  }

  static Future<void> forgetOnline(MediaEntry e) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_netKey(e));
    _tried.remove(e.key);
  }

  static Future<Lyrics?> _sidecar(MediaEntry e) async {
    try {
      final f = await e.file();
      if (f == null) return null;
      final p = f.path;
      final dot = p.lastIndexOf('.');
      if (dot < 0) return null;
      final lrc = File('${p.substring(0, dot)}.lrc');
      if (!await lrc.exists()) return null;
      final raw = utf8.decode(await lrc.readAsBytes(), allowMalformed: true);
      final l = parse(raw, 'file');
      return l.isEmpty ? null : l;
    } catch (_) {
      return null;
    }
  }

  static String _cleanTitle(String t) {
    var s = t.replaceAll('_', ' ');
    s = s.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
    s = s.replaceAll(
        RegExp(r'official|lyrics?|video|audio|hd|hq|\.com|www\.', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'^\s*\d{1,3}\s*[-.]\s*'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Future<Lyrics?> _online(MediaEntry e) async {
    try {
      final q = _cleanTitle(e.title);
      if (q.isEmpty) return null;
      final res = await http
          .get(
            Uri.https('lrclib.net', '/api/search', {'q': q}),
            headers: {'User-Agent': 'Deeprowss/1.0'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List || list.isEmpty) return null;
      String? pick;
      final want = e.duration.inSeconds;
      String? s(dynamic m, String k) {
        final v = m is Map ? m[k] : null;
        return v is String && v.trim().isNotEmpty ? v : null;
      }

      // Best: synced lyrics whose length matches the song.
      for (final m in list) {
        final d = m is Map && m['duration'] is num ? (m['duration'] as num).round() : 0;
        if (s(m, 'syncedLyrics') != null && (want == 0 || (d - want).abs() <= 6)) {
          pick = s(m, 'syncedLyrics');
          break;
        }
      }
      pick ??= list.map((m) => s(m, 'syncedLyrics')).whereType<String>().firstOrNull;
      pick ??= list.map((m) => s(m, 'plainLyrics')).whereType<String>().firstOrNull;
      if (pick == null) return null;
      final p = await SharedPreferences.getInstance();
      await p.setString(_netKey(e), pick);
      final l = parse(pick, 'online');
      return l.isEmpty ? null : l;
    } catch (_) {
      return null;
    }
  }

  /// Saved -> cached online -> .lrc beside the song -> online search.
  static Future<Lyrics?> load(MediaEntry e, {bool online = true, bool force = false}) async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_userKey(e));
    if (user != null && user.trim().isNotEmpty) {
      final l = parse(user, 'saved');
      if (!l.isEmpty) return l;
    }
    final cached = p.getString(_netKey(e));
    if (!force && cached != null) {
      final l = parse(cached, 'online');
      if (!l.isEmpty) return l;
    }
    final side = await _sidecar(e);
    if (side != null) return side;
    if (online && (force || _tried.add(e.key))) return _online(e);
    return null;
  }
}
