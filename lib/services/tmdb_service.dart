import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/movie.dart';

/// Talks to TMDB (api.themoviedb.org, v3) and turns its results into [Movie]s.
///
/// Every title is keyed by its TMDB id:
///   player   -> `<AppConfig.embedBase>/movie|tv/<id>`
///   download -> `<AppConfig.downloadBase>/movie|tv/<id>`
class TmdbService {
  static bool get enabled => AppConfig.tmdbApiKey.isNotEmpty;

  static const _detailsKey = 'cache_tmdb_details';
  static const _trendingKey = 'cache_tmdb_trending';

  static const _genres = <int, String>{
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
    10759: 'Action & Adventure',
    10762: 'Kids',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
  };

  Future<dynamic> _get(String path, [Map<String, String> query = const {}]) async {
    try {
      final uri = Uri.https('api.themoviedb.org', '/3$path', {
        'api_key': AppConfig.tmdbApiKey,
        'language': 'en-US',
        ...query,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// One TMDB result (list item or details) -> [Movie]. [type] is used when
  /// the result has no `media_type` of its own ("movie" or "tv").
  static Movie? fromJson(dynamic raw, {String type = 'movie'}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! int) return null;
    final mediaType = (raw['media_type'] ?? type).toString();
    if (mediaType != 'movie' && mediaType != 'tv') return null; // e.g. person
    final tv = mediaType == 'tv';

    final title =
        (raw[tv ? 'name' : 'title'] ?? raw['title'] ?? raw['name'] ?? '')
            .toString()
            .trim();
    if (title.isEmpty) return null;

    final dateStr =
        (raw[tv ? 'first_air_date' : 'release_date'] ?? '').toString();
    final year = dateStr.length >= 4 ? dateStr.substring(0, 4) : null;

    final genres = <String>[];
    if (raw['genres'] is List) {
      for (final g in raw['genres'] as List) {
        if (g is Map && g['name'] != null) genres.add(g['name'].toString());
      }
    } else if (raw['genre_ids'] is List) {
      for (final g in raw['genre_ids'] as List) {
        final n = _genres[g];
        if (n != null) genres.add(n);
      }
    }

    final vote = raw['vote_average'];
    final rating = (vote is num && vote > 0)
        ? Movie.parseRating('${vote.toStringAsFixed(1)}/10')
        : null;
    final poster = (raw['poster_path'] ?? '').toString();

    return Movie(
      name: year == null ? title : '$title ($year)',
      url: Movie.embedUrlFor(id, tv: tv),
      downloadUrl: Movie.downloadUrlFor(id, tv: tv),
      date: null, // keep "Added <date>" for rows you add yourself
      rating: rating,
      genres: genres,
      image: poster.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$poster',
      tmdbId: id,
    );
  }

  /// Fills in a row that only has a TMDB id. Uses the saved copy when
  /// [fetch] is false (or the request fails).
  Future<Movie?> details(int id, {required bool tv, bool fetch = true}) async {
    final key = '${tv ? 'tv' : 'movie'}:$id';
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> cache = {};
    try {
      final c = prefs.getString(_detailsKey);
      if (c != null) cache = Map<String, dynamic>.from(jsonDecode(c) as Map);
    } catch (_) {}

    if (fetch) {
      final d = await _get('/${tv ? 'tv' : 'movie'}/$id');
      if (d is Map && d['id'] == id) {
        cache[key] = d;
        await prefs.setString(_detailsKey, jsonEncode(cache));
      }
    }
    return fromJson(cache[key], type: tv ? 'tv' : 'movie');
  }

  /// Trending movies + series this week (about 40). Without [fetch] only the
  /// last saved copy is returned, so the first paint never waits on TMDB.
  Future<List<Movie>> trending({bool fetch = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (fetch) {
      final pages = await Future.wait([
        _get('/trending/all/week', {'page': '1'}),
        _get('/trending/all/week', {'page': '2'}),
      ]);
      final all = <dynamic>[];
      for (final p in pages) {
        if (p is Map && p['results'] is List) all.addAll(p['results'] as List);
      }
      if (all.isNotEmpty) await prefs.setString(_trendingKey, jsonEncode(all));
    }
    try {
      final c = prefs.getString(_trendingKey);
      if (c == null) return const [];
      return (jsonDecode(c) as List)
          .map((e) => fromJson(e))
          .whereType<Movie>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Searches movies and series on TMDB.
  Future<List<Movie>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final d = await _get('/search/multi', {'query': q, 'include_adult': 'false'});
    if (d is! Map || d['results'] is! List) return const [];
    return (d['results'] as List)
        .map((e) => fromJson(e))
        .whereType<Movie>()
        .toList();
  }
}

final tmdb = TmdbService();
