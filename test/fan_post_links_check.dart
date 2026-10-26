// Standalone: dart run test/fan_post_links_check.dart
import '../lib/models/fan_post_link.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void main() {
  check(
    fanVideoUrl('https://youtu.be/efzxdQeODpU').contains('/embed/efzxdQeODpU'),
    'short YouTube',
  );
  check(
    fanVideoUrl(
      'https://www.youtube.com/watch?v=efzxdQeODpU',
    ).contains('/embed/efzxdQeODpU'),
    'watch YouTube',
  );
  check(
    fanVideoUrl(
      'https://www.youtube.com/shorts/efzxdQeODpU',
    ).contains('/embed/efzxdQeODpU'),
    'shorts YouTube',
  );
  check(
    fanVideoUrl('https://filemoon.sx/d/abc/video').contains('/e/abc/video'),
    'Filemoon embed conversion',
  );
  check(
    fanVideoUrl('https://cdn.test/live.m3u8') == 'https://cdn.test/live.m3u8',
    'direct stream preserved',
  );
  check(
    fanPostLinks('No link javascript:bad data:bad').isEmpty,
    'reject non HTTP URLs',
  );
  check(
    fanPostLinks('<iframe src="https://filemoon.sx/e/abc"></iframe>').single ==
        'https://filemoon.sx/e/abc',
    'pasted iframe extracts URL without executing markup',
  );
  check(
    fanPostLinks('https://u:p@example.test/a').isEmpty,
    'reject credential URLs',
  );
  check(
    fanPostLinks('https://example.test/a. https://example.test/a').length == 1,
    'deduplicate and trim punctuation',
  );
  check(
    fanPostLinks(
          'https://1.test https://2.test https://3.test https://4.test',
        ).length ==
        3,
    'bound player card count',
  );
  print(
    'Post links: YouTube variants, Filemoon, direct streams, iframe URL extraction and URL validation passed.',
  );
}
