import 'dart:convert';

import 'package:http/http.dart' as http;

/// On-demand post translation. Uses Google's public web translation endpoint;
/// no API key or account data is sent. Keep the endpoint replaceable if the
/// app later moves translation behind its own Cloudflare Worker.
class PostTranslationService {
  PostTranslationService._();
  static final instance = PostTranslationService._();
  final Map<String, String> _cache = {};

  Future<String> translate(String text, String targetLanguage) async {
    final source = text.trim();
    final target = targetLanguage.trim().toLowerCase();
    if (source.isEmpty) throw Exception('There is no text to translate.');
    if (target.isEmpty) throw Exception('Choose a translation language.');
    if (source.length > 4500) {
      throw Exception('This post is too long to translate at once.');
    }
    final key = '${target}\n$source';
    final cached = _cache[key];
    if (cached != null) return cached;

    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': target,
      'dt': 't',
      'q': source,
    });
    final response = await http.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'Deeprowss/1.0',
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Translation is temporarily unavailable. Please try again.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty || decoded[0] is! List) {
      throw Exception('Could not translate this post.');
    }
    final translated = (decoded[0] as List)
        .whereType<List>()
        .map((part) => part.isNotEmpty ? '${part[0] ?? ''}' : '')
        .join()
        .trim();
    if (translated.isEmpty) throw Exception('Could not translate this post.');
    _cache[key] = translated;
    return translated;
  }
}
