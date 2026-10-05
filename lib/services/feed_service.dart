import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class FeedService {
  static const String _fixturesCacheKey = 'cache_fixtures';
  static const String _highlightsCacheKey = 'cache_highlights';
  static const String _moviesCacheKey = 'cache_movies';
  static const String _tvCacheKey = 'cache_tv';
  static const String _tickerCacheKey = 'cache_ticker';

  /// Loads a JSON feed.
  ///
  /// Order:
  /// 1. Remote URL, when configured.
  /// 2. Previously cached remote data.
  /// 3. Bundled asset.
  ///
  /// Remote requests use cache-busting + no-cache headers so updated
  /// GitHub raw files are picked up immediately.
  static Future<List<dynamic>> loadFeed({
    required String assetPath,
    required String remoteUrl,
    required String cacheKey,
    bool remote = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try the remote feed first.
    if (remote && remoteUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(remoteUrl).replace(
          queryParameters: {
            ...Uri.parse(remoteUrl).queryParameters,
            '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );

        final response = await http.get(
          uri,
          headers: const {
            'Cache-Control': 'no-cache, no-store, max-age=0',
            'Pragma': 'no-cache',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = _decode(
            utf8.decode(response.bodyBytes),
          );

          if (decoded.isNotEmpty) {
            // Save the newest valid remote data.
            await prefs.setString(
              cacheKey,
              jsonEncode(decoded),
            );

            return decoded;
          }
        }
      } catch (_) {
        // Remote failed. Continue to cache/asset fallback.
      }
    }

    // 2. Try previously cached remote data.
    try {
      final cached = prefs.getString(cacheKey);

      if (cached != null && cached.isNotEmpty) {
        final decoded = _decode(cached);

        if (decoded.isNotEmpty) {
          return decoded;
        }
      }
    } catch (_) {
      // Ignore cache errors and continue to bundled asset.
    }

    // 3. Finally load the bundled JSON from assets.
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = _decode(raw);

      if (decoded.isNotEmpty) {
        return decoded;
      }
    } catch (_) {
      // Ignore asset errors.
    }

    return <dynamic>[];
  }

  static List<dynamic> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded;
      }

      // Also support a JSON object containing a data/items/results array.
      if (decoded is Map<String, dynamic>) {
        for (final key in const [
          'data',
          'items',
          'results',
          'fixtures',
          'matches',
        ]) {
          final value = decoded[key];

          if (value is List) {
            return value;
          }
        }
      }
    } catch (_) {
      // Invalid JSON.
    }

    return <dynamic>[];
  }

  static Future<List<dynamic>> loadFixtures({
    bool remote = true,
  }) {
    return loadFeed(
      assetPath: 'assets/data/fixtures.json',
      remoteUrl: AppConfig.fixturesUrl,
      cacheKey: _fixturesCacheKey,
      remote: remote,
    );
  }

  static Future<List<dynamic>> loadHighlights({
    bool remote = true,
  }) {
    return loadFeed(
      assetPath: 'assets/data/highlights.json',
      remoteUrl: AppConfig.highlightsUrl,
      cacheKey: _highlightsCacheKey,
      remote: remote,
    );
  }

  static Future<List<dynamic>> loadMovies({
    bool remote = true,
  }) {
    return loadFeed(
      assetPath: 'assets/data/movies.json',
      remoteUrl: AppConfig.moviesUrl,
      cacheKey: _moviesCacheKey,
      remote: remote,
    );
  }

  static Future<List<dynamic>> loadTv({
    bool remote = true,
  }) {
    return loadFeed(
      assetPath: 'assets/data/tv.json',
      remoteUrl: AppConfig.tvUrl,
      cacheKey: _tvCacheKey,
      remote: remote,
    );
  }

  static Future<List<dynamic>> loadTicker({
    bool remote = true,
  }) {
    return loadFeed(
      assetPath: 'assets/data/ticker.json',
      remoteUrl: AppConfig.tickerUrl,
      cacheKey: _tickerCacheKey,
      remote: remote,
    );
  }
}
