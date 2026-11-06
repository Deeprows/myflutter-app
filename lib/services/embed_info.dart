import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'stream_resolver.dart';

/// What kind of site a pasted link points at. Used to pick an embed player
/// and a sensible first guess for the embed's shape (portrait / landscape).
enum EmbedKind { youtube, tiktok, facebook, vimeo, dailymotion, filemoon, hls, direct, generic }

class EmbedInfo {
  final EmbedKind kind;

  /// Width / height guess. Portrait links (Shorts, TikTok, Reels) are < 1.
  /// The player replaces this with the real video shape when it can measure it.
  final double ratio;

  const EmbedInfo(this.kind, this.ratio);

  bool get isPortrait => ratio < 1;

  String get label {
    switch (kind) {
      case EmbedKind.tiktok:
        return 'TikTok';
      case EmbedKind.facebook:
        return 'Facebook video';
      case EmbedKind.youtube:
        return 'YouTube';
      case EmbedKind.vimeo:
        return 'Vimeo';
      case EmbedKind.dailymotion:
        return 'Dailymotion';
      case EmbedKind.filemoon:
        return 'Filemoon';
      case EmbedKind.hls:
        return 'HLS stream';
      case EmbedKind.direct:
        return 'Direct stream';
      case EmbedKind.generic:
        return 'video';
    }
  }
}

const double kLandscape = 16 / 9;
const double kPortrait = 9 / 16;

bool _hostIs(String host, String site) => host == site || host.endsWith('.$site');

bool isTikTokHost(String host) {
  final h = host.toLowerCase();
  return _hostIs(h, 'tiktok.com') || _hostIs(h, 'tiktokv.com');
}

bool isTikTokShortLink(Uri u) {
  final h = u.host.toLowerCase();
  if (h == 'vm.tiktok.com' || h == 'vt.tiktok.com') return true;
  return _hostIs(h, 'tiktok.com') &&
      u.pathSegments.isNotEmpty &&
      u.pathSegments.first == 't';
}

bool isFacebookHost(String host) {
  final h = host.toLowerCase();
  return _hostIs(h, 'facebook.com') || h == 'fb.watch' || h == 'fb.com';
}

/// True for Facebook links that are videos / reels (not plain posts or pages).
bool isFacebookVideo(Uri u) {
  final h = u.host.toLowerCase();
  if (h == 'fb.watch') return true;
  if (!isFacebookHost(h)) return false;
  final path = u.path.toLowerCase();
  if (path.startsWith('/plugins/video.php')) return true;
  if (path.startsWith('/watch')) return true;
  if (path.startsWith('/reel/') || path.startsWith('/reels/')) return true;
  if (path.startsWith('/video.php') || path.contains('/videos/')) return true;
  if (path.startsWith('/share/v/') || path.startsWith('/share/r/')) return true;
  if (u.queryParameters.containsKey('v') && path.contains('watch')) return true;
  return false;
}

/// First TikTok video id found in [raw], or null (short links need
/// [resolveTikTokId]).
String? tiktokIdFrom(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null) return null;
  final m = RegExp(r'/(?:video|v|embed/v2|embed|player/v1)/(\d{8,25})')
      .firstMatch(u.path);
  if (m != null) return m.group(1);
  for (final k in const ['share_item_id', 'item_id', 'aweme_id']) {
    final v = u.queryParameters[k];
    if (v != null && RegExp(r'^\d{8,25}$').hasMatch(v)) return v;
  }
  return null;
}

EmbedInfo embedInfoFor(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null) return const EmbedInfo(EmbedKind.generic, kLandscape);
  final host = u.host.toLowerCase();
  if (isTikTokHost(host)) return const EmbedInfo(EmbedKind.tiktok, kPortrait);
  if (isFacebookHost(host) && isFacebookVideo(u)) {
    final p = u.path.toLowerCase();
    final reel =
        p.startsWith('/reel') || p.startsWith('/share/r/') || p.contains('/reels/');
    return EmbedInfo(EmbedKind.facebook, reel ? kPortrait : kLandscape);
  }
  if (_hostIs(host, 'youtube.com') || host == 'youtu.be') {
    final shorts = u.pathSegments.isNotEmpty && u.pathSegments.first == 'shorts';
    return EmbedInfo(EmbedKind.youtube, shorts ? kPortrait : kLandscape);
  }
  if (_hostIs(host, 'vimeo.com')) return const EmbedInfo(EmbedKind.vimeo, kLandscape);
  if (_hostIs(host, 'dailymotion.com') || host == 'dai.ly') {
    return const EmbedInfo(EmbedKind.dailymotion, kLandscape);
  }
  if (_hostIs(host, 'filemoon.sx') || _hostIs(host, 'filemoon.to') ||
      host.contains('filemoon')) {
    return const EmbedInfo(EmbedKind.filemoon, kLandscape);
  }
  final stream = StreamResolver.resolve(raw);
  if (stream.kind == StreamKind.hls) return const EmbedInfo(EmbedKind.hls, kLandscape);
  if (stream.kind == StreamKind.video || stream.kind == StreamKind.dash) {
    return const EmbedInfo(EmbedKind.direct, kLandscape);
  }
  return const EmbedInfo(EmbedKind.generic, kLandscape);
}

