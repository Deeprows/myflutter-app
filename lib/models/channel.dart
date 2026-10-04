import 'package:flutter/material.dart';

enum ChannelCategory { sports, movies, music, news, other }

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
      case ChannelCategory.other:
        return Icons.live_tv_rounded;
    }
  }
}

class Channel {
  final String name;
  final String url;
  final ChannelCategory category;

  const Channel({
    required this.name,
    required this.url,
    required this.category,
  });

  static Channel? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    final url = (raw['url'] ?? '').toString().trim();
    if (name.isEmpty || url.isEmpty) return null;
    final c = (raw['category'] ?? '').toString().trim().toLowerCase();
    final cat = ChannelCategory.values.firstWhere(
      (e) => e.name == c,
      orElse: () => ChannelCategory.other,
    );
    return Channel(name: name, url: url, category: cat);
  }
}
