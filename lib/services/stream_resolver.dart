import 'dart:async';

import 'package:http/http.dart' as http;

import 'dailymotion_check.dart';

/// Works out how a link should be played inside the WebView.
enum StreamKind { hls, dash, video, embed, invalid }

class ResolvedStream {
  final String url;
  final StreamKind kind;
  const ResolvedStream(this.url, this.kind);

  /// m3u8 / mpd / mp4 etc. are played by our own HTML5 player page.
  bool get usesHtmlPlayer =>
      kind == StreamKind.hls ||
      kind == StreamKind.dash ||
      kind == StreamKind.video;

  /// The Dailymotion video id when this is a Dailymotion link or embed
  /// (dailymotion.com/video|embed, geo.dailymotion.com player, dai.ly).
  String? get dailymotionId {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (!(host == 'dai.ly' || host == 'dailymotion.com' || host.endsWith('.dailymotion.com'))) {
      return null;
    }
    return DailymotionCheck.idFrom(uri);
  }

  String get label {
    switch (kind) {
      case StreamKind.hls:
        return 'HLS · m3u8';
      case StreamKind.dash:
        return 'DASH · mpd';
      case StreamKind.video:
        return 'Direct video';
      case StreamKind.embed:
        return 'Web embed';
      case StreamKind.invalid:
        return 'Unknown';
    }
  }
}

class StreamResolver {
  static final _mediaExt = RegExp(
    r'\.(mp4|m4v|webm|mov|ogv|ogg|mkv|mp3|aac|m4a)(\?|#|$)',
    caseSensitive: false,
  );
  static final _http = RegExp(r'^https?://', caseSensitive: false);

  static ResolvedStream resolve(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return const ResolvedStream('', StreamKind.invalid);
    // A pasted embed code (<iframe ... src="https://...">): use its src.
    if (trimmed.contains('<')) {
      final m = RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false)
          .firstMatch(trimmed);
      if (m != null) {
        trimmed = m.group(1)!.replaceAll('&amp;', '&').trim();
      }
    }
    final s = trimmed.split(RegExp(r'\s+')).first;

    var candidate = _extractInner(s) ?? s;
    if (candidate.startsWith('//')) candidate = 'https:$candidate';
    if (!_http.hasMatch(candidate)) {
      return ResolvedStream(candidate, StreamKind.invalid);
    }
    return ResolvedStream(candidate, _kindOf(candidate));
  }

  /// Direct links without a file extension (`/live/abc`, `get.php?id=1`) look
  /// like web pages, so they used to be opened as pages and showed a black
  /// screen. This asks the server what the link really is (looking only at
  /// the response headers) and returns hls / dash / video, or null when it is
  /// a normal web page or cannot be checked.
  static Future<StreamKind?> sniff(String url,
      {String? referer, String? userAgent}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers.addAll({
          'Range': 'bytes=0-1023',
          if ((userAgent ?? '').trim().isNotEmpty) 'User-Agent': userAgent!,
          if ((referer ?? '').trim().isNotEmpty) 'Referer': referer!,
        });
      final res = await client.send(req).timeout(const Duration(seconds: 6));
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      final finalUrl = res.request?.url.toString().toLowerCase() ?? '';
      if (res.statusCode >= 400) return null;
      if (type.contains('mpegurl')) return StreamKind.hls;
      if (type.contains('dash+xml')) return StreamKind.dash;
      if (type.startsWith('video/') || type.startsWith('audio/')) {
        return StreamKind.video;
      }
      if (finalUrl.contains('.m3u8')) return StreamKind.hls;
      if (_mediaExt.hasMatch(finalUrl)) return StreamKind.video;
      if (type.contains('octet-stream') || type.contains('mp2t')) {
        return StreamKind.video;
      }
      return null; // text/html etc. = a normal embed page
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static StreamKind _kindOf(String url) {
    final l = url.toLowerCase();
    if (l.contains('.m3u8')) return StreamKind.hls;
    if (l.contains('.mpd')) return StreamKind.dash;
    if (_mediaExt.hasMatch(l)) return StreamKind.video;
    return StreamKind.embed;
  }

  /// Handles wrapper links such as
  ///   hls-player/player.html#https://host/live.m3u8
  ///   https://some-player/?url=https%3A%2F%2Fhost%2Flive.m3u8
  static String? _extractInner(String s) {
    final hash = s.indexOf('#');
    if (hash >= 0 && hash < s.length - 1) {
      var frag = s.substring(hash + 1);
      if (RegExp(r'^https?%3A', caseSensitive: false).hasMatch(frag)) {
        try {
          frag = Uri.decodeComponent(frag);
        } catch (_) {}
      }
      if (_http.hasMatch(frag)) return frag;
    }
    final uri = Uri.tryParse(s);
    if (uri != null && uri.hasQuery) {
      for (final k in const ['url', 'src', 'file', 'source', 'stream']) {
        final v = uri.queryParameters[k];
        if (v != null && _http.hasMatch(v) && _kindOf(v) != StreamKind.embed) {
          return v;
        }
      }
    }
    return null;
  }
}
