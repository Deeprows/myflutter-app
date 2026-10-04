import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/channel.dart';
import '../models/fixture.dart';
import '../models/highlight.dart';
import '../models/movie.dart';

/// Loads fixtures and highlights. Order of preference:
/// remote feed (when asked) -> last cached remote copy -> bundled asset.
class FeedService {
  Future<List<Fixture>> loadFixtures({bool remote = false}) async {
    final raw = await _list(
      asset: 'assets/data/fixtures.json',
      cacheKey: 'cache_fixtures',
      remoteUrl: AppConfig.fixturesUrl,
      remote: remote,
    );
    return raw.map(Fixture.tryParse).whereType<Fixture>().toList();
  }

  Future<List<Highlight>> loadHighlights({bool remote = false}) async {
    final raw = await _list(
      asset: 'assets/data/highlights.json',
      cacheKey: 'cache_highlights',
      remoteUrl: AppConfig.highlightsUrl,
      remote: remote,
    );
    final list = raw.map(Highlight.tryParse).whereType<Highlight>().toList();
    list.sort((a, b) {
      final da = a.date, db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  Future<List<Channel>> loadChannels({bool remote = false}) async {
    final raw = await _list(
      asset: 'assets/data/tv.json',
      cacheKey: 'cache_tv',
      remoteUrl: AppConfig.tvUrl,
      remote: remote,
    );
    return raw.map(Channel.tryParse).whereType<Channel>().toList();
  }

  Future<List<Movie>> loadMovies({bool remote = false}) async {
    final raw = await _list(
      asset: 'assets/data/movies.json',
      cacheKey: 'cache_movies',
      remoteUrl: AppConfig.moviesUrl,
      remote: remote,
    );
    final seen = <String>{};
    final list = raw
        .map(Movie.tryParse)
        .whereType<Movie>()
        .where((m) => seen.add(m.url))
        .toList();
    list.sort((a, b) {
      final da = a.date, db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  Future<List<dynamic>> _list({
    required String asset,
    required String cacheKey,
    required String remoteUrl,
    required bool remote,
  }) async {
    if (remote && remoteUrl.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(remoteUrl))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = _decode(utf8.decode(res.bodyBytes));
          if (data.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(cacheKey, jsonEncode(data));
            return data;
          }
        }
      } catch (_) {
        // fall through to cache / bundled copy
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final data = _decode(cached);
        if (data.isNotEmpty) return data;
      }
    } catch (_) {}
    return _decode(await rootBundle.loadString(asset));
  }

  List<dynamic> _decode(String body) {
    final d = jsonDecode(body);
    if (d is List) return d;
    if (d is Map) {
      for (final k in const [
        'fixtures',
        'matches',
        'highlights',
        'movies',
        'channels',
        'items'
      ]) {
        if (d[k] is List) return d[k] as List;
      }
    }
    return const [];
  }
}

final feed = FeedService();
