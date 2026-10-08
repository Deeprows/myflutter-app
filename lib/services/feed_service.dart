import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/channel.dart';
import '../models/fixture.dart';
import '../models/highlight.dart';
import '../models/movie.dart';
import '../models/ticker.dart';
import '../utils/posted_at.dart';
import 'install_id.dart';
import 'tmdb_service.dart';

/// Loads fixtures and highlights. Order of preference:
/// remote feed (when asked) -> last cached remote copy -> bundled asset.
class FeedService {
  /// True when the last remote download failed and saved/bundled content was
  /// used instead. Read right after a load; the screens show it after a pull.
  bool lastRemoteFailed = false;

  Future<List<Fixture>> loadFixtures({bool remote = false}) async {
    final raw = await _list(
      name: 'fixtures',
      asset: 'assets/data/fixtures.json',
      cacheKey: 'cache_fixtures',
      remoteUrl: AppConfig.fixturesUrl,
      remote: remote,
    );
    return raw.map(Fixture.tryParse).whereType<Fixture>().toList();
  }

  Future<List<Highlight>> loadHighlights({bool remote = false}) async {
    final raw = await _list(
      name: 'highlights',
      asset: 'assets/data/highlights.json',
      cacheKey: 'cache_highlights',
      remoteUrl: AppConfig.highlightsUrl,
      remote: remote,
    );

    final list = raw.map(Highlight.tryParse).whereType<Highlight>().toList();

    // Newest first (date and time), stable for items posted the same day.
    return newestFirst(list, (h) => h.date);
  }

  /// Ticker text: remote (when asked) -> last cached copy -> bundled asset.
  /// Never throws; a broken file just hides the ticker.
  Future<TickerData> loadTicker({bool remote = false}) async {
    const cacheKey = 'cache_ticker';

    try {
      final prefs = await SharedPreferences.getInstance();

      if (AppConfig.tickerUrl.isEmpty) {
        await prefs.remove(cacheKey);
      } else {
        if (remote) {
          try {
            final res = await _download('ticker', AppConfig.tickerUrl);

            if (res != null && res.statusCode == 200) {
              final body = utf8.decode(res.bodyBytes);
              final data = TickerData.parse(jsonDecode(body));

              // An explicit "enabled": false is valid; only unusable
              // content (no items and not disabled) is ignored.
              if (data.visible || !data.enabled) {
                await prefs.setString(cacheKey, body);
                return data;
              }
            }
          } catch (_) {}
        }

        final cached = prefs.getString(cacheKey);

        if (cached != null) {
          final data = TickerData.parse(jsonDecode(cached));

          if (data.visible || !data.enabled) {
            return data;
          }
        }
      }
    } catch (_) {}

    try {
      return TickerData.parse(
        jsonDecode(
          await rootBundle.loadString('assets/data/ticker.json'),
        ),
      );
    } catch (_) {
      return TickerData.empty;
    }
  }

  Future<List<Channel>> loadChannels({bool remote = false}) async {
    final raw = await _list(
      name: 'tv',
      asset: 'assets/data/tv.json',
      cacheKey: 'cache_tv',
      remoteUrl: AppConfig.tvUrl,
      remote: remote,
    );

    return raw.map(Channel.tryParse).whereType<Channel>().toList();
  }

