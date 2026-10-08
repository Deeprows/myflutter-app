import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/movie.dart';
import '../models/push_target.dart';
import '../services/feed_service.dart';
import '../services/push_service.dart';
import '../services/support_gate.dart';
import '../services/tmdb_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/app_refresh.dart';
import '../utils/format.dart';
import '../widgets/movie_card.dart';
import '../widgets/pitch_painter.dart';
import '../services/download_manager.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  List<Movie> _all = const [];
  bool _loading = true;
  String _query = '';
  String? _genre;
  List<Movie> _found = const []; // TMDB search results
  Timer? _debounce;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.moviesUrl.isNotEmpty) _load(remote: true);
    });
    PushService.instance.target.addListener(_onTarget);
    ContentSync.tick.addListener(_onSync);
  }

  void _onSync() {
    if (!_loading) _load(remote: true);
  }

  // ---- a tapped notification that points at one movie -----------------------

  void _onTarget() {
    final t = PushService.instance.target.value;
    if (t == null || t.kind != 'movies' || _loading) return;
    if (!_openTarget(t)) _load(remote: true);
  }

  bool _openTarget(PushTarget t) {
    for (final m in _all) {
      if (m.url.trim() == t.url) {
        PushService.instance.target.value = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _details(m);
        });
        return true;
      }
    }
    return false;
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
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadMovies(remote: remote);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
    _afterLoad(last: remote || AppConfig.moviesUrl.isEmpty);
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

  List<String> get _genres {
    final counts = <String, int>{};
    for (final m in _all) {
      for (final g in m.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(8).toList();
  }

  void _play(Movie m) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: m.title,
        subtitle: [
          m.isSeries ? 'Series' : 'Movie',
          if (m.year != null) m.year!,
          if (m.rating != null) '★ ${m.rating}',
        ].join(' · '),
        url: m.url,
      ),
    ));
  }

  void _details(Movie m) {
    SupportGate.guard(context, () {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _MovieSheet(
          movie: m,
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
    final filtered = _all.where((m) {
      if (_genre != null && !m.genres.contains(_genre)) return false;
      return q.isEmpty || m.name.toLowerCase().contains(q);
    }).toList();
    if (q.isNotEmpty) {
      // Add TMDB search hits that are not already in the list.
      final urls = {for (final m in _all) m.url};
      final ids = {for (final m in _all) if (m.tmdbId != null) m.tmdbId};
      for (final m in _found) {
        if (_genre != null && !m.genres.contains(_genre)) continue;
        if (!urls.contains(m.url) && !ids.contains(m.tmdbId)) filtered.add(m);
      }
    }
    final top = MediaQuery.of(context).padding.top;

    return AppRefresh(
      onRefresh: () async {
        await _load(remote: true);
        return !feed.lastRemoteFailed;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(16, top + 16, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Ui.red.withValues(alpha: .20), Ui.bg],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                      child: CustomPaint(painter: PitchPainter())),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Movies',
                                style: TextStyle(
                                    fontSize: 26,
                                    height: 1.1,
                                    fontWeight: FontWeight.w900)),
                          ),
                          const _DownloadsButton(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _loading
                            ? 'Loading…'
                            : '${_all.length} movies and series',
                        style: TextStyle(
                            color: Ui.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _search,
                        onChanged: _onQuery,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search movies',
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
                              const EdgeInsets.symmetric(vertical: 12),
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
                                color: Ui.red.withValues(alpha: .7)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                children: [
                  _Pill('All', _genre == null,
                      () => setState(() => _genre = null)),
                  for (final g in _genres)
                    _Pill(g, _genre == g, () => setState(() => _genre = g)),
                ],
              ),
            ),
          ),
          if (_loading)
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
                  Text('Nothing found',
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

/// Header button that opens the Downloads list; shows a badge with the number
/// of downloads currently running.
class _DownloadsButton extends StatelessWidget {
  const _DownloadsButton();

  @override
  Widget build(BuildContext context) {
    final m = DownloadManager.instance;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final active = m.activeCount;
        return IconButton(
          tooltip: 'Downloads',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const DownloadsScreen(),
          )),
          icon: Badge(
            isLabelVisible: active > 0,
            label: Text('$active'),
            backgroundColor: Ui.red,
            child: const Icon(Icons.download_rounded),
          ),
        );
      },
    );
  }
}

class _MovieSheet extends StatelessWidget {
  final Movie movie;
  final VoidCallback onPlay;
  const _MovieSheet({required this.movie, required this.onPlay});

  Future<void> _download(BuildContext context) async {
    // Download links always open in the phone's own browser.
    final ok = await openExternally(movie.downloadUrl);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the download link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                    color: Colors.white24,
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
                        Text(movie.genres.join(' · '),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    style: FilledButton.styleFrom(
                      backgroundColor: Ui.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                if (movie.hasDownload) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _download(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Ui.line),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
          ],
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
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? Ui.muted),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
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
                    color: selected ? Colors.white : Ui.muted)),
          ),
        ),
      ),
    );
  }
}
