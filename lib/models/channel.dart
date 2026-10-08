import 'package:flutter/material.dart';

enum ChannelCategory {
  sports,
  movies,
  music,
  news,
  kids,
  entertainment,
  documentary,
  lifestyle,
  religious,
  general,
  other
}

extension ChannelCategoryX on ChannelCategory {
  String get label {
    switch (this) {
      case ChannelCategory.sports:
        return 'Sports';
      case ChannelCategory.movies:
        return 'Movies';
      case ChannelCategory.music:
        return 'Music';
      case ChannelCategory.news:
        return 'News';
      case ChannelCategory.kids:
        return 'Kids';
      case ChannelCategory.entertainment:
        return 'Entertainment';
      case ChannelCategory.documentary:
        return 'Documentary';
      case ChannelCategory.lifestyle:
        return 'Lifestyle';
      case ChannelCategory.religious:
        return 'Religious';
      case ChannelCategory.general:
        return 'General';
      case ChannelCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ChannelCategory.sports:
        return Icons.sports_soccer_rounded;
      case ChannelCategory.movies:
        return Icons.movie_outlined;
      case ChannelCategory.music:
        return Icons.music_note_rounded;
      case ChannelCategory.news:
        return Icons.newspaper_rounded;
      case ChannelCategory.kids:
        return Icons.child_care_rounded;
      case ChannelCategory.entertainment:
        return Icons.theater_comedy_rounded;
      case ChannelCategory.documentary:
        return Icons.travel_explore_rounded;
      case ChannelCategory.lifestyle:
        return Icons.spa_rounded;
      case ChannelCategory.religious:
        return Icons.church_rounded;
      case ChannelCategory.general:
        return Icons.tv_rounded;
      case ChannelCategory.other:
        return Icons.live_tv_rounded;
    }
  }
}

class Channel {
  final String name;
  final String url;
  final ChannelCategory category;

  /// Optional extras (filled for IPTV Nexus channels).
  final String? id;
  final String? logo;
  final String? country; // ISO code, e.g. "US"
  final String? quality; // e.g. "1080p"
  final double score; // 0-100 health score (0 when unknown)

  /// Headers some hosts require. [referer] is used as the player page origin.
  final String? referer;
  final String? userAgent;

  /// Backup stream (next best working stream of the same channel).
  final String? altUrl;
  final String? altReferer;
  final String? altUserAgent;

  const Channel({
    required this.name,
    required this.url,
    required this.category,
    this.id,
    this.logo,
    this.country,
    this.quality,
    this.score = 0,
    this.referer,
    this.userAgent,
    this.altUrl,
    this.altReferer,
    this.altUserAgent,
  });

  static String? _opt(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static ChannelCategory categoryOf(String raw) {
    final c = raw.trim().toLowerCase();
    return ChannelCategory.values.firstWhere(
      (e) => e.name == c,
      orElse: () => ChannelCategory.other,
    );
  }

  static Channel? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    final url = (raw['url'] ?? '').toString().trim();
    if (name.isEmpty || url.isEmpty) return null;
    return Channel(
      name: name,
      url: url,
      category: categoryOf((raw['category'] ?? '').toString()),
      id: _opt(raw['id']),
      logo: _opt(raw['logo']),
      country: _opt(raw['country']),
      quality: _opt(raw['quality']),
      score: raw['score'] is num ? (raw['score'] as num).toDouble() : 0,
      referer: _opt(raw['referer']),
      userAgent: _opt(raw['userAgent']),
      altUrl: _opt(raw['altUrl']),
      altReferer: _opt(raw['altReferer']),
      altUserAgent: _opt(raw['altUserAgent']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'category': category.name,
        if (id != null) 'id': id,
        if (logo != null) 'logo': logo,
        if (country != null) 'country': country,
        if (quality != null) 'quality': quality,
        if (score > 0) 'score': score,
        if (referer != null) 'referer': referer,
        if (userAgent != null) 'userAgent': userAgent,
        if (altUrl != null) 'altUrl': altUrl,
        if (altReferer != null) 'altReferer': altReferer,
        if (altUserAgent != null) 'altUserAgent': altUserAgent,
      };

  Channel copyWith({
    String? logo,
    String? country,
    String? quality,
    double? score,
    String? altUrl,
    String? altReferer,
    String? altUserAgent,
  }) =>
      Channel(
        name: name,
        url: url,
        category: category,
        id: id,
        logo: logo ?? this.logo,
        country: country ?? this.country,
        quality: quality ?? this.quality,
        score: score ?? this.score,
        referer: referer,
        userAgent: userAgent,
        altUrl: altUrl ?? this.altUrl,
        altReferer: altReferer ?? this.altReferer,
        altUserAgent: altUserAgent ?? this.altUserAgent,
      );

  /// "1080p" -> "FHD", "720p" -> "HD", "480p" -> "SD", "2160p" -> "4K".
  String get qualityLabel {
    final n = int.tryParse(
        RegExp(r'\d+').firstMatch(quality ?? '')?.group(0) ?? '');
    if (n == null) return '';
    if (n >= 2160) return '4K';
    if (n >= 1080) return 'FHD';
    if (n >= 720) return 'HD';
    return 'SD';
  }

  /// "US" -> flag emoji. Empty when the code is not two letters.
  String get flag {
    final c = (country ?? '').toUpperCase();
    if (c.length != 2) return '';
    final a = c.codeUnitAt(0), b = c.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '';
    return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
  }
}
