import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_media.dart';
import 'media_entry.dart';

class PlItem {
  final String key;
  final String title;
  final String? path;
  const PlItem(this.key, this.title, this.path);

  Map<String, dynamic> toJson() => {'k': key, 't': title, if (path != null) 'p': path};
  factory PlItem.fromJson(Map<String, dynamic> j) =>
      PlItem(j['k'] as String, (j['t'] as String?) ?? '', j['p'] as String?);
}

class Playlist {
  final String id;
  String name;
  final List<PlItem> items;
  Playlist(this.id, this.name, this.items);

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'i': [for (final i in items) i.toJson()],
      };
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        j['id'] as String,
        (j['n'] as String?) ?? 'Playlist',
        [
          for (final i in (j['i'] as List? ?? const []))
            PlItem.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
      );
}

/// Playlists of songs, saved on the phone.
class PlaylistStore extends ChangeNotifier {
  static final PlaylistStore instance = PlaylistStore._();
  PlaylistStore._();

  static const _k = 'playlists_v1';
  final List<Playlist> lists = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_k);
      if (raw != null) {
        final data = jsonDecode(raw) as List;
        lists
          ..clear()
          ..addAll([
            for (final m in data) Playlist.fromJson(Map<String, dynamic>.from(m as Map)),
          ]);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode([for (final l in lists) l.toJson()]));
    notifyListeners();
  }

  Playlist? byId(String id) {
    for (final l in lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  Playlist create(String name) {
    final p = Playlist(DateTime.now().microsecondsSinceEpoch.toString(),
        name.trim().isEmpty ? 'New playlist' : name.trim(), []);
    lists.add(p);
    _save();
    return p;
  }

  void rename(Playlist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _save();
  }

  void delete(Playlist p) {
    lists.remove(p);
    _save();
  }

  bool contains(Playlist p, MediaEntry e) => p.items.any((i) => i.key == e.key);

  /// False if the song was already in the playlist.
  bool add(Playlist p, MediaEntry e) {
    if (contains(p, e)) return false;
    p.items.add(PlItem(e.key, e.title, e.path));
    _save();
    return true;
  }

  void removeAt(Playlist p, int i) {
    p.items.removeAt(i);
    _save();
  }

  void move(Playlist p, int from, int to) {
    final it = p.items.removeAt(from);
    p.items.insert(to, it);
    _save();
  }

  /// Turns a saved item back into a playable song (null if it's gone).
  MediaEntry? resolve(PlItem it) {
    for (final s in LocalMedia.instance.songs) {
      if (s.key == it.key) return s;
    }
    final path = it.path;
    if (path != null && File(path).existsSync()) return MediaEntry.fromPath(path);
    return null;
  }
}
