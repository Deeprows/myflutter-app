import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class SportsNewsArticle {
  final String title, url, source;
  final String? image;
  final DateTime publishedAt;
  const SportsNewsArticle({
    required this.title,
    required this.url,
    required this.source,
    required this.publishedAt,
    this.image,
  });
  static SportsNewsArticle? parse(dynamic raw) {
    if (raw is! Map || raw['published_at'] is! num) return null;
    final url = Uri.tryParse('${raw['url']}'),
        title = '${raw['title'] ?? ''}'.trim();
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        title.isEmpty)
      return null;
    return SportsNewsArticle(
      title: title,
      url: url.toString(),
      source: '${raw['source'] ?? 'Sports news'}',
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['published_at'] as num).toInt(),
      ),
      image: raw['image'] is String ? raw['image'] as String : null,
    );
  }
}

class SportsNewsFeed {
  final List<SportsNewsArticle> items;
  final bool stale, partial, unavailable;
  const SportsNewsFeed(
    this.items, {
    this.stale = false,
    this.partial = false,
    this.unavailable = false,
  });
}

class SportsNewsService {
  static Future<SportsNewsFeed> load(String category) async {
    final uri = Uri.parse(
      '${AppConfig.feedBase}/sports-news',
    ).replace(queryParameters: {'category': category});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200)
      throw Exception(
        'News is unavailable. Check that the updated Worker is deployed.',
      );
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map || data['items'] is! List)
      throw Exception('News needs the updated Cloudflare Worker.');
    return SportsNewsFeed(
      (data['items'] as List)
          .map(SportsNewsArticle.parse)
          .whereType<SportsNewsArticle>()
          .toList(),
      stale: data['stale'] == true,
      partial: data['partial'] == true,
      unavailable: data['unavailable'] == true,
    );
  }
}
