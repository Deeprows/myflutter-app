// Standalone: dart run test/embed_info_check.dart
import '../lib/services/embed_info.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void main() {
  // X (Twitter) post links
  check(
    tweetIdFrom('https://x.com/user/status/1234567890123456789?s=20&t=abc') ==
        '1234567890123456789',
    'x.com status id',
  );
  check(
    tweetIdFrom('https://twitter.com/user/status/1234567890123456789') ==
        '1234567890123456789',
    'twitter.com status id',
  );
  check(
    tweetIdFrom('https://mobile.twitter.com/user/status/1234567890123456789') ==
        '1234567890123456789',
    'mobile.twitter.com status id',
  );
  check(
    tweetIdFrom('https://x.com/i/status/1234567890123456789') ==
        '1234567890123456789',
    '/i/status id',
  );
  check(
    tweetIdFrom('https://x.com/user/status/1234567890123456789/video/1') ==
        '1234567890123456789',
    'video suffix',
  );
  check(tweetIdFrom('https://x.com/user') == null, 'profile is not a post');
  check(tweetIdFrom('https://example.com/status/1234567890123456789') == null, 'other host');
  check(
    embedInfoFor('https://x.com/user/status/1234567890123456789').kind == EmbedKind.twitter,
    'x.com post is twitter',
  );
  check(embedInfoFor('https://x.com/user').kind == EmbedKind.generic, 'x profile is generic');
  check(
    embedInfoFor('https://www.tiktok.com/@u/video/7234567890123456789').kind == EmbedKind.generic,
    'tiktok no longer special',
  );
  check(
    embedInfoFor('https://www.facebook.com/watch/?v=123456').kind == EmbedKind.generic,
    'facebook no longer special',
  );
  final tw = twitterEmbedUrl('1234567890123456789');
  check(tw.startsWith('https://platform.twitter.com/embed/Tweet.html?'), 'tweet embed url');
  check(tw.contains('id=1234567890123456789'), 'tweet embed id');
  check(embedInfoFor('https://www.youtube.com/shorts/efzxdQeODpU').isPortrait, 'shorts portrait');
  check(embedInfoFor('https://example.com/x').kind == EmbedKind.generic, 'generic');
  check(embedInfoFor('https://vimeo.com/123456789').kind == EmbedKind.vimeo, 'Vimeo');
  check(embedInfoFor('https://www.dailymotion.com/video/x8abcde').kind == EmbedKind.dailymotion, 'Dailymotion');
  check(embedInfoFor('https://dai.ly/x8abcde').kind == EmbedKind.dailymotion, 'Dailymotion short link');
  check(embedInfoFor('https://filemoon.sx/d/abc123').kind == EmbedKind.filemoon, 'Filemoon');
  check(embedInfoFor('https://cdn.example.com/live/index.m3u8').kind == EmbedKind.hls, 'HLS stream');
  check(embedInfoFor('https://cdn.example.com/video.mp4').kind == EmbedKind.direct, 'direct video');
  check(embedInfoFor('https://cdn.example.com/live/manifest.mpd').kind == EmbedKind.direct, 'DASH stream');
  print('embed_info checks passed');
}
