import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'auth_service.dart';
import '../models/fixture.dart';

/// Uses the signed-in Google identity. The server verifies every ID token.
class FanZoneService {
  static String matchKey(Fixture f) =>
      '${f.id}|${f.kickoff.millisecondsSinceEpoch}';
  static Future<String> _token() => AuthService.instance.idToken();
  static String get _blockedKey =>
      'fan_zone_blocked_${AuthService.instance.user?.id ?? 'signed_out'}';

  static Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final token = await _token();
      final uri = Uri.parse(
        '${AppConfig.feedBase}/fan/$path',
      ).replace(queryParameters: query);
      final headers = {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      };
      final response =
          await (body == null
                  ? http.get(uri, headers: headers)
                  : http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(timeout);
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw Exception('Fan Zone received an invalid response.');
      }
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Fan Zone is unavailable.');
      }
      return data;
    } on FormatException {
      throw Exception('Fan Zone needs the updated Cloudflare Worker.');
    }
  }

  static String handle(String id) =>
      'fan_${id.length <= 12 ? id : id.substring(0, 12)}';

  static String postUrl(String postId) =>
      '${AppConfig.feedBase}/fan/share/${Uri.encodeComponent(postId)}';

  static String imageUrl(String postId) =>
      '${AppConfig.feedBase}/fan/image/${Uri.encodeComponent(postId)}';

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
      throw Exception('Photo uploads need the updated Cloudflare Worker.');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not upload your photo.');
    }
  }

  static Future<void> publish({
    required String kind,
    required String text,
    Uint8List? image,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.feedBase}/fan/post'),
    );
    request.headers['authorization'] = 'Bearer ${await _token()}';
    request.fields.addAll({'kind': kind, 'text': text.trim()});
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
      throw Exception('Uploads need the updated Cloudflare Worker.');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not publish your post.');
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
