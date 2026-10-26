/// Only HTTP(S) URLs are accepted; pasted iframe markup is treated as text.
List<String> fanPostLinks(String text) {
  final links = <String>{};
  for (final m in RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  ).allMatches(text)) {
    final raw = m
        .group(0)!
        .replaceFirst(RegExp(r'[.,;!?)\]]+$'), '')
        .replaceAll('&amp;', '&');
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
    links.add(raw);
    if (links.length == 3) break;
  }
  return links.toList();
}

String fanVideoUrl(String raw) {
  final u = Uri.parse(raw), host = Uri.parse(raw).host.toLowerCase();
  String? id;
  if (host == 'youtu.be') id = u.pathSegments.firstOrNull;
  if (host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com')) {
    id = u.queryParameters['v'];
    if (id == null &&
        u.pathSegments.length > 1 &&
        ['embed', 'shorts', 'live'].contains(u.pathSegments.first))
      id = u.pathSegments[1];
  }
  if (id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
    return Uri.https('www.youtube.com', '/embed/$id', {
      'playsinline': '1',
      'rel': '0',
      'origin': 'https://deeprowss.com',
    }).toString();
  }
  if ((host.startsWith('filemoon.') || host.startsWith('www.filemoon.')) &&
      u.pathSegments.length > 1 &&
      u.pathSegments.first == 'd') {
    return u.replace(path: '/e/${u.pathSegments.skip(1).join('/')}').toString();
  }
  return raw;
}
