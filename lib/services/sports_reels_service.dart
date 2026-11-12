import 'dart:convert';
import 'dart:math' show Random;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../config.dart';
import '../utils/currency_map.dart';

/// One reel. YouTube reels have no [embedUrl] and play on the Shorts page;
/// PeerTube / RSS / own videos play in their [embedUrl] player.
class SportsReel {
  final String id, title, channel, category, thumb;
  final DateTime publishedAt;
  final int views;

  /// Player page for non-YouTube videos (null for YouTube).
  final String? embedUrl;

  /// Normal web page of the video, used by "Open in browser".
  final String? pageUrl;

  const SportsReel({
    required this.id,
    required this.title,
    required this.channel,
    required this.category,
    required this.thumb,
    required this.publishedAt,
    this.views = 0,
    this.embedUrl,
    this.pageUrl,
  });

  bool get isYouTube => embedUrl == null;

  String get watchUrl =>
      pageUrl ?? embedUrl ?? 'https://www.youtube.com/shorts/$id';

  /// "5m ago", "3h ago" ... or '' when the date is unknown.
  String get ago {
    if (publishedAt.millisecondsSinceEpoch <= 0) return '';
    final m = DateTime.now().difference(publishedAt).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '${m}m ago';
    if (m < 60 * 24) return '${m ~/ 60}h ago';
    if (m < 60 * 24 * 7) return '${m ~/ (60 * 24)}d ago';
    if (m < 60 * 24 * 30) return '${m ~/ (60 * 24 * 7)}w ago';
    return '${m ~/ (60 * 24 * 30)}mo ago';
  }

  SportsReel withThumb(String url) => SportsReel(
        id: id,
        title: title,
        channel: channel,
        category: category,
        thumb: url,
        publishedAt: publishedAt,
        views: views,
        embedUrl: embedUrl,
        pageUrl: pageUrl,
      );
}

/// Everything the Reels tab needs: the videos, the tabs (in order) and the
/// title from the config.
class SportsReelsFeed {
  final List<SportsReel> items;
  final List<String> categories;
  final String title;
  final bool enabled;
  final String country;
  final bool unavailable;

  /// Changes with every download, so "For You" does not always open with the
  /// same category.
  final int seed;
  const SportsReelsFeed(
    this.items, {
    this.categories = const [],
    this.title = 'Reels',
    this.enabled = true,
    this.country = '',
    this.unavailable = false,
    this.seed = 0,
  });

  /// Ids of the first reels of a tab, used to tell whether a download brought
  /// anything new.
  String signature(String tab) =>
      forTab(tab).take(12).map((r) => r.id).join(',');

  /// Videos of one tab. `all` = "For You": categories mixed one by one.
  List<SportsReel> forTab(String tab) {
    if (tab != 'all') return items.where((r) => r.category == tab).toList();
    final groups = categories
        .map((c) => items.where((r) => r.category == c).toList())
        .where((g) => g.isNotEmpty)
        .toList();
    if (seed != 0) groups.shuffle(Random(seed));
    final out = <SportsReel>[];
    for (var i = 0; groups.any((g) => g.length > i); i++) {
      for (final g in groups) {
        if (g.length > i) out.add(g[i]);
      }
    }
    return out;
  }

  /// Tab bar: "For You" first, then the categories that have videos.
  List<String> get tabs => [
        'all',
        ...categories.where((c) => items.any((r) => r.category == c)),
      ];

  String label(String key) => SportsReelsService.categoryLabel(key, country);
}

class _Source {
  final String kind, name, category, id, channel, host, url;
  const _Source({
    required this.kind,
    required this.name,
    required this.category,
    this.id = '',
    this.channel = '',
    this.host = '',
    this.url = '',
  });
}

class _Config {
  final bool enabled, shortsOnly;
  final String title;
  final List<_Source> channels, sources;
  final List<SportsReel> custom;
  final Map<String, List<_Source>> regional;
  const _Config({
    required this.enabled,
    required this.shortsOnly,
    required this.title,
    required this.channels,
    required this.sources,
    required this.custom,
    required this.regional,
  });
}

