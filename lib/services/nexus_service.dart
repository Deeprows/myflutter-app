import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/channel.dart';

/// IPTV Nexus: static JSON API (no key, no auth).
///
/// `channels.online.json` is large, so it is parsed in a background isolate,
/// reduced to one best + one backup working stream per channel and saved as a
/// small file. Later launches read that file; the big download only happens
/// again after [AppConfig.nexusRefreshMinutes] (or on pull-to-refresh).
class NexusService {
  static bool get enabled => AppConfig.nexusBase.trim().isNotEmpty;

  /// True when the last attempt to download failed (saved copy used).
  bool lastFailed = false;

  static const _file = 'nexus_channels.json';

  Uri get _uri {
    final base = AppConfig.nexusBase.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base${AppConfig.nexusOnlinePath}');
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_file');
  }

  Future<List<Channel>> load({bool remote = false, bool force = false}) async {
    if (!enabled) return const [];
    lastFailed = false;

    File? f;
    try {
      f = await _cacheFile();
    } catch (_) {}

    if (remote) {
      var stale = true;
      try {
        if (f != null && await f.exists()) {
          final age = DateTime.now().difference(await f.lastModified());
          stale = age.inMinutes >= AppConfig.nexusRefreshMinutes;
        }
      } catch (_) {}

      if (force || stale) {
        try {
          final res =
              await http.get(_uri).timeout(const Duration(seconds: 90));
          if (res.statusCode == 200) {
            final slim = await compute(slimDown, utf8.decode(res.bodyBytes));
            if (slim.isNotEmpty) {
              try {
                await f?.writeAsString(jsonEncode(slim), flush: true);
              } catch (_) {}
              return slim.map(Channel.tryParse).whereType<Channel>().toList();
            }
          }
          lastFailed = true;
        } catch (_) {
          lastFailed = true;
        }
      }
    }

    try {
      if (f != null && await f.exists()) {
        final data = await compute(_decodeList, await f.readAsString());
        return data.map(Channel.tryParse).whereType<Channel>().toList();
      }
    } catch (_) {}
    return const [];
  }
}

List<dynamic> _decodeList(String body) {
  final d = jsonDecode(body);
  return d is List ? d : const [];
}

const _categoryMap = <String, ChannelCategory>{
  'sports': ChannelCategory.sports,
  'movies': ChannelCategory.movies,
  'series': ChannelCategory.movies,
  'classic': ChannelCategory.movies,
  'music': ChannelCategory.music,
  'news': ChannelCategory.news,
  'kids': ChannelCategory.kids,
  'animation': ChannelCategory.kids,
  'entertainment': ChannelCategory.entertainment,
  'comedy': ChannelCategory.entertainment,
  'documentary': ChannelCategory.documentary,
  'science': ChannelCategory.documentary,
  'education': ChannelCategory.documentary,
  'lifestyle': ChannelCategory.lifestyle,
  'culture': ChannelCategory.lifestyle,
  'relax': ChannelCategory.lifestyle,
  'outdoor': ChannelCategory.lifestyle,
  'travel': ChannelCategory.lifestyle,
  'cooking': ChannelCategory.lifestyle,
  'family': ChannelCategory.lifestyle,
  'religious': ChannelCategory.religious,
  'general': ChannelCategory.general,
  'public': ChannelCategory.general,
};

// First match wins, so a channel tagged ["news","business"] becomes News.
const _categoryOrder = [
  'sports',
  'news',
  'kids',
  'animation',
  'movies',
  'series',
  'classic',
  'music',
  'documentary',
  'science',
  'education',
  'entertainment',
  'comedy',
  'lifestyle',
  'culture',
  'relax',
  'outdoor',
  'travel',
  'cooking',
  'family',
  'religious',
  'general',
  'public',
];

String? _s(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// Runs in an isolate. Turns the Nexus payload into small Channel-JSON maps
/// (see [Channel.toJson]): one primary and one backup working stream each.
List<Map<String, dynamic>> slimDown(String body) {
  final data = jsonDecode(body);
  final list = data is List
      ? data
      : (data is Map && data['channels'] is List ? data['channels'] as List : const []);

  final out = <Map<String, dynamic>>[];
  for (final raw in list) {
    if (raw is! Map) continue;
    if (AppConfig.nexusHideNsfw && raw['is_nsfw'] == true) continue;

    final name = _s(raw['name']);
    if (name == null) continue;

    // Working streams only, best rank first.
    final streams = <Map>[];
    if (raw['streams'] is List) {
      for (final st in raw['streams'] as List) {
        if (st is! Map || _s(st['url']) == null) continue;
        final h = st['health'];
        final status = h is Map ? h['status'] : null;
        if (status == 'online') streams.add(st);
      }
    }
    if (streams.isEmpty) continue;
    streams.sort((a, b) =>
        ((b['rank'] as num?) ?? 0).compareTo((a['rank'] as num?) ?? 0));

    final cats = raw['categories'] is List
        ? (raw['categories'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    var cat = ChannelCategory.other;
    for (final k in _categoryOrder) {
      if (cats.contains(k)) {
        cat = _categoryMap[k]!;
        break;
      }
    }

    final best = streams.first;
    final alt = streams.length > 1 ? streams[1] : null;

    out.add({
      'id': _s(raw['id']),
      'name': name,
      'url': _s(best['url']),
      'category': cat.name,
      'logo': _s(raw['logo']),
      'country': _s(raw['country']),
      'quality': _s(best['quality']) ?? _s(raw['best_quality']),
      'score': raw['score'] is num ? raw['score'] : 0,
      'referer': _s(best['referrer']),
      'userAgent': _s(best['user_agent']),
      if (alt != null) 'altUrl': _s(alt['url']),
      if (alt != null) 'altReferer': _s(alt['referrer']),
      if (alt != null) 'altUserAgent': _s(alt['user_agent']),
    }..removeWhere((_, v) => v == null));
  }

  // Healthiest first, then A-Z.
  out.sort((a, b) {
    final c = ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0);
    return c != 0
        ? c
        : (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase());
  });
  return out;
}

/// Merges your own channels with Nexus ones. A Nexus channel with the same
/// name as one of yours is folded into it (your stream stays first; the Nexus
/// stream becomes the backup and fills in logo / country / quality). All other
/// Nexus channels are appended in their given order.
List<Channel> mergeChannels(List<Channel> own, List<Channel> nexus) {
  if (nexus.isEmpty) return own;

  final byName = <String, Channel>{};
  for (final c in nexus) {
    byName.putIfAbsent(c.name.toLowerCase(), () => c);
  }
  final ownNames = {for (final c in own) c.name.toLowerCase()};
  final ownUrls = {for (final c in own) c.url};

  final merged = <Channel>[
    for (final c in own)
      () {
        final n = byName[c.name.toLowerCase()];
        if (n == null) return c;
        final useAlt = (c.altUrl ?? '').isEmpty && n.url != c.url;
        return c.copyWith(
          logo: n.logo,
          country: n.country,
          quality: n.quality,
          score: n.score,
          altUrl: useAlt ? n.url : null,
          altReferer: useAlt ? n.referer : null,
          altUserAgent: useAlt ? n.userAgent : null,
        );
      }(),
  ];

  for (final c in nexus) {
    if (ownNames.contains(c.name.toLowerCase())) continue;
    if (ownUrls.contains(c.url)) continue;
    merged.add(c);
  }
  return merged;
}
