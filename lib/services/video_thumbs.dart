import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dailymotion_check.dart';
import 'embed_info.dart';

/// A poster picture for a video link, plus the real shape (width / height)
/// when the host tells us, so the card is the right size before it plays.
class VideoThumb {
  final String url;

  /// Used when [url] cannot be loaded (e.g. YouTube has no max-res picture).
  final String? fallback;
  final double? ratio;
  const VideoThumb(this.url, {this.fallback, this.ratio});
}

/// Finds a real thumbnail for YouTube, Vimeo, Dailymotion and X videos, like
/// the poster frame a Twitter timeline shows before a video starts.
/// Direct mp4 / m3u8 links need no lookup: the native player shows frame one.
class VideoThumbs {
  VideoThumbs._();
  static final Map<String, Future<VideoThumb?>> _cache = {};

  static Future<VideoThumb?> lookup(String raw, EmbedKind kind) {
    final key = raw.trim();
    return _cache.putIfAbsent(key, () => _fetch(key, kind).catchError((Object _) => null));
  }

  static Future<VideoThumb?> _fetch(String raw, EmbedKind kind) async {
    final uri = Uri.tryParse(raw);
    switch (kind) {
      case EmbedKind.youtube:
        final id = _youtubeId(uri);
        if (id == null) return null;
        return VideoThumb(
          'https://img.youtube.com/vi/$id/maxresdefault.jpg',
          fallback: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
        );
      case EmbedKind.vimeo:
        final r = await http
            .get(Uri.https('vimeo.com', '/api/oembed.json', {'url': raw, 'width': '960'}))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) return null;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final t = j['thumbnail_url'] as String?;
        if (t == null) return null;
        final w = (j['width'] as num?)?.toDouble(), h = (j['height'] as num?)?.toDouble();
        return VideoThumb(t, ratio: (w != null && h != null && h > 0) ? w / h : null);
      case EmbedKind.dailymotion:
        final id = DailymotionCheck.idFrom(uri);
        if (id == null) return null;
        final r = await http
            .get(Uri.https('api.dailymotion.com', '/video/$id',
                {'fields': 'thumbnail_720_url,aspect_ratio'}))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) return null;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final t = j['thumbnail_720_url'] as String?;
        if (t == null) return null;
        final ar = (j['aspect_ratio'] as num?)?.toDouble();
        return VideoThumb(t, ratio: (ar != null && ar > 0) ? ar : null);
      case EmbedKind.twitter:
        final id = tweetIdFrom(raw);
        if (id == null) return null;
        final r = await http
            .get(Uri.https('cdn.syndication.twimg.com', '/tweet-result',
                {'id': id, 'lang': 'en', 'token': 'a'}))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) return null;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final media = (j['mediaDetails'] as List?) ?? const [];
        for (final m in media) {
          if (m is! Map) continue;
          final type = m['type'];
          if (type != 'video' && type != 'animated_gif') continue;
          final t = m['media_url_https'] as String?;
          if (t == null) continue;
          double? ratio;
          final ar = (m['video_info'] as Map?)?['aspect_ratio'];
          if (ar is List && ar.length == 2 && (ar[1] as num) > 0) {
            ratio = (ar[0] as num) / (ar[1] as num);
          }
          return VideoThumb('$t?name=large', fallback: t, ratio: ratio);
        }
        return null;
      default:
        return null;
    }
  }

  static String? _youtubeId(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host == 'youtube.com' || host.endsWith('.youtube.com') || host == 'youtu.be')) {
      return null;
    }
    String? id;
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.first;
    } else if (uri.pathSegments.length > 1 &&
        ['embed', 'shorts', 'live'].contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['v'];
    }
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
  }
}