const _ua =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

/// Finds the numeric TikTok video id, following short links (vm.tiktok.com,
/// tiktok.com/t/...) when needed.
Future<String?> resolveTikTokId(String raw) async {
  final direct = tiktokIdFrom(raw);
  if (direct != null) return direct;
  final start = Uri.tryParse(raw);
  if (start != null) {
    final end = await _followRedirects(start);
    final id = end == null ? null : tiktokIdFrom(end.toString());
    if (id != null) return id;
  }
  try {
    final r = await http
        .get(Uri.parse(raw), headers: {'user-agent': _ua})
        .timeout(const Duration(seconds: 8));
    final finalUrl = r.request?.url.toString();
    if (finalUrl != null) {
      final id = tiktokIdFrom(finalUrl);
      if (id != null) return id;
    }
    final m = RegExp(r'/video/(\d{8,25})').firstMatch(r.body);
    if (m != null) return m.group(1);
  } catch (_) {}
  return null;
}

/// Cover image for a TikTok link (public oEmbed endpoint), or null.
Future<String?> tiktokThumbnail(String raw) async {
  try {
    final r = await http
        .get(
          Uri.https('www.tiktok.com', '/oembed', {'url': raw}),
          headers: {'user-agent': _ua},
        )
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(r.bodyBytes));
    final t = data is Map ? data['thumbnail_url'] : null;
    return t is String && t.startsWith('https://') ? t : null;
  } catch (_) {
    return null;
  }
}

/// TikTok's embeddable player: just the video with its own controls, and it
/// starts by itself.
String tiktokEmbedUrl(String id) =>
    'https://www.tiktok.com/player/v1/$id?autoplay=1&controls=1&progress_bar=1'
    '&play_button=1&volume_control=1&fullscreen_button=1&description=0'
    '&music_info=0&rel=0&native_context_menu=0&closed_caption=0';

/// Follows redirects by hand and returns the final address (the http package
/// does not report it), or null when the site cannot be reached.
Future<Uri?> _followRedirects(Uri start) async {
  final client = http.Client();
  try {
    var cur = start;
    for (var i = 0; i < 6; i++) {
      final req = http.Request('GET', cur)
        ..followRedirects = false
        ..headers['user-agent'] = _ua;
      final res = await client.send(req).timeout(const Duration(seconds: 8));
      await res.stream.drain<void>();
      final loc = res.headers['location'];
      if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
        cur = cur.resolve(loc);
        continue;
      }
      return cur;
    }
    return cur;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Facebook's plugin only understands the real video address. Share links
/// (facebook.com/share/v/…, /share/r/…) and fb.watch short links are followed
/// to it first; other links are only cleaned of tracking parameters.
Future<String> resolveFacebookUrl(String raw) async {
  var u = Uri.tryParse(raw);
  if (u == null) return raw;
  final needsResolve = u.host.toLowerCase() == 'fb.watch' ||
      u.path.toLowerCase().startsWith('/share/');
  if (needsResolve) {
    final end = await _followRedirects(u);
    if (end != null && isFacebookHost(end.host)) {
      final next = end.path.startsWith('/login') ? end.queryParameters['next'] : null;
      u = next != null ? (Uri.tryParse(next) ?? end) : end;
    }
  }
  if (!isFacebookHost(u.host)) return raw;
  // Keep only what identifies the video (v=… on /watch), drop tracking.
  final keep = <String, String>{};
  final v = u.queryParameters['v'];
  if (v != null && v.isNotEmpty) keep['v'] = v;
  return Uri.https('www.facebook.com', u.path, keep.isEmpty ? null : keep)
      .toString();
}

/// Facebook's official video plugin URL for a video / reel link.
String facebookEmbedUrl(String raw, {int width = 734}) {
  var u = Uri.parse(raw);
  final h = u.host.toLowerCase();
  if (h == 'm.facebook.com' ||
      h == 'web.facebook.com' ||
      h == 'mbasic.facebook.com' ||
      h == 'touch.facebook.com') {
    u = u.replace(host: 'www.facebook.com');
  }
  return Uri.https('www.facebook.com', '/plugins/video.php', {
    'href': u.toString(),
    'show_text': 'false',
    'autoplay': 'true',
    'width': '$width',
  }).toString();
}

/// JavaScript that reports the real shape of the video being played to the
/// app (channel "FanSize"), so the embed box can match it. Only the video's own
/// intrinsic size is trusted, so the box never feeds back into itself.
const String embedSizeJs = r'''
(function(){
  if (window.__fanSizeOn) return; window.__fanSizeOn = 1;
  var last = '';
  function send(){
    try {
      var vs = document.querySelectorAll('video');
      for (var i = 0; i < vs.length; i++) {
        var v = vs[i];
        if (v.videoWidth > 0 && v.videoHeight > 0) {
          var k = v.videoWidth + 'x' + v.videoHeight;
          if (k !== last) { last = k; FanSize.postMessage(k); }
          return;
        }
      }
    } catch (e) {}
  }
  document.addEventListener('loadedmetadata', send, true);
  document.addEventListener('resize', send, true);
  setInterval(send, 800);
  send();
})();
''';
