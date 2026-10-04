import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedPlaylist {
  final String name;
  final String url;
  const SavedPlaylist(this.name, this.url);

  Map<String, String> toJson() => {'name': name, 'url': url};
}

/// Small wrapper over SharedPreferences for the drawer menu settings.
class Settings {
  static const _kLow = 'footbolive_force_low_quality';
  static const _kFloat = 'footbolive_floating_player';
  static const _kCopyright = 'footbolive_copyright_seen';
  static const _kPlaylists = 'footbolive_playlists';

  static Future<bool> forceLowQuality() async =>
      (await SharedPreferences.getInstance()).getBool(_kLow) ?? false;
  static Future<void> setForceLowQuality(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kLow, v);

  static Future<bool> floatingPlayer() async =>
      (await SharedPreferences.getInstance()).getBool(_kFloat) ?? false;
  static Future<void> setFloatingPlayer(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kFloat, v);

  static Future<bool> copyrightSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_kCopyright) ?? false;
  static Future<void> setCopyrightSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_kCopyright, true);

  static Future<List<SavedPlaylist>> playlists() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kPlaylists);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => SavedPlaylist(
              (m['name'] ?? '').toString(), (m['url'] ?? '').toString()))
          .where((p) => p.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePlaylists(List<SavedPlaylist> list) async =>
      (await SharedPreferences.getInstance())
          .setString(_kPlaylists, jsonEncode(list.map((e) => e.toJson()).toList()));
}