/// Builds the Reels feed on the phone from the public feeds of the sources
/// listed in `assets/data/reels_channels.json` (or [AppConfig.reelsConfigUrl]):
/// YouTube channels (Shorts), PeerTube and RSS video feeds, your
/// own videos, and per-country "Near You" videos. No API key, no Worker.
/// This is the same setup the Deeprowss browser uses for its Reels.
class SportsReelsService {
  static const _asset = 'assets/data/reels_channels.json';
  static const _referer = 'https://deeprows.github.io/';
  static const _perSource = 6;
  static const _limit = 120;
  static const _keep = Duration(minutes: 5);

  static SportsReelsFeed? _cached;
  static DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<SportsReelsFeed>? _running;

  /// Forget the cached feed so the next [load] downloads fresh videos.
  static void invalidate() => _cached = null;

  /// True when the saved feed is older than the cache time (or missing).
  static bool get isStale =>
      _cached == null || DateTime.now().difference(_cachedAt) >= _keep;

  static Future<SportsReelsFeed> load({bool force = false}) {
    final saved = _cached;
    if (!force &&
        saved != null &&
        DateTime.now().difference(_cachedAt) < _keep) {
      return Future.value(saved);
    }
    return _running ??= _build().whenComplete(() => _running = null);
  }

  // ---------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------

