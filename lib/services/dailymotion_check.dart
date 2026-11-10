import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Whether a Dailymotion video may be played inside our player.
enum DailymotionEmbed { ok, blocked, unknown }

/// Dailymotion answers "Forbidden" inside an embed when the video's owner has
/// turned embedding off (or the video is private / removed). We ask Dailymotion's
/// public API first so the app can say so plainly, and so a post is never
/// published with a video nobody can play.
class DailymotionCheck {
  /// The video id from a dailymotion.com/video/…, /embed/video/… or dai.ly link.
  static String? idFrom(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'dai.ly') {
      return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    }
    // Embed code from Dailymotion's Share menu: player.html?video=x8abc12
    final q = uri.queryParameters['video'];
    if (q != null && RegExp(r'^[A-Za-z0-9]+$').hasMatch(q)) return q;
    // Plain /video/x8abc12_title-slug and /embed/video/x8abc12 both work.
    final match = RegExp(r'/(?:embed/)?video/([A-Za-z0-9]+)').firstMatch(uri.path);
    return match?.group(1);
  }

  /// Dailymotion's current player page (the old /embed/video/ path redirects
  /// to it).
  static String playerUrl(String id) =>
      'https://geo.dailymotion.com/player.html?video=$id&autoplay=1';

  static final Map<String, DailymotionEmbed> _cache = {};

  /// [DailymotionEmbed.blocked] only when Dailymotion clearly says the video
  /// cannot be embedded; any network problem is [DailymotionEmbed.unknown] and
  /// the player simply tries to play it.
  static Future<DailymotionEmbed> check(String id) async {
    final cached = _cache[id];
    if (cached != null && cached != DailymotionEmbed.unknown) return cached;
    try {
      final r = await http
          .get(
            Uri.https('api.dailymotion.com', '/video/$id', {
              'fields': 'allow_embed,private,status',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 404 || r.statusCode == 403) {
        return _cache[id] = DailymotionEmbed.blocked;
      }
      if (r.statusCode != 200) return DailymotionEmbed.unknown;
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is! Map) return DailymotionEmbed.unknown;
      final status = data['status'];
      final blocked = data['allow_embed'] == false ||
          data['private'] == true ||
          (status is String && status != 'published');
      return _cache[id] = blocked ? DailymotionEmbed.blocked : DailymotionEmbed.ok;
    } catch (_) {
      return DailymotionEmbed.unknown;
    }
  }
}
