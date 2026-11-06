// Standalone: dart run test/embed_info_check.dart
import '../lib/services/embed_info.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void main() {
  check(
    tiktokIdFrom('https://www.tiktok.com/@user/video/7234567890123456789') ==
        '7234567890123456789',
    'tiktok video id',
  );
  check(tiktokIdFrom('https://vm.tiktok.com/ZMabc123/') == null, 'short link needs resolve');
  check(isTikTokShortLink(Uri.parse('https://vm.tiktok.com/ZMabc123/')), 'vm short link');
  check(isTikTokShortLink(Uri.parse('https://www.tiktok.com/t/ZTabc/')), '/t/ short link');
  check(embedInfoFor('https://www.tiktok.com/@u/video/7234567890123456789').isPortrait, 'tiktok is portrait');
  check(embedInfoFor('https://www.facebook.com/reel/123456').isPortrait, 'reel is portrait');
  check(!embedInfoFor('https://www.facebook.com/watch/?v=123456').isPortrait, 'watch is landscape');
  check(embedInfoFor('https://fb.watch/abc123/').kind == EmbedKind.facebook, 'fb.watch');
  check(embedInfoFor('https://www.youtube.com/shorts/efzxdQeODpU').isPortrait, 'shorts portrait');
  check(embedInfoFor('https://example.com/x').kind == EmbedKind.generic, 'generic');
  final fb = facebookEmbedUrl('https://m.facebook.com/watch/?v=123456');
  check(fb.startsWith('https://www.facebook.com/plugins/video.php?href='), 'fb plugin url');
  check(fb.contains('www.facebook.com%2Fwatch'), 'm. host normalised');
  print('embed_info checks passed');
}