  static Future<_Config> _config() async {
    final remote = AppConfig.reelsConfigUrl.trim();
    if (remote.startsWith('https://')) {
      try {
        final res = await http
            .get(Uri.parse(remote))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final cfg = _parseConfig(jsonDecode(utf8.decode(res.bodyBytes)));
          if (cfg != null) return cfg;
        }
      } catch (_) {}
    }
    final text = await rootBundle.loadString(_asset);
    return _parseConfig(jsonDecode(text)) ??
        const _Config(
          enabled: true,
          shortsOnly: true,
          title: 'Reels',
          channels: [],
          sources: [],
          custom: [],
          regional: {},
        );
  }

  static bool _validSource(_Source s) {
    switch (s.kind) {
      case 'youtube':
        return s.id.startsWith('UC') && s.id.length == 24;
      case 'peertube':
        return s.host.isNotEmpty;
      case 'rss':
        return s.url.startsWith('https://');
    }
    return false;
  }

  static _Source? _source(dynamic raw,
      {String? forceCategory, String? forceKind}) {
    if (raw is! Map) return null;
    final kind =
        (forceKind ?? '${raw['kind'] ?? 'youtube'}').trim().toLowerCase();
    final cat =
        (forceCategory ?? '${raw['category'] ?? 'other'}').trim().toLowerCase();
    final s = _Source(
      kind: kind,
      name: '${raw['name'] ?? kind}'.trim(),
      category: cat.isEmpty ? 'other' : cat,
      id: '${raw['id'] ?? ''}'.trim(),
      channel: '${raw['channel'] ?? ''}'.trim(),
      host: '${raw['host'] ?? ''}'.trim(),
      url: '${raw['url'] ?? ''}'.trim(),
    );
    return _validSource(s) ? s : null;
  }

  static _Config? _parseConfig(dynamic root) {
    if (root is! Map) return null;
    final reels = root['reels'] is Map ? root['reels'] as Map : const {};

    final channels = <_Source>[];
    final channelList = root['channels'] ?? root['videoChannels'];
    if (channelList is List) {
      for (final c in channelList) {
        final s = _source(c, forceKind: 'youtube');
        if (s != null) channels.add(s);
      }
    }

    final sources = <_Source>[];
    if (root['videoSources'] is List) {
      for (final c in root['videoSources'] as List) {
        final s = _source(c);
        if (s != null) sources.add(s);
      }
    }

    final regional = <String, List<_Source>>{};
    if (root['regionalVideos'] is Map) {
      (root['regionalVideos'] as Map).forEach((code, list) {
        if (list is! List) return;
        final parsed = <_Source>[];
        for (final c in list) {
          final s = _source(c, forceCategory: 'local');
          if (s != null) parsed.add(s);
        }
        if (parsed.isNotEmpty) {
          regional[code.toString().trim().toUpperCase()] = parsed;
        }
      });
    }

    final custom = <SportsReel>[];
    if (root['customVideos'] is List) {
      for (final v in root['customVideos'] as List) {
        final r = _custom(v);
        if (r != null) custom.add(r);
      }
    }

    if (channels.isEmpty &&
        sources.isEmpty &&
        custom.isEmpty &&
        regional.isEmpty) {
      return null;
    }
    final title = '${reels['title'] ?? ''}'.trim();
    return _Config(
      enabled: reels['enabled'] != false,
      shortsOnly: reels['shortsOnly'] != false,
      title: title.isEmpty ? 'Reels' : title,
      channels: channels,
      sources: sources,
      custom: custom,
      regional: regional,
    );
  }

  /// Your own hand-picked video from the config ("customVideos").
  static SportsReel? _custom(dynamic v) {
    if (v is! Map) return null;
    final url = '${v['url'] ?? ''}'.trim();
    final title = '${v['title'] ?? ''}'.trim();
    if (!url.startsWith('https://') || title.isEmpty) return null;
    final yt = youtubeId(url);
    var cat = '${v['category'] ?? 'other'}'.trim().toLowerCase();
    // There is no separate "Deeprows" tab any more: these videos mix into
    // the normal reels.
    if (cat.isEmpty || cat == 'deeprows') cat = 'other';
    final chan = '${v['channel'] ?? ''}'.trim();
    final thumb = '${v['thumbnail'] ?? ''}'.trim();
    return SportsReel(
      id: yt ?? 'custom-${url.hashCode}',
      title: title,
      channel: chan.isEmpty ? 'Sports' : chan,
      category: cat,
      thumb: thumb.isNotEmpty
          ? thumb
          : (yt != null ? 'https://i.ytimg.com/vi/$yt/hqdefault.jpg' : ''),
      publishedAt: _date('${v['published'] ?? ''}'),
      embedUrl: yt == null ? url : null,
    );
  }

  /// The 11-character id out of any normal YouTube link.
  static String? youtubeId(String url) {
    for (final p in [
      RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
      RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
      RegExp(
          r'youtube(?:-nocookie)?\.com/(?:embed|shorts|live)/([A-Za-z0-9_-]{11})'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Tab names
  // ---------------------------------------------------------------------

  static String categoryLabel(String key, [String country = '']) {
    switch (key.toLowerCase()) {
      case 'all':
        return '\u2728 For You';
      case 'local':
        final code = country.toUpperCase();
        if (code.length != 2) return '\u{1F4CD} Near You';
        final flag = String.fromCharCodes([
          0x1F1E6 + code.codeUnitAt(0) - 65,
          0x1F1E6 + code.codeUnitAt(1) - 65,
        ]);
        final name = countryName(code);
        return name == code ? '$flag Near You' : '$flag $name';
      case 'football':
        return '\u26BD Football';
      case 'cricket':
        return '\u{1F3CF} Cricket';
      case 'f1':
        return '\u{1F3CE}\uFE0F F1';
      case 'sports':
        return '\u26BD Sports';
      case 'other':
        return '\u{1F3C5} More sports';
      default:
        return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
    }
  }

  // ---------------------------------------------------------------------
  // Build the feed
  // ---------------------------------------------------------------------

  /// Dailymotion is not used for Reels any more (its embeds answer
  /// "Forbidden"), whichever source or hand-picked link it comes from.
  static bool _isDailymotion(SportsReel r) =>
      '${r.embedUrl ?? ''} ${r.pageUrl ?? ''}'.toLowerCase().contains('dailymotion.') ||
      '${r.embedUrl ?? ''} ${r.pageUrl ?? ''}'.toLowerCase().contains('dai.ly/');

  static Future<SportsReelsFeed> _build() async {
    final cfg = await _config();
    final country = PlatformDispatcher.instance.locale.countryCode ?? '';
    final local = cfg.regional[country.toUpperCase()] ?? const <_Source>[];

    // Same order as the browser: own videos, Near You, channels, other sources.
    final categories = <String>{
      ...cfg.custom.map((r) => r.category),
      ...local.map((s) => s.category),
      ...cfg.channels.map((s) => s.category),
      ...cfg.sources.map((s) => s.category),
    }.toList();

    if (!cfg.enabled) {
      return SportsReelsFeed(
        const [],
        categories: categories,
        title: cfg.title,
        enabled: false,
        country: country,
      );
    }

    final jobs = <Future<List<SportsReel>>>[
      for (final s in [...cfg.channels, ...cfg.sources, ...local])
        _safe(() => _fetch(s, cfg.shortsOnly)),
    ];
    var fetched = (await Future.wait(jobs)).expand((x) => x).toList();
    // The Shorts-only YouTube feeds can come back empty (blocked, changed or
    // slow). When that happens, fall back to the channels' latest uploads so
    // Reels is never empty.
    if (cfg.shortsOnly && fetched.where((r) => r.isYouTube).length < 8) {
      final more = await Future.wait([
        for (final s in [...cfg.channels, ...cfg.sources, ...local])
          if (s.kind == 'youtube') _safe(() => _fetch(s, false)),
      ]);
      fetched = [...fetched, ...more.expand((x) => x)];
    }
    fetched = fetched.where((r) => !_isDailymotion(r)).toList()
      // Near You wins when the same video is also in a general channel.
      ..sort((a, b) =>
          (b.category == 'local' ? 1 : 0) - (a.category == 'local' ? 1 : 0));
    final seen = <String>{};
    final videos = [
      for (final r in fetched)
        if (seen.add(r.id)) r,
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    // Your own videos always come first, even if YouTube cannot be reached.
    final custom = await Future.wait(
        cfg.custom.where((r) => !_isDailymotion(r)).map(_withThumb));
    final items = [
      ...custom,
      ...videos.where((r) => !custom.any((c) => c.id == r.id)).take(_limit),
    ];

    final feed = SportsReelsFeed(
      items,
      categories: categories,
      title: cfg.title,
      country: country,
      unavailable: items.isEmpty,
      seed: DateTime.now().millisecondsSinceEpoch % 100000 + 1,
    );
    if (items.isNotEmpty) {
      _cached = feed;
      _cachedAt = DateTime.now();
    }
    return feed;
  }

  static Future<List<SportsReel>> _safe(
      Future<List<SportsReel>> Function() job) async {
    try {
      return await job();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<SportsReel>> _fetch(_Source s, bool shortsOnly) {
    switch (s.kind) {
      case 'youtube':
        return _youtube(s, shortsOnly);
      case 'peertube':
        return _peertube(s);
      case 'rss':
        return _rss(s);
    }
    return Future.value(const <SportsReel>[]);
  }

  static Future<String?> _get(String url) async {
    final res = await http.get(Uri.parse(url), headers: {
      'User-Agent': AppConfig.userAgent,
      'Accept': 'application/json, application/xml, text/xml, */*',
    }).timeout(const Duration(seconds: 8));
    return res.statusCode == 200 ? utf8.decode(res.bodyBytes) : null;
  }

  // ---- parsing helpers -------------------------------------------------

  static String _text(String raw) => raw
      .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .trim();

  static String _tag(String block, String name) {
    final m = RegExp('<$name\\b[^>]*>([\\s\\S]*?)</$name>', caseSensitive: false)
        .firstMatch(block);
    return m == null ? '' : _text(m.group(1)!);
  }

  static String _attr(String block, String tag, String attr) {
    final m = RegExp('<(?:$tag)\\b[^>]*\\b$attr\\s*=\\s*["\']([^"\']+)["\']',
            caseSensitive: false)
        .firstMatch(block);
    return m == null ? '' : _text(m.group(1)!);
  }

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// ISO or RSS dates. Epoch 0 when unreadable (sorts last, shows no age).
  static DateTime _date(String raw) {
    final text = raw.trim();
    final zero = DateTime.fromMillisecondsSinceEpoch(0);
    if (text.isEmpty) return zero;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;
    final m = RegExp(
            r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|GMT|UTC|Z)?')
        .firstMatch(text);
    if (m == null) return zero;
    final month = _months.indexOf(m.group(2)!.toLowerCase());
    if (month < 0) return zero;
    var at = DateTime.utc(
      int.parse(m.group(3)!),
      month + 1,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.tryParse(m.group(6) ?? '0') ?? 0,
    );
    final z = m.group(7) ?? '';
    if (z.length == 5) {
      final off = Duration(
        hours: int.parse(z.substring(1, 3)),
        minutes: int.parse(z.substring(3, 5)),
      );
      at = z.startsWith('-') ? at.add(off) : at.subtract(off);
    }
    return at;
  }

  // ---- YouTube ---------------------------------------------------------

  static Future<List<SportsReel>> _youtube(_Source s, bool shortsOnly) async {
    // "UUSH" + the rest of the channel id is that channel's Shorts-only playlist.
    final feed = shortsOnly
        ? 'https://www.youtube.com/feeds/videos.xml?playlist_id=UUSH${s.id.substring(2)}'
        : 'https://www.youtube.com/feeds/videos.xml?channel_id=${s.id}';
    final xml = await _get(feed);
    if (xml == null || xml.length > 700000) return const [];
    final out = <SportsReel>[];
    final entries =
        RegExp(r'<entry\b[^>]*>([\s\S]*?)</entry>', caseSensitive: false);
    for (final m in entries.allMatches(xml)) {
      final e = m.group(1)!;
      final id = _tag(e, 'yt:videoId');
      final title = _tag(e, 'title');
      if (!RegExp(r'^[\w-]{11}$').hasMatch(id) || title.isEmpty) continue;
      final thumb = _attr(e, 'media:thumbnail', 'url');
      out.add(SportsReel(
        id: id,
        title: title,
        channel: s.name.isNotEmpty ? s.name : _tag(_tag(e, 'author'), 'name'),
        category: s.category,
        thumb: thumb.isNotEmpty
            ? thumb
            : 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        publishedAt: _date(_tag(e, 'published')),
        views: int.tryParse(_attr(e, 'media:statistics', 'views')) ?? 0,
      ));
      if (out.length >= _perSource) break;
    }
    return out;
  }

  // ---- PeerTube --------------------------------------------------------

  static Future<List<SportsReel>> _peertube(_Source s) async {
    final host =
        s.host.replaceFirst('https://', '').replaceAll(RegExp(r'/+$'), '');
    if (host.isEmpty) return const [];
    final path = s.id.isNotEmpty
        ? '/api/v1/video-channels/${s.id}/videos'
        : '/api/v1/videos';
    final body = await _get(
        'https://$host$path?count=$_perSource&sort=-publishedAt&nsfw=false');
    if (body == null) return const [];
    final data = (jsonDecode(body) as Map)['data'];
    if (data is! List) return const [];
    final out = <SportsReel>[];
    for (final v in data) {
      if (v is! Map) continue;
      final uuid = '${v['uuid'] ?? ''}';
      final title = '${v['name'] ?? ''}'.trim();
      if (uuid.isEmpty || title.isEmpty || v['isLive'] == true) continue;
      final thumbPath = '${v['previewPath'] ?? v['thumbnailPath'] ?? ''}';
      final embedRaw = '${v['embedPath'] ?? ''}';
      final embedPath = embedRaw.isEmpty ? '/videos/embed/$uuid' : embedRaw;
      final chan = v['channel'] is Map
          ? '${(v['channel'] as Map)['displayName'] ?? ''}'.trim()
          : '';
      out.add(SportsReel(
        id: 'pt-$uuid',
        title: title,
        channel: chan.isEmpty ? s.name : chan,
        category: s.category,
        thumb: thumbPath.isEmpty ? '' : 'https://$host$thumbPath',
        publishedAt: _date('${v['publishedAt'] ?? ''}'),
        embedUrl: 'https://$host$embedPath?autoplay=1',
        pageUrl: 'https://$host/w/$uuid',
      ));
    }
    return out;
  }

  // ---- RSS / Atom / Media RSS -----------------------------------------

  static bool _looksLikeVideo(String url, String type, String medium) {
    if (!url.startsWith('https://')) return false;
    final clean = url.split('?').first.toLowerCase();
    return type.startsWith('video/') ||
        medium == 'video' ||
        clean.endsWith('.mp4') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.m3u8');
  }

  /// Video links in an article page URL that we know how to play.
  static String? _embedFromPage(String link) {
    final vimeo = RegExp(r'vimeo\.com/(?:.*/)?(\d{6,})').firstMatch(link);
    if (vimeo != null) {
      return 'https://player.vimeo.com/video/${vimeo.group(1)}';
    }
    return null;
  }

  static Future<List<SportsReel>> _rss(_Source s) async {
    final xml = await _get(s.url);
    if (xml == null || xml.length > 900000) return const [];
    final out = <SportsReel>[];
    final items = RegExp(r'<(item|entry)\b[^>]*>([\s\S]*?)</\1>',
        caseSensitive: false);
    final media = RegExp(r'<(?:enclosure|media:content)\b[^>]*>',
        caseSensitive: false);
    for (final m in items.allMatches(xml)) {
      final block = m.group(2)!;
      final title = _tag(block, 'title');
      if (title.isEmpty) continue;
      var link = _attr(block, 'link', 'href');
      if (link.isEmpty) link = _tag(block, 'link');
      var date = _tag(block, 'pubDate');
      if (date.isEmpty) date = _tag(block, 'published');
      if (date.isEmpty) date = _tag(block, 'updated');
      var videoUrl = '';
      for (final t in media.allMatches(block)) {
        final tag = t.group(0)!;
        final url = _attr(tag, 'enclosure|media:content', 'url');
        final type =
            _attr(tag, 'enclosure|media:content', 'type').toLowerCase();
        final medium =
            _attr(tag, 'enclosure|media:content', 'medium').toLowerCase();
        if (_looksLikeVideo(url, type, medium)) {
          videoUrl = url;
          break;
        }
      }
      final thumb = _attr(block, 'media:thumbnail', 'url');
      final yt = youtubeId(link);
      final embed = videoUrl.isNotEmpty ? videoUrl : _embedFromPage(link);
      if (yt != null && videoUrl.isEmpty) {
        out.add(SportsReel(
          id: yt,
          title: title,
          channel: s.name,
          category: s.category,
          thumb: thumb.isNotEmpty
              ? thumb
              : 'https://i.ytimg.com/vi/$yt/hqdefault.jpg',
          publishedAt: _date(date),
        ));
      } else if (embed != null) {
        out.add(SportsReel(
          id: 'feed-${embed.hashCode}',
          title: title,
          channel: s.name,
          category: s.category,
          thumb: thumb,
          publishedAt: _date(date),
          embedUrl: embed,
          pageUrl: videoUrl.isEmpty && link.isNotEmpty ? link : null,
        ));
      }
      if (out.length >= _perSource) break;
    }
    return out;
  }

  // ---- thumbnails for own videos --------------------------------------

  static final _thumbPatterns = [
    RegExp(
        r'''<meta[^>]+property=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false),
    RegExp(
        r'''<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']''',
        caseSensitive: false),
    RegExp(
        r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false),
    RegExp(r'''poster=["']([^"']+)["']''', caseSensitive: false),
    RegExp(
        r'''["'](?:image|poster|thumbnail|thumb)["']\s*:\s*["']([^"']+\.(?:jpe?g|png|webp)[^"']*)["']''',
        caseSensitive: false),
  ];

  /// Own videos with no "thumbnail" in the config use the picture the player
  /// page provides itself (og:image, poster ...). Stays '' when none is found.
  static Future<SportsReel> _withThumb(SportsReel r) async {
    final page = r.embedUrl;
    if (r.thumb.isNotEmpty || page == null) return r;
    try {
      final res = await http.get(Uri.parse(page), headers: {
        'User-Agent': AppConfig.userAgent,
        'Referer': _referer,
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return r;
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      final head = html.length > 400000 ? html.substring(0, 400000) : html;
      final u = Uri.parse(page);
      for (final p in _thumbPatterns) {
        final raw = p.firstMatch(head)?.group(1);
        if (raw == null) continue;
        final clean =
            raw.replaceAll(r'\/', '/').replaceAll('&amp;', '&').trim();
        final abs = clean.startsWith('//')
            ? 'https:$clean'
            : clean.startsWith('http')
                ? clean
                : clean.startsWith('/')
                    ? '${u.scheme}://${u.host}$clean'
                    : '';
        if (abs.startsWith('http')) return r.withThumb(abs);
      }
    } catch (_) {}
    return r;
  }
}
