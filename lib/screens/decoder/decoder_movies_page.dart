import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/cast_target.dart';
import '../../models/movie.dart';
import '../../services/feed_service.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_movie.dart';
import '../../utils/premium_gate.dart';
import '../../widgets/movie_card.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';

/// Movie browser for Smart Decoder. It shows the same Trending / Top 10 /
/// Trending Movies rails, categories and search as the Movies tab, but a tap
/// never opens a details page: it goes straight to the two cast options
/// (TV / Kodi or receiver page). Nothing plays inside the app.
class DecoderMoviesPage extends StatefulWidget {
  const DecoderMoviesPage({super.key});
  @override
  State<DecoderMoviesPage> createState() => _DecoderMoviesPageState();
}

class _DecoderMoviesPageState extends State<DecoderMoviesPage> {
  final _search = TextEditingController();
  List<Movie> _all = const [];
  List<Movie> _heroTrending = const [];
  List<Movie> _top10 = const [];
  List<Movie> _trendingMovies = const [];
  List<Movie> _found = const [];
  final Map<String, List<Movie>> _discover = {};
  bool _loading = true;
  bool _homeLoading = true;
  bool _discovering = false;
  String _query = '';
  String? _genre;
  String? _type; // null = all, 'movie' or 'tv'
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHome());
    _load().then((_) {
      if (AppConfig.moviesUrl.isNotEmpty) _load(remote: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    try {
      final list = await feed.loadMovies(remote: remote);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHome() async {
    if (!TmdbService.enabled) {
      if (mounted) setState(() => _homeLoading = false);
      return;
    }
    try {
      final r = await Future.wait<List<Movie>>([
        tmdb.trending(),
        tmdb.topRatedMovies(),
        tmdb.trendingMovies(),
      ]).timeout(const Duration(seconds: 28), onTimeout: () => <List<Movie>>[[], [], []]);
      if (!mounted) return;
      setState(() {
        _heroTrending = r[0].take(15).toList();
        _top10 = r[1].take(10).toList();
        _trendingMovies = r[2].take(20).toList();
        _homeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _homeLoading = false);
    }
  }

  void _onQuery(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (!AppConfig.tmdbSearch || !TmdbService.enabled || v.trim().length < 2) {
      if (_found.isNotEmpty) setState(() => _found = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await tmdb.search(v);
      if (!mounted || _query.trim() != v.trim()) return;
      setState(() => _found = res);
    });
  }

  void _pickGenre(String g) {
    setState(() => _genre = _genre == g ? null : g);
    _fetchDiscover();
  }

  Future<void> _fetchDiscover() async {
    final g = _genre;
    if (g == null || !AppConfig.tmdbCategories || !TmdbService.enabled) return;
    if (_discover.containsKey(g)) return;
    setState(() => _discovering = true);
    final res = await tmdb.discover(g);
    if (!mounted) return;
    setState(() {
      _discover[g] = res;
      _discovering = false;
    });
  }

  List<String> get _genres {
    final counts = <String, int>{};
    for (final m in _all) {
      for (final g in m.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(12).toList();
  }

  /// Tap on any title: watch it in the app, or cast it to a bigger screen.
  Future<void> _select(Movie movie) async {
    final key = '${movie.isSeries ? 'tv' : 'movie'}:${movie.tmdbId ?? movie.title.toLowerCase()}';
    if (!await PremiumGate.allowDecoderMovies(context, key, action: 'play')) return;
    if (!mounted) return;
    if (movie.url.trim().isEmpty) {
      decoderToast(context, 'No video link is available for this title.');
      return;
    }
    final meta = [
      movie.isSeries ? 'Series' : 'Movie',
      if (movie.year != null) movie.year!,
      if (movie.rating != null) '★ ${movie.rating}',
    ].join(' · ');
    await chooseConnectivity(
      context,
      CastTarget(title: movie.title.isEmpty ? movie.name : movie.title, url: movie.url),
      image: movie.image,
      meta: meta,
      onWatchInApp: () => openMoviePlayer(context, movie, decoder: true),
    );
  }

  // ---- rails --------------------------------------------------------------

  Widget _trendingCarousel(List<Movie> movies) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: decoderSectionHeader(
          icon: Icons.local_fire_department_rounded,
          kicker: 'This week',
          title: 'Trending now',
          trailing: 'HOT',
        ),
      ),
      SizedBox(
        height: 235,
        child: PageView.builder(
          controller: PageController(viewportFraction: .83),
          padEnds: false,
          itemCount: movies.length,
          itemBuilder: (context, i) {
            final movie = movies[i];
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 16 : 0, right: 10),
              child: GestureDetector(
                onTap: () => _select(movie),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(fit: StackFit.expand, children: [
                    if (movie.hasImage)
                      Image.network(movie.image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Ui.card))
                    else
                      Container(color: Ui.card),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: .08), Colors.black.withValues(alpha: .88)],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), shape: BoxShape.circle),
                        child: Icon(Icons.cast_rounded, size: 18, color: Ui.redSoft),
                      ),
                    ),
                    Positioned(
                      left: 15,
                      right: 15,
                      bottom: 14,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(30)),
                          child: Text('#${i + 1} TRENDING',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Ui.palette.onAccent)),
                        ),
                        const SizedBox(height: 8),
                        Text(movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                inherit: false,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                        const SizedBox(height: 4),
                        Text('${movie.year ?? ''}${movie.rating == null ? '' : '  ·  ★ ${movie.rating}/10'}',
                            style: const TextStyle(inherit: false, color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _rail(Widget header, List<Movie> movies, {bool ranked = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 0), child: header),
      SizedBox(
        height: 258,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: movies.length,
          separatorBuilder: (_, __) => const SizedBox(width: 11),
          itemBuilder: (context, i) => SizedBox(
            width: 145,
            child: Stack(children: [
              Positioned.fill(child: MovieCard(movie: movies[i], onTap: () => _select(movies[i]))),
              if (ranked)
                Positioned(
                  left: 5,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(8)),
                    child: Text('${i + 1}',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Ui.palette.onAccent)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _pill(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Ui.red : Ui.card,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? Ui.red : Ui.line),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? Ui.palette.onAccent : Ui.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool typeOk(Movie m) => _type == null || m.isSeries == (_type == 'tv');
    bool genreOk(Movie m) => _genre == null || m.genres.contains(_genre);

    final filtered = _all.where((m) {
      if (!typeOk(m) || !genreOk(m)) return false;
      return q.isEmpty || m.name.toLowerCase().contains(q);
    }).toList();

    final urls = {for (final m in _all) m.url};
    final ids = {for (final m in _all) if (m.tmdbId != null) m.tmdbId};
    void addExtra(Movie m, {required bool matchName}) {
      if (!typeOk(m) || !genreOk(m)) return;
      if (matchName && q.isNotEmpty && !m.name.toLowerCase().contains(q)) return;
      if (urls.contains(m.url) || ids.contains(m.tmdbId)) return;
      urls.add(m.url);
      filtered.add(m);
    }

    if (q.isNotEmpty) {
      for (final m in _found) {
        addExtra(m, matchName: false);
      }
    }
    if (_genre != null) {
      for (final m in _discover[_genre] ?? const <Movie>[]) {
        addExtra(m, matchName: true);
      }
    }

    final browsing = q.isEmpty && _genre == null && _type == null;

    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Moviebox', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('Tap any title to cast it', style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: TextField(
                controller: _search,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search any movie or series…',
                  hintStyle: TextStyle(color: Ui.dim),
                  prefixIcon: Icon(Icons.search_rounded, color: Ui.muted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            _onQuery('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Ui.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Ui.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Ui.line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Ui.red.withValues(alpha: .8))),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                children: [
                  _pill('All', _genre == null && _type == null, () => setState(() {
                        _genre = null;
                        _type = null;
                      })),
                  _pill('Movies', _type == 'movie', () => setState(() => _type = _type == 'movie' ? null : 'movie')),
                  _pill('Series', _type == 'tv', () => setState(() => _type = _type == 'tv' ? null : 'tv')),
                  for (final g in _genres) _pill(g, _genre == g, () => _pickGenre(g)),
                ],
              ),
            ),
          ),
          if (browsing) ...[
            if (_heroTrending.isNotEmpty) SliverToBoxAdapter(child: _trendingCarousel(_heroTrending)),
            if (_top10.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  decoderSectionHeader(
                    icon: Icons.emoji_events_rounded,
                    kicker: 'Highest rated',
                    title: 'Top 10',
                    trailing: 'RANKED',
                  ),
                  _top10,
                  ranked: true,
                ),
              ),
            if (_trendingMovies.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  decoderSectionHeader(
                    icon: Icons.movie_filter_rounded,
                    kicker: 'On everyone’s screen',
                    title: 'Trending movies',
                  ),
                  _trendingMovies,
                ),
              ),
            if (_homeLoading && _heroTrending.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('Loading movie trends…', style: TextStyle(color: Ui.muted)),
                  ]),
                ),
              ),
          ],
          if (filtered.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: decoderSectionHeader(
                  icon: browsing ? Icons.video_library_rounded : Icons.manage_search_rounded,
                  kicker: browsing ? 'The full library' : 'Matches',
                  title: browsing ? 'All movies & series' : (q.isEmpty ? _genre ?? 'Results' : 'Search results'),
                  trailing: '${filtered.length}',
                ),
              ),
            ),
          if (_loading || (filtered.isEmpty && _discovering))
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: Ui.red)),
            )
          else if (filtered.isEmpty && !browsing)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off_rounded, size: 44, color: Ui.dim),
                const SizedBox(height: 10),
                Text('Nothing found', style: TextStyle(color: Ui.muted, fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 270,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => MovieCard(movie: filtered[i], onTap: () => _select(filtered[i])),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
