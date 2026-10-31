import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/fixture.dart';
import '../models/movie.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../services/support_gate.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/l10n.dart';
import '../utils/open_movie.dart';
import 'fan_profile_screen.dart';
import 'fan_thread_screen.dart';
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';
import 'player_screen.dart';
import 'sports_news_screen.dart';

/// Search tab: live football matches, movies and series, people and posts,
/// plus a tray of trending hashtags when the search box is empty.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _feed = FeedService();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _seq = 0;

  List<Fixture> _fixtures = const [];
  List<Movie> _movies = const [];
  List<Map<String, dynamic>> _trending = const [];
  bool _trendingLoaded = false;

  String _query = '';
  bool _busy = false;
  List<Movie> _movieHits = const [];
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _posts = const [];

  @override
  void initState() {
    super.initState();
    _feed.loadFixtures().then((v) {
      if (mounted) setState(() => _fixtures = v);
    }).catchError((_) {});
    _feed.loadMovies().then((v) {
      if (mounted) setState(() => _movies = v);
    }).catchError((_) {});
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    try {
      final data = await FanZoneService.call('social/trending');
      if (!mounted) return;
      setState(() {
        _trending = FanZoneService.rows(data['tags']);
        _trendingLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _trendingLoaded = true);
    }
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().length < 2) {
      _seq++;
      setState(() {
        _busy = false;
        _movieHits = const [];
        _users = const [];
        _posts = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value));
  }

  void _setQuery(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _focus.unfocus();
    _onChanged(value);
    _debounce?.cancel();
    _run(value);
  }

  Future<void> _run(String raw) async {
    final q = raw.trim();
    if (q.length < 2) return;
    final seq = ++_seq;
    setState(() => _busy = true);

    final movieFuture = (AppConfig.tmdbSearch && TmdbService.enabled)
        ? tmdb.search(q).catchError((_) => <Movie>[])
        : Future.value(<Movie>[]);
    final fanFuture = FanZoneService.call(
      'social/search',
      query: {'q': q},
    ).then<Map<String, dynamic>?>((v) => v).catchError((_) => null);

    final movies = await movieFuture;
    final fan = await fanFuture;
    final blocked = await FanZoneService.blocked();
    if (!mounted || seq != _seq) return;

    setState(() {
      _movieHits = movies;
      _users = fan == null
          ? const []
          : FanZoneService.rows(fan['users'])
              .where((u) => !blocked.contains('${u['id']}'))
              .toList();
      _posts = fan == null
          ? const []
          : FanZoneService.rows(fan['posts'])
              .where((p) => !blocked.contains('${p['user_id']}'))
              .toList();
      _busy = false;
    });
  }

  // ---------------------------------------------------------------------------
  // LOCAL MATCHING
  // ---------------------------------------------------------------------------

  List<Fixture> get _matchHits {
    final q = _query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final now = DateTime.now();
    final hits = _fixtures.where((f) {
      return f.home.toLowerCase().contains(q) ||
          f.away.toLowerCase().contains(q) ||
          f.league.toLowerCase().contains(q);
    }).toList();
    int rank(Fixture f) => switch (f.phaseAt(now)) {
          MatchPhase.live => 0,
          MatchPhase.upcoming => 1,
          MatchPhase.ended => 2,
        };
    hits.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return rank(a) == 2
          ? b.kickoff.compareTo(a.kickoff)
          : a.kickoff.compareTo(b.kickoff);
    });
    return hits.take(8).toList();
  }

  List<Movie> get _allMovieHits {
    final q = _query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final out = <Movie>[];
    final seen = <String>{};
    bool add(Movie m) => seen.add('${m.title.toLowerCase()}|${m.year ?? ''}');
    for (final m in _movies) {
      if (m.title.toLowerCase().contains(q) && add(m)) out.add(m);
    }
    for (final m in _movieHits) {
      if (add(m)) out.add(m);
    }
    return out.take(10).toList();
  }

  // ---------------------------------------------------------------------------
  // OPENERS
  // ---------------------------------------------------------------------------

  void _openMatch(Fixture f) {
    if (!f.hasStream) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No stream for this match yet'.tr)),
      );
      return;
    }
    SupportGate.guard(context, () {
      if (!mounted) return;
      final phase = f.phaseAt(DateTime.now());
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            title: f.title,
            subtitle: '${longDate(f.kickoff.toLocal())} · '
                '${fmtTime(f.kickoff.toLocal())} '
                '${tzShort(f.kickoff.toLocal())}'
                '${f.league.isEmpty ? '' : ' · ${f.league}'}',
            url: f.url,
            altUrl: f.hasAlt ? f.altUrl : null,
              moreUrls: f.moreUrls,
            isLive: phase == MatchPhase.live,
            chatMatch: f.title,
          ),
        ),
      );
    });
  }

  void _openMovie(Movie m) {
    SupportGate.guard(context, () {
      if (mounted) openMoviePlayer(context, m);
    });
  }

  void _openUser(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FanProfileScreen(userId: id)),
    );
  }

  void _openPost(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FanThreadScreen(postId: id)),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final searching = _query.trim().length >= 2;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(14, top + 10, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Ui.red.withValues(alpha: .20), Ui.bg],
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) {
              _debounce?.cancel();
              _run(v);
            },
            decoration: InputDecoration(
              hintText: 'Search matches, movies, people, news'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear'.tr,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .07),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          // Sports news (headlines, matches strip, tabs) lives under the box,
          // like Explore on X. Typing filters the headlines and adds matches,
          // movies, people and posts above them.
          child: SportsNewsScreen(
            embedded: true,
            query: searching ? _query : '',
            leading: searching ? _resultWidgets() : _trendingWidgets(),
          ),
        ),
      ],
    );
  }

  List<Widget> _trendingWidgets() {
    return [
              XSectionHeader('Trending'.tr, icon: Icons.trending_up_rounded),
        if (!_trendingLoaded)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_trending.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No trending hashtags yet. Posts with #hashtags will show here.'
                  .tr,
              style: TextStyle(color: Ui.muted, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _trending.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final t = _trending[i];
                final posts = (t['posts'] as num?)?.toInt() ?? 0;
                return InkWell(
                  borderRadius: BorderRadius.circular(Ui.radius),
                  onTap: () => _setQuery('${t['tag']}'),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Ui.card,
                      borderRadius: BorderRadius.circular(Ui.radius),
                      border: Border.all(color: Ui.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${i + 1} · Trending'.tr,
                          style: TextStyle(color: Ui.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${t['tag']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Ui.redSoft,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          posts == 1 ? '1 post' : '$posts posts',
                          style: TextStyle(color: Ui.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
    ];
  }

  List<Widget> _resultWidgets() {
    final matches = _matchHits;
    final movies = _allMovieHits;

    return [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (matches.isNotEmpty) ...[
          XSectionHeader('Matches'.tr, icon: Icons.sports_soccer_rounded),
          for (final f in matches) _matchTile(f),
        ],
        if (movies.isNotEmpty) ...[
          XSectionHeader('Movies & Series'.tr, icon: Icons.movie_outlined),
          for (final m in movies) _movieTile(m),
        ],
        if (_users.isNotEmpty) ...[
          XSectionHeader('People'.tr, icon: Icons.people_alt_outlined),
          for (final u in _users) _userTile(u),
        ],
        if (_posts.isNotEmpty) ...[
          XSectionHeader('Posts'.tr, icon: Icons.forum_outlined),
          for (final p in _posts) _postTile(p),
        ],
    ];
  }

  Widget _tile({
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: leading,
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Ui.muted, fontSize: 12.5),
            ),
      trailing: trailing,
    );
  }

  Widget _matchTile(Fixture f) {
    final now = DateTime.now();
    final phase = f.phaseAt(now);
    final label = switch (phase) {
      MatchPhase.live => 'LIVE'.tr,
      MatchPhase.upcoming => fmtTime(f.kickoff.toLocal()),
      MatchPhase.ended => 'FT'.tr,
    };
    return _tile(
      leading: CircleAvatar(
        backgroundColor: Ui.card,
        child: Icon(Icons.sports_soccer_rounded, color: Ui.redSoft, size: 20),
      ),
      title: f.title,
      subtitle: [
        dayLabel(f.kickoff.toLocal(), now),
        if (f.league.isNotEmpty) f.league,
      ].join(' · '),
      trailing: Text(
        label,
        style: TextStyle(
          color: phase == MatchPhase.live ? Ui.red : Ui.muted,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      onTap: () => _openMatch(f),
    );
  }

  Widget _movieTile(Movie m) {
    return _tile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 40,
          height: 56,
          child: m.hasImage
              ? Image.network(
                  m.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: Ui.card),
                )
              : ColoredBox(color: Ui.card),
        ),
      ),
      title: m.title,
      subtitle: [
        m.isSeries ? 'Series'.tr : 'Movie'.tr,
        if (m.year != null) m.year!,
        if (m.rating != null) '★ ${m.rating}',
      ].join(' · '),
      onTap: () => _openMovie(m),
    );
  }

  Widget _userTile(Map<String, dynamic> u) {
    final id = '${u['id']}';
    final name = '${u['name']}';
    return _tile(
      leading: FanAvatar(
        name: name,
        seed: id,
        size: 42,
        imageUrl: FanZoneService.avatarUrl(id, u['avatar_at']),
      ),
      title: name,
      subtitle: '@${FanZoneService.handle(id)}',
      onTap: () => _openUser(id),
    );
  }

  Widget _postTile(Map<String, dynamic> p) {
    final id = '${p['user_id']}';
    final name = '${p['name']}';
    final likes = p['likes'] ?? 0;
    final replies = p['comments'] ?? 0;
    return InkWell(
      onTap: () => _openPost('${p['id']}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FanAvatar(
              name: name,
              seed: id,
              size: 38,
              imageUrl: FanZoneService.avatarUrl(id, p['avatar_at']),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: xRichSpans(
                        '${p['text']}',
                        base: const TextStyle(fontSize: 14, height: 1.35),
                      ),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$likes likes · $replies replies',
                    style: TextStyle(color: Ui.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
