import 'dart:async';
import 'dart:math' show Random;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/push_target.dart';
import '../services/feed_service.dart';
import '../services/partner_browser.dart';
import '../services/push_service.dart';
import '../services/support_gate.dart';
import '../services/tmdb_service.dart';
import '../services/locale_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/app_refresh.dart';
import '../utils/format.dart';
import '../widgets/movie_card.dart';
import '../widgets/movie_info_panel.dart';
import '../services/movie_library.dart';
import '../utils/open_movie.dart';
import '../utils/premium_gate.dart';
import 'browser_screen.dart';
import 'library_screen.dart';
import 'trailer_player_screen.dart';
import '../utils/l10n.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  List<Movie> _all = const [];
  List<Movie> _heroTrending = const [];
  List<Movie> _top10 = const [];
  List<Movie> _trendingMovies = const [];
  List<TmdbTrailer> _latestTrailers = const [];
  bool _homeSectionsLoading = true;
  bool _loading = true;
  String _query = '';
  String? _genre;
  String? _type; // null = all, 'movie' or 'tv'
  List<Movie> _found = const []; // TMDB search results
  final Map<String, List<Movie>> _discover = {}; // TMDB titles per category
  bool _discovering = false;
  Timer? _debounce;
  final _search = TextEditingController();

  // Random poster behind the header; picked once, and again on a new day.
  Movie? _bg;
  int _bgDay = 0;

  void _pickBg() {
    if (_bg != null && _bgDay == _dayKey) return;
    final withArt = _all.where((m) => m.hasImage).toList();
    if (withArt.isEmpty) return;
    _bg = withArt[Random().nextInt(withArt.length)];
    _bgDay = _dayKey;
  }

  /// Poster behind "Trending now / Top Movies & Series": darkened and fading
  /// into the page colour so the text stays readable.
  Widget _headerBackdrop() {
    final poster = _bg;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base: accent tint fading into the page colour (also the fallback
        // when there is no poster).
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Ui.red.withValues(alpha: .28), Ui.bg],
            ),
          ),
        ),
        if (poster != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: SizedBox.expand(
              key: ValueKey(poster.url),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: ColorFiltered(
                  // Dim the artwork so white text always stands out.
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: .55), BlendMode.darken),
                  child: Image.network(
                    poster.image,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.5),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        // Dark veil: strongest where the text sits, clear fade to the page
        // colour at the bottom edge (no visible line under the header).
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                // Dark where the white title sits (any theme), then a fade
                // into the page colour so there is no line under the header.
                Colors.black.withValues(alpha: .50),
                Colors.black.withValues(alpha: .58),
                Color.alphaBlend(Colors.black.withValues(alpha: .25), Ui.bg)
                    .withValues(alpha: .86),
                Ui.bg,
              ],
              stops: const [0, .45, .8, 1],
            ),
          ),
        ),
        // Accent glow (lives here, so it is never cut off into a box).
        Positioned(
          right: -50,
          top: -30,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Ui.red.withValues(alpha: .22),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // The front page order is shuffled once per day (local midnight).
  Timer? _midnight;
  int _dayKey = _today();

  static int _today() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  /// Rebuilds the front page when the day changes while the app is open.
  void _armMidnight() {
    _midnight?.cancel();
    final n = DateTime.now();
    final next = DateTime(n.year, n.month, n.day + 1, 0, 0, 2);
    _midnight = Timer(next.difference(n), () {
      if (!mounted) return;
      setState(() {
        _dayKey = _today();
        _pickBg();
      });
      _armMidnight();
    });
  }

  /// Same title, same day -> same number, so the order holds all day and
  /// changes tomorrow. New titles added meanwhile don't reshuffle the rest.
  int _dayRank(Movie m) {
    var h = 0x811C9DC5;
    for (final c in '$_dayKey|${m.url}'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadHomeSections());
    _load().then((_) {
      if (AppConfig.moviesUrl.isNotEmpty) _load(remote: true);
    });
    PushService.instance.target.addListener(_onTarget);
    ContentSync.tick.addListener(_onSync);
    AppLocale.notifier.addListener(_onLanguage);
    MovieLibrary.instance.load();
    _armMidnight();
  }

  void _onSync() {
    // Coming back to the app after midnight: pick up the new day's order.
    if (_dayKey != _today()) {
      setState(() {
        _dayKey = _today();
        _pickBg();
      });
    }
    if (_loading) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && !_loading) _load(remote: true);
      });
      return;
    }
    _load(remote: true);
  }

  /// New app language: reload so titles and descriptions follow it.
  void _onLanguage() {
    _discover.clear();
    if (_genre != null) _fetchDiscover();
    if (_query.trim().length >= 2) _onQuery(_query);
    _load().then((_) => _load(remote: true));
  }

  // ---- a tapped notification that points at one movie -----------------------

  void _onTarget() {
    final t = PushService.instance.target.value;
    if (t == null || t.kind != 'movies' || _loading) return;
    if (!_openTarget(t)) _load(remote: true);
  }

  bool _openTarget(PushTarget t) {
    for (final m in _all) {
      if (t.url.isNotEmpty && m.url.trim() == t.url) {
        PushService.instance.target.value = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _details(m);
        });
        return true;
      }
    }
    if (t.tmdbId != null && t.tmdbId! > 0) {
      PushService.instance.target.value = null;
      unawaited(_openTrendingMovieTarget(t));
      return true;
    }
    return false;
  }

  Future<void> _openTrendingMovieTarget(PushTarget target) async {
    final movie = await tmdb.details(target.tmdbId!, tv: target.mediaType == 'tv');
    if (!mounted || movie == null) return;
    if (!_all.any((m) => m.tmdbId == movie.tmdbId)) {
      setState(() => _all = [..._all, movie]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _details(movie);
    });
  }

  void _afterLoad({required bool last}) {
    final t = PushService.instance.target.value;
    if (t == null || t.kind != 'movies') return;
    if (!_openTarget(t) && last) PushService.instance.target.value = null;
  }

  @override
  void dispose() {
    PushService.instance.target.removeListener(_onTarget);
    ContentSync.tick.removeListener(_onSync);
    AppLocale.notifier.removeListener(_onLanguage);
    _debounce?.cancel();
    _midnight?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadMovies(remote: remote);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
      _pickBg();
    });
    _afterLoad(last: remote || AppConfig.moviesUrl.isEmpty);
  }

  /// Populate the four homepage rails from the same TMDB endpoints used by
  /// DamiMovies. Requests are isolated so one unavailable rail doesn't hide
  /// the other content or the user's bundled movie catalogue.
  Future<void> _loadHomeSections() async {
    if (!TmdbService.enabled) {
      if (mounted) setState(() => _homeSectionsLoading = false);
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        tmdb.trending(),
        tmdb.topRatedMovies(),
        tmdb.trendingMovies(),
        tmdb.latestTrailers(),
      ]).timeout(const Duration(seconds: 28), onTimeout: () => <dynamic>[[], [], [], []]);
      if (!mounted) return;
      setState(() {
        _heroTrending = (results[0] as List<Movie>).take(15).toList();
        _top10 = (results[1] as List<Movie>).take(10).toList();
        _trendingMovies = (results[2] as List<Movie>).take(20).toList();
        _latestTrailers = (results[3] as List<TmdbTrailer>).take(12).toList();
        _homeSectionsLoading = false;
        _pickBg();
      });
    } catch (_) {
      if (mounted) setState(() => _homeSectionsLoading = false);
    }
  }

  void _openTrailer(TmdbTrailer trailer) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrailerPlayerScreen(
        title: trailer.title,
        youtubeKey: trailer.youtubeKey,
        poster: trailer.poster,
      ),
    ));
  }

  Widget _homeSectionHeading(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Row(
          children: [
            Expanded(child: Text(title.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            if (subtitle != null)
              Text(subtitle, style: TextStyle(color: Ui.dim, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _movieRail(String title, List<Movie> movies, {bool ranked = false}) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _homeSectionHeading(title, subtitle: ranked ? 'TOP 10' : null),
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
              Positioned.fill(child: MovieCard(movie: movies[i], onTap: () => _details(movies[i]))),
              if (ranked)
                Positioned(left: 5, top: 5, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(8)),
                  child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white)),
                )),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _trendingCarousel(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _homeSectionHeading('Trending Now', subtitle: 'THIS WEEK'),
      SizedBox(
        height: 235,
        child: PageView.builder(
          controller: PageController(viewportFraction: .83),
          itemCount: movies.length,
          itemBuilder: (context, i) {
            final movie = movies[i];
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => _details(movie),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(fit: StackFit.expand, children: [
                    if (movie.hasImage) Image.network(movie.image, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Ui.card))
                    else Container(color: Ui.card),
                    DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: .08), Colors.black.withValues(alpha: .88)],
                    ))),
                    Positioned(left: 15, right: 15, bottom: 14, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(30)),
                          child: const Text('🔥 TRENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white))),
                        const SizedBox(height: 8),
                        Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(inherit: false, fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                        const SizedBox(height: 4),
                        Text('${movie.year ?? ''}${movie.rating == null ? '' : '  ·  ★ ${movie.rating}/10'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    )),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _latestTrailerRail(List<TmdbTrailer> trailers) {
    if (trailers.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _homeSectionHeading('Latest Trailers', subtitle: 'WATCH PREVIEWS'),
      SizedBox(
        height: 165,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: trailers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final trailer = trailers[i];
            return GestureDetector(
              onTap: () => _openTrailer(trailer),
              child: SizedBox(width: 220, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [
                  Image.network('https://img.youtube.com/vi/${trailer.youtubeKey}/hqdefault.jpg', fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => trailer.poster.startsWith('http') ? Image.network(trailer.poster, fit: BoxFit.cover) : Container(color: Ui.card)),
                  Container(color: Colors.black.withValues(alpha: .2)),
                  const Center(child: Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white)),
                ]))),
                const SizedBox(height: 7),
                Text(trailer.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ])),
            );
          },
        ),
      ),
    ]);
  }

  /// Searches the whole TMDB catalogue shortly after typing stops.
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

  /// Loads TMDB's popular titles for the selected category.
  Future<void> _fetchDiscover({bool force = false}) async {
    final g = _genre;
    if (g == null || !AppConfig.tmdbCategories || !TmdbService.enabled) return;
    if (!force && _discover.containsKey(g)) return;
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
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(12).toList();
  }

  void _play(Movie m) => openMoviePlayer(context, m);

  void _details(Movie m) {
    SupportGate.guard(context, () {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _MovieSheet(
          movie: m,
          infoFuture: tmdb.info(m),
          trailerFuture: tmdb.trailerFor(m),
          similarFuture: tmdb.similar(m),
          onMovieTap: (other) { Navigator.of(ctx).pop(); _details(other); },
          onPlay: () {
            Navigator.of(ctx).pop();
            _play(m);
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool typeOk(Movie m) => _type == null || m.isSeries == (_type == 'tv');
    bool genreOk(Movie m) => _genre == null || m.genres.contains(_genre);
    final filtered = _all.where((m) {
      if (!typeOk(m) || !genreOk(m)) return false;
      return q.isEmpty || m.name.toLowerCase().contains(q);
    }).toList();

    // TMDB titles from the search box and from the selected category come
    // after the ones in your own list.
    final urls = {for (final m in _all) m.url};
    final ids = {for (final m in _all) if (m.tmdbId != null) m.tmdbId};
    void addExtra(Movie m, {required bool matchName}) {
      if (!typeOk(m) || !genreOk(m)) return;
      if (matchName && q.isNotEmpty && !m.name.toLowerCase().contains(q)) {
        return;
      }
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
    // Browsing (no search text): a fresh order every day. Searching keeps
    // the best matches first.
    if (q.isEmpty) {
      final rank = {for (final m in filtered) m.url: _dayRank(m)};
      filtered.sort((a, b) => rank[a.url]!.compareTo(rank[b.url]!));
    }
    final top = MediaQuery.of(context).padding.top;

    return AppRefresh(
      onRefresh: () async {
        _discover.clear();
        await _load(remote: true);
        await _fetchDiscover(force: true);
        return !feed.lastRemoteFailed;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Positioned.fill(child: _headerBackdrop()),
                Container(
              padding: EdgeInsets.fromLTRB(16, top + 14, 16, 14),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Ui.bg.withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(99),
                              border:
                                  Border.all(color: Ui.red.withValues(alpha: .5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_fire_department_rounded,
                                    size: 14, color: Ui.redSoft),
                                const SizedBox(width: 5),
                                Text('TRENDING NOW'.tr,
                                    style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.w900,
                                        color: Ui.red)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const _LibraryButtons(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Sits on the dimmed poster, so it is always white.
                      Text('Top Movies & Series\nDatabase'.tr,
                          style: const TextStyle(
                              fontSize: 29,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 10)
                              ])),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              size: 17, color: Ui.red),
                          const SizedBox(width: 6),
                          Text('Search any movie and watch.'.tr,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .88),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                        color: Colors.black87, blurRadius: 8)
                                  ])),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: Ui.red.withValues(alpha: .28),
                                blurRadius: 22,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        child: TextField(
                          controller: _search,
                          onChanged: _onQuery,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search any movie or series…'.tr,
                            hintStyle: TextStyle(color: Ui.dim),
                            prefixIcon:
                                Icon(Icons.search_rounded, color: Ui.muted),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _search.clear();
                                      _onQuery('');
                                    },
                                  ),
                            filled: true,
                            fillColor: Ui.card,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Ui.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Ui.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: Ui.red.withValues(alpha: .8)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                children: [
                  _Pill('All'.tr, _genre == null && _type == null,
                      () => setState(() {
                            _genre = null;
                            _type = null;
                          })),
                  _Pill('Movies', _type == 'movie',
                      () => setState(
                          () => _type = _type == 'movie' ? null : 'movie')),
                  _Pill('Series', _type == 'tv',
                      () => setState(() => _type = _type == 'tv' ? null : 'tv')),
                  for (final g in _genres)
                    _Pill(g.tr, _genre == g, () => _pickGenre(g)),
                ],
              ),
            ),
          ),
          if (q.isEmpty && _genre == null && _type == null) ...[
            if (_heroTrending.isNotEmpty) SliverToBoxAdapter(child: _trendingCarousel(_heroTrending)),
            if (_top10.isNotEmpty) SliverToBoxAdapter(child: _movieRail('Top 10', _top10, ranked: true)),
            if (_trendingMovies.isNotEmpty) SliverToBoxAdapter(child: _movieRail('Trending Movies', _trendingMovies)),
            if (_latestTrailers.isNotEmpty) SliverToBoxAdapter(child: _latestTrailerRail(_latestTrailers)),
            if (_homeSectionsLoading && _heroTrending.isEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text('Loading movie trends…', style: TextStyle(color: Ui.muted))]),
              )),
          ],
          if (_loading || (filtered.isEmpty && _discovering))
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: Ui.red)),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded, size: 44, color: Ui.dim),
                  SizedBox(height: 10),
                  Text('Nothing found'.tr,
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
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
                  (context, i) => MovieCard(
                    movie: filtered[i],
                    onTap: () => _details(filtered[i]),
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Header icons: Watch later (badge = saved titles) and Watch history.
class _LibraryButtons extends StatelessWidget {
  const _LibraryButtons();

  void _open(BuildContext context, int tab) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(initialTab: tab),
      ));

  @override
  Widget build(BuildContext context) {
    final lib = MovieLibrary.instance;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final saved = lib.watchLater.length;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Save & watch later',
              onPressed: () => _open(context, 0),
              icon: Badge(
                isLabelVisible: saved > 0,
                label: Text('$saved'),
                backgroundColor: Ui.red,
                child: const Icon(Icons.bookmark_rounded),
              ),
            ),
            IconButton(
              tooltip: 'Watch history',
              onPressed: () => _open(context, 1),
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _MovieSheet extends StatelessWidget {
  final Movie movie;
  final VoidCallback onPlay;
  final Future<MovieInfo?> infoFuture;
  final Future<TmdbTrailer?> trailerFuture;
  final Future<List<Movie>> similarFuture;
  final ValueChanged<Movie> onMovieTap;
  const _MovieSheet({required this.movie, required this.onPlay, required this.infoFuture,
    required this.trailerFuture, required this.similarFuture, required this.onMovieTap});

  Future<void> _download(BuildContext context) async {
    // Premium only: everyone else is sent to upgrade.
    if (!await PremiumGate.allowMovies(context)) return;
    if (!context.mounted) return;
    // Deeprows Browser offer; otherwise the phone's own browser.
    await PartnerBrowser.instance.download(context, movie.downloadUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Ui.line,
                    borderRadius: BorderRadius.circular(9)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  height: 160,
                  child: MoviePoster(movie: movie),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(movie.title,
                          style: const TextStyle(
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _Meta(
                              icon: movie.isSeries
                                  ? Icons.tv_rounded
                                  : Icons.movie_outlined,
                              text: movie.isSeries ? 'Series' : 'Movie'),
                          if (movie.year != null)
                            _Meta(
                                icon: Icons.calendar_today_rounded,
                                text: movie.year!),
                          if (movie.rating != null)
                            _Meta(
                                icon: Icons.star_rounded,
                                text: '${movie.rating} / 10',
                                color: const Color(0xFFFFC107)),
                        ],
                      ),
                      if (movie.genres.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(movie.genres.map((g) => g.tr).join(' · '),
                            style: TextStyle(
                                color: Ui.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                      if (movie.date != null) ...[
                        const SizedBox(height: 8),
                        Text('Added ${shortDate(movie.date!)}',
                            style: TextStyle(
                                color: Ui.dim,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    style: FilledButton.styleFrom(
                      backgroundColor: Ui.red,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(PremiumGate.locked ? Icons.lock_rounded : Icons.play_arrow_rounded, size: 24),
                    label: Text('Play'.tr, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 10),
                ListenableBuilder(
                  listenable: MovieLibrary.instance,
                  builder: (context, _) {
                    final saved = MovieLibrary.instance.isSaved(movie);
                    return IconButton.outlined(
                      tooltip: saved ? 'Remove from Watch later' : 'Watch later',
                      onPressed: () async {
                        final now = await MovieLibrary.instance.toggleWatchLater(movie);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(now ? 'Saved to Watch later' : 'Removed from Watch later')));
                      },
                      style: IconButton.styleFrom(
                        side: BorderSide(color: saved ? Ui.red : Ui.line),
                        minimumSize: const Size(52, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                          color: saved ? Ui.red : null),
                    );
                  },
                ),
                if (movie.hasDownload) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _download(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: BorderSide(color: Ui.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: Icon(PremiumGate.locked ? Icons.lock_rounded : Icons.download_rounded),
                      label: Text('Download'.tr, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            FutureBuilder<TmdbTrailer?>(
              future: trailerFuture,
              builder: (context, snapshot) {
                final trailer = snapshot.data;
                if (trailer == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => TrailerPlayerScreen(
                        title: trailer.title,
                        youtubeKey: trailer.youtubeKey,
                        poster: trailer.poster,
                      ),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(height: 150, width: double.infinity,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.network('https://img.youtube.com/vi/${trailer.youtubeKey}/hqdefault.jpg', fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => movie.hasImage ? Image.network(movie.image, fit: BoxFit.cover) : Container(color: Ui.card)),
                          Container(color: Colors.black.withValues(alpha: .25)),
                          const Center(child: Icon(Icons.play_circle_fill_rounded, size: 56, color: Colors.white)),
                          Positioned(left: 12, bottom: 10, child: Text('TRAILER · ${movie.title}', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
            FutureBuilder<MovieInfo?>(
              future: infoFuture,
              builder: (context, snapshot) => MovieInfoPanel(
                movie: movie,
                info: snapshot.data,
                loading: snapshot.connectionState == ConnectionState.waiting,
              ),
            ),
            FutureBuilder<List<Movie>>(
              future: similarFuture,
              builder: (context, snapshot) {
                final related = snapshot.data ?? const <Movie>[];
                if (related.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 20),
                  Text('More Like This'.tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  SizedBox(height: 245, child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(width: 135,
                      child: MovieCard(movie: related[i], onTap: () => onMovieTap(related[i]))),
                  )),
                ]);
              },
            ),
            const SizedBox(height: 20),

          ],
        ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Meta({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Ui.text.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? Ui.muted),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Ui.text)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? Ui.red : Ui.card,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: selected ? Colors.transparent : Ui.line),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Ui.text : Ui.muted)),
          ),
        ),
      ),
    );
  }
}
