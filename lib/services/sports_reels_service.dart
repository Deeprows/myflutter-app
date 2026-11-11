import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'auth_service.dart';

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

  static const _api = 'https://www.googleapis.com/youtube/v3/videos';

  /// true = liked, false = not liked, null = unknown (not signed in / error).
  static Future<bool?> isLiked(String id) async {
    final token = await AuthService.instance.youtubeAccessToken();
    if (token == null) return null;
    try {
      final res = await http
          .get(Uri.parse('$_api/getRating?id=$id'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final items = (jsonDecode(res.body) as Map)['items'];
      if (items is List && items.isNotEmpty) {
        return (items.first as Map)['rating'] == 'like';
      }
    } catch (_) {}
    return null;
  }

  /// Likes or un-likes a reel on the user's own YouTube account.
  /// Returns an error message, or null on success.
  static Future<String?> setLike(String id, bool like) async {
    if (!AuthService.instance.signedIn) return 'Log in with Gmail to like reels.';
    final token = await AuthService.instance.youtubeAccessToken();
    if (token == null) return 'Allow YouTube access to like reels.';
    try {
      final res = await http
          .post(Uri.parse('$_api/rate?id=$id&rating=${like ? 'like' : 'none'}'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 204 || res.statusCode == 200) return null;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'YouTube refused the like. Log out and log in again.';
      }
      return 'Could not like this reel. Try again.';
    } catch (_) {
      return 'No connection. Try again.';
    }
  }
}