  Future<List<Movie>> loadMovies({bool remote = false}) async {
    final raw = await _list(
      name: 'movies',
      asset: 'assets/data/movies.json',
      cacheKey: 'cache_movies',
      remoteUrl: AppConfig.moviesUrl,
      remote: remote,
    );

    final parsed = raw.map(Movie.tryParse).whereType<Movie>().toList();

    // Rows that only hold a TMDB id get their name, poster, rating and genres
    // from TMDB (saved copy when offline / not refreshing).
    final fetch = remote && TmdbService.enabled;
    final filled = <Movie>[];
    for (var i = 0; i < parsed.length; i += 8) {
      final chunk = parsed.skip(i).take(8);
      filled.addAll((await Future.wait(chunk.map((m) async {
        if (!m.needsDetails) return m;
        final d = await tmdb.details(m.tmdbId!,
            tv: m.isSeries, fetch: fetch);
        return d == null ? null : m.fillFrom(d);
      })))
          .whereType<Movie>());
    }

    final seen = <String>{};
    final list = filled.where((m) => seen.add(m.url)).toList();

    // Newest first (date and time), stable for items posted the same day.
    final sorted = newestFirst(list, (m) => m.date);

    // TMDB trending titles go after your own list.
    if (AppConfig.tmdbTrending && TmdbService.enabled) {
      final ids = {for (final m in sorted) if (m.tmdbId != null) m.tmdbId};
      for (final m in await tmdb.trending(fetch: remote)) {
        if (seen.add(m.url) && !ids.contains(m.tmdbId)) sorted.add(m);
      }
    }
    return sorted;
  }

  Future<List<dynamic>> _list({
    required String name,
    required String asset,
    required String cacheKey,
    required String remoteUrl,
    required bool remote,
  }) async {
    if (remote && remoteUrl.isNotEmpty) {
      lastRemoteFailed = true; // until a download succeeds below
      try {
        final res = await _download(name, remoteUrl);

        if (res != null && res.statusCode == 200) {
          final data = _decode(utf8.decode(res.bodyBytes));

          if (data.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();

            await prefs.setString(
              cacheKey,
              jsonEncode(data),
            );

            lastRemoteFailed = false;
            return data;
          }
        }
      } catch (_) {
        // fall through to cache / bundled copy
      }
    } else if (remote) {
      lastRemoteFailed = false; // bundled-only mode: nothing to download
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (remoteUrl.isEmpty) {
        // Bundled-only mode: drop any copy cached from an older remote feed,
        // otherwise it would keep hiding the data shipped in the app.
        await prefs.remove(cacheKey);
      } else {
        final cached = prefs.getString(cacheKey);

        if (cached != null) {
          final data = _decode(cached);

          if (data.isNotEmpty) {
            return data;
          }
        }
      }
    } catch (_) {}

    return _decode(
      await rootBundle.loadString(asset),
    );
  }

  /// Downloads one feed: through your Cloudflare Worker when
  /// [AppConfig.feedBase] is set (so the request is counted), otherwise - or if
  /// the Worker is unreachable - straight from [fallbackUrl] (GitHub).
  Future<http.Response?> _download(String name, String fallbackUrl) async {
    final base = AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isNotEmpty) {
      try {
        final res = await _getFresh(
          '$base/feed/$name.json',
          headers: {
            'X-Install-Id': await InstallId.get(),
            'X-App-Version': AppConfig.appVersion,
            'X-Platform': 'android',
          },
        );
        if (res.statusCode == 200) return res;
      } catch (_) {
        // Worker down / blocked: use the direct link below.
      }
    }
    if (fallbackUrl.isEmpty) return null;
    try {
      return await _getFresh(fallbackUrl);
    } catch (_) {
      return null;
    }
  }

  /// Fetches a remote feed while preventing normal HTTP/proxy caching.
  ///
  /// The timestamp is added to the URL so GitHub Raw/CDN/proxy layers
  /// treat each refresh as a new request.
  Future<http.Response> _getFresh(
    String url, {
    Map<String, String> headers = const {},
  }) {
    final original = Uri.parse(url);

    final uri = original.replace(
      queryParameters: {
        ...original.queryParameters,
        '_refresh': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    return http
        .get(
          uri,
          headers: {
            'Cache-Control': 'no-cache, no-store, max-age=0',
            'Pragma': 'no-cache',
            ...headers,
          },
        )
        .timeout(
          const Duration(seconds: 10),
        );
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
        'items',
      ]) {
        if (d[k] is List) {
          return d[k] as List;
        }
      }
    }

    return const [];
  }
}

final feed = FeedService();
