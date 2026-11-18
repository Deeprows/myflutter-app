import 'stream_resolver.dart';

/// What kind of site a pasted link points at. Used to pick an embed player
/// and a sensible first guess for the embed's shape (portrait / landscape).
enum EmbedKind { youtube, twitter, vimeo, dailymotion, filemoon, hls, direct, generic }

class EmbedInfo {
  final EmbedKind kind;

  /// Width / height guess. Portrait links (Shorts) are < 1.
  /// The player replaces this with the real video shape when it can measure it.
  final double ratio;

  const EmbedInfo(this.kind, this.ratio);

  bool get isPortrait => ratio < 1;

  String get label {
    switch (kind) {
      case EmbedKind.twitter:
        return 'X (Twitter) video';
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

/// First guess for an embedded X post (video + header + actions). The real
/// height is reported by the embed itself once it has loaded.
const double kTweet = 0.72;

bool _hostIs(String host, String site) => host == site || host.endsWith('.$site');

bool isTwitterHost(String host) {
  final h = host.toLowerCase();
  return _hostIs(h, 'twitter.com') ||
      _hostIs(h, 'x.com') ||
      _hostIs(h, 'fxtwitter.com') ||
      _hostIs(h, 'vxtwitter.com') ||
      _hostIs(h, 'fixupx.com') ||
      _hostIs(h, 'fixvx.com');
}

/// The numeric id of the post in a Twitter / X post link, or null.
/// Handles x.com/user/status/ID, twitter.com/user/status/ID (with ?s=20 style
/// tracking), mobile.twitter.com, /i/status/ID, /i/web/status/ID and
/// /user/status/ID/video/1.
String? tweetIdFrom(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null || !isTwitterHost(u.host)) return null;
  final m = RegExp(r'/(?:status|statuses)/(\d{5,25})(?:/|$)').firstMatch(u.path);
  return m?.group(1);
}

EmbedInfo embedInfoFor(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null) return const EmbedInfo(EmbedKind.generic, kLandscape);
  final host = u.host.toLowerCase();
  if (isTwitterHost(host) && tweetIdFrom(raw) != null) {
    return const EmbedInfo(EmbedKind.twitter, kTweet);
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

/// X's embeddable post player. It plays the post's video natively (with its
/// own controls), exactly like the post does on X.
String twitterEmbedUrl(String id, {bool dark = true}) =>
    Uri.https('platform.twitter.com', '/embed/Tweet.html', {
      'id': id,
      'theme': dark ? 'dark' : 'light',
      'lang': 'en',
      'dnt': 'true',
      'hideThread': 'true',
      'embedId': 'twitter-widget-0',
    }).toString();

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
