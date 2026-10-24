import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/fixture.dart';

/// Private bearer credential, separate from the public analytics install ID.
class FanZoneService {
  static Future<String>? _credential;
  static String matchKey(Fixture f) =>
      '${f.id}|${f.kickoff.millisecondsSinceEpoch}';

  static Future<String> _token() => _credential ??= _loadToken();
  static Future<String> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString('fan_zone_token');
    if (token == null) {
      final random = Random.secure();
      token = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      if (!await prefs.setString('fan_zone_token', token)) {
        throw Exception('Could not save your Fan Zone identity.');
      }
    }
    return token;
  }

  static Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final token = await _token();
      final uri = Uri.parse('${AppConfig.feedBase}/fan/$path')
          .replace(queryParameters: query);
      final headers = {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      };
      final response =
          await (body == null
                  ? http.get(uri, headers: headers)
                  : http.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 20));
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

  static String imageUrl(String postId) =>
      '${AppConfig.feedBase}/fan/image/${Uri.encodeComponent(postId)}';

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
          .getStringList('fan_zone_blocked')
          ?.toSet() ??
      <String>{};
  static Future<void> block(String id) async {
    final ids = await blocked();
    ids.add(id);
    await (await SharedPreferences.getInstance()).setStringList(
      'fan_zone_blocked',
      ids.toList(),
    );
  }

  static Future<void> unblockAll() async {
    await (await SharedPreferences.getInstance()).remove('fan_zone_blocked');
  }
}
