import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class SportsReel {
  final String id, title, channel, category, thumb;
  final DateTime publishedAt;
  final int views;
  const SportsReel({
    required this.id,
    required this.title,
    required this.channel,
    required this.category,
    required this.thumb,
    required this.publishedAt,
    required this.views,
  });

  String get watchUrl => 'https://www.youtube.com/shorts/$id';

  static SportsReel? parse(dynamic raw) {
    if (raw is! Map || raw['published_at'] is! num) return null;
    final id = '${raw['id'] ?? ''}', title = '${raw['title'] ?? ''}'.trim();
    if (!RegExp(r'^[\w-]{11}$').hasMatch(id) || title.isEmpty) return null;
    return SportsReel(
      id: id,
      title: title,
      channel: '${raw['channel'] ?? 'Sports'}',
      category: '${raw['category'] ?? 'other'}',
      thumb: '${raw['thumb'] ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'}',
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['published_at'] as num).toInt(),
      ),
      views: raw['views'] is num ? (raw['views'] as num).toInt() : 0,
    );
  }
}

class SportsReelsFeed {
  final List<SportsReel> items;
  final bool unavailable;
  const SportsReelsFeed(this.items, {this.unavailable = false});
}

class SportsReelsService {
  /// [category] is `all`, `football`, `cricket`, `f1` or `other`.
  static Future<SportsReelsFeed> load(String category) async {
    final uri = Uri.parse(
      '${AppConfig.feedBase}/sports-reels',
    ).replace(queryParameters: {'category': category});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Reels need the updated Cloudflare Worker.');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map || data['items'] is! List) {
      throw Exception('Reels need the updated Cloudflare Worker.');
    }
    return SportsReelsFeed(
      (data['items'] as List)
          .map(SportsReel.parse)
          .whereType<SportsReel>()
          .toList(),
      unavailable: data['unavailable'] == true,
    );
  }
}
