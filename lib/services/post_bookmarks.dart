import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Thread posts the user saved with the bookmark button. The whole post is
/// kept on the phone (per signed-in account), so the Bookmarks page opens
/// instantly and still works offline.
class PostBookmarks {
  PostBookmarks._();
  static final PostBookmarks instance = PostBookmarks._();

  static const _max = 300;

  /// Saved posts, newest bookmark first.
  final ValueNotifier<List<Map<String, dynamic>>> posts =
      ValueNotifier<List<Map<String, dynamic>>>(const []);

  /// Ids of the saved posts, for the filled/outlined bookmark icon.
  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>(<String>{});

  String? _loadedFor;

  String get _uid => AuthService.instance.user?.id ?? 'guest';
  String get _key => 'post_bookmarks_$_uid';

  Future<void> load() async {
    final uid = _uid;
    if (_loadedFor == uid) return;
    _loadedFor = uid;
    var saved = <Map<String, dynamic>>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('post_bookmarks_$uid');
      if (raw != null) {
        saved = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    _set(saved);
  }

  void _set(List<Map<String, dynamic>> list) {
    posts.value = list;
    ids.value = {for (final p in list) '${p['id']}'};
  }

  bool isBookmarked(String id) => ids.value.contains(id);

  /// Saves or removes the post. Returns true when it is now bookmarked.
  Future<bool> toggle(Map<String, dynamic> post) async {
    await load();
    final id = '${post['id']}';
    final list = [...posts.value];
    final at = list.indexWhere((p) => '${p['id']}' == id);
    final added = at < 0;
    if (added) {
      list.insert(0, {
        ...post,
        'bookmarked_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (list.length > _max) list.removeRange(_max, list.length);
    } else {
      list.removeAt(at);
    }
    _set(list);
    await _save();
    return added;
  }

  Future<void> clear() async {
    await load();
    _set(const []);
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(posts.value));
    } catch (_) {}
  }
}
