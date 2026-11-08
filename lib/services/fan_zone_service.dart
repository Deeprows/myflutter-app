import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'auth_service.dart';
import 'install_id.dart';
import 'subscription_service.dart';
import '../models/fixture.dart';

/// Uses the signed-in Google identity. The server verifies every ID token.
class FanZoneService {
  static String matchKey(Fixture f) =>
      '${f.id}|${f.kickoff.millisecondsSinceEpoch}';
  static Future<String> _token({bool refresh = false}) =>
      AuthService.instance.idToken(refresh: refresh);
  static String get _blockedKey =>
      'fan_zone_blocked_${AuthService.instance.user?.id ?? 'signed_out'}';

  static Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.feedBase}/fan/$path',
      ).replace(queryParameters: query);
      final installId = await InstallId.get();
      Future<http.Response> send(String token) async {
        final headers = {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
          // Lets the server see a paid subscription and show the blue tick.
          'x-install-id': installId,
        };
        // Reads are safe to repeat: one quiet retry on a slow/dropped connection.
        try {
          return await (body == null
                  ? http.get(uri, headers: headers)
                  : http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(timeout);
        } on TimeoutException {
          if (body != null) rethrow;
          return await http.get(uri, headers: headers).timeout(timeout);
        } on http.ClientException {
          if (body != null) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return await http.get(uri, headers: headers).timeout(timeout);
        }
      }

      var response = await send(await _token());
      if (response.statusCode == 401) {
        // The Google token was rejected (usually expired): get a new one once.
        response = await send(await _token(refresh: true));
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw Exception('Fan Zone is unavailable right now. Please try again later.');
      }
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Fan Zone is unavailable.');
      }
      return data;
    } on FormatException {
      throw Exception('Fan Zone is unavailable right now. Please try again later.');
    }
  }

  static String handle(String id) =>
      'fan_${id.length <= 12 ? id : id.substring(0, 12)}';

  /// The @username shown for a fan: the one they chose (sent by the server as
  /// `handle`), otherwise the generated default.
  static String handleOf(Map m, String id) {
    final h = '${m['handle'] ?? ''}'.trim();
    return h.isNotEmpty ? h : handle(id);
  }

  /// Sets the signed-in fan's @username. Throws with the server's message.
  static Future<String> setHandle(String handle) async {
    final data = await call('social/handle', body: {'handle': handle});
    return '${data['handle'] ?? handle}';
  }

  /// Premium awarded by the weekly Fan Zone leaderboard (separate from a paid
  /// ad-free subscription). The Worker is authoritative for the expiry.
  static Future<bool> hasWeeklyPremium() async {
    try {
      final data = await call('premium/status');
      return data['premium'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Editing posts and comments is for Premium members: a paid subscription on
  /// this install, or the weekly Fan Zone premium. The Worker checks it again.
  static Future<bool> canEditContent() async {
    if (SubscriptionService.instance.isPremium) return true;
    return hasWeeklyPremium();
  }

  static Future<Map<String, dynamic>> editPost(String id, String text) async =>
      call(
        'post/edit',
        body: {'id': id, 'text': text, 'install_id': await InstallId.get()},
      );

  static Future<Map<String, dynamic>> editComment(String id, String text) async =>
      call(
        'social/comment-edit',
        body: {'id': id, 'text': text, 'install_id': await InstallId.get()},
      );

  static String postUrl(String postId) =>
      '${AppConfig.feedBase}/fan/share/${Uri.encodeComponent(postId)}';

  static String imageUrl(String postId) =>
      '${AppConfig.feedBase}/fan/image/${Uri.encodeComponent(postId)}';

  /// Image or GIF attached to a reply (comment).
  static String commentImageUrl(String commentId) =>
      '${AppConfig.feedBase}/fan/comment-image/${Uri.encodeComponent(commentId)}';

  /// Public URL of a fan's profile photo or cover photo. [version] is the
  /// upload time the server reports, so a new upload is a new URL.
  static String profileImageUrl(String userId, String kind, num version) =>
      '${AppConfig.feedBase}/fan/profile-image/${Uri.encodeComponent(userId)}/$kind?v=${version.toInt()}';

  /// The avatar URL, or null when the fan has not uploaded a photo.
  static String? avatarUrl(String userId, dynamic version) =>
      userId.isNotEmpty && version is num && version > 0
      ? profileImageUrl(userId, 'avatar', version)
      : null;

  /// Uploads a profile photo ([kind] = 'avatar') or cover photo ('cover').
  static Future<void> uploadProfileImage({
    required String kind,
    required Uint8List image,
  }) async {
    if (image.length > 4 * 1024 * 1024) {
      throw Exception('Choose an image smaller than 4 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.feedBase}/fan/profile/image'),
    );
    request.headers['authorization'] = 'Bearer ${await _token()}';
    request.fields['kind'] = kind;
    request.files.add(
      http.MultipartFile.fromBytes('image', image, filename: 'fan-$kind'),
    );
    final response = await request.send().timeout(const Duration(seconds: 45));
    final body = await response.stream.bytesToString().timeout(
      const Duration(seconds: 20),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Photo upload is unavailable right now. Please try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not upload your photo.');
    }
  }

  static Future<void> publish({
    required String kind,
    required String text,
    Uint8List? image,
    String? matchKey,
    Map<String, dynamic>? matchFixture,
    String? quoteOf,
    bool isAd = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.feedBase}/fan/post'),
    );
    request.headers['authorization'] = 'Bearer ${await _token()}';
    request.fields.addAll({
      'kind': kind,
      'text': text.trim(),
      if (matchKey != null) 'match_key': matchKey,
      if (matchFixture != null) 'match_fixture': jsonEncode(matchFixture),
      if (quoteOf != null && quoteOf.isNotEmpty) 'quote_of': quoteOf,
      if (isAd) 'is_ad': '1',
    });
    if (image != null) {
      if (image.length > 4 * 1024 * 1024) {
        throw Exception('Choose an image smaller than 4 MB.');
      }
      request.files.add(
        http.MultipartFile.fromBytes('image', image, filename: 'fan-image'),
      );
    }
    final response = await request.send().timeout(const Duration(seconds: 45));
    final body = await response.stream.bytesToString().timeout(
      const Duration(seconds: 20),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Upload is unavailable right now. Please try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not publish your post.');
    }
  }

  /// Posts a reply. [parentId] makes it a reply to another comment; [image]
  /// may be a JPG, PNG or GIF (up to 4 MB).
  static Future<void> postComment({
    required String postId,
    String text = '',
    String? parentId,
    Uint8List? image,
  }) async {
    if (image != null && image.length > 4 * 1024 * 1024) {
      throw Exception('Choose an image smaller than 4 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.feedBase}/fan/social/comment'),
    );
    request.headers['authorization'] = 'Bearer ${await _token()}';
    request.fields.addAll({
      'id': postId,
      'text': text.trim(),
      if (parentId != null && parentId.isNotEmpty) 'parent_id': parentId,
    });
    if (image != null) {
      request.files.add(
        http.MultipartFile.fromBytes('image', image, filename: 'reply-image'),
      );
    }
    final response = await request.send().timeout(const Duration(seconds: 45));
    final body = await response.stream.bytesToString().timeout(
      const Duration(seconds: 20),
    );
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Reply is unavailable right now. Please try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not post your reply.');
    }
  }

  /// Admin only: pins a post to the top of the Thread page as "Sponsored"
  /// for [days] days (0 = until unpinned), or removes the pin.
  static Future<void> pinPost(
    String postId, {
    required bool pinned,
    int days = 0,
  }) async {
    await call(
      'post/pin',
      body: {'id': postId, 'pinned': pinned, if (pinned) 'days': days},
    );
  }

  /// Counts a view of a post (one per fan). Never throws: views are best effort.
  static Future<int?> recordView(String postId) async {
    try {
      final data = await call('social/view', body: {'id': postId});
      return (data['views'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  static Future<Set<String>> blocked() async =>
      (await SharedPreferences.getInstance())
          .getStringList(_blockedKey)
          ?.toSet() ??
      <String>{};
  static Future<void> block(String id) async {
    final ids = await blocked();
    ids.add(id);
    await (await SharedPreferences.getInstance()).setStringList(
      _blockedKey,
      ids.toList(),
    );
  }

  static Future<void> unblockAll() async {
    await (await SharedPreferences.getInstance()).remove(_blockedKey);
  }
}
