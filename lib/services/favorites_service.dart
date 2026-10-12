import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';

/// Channels the user bookmarked with the star on the TV page. Saved on the
/// phone, so they survive restarts and feed refreshes.
class FavoriteChannels {
  FavoriteChannels._();
  static final FavoriteChannels instance = FavoriteChannels._();

  static const _key = 'favorite_channels';

  /// Keys of the bookmarked channels (see [keyOf]).
  final ValueNotifier<Set<String>> keys = ValueNotifier<Set<String>>({});

  bool _loaded = false;

  /// A key that stays the same across refreshes: the channel id when it has
  /// one, otherwise its stream link.
  static String keyOf(Channel c) {
    final id = (c.id ?? '').trim();
    return id.isNotEmpty ? 'id:$id' : 'url:${c.url.trim()}';
  }

  bool isFavorite(Channel c) => keys.value.contains(keyOf(c));

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key) ?? const <String>[];
      // Keep anything toggled while loading.
      keys.value = {...saved, ...keys.value};
    } catch (_) {}
  }

  /// Adds or removes the channel. Returns true when it is now a favourite.
  Future<bool> toggle(Channel c) async {
    final k = keyOf(c);
    final next = {...keys.value};
    final added = next.add(k);
    if (!added) next.remove(k);
    keys.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, next.toList());
    } catch (_) {}
    return added;
  }
}
