import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fixture.dart';
import '../models/live_score.dart';
import '../services/feed_service.dart';
import '../services/score_service.dart';
import '../services/sports_news_service.dart';
import '../services/support_gate.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';
import 'player_screen.dart';

/// Explore-style sports news, with publisher attribution and actual timestamps.
class SportsNewsScreen extends StatefulWidget {
  const SportsNewsScreen({super.key});
  @override
  State<SportsNewsScreen> createState() => _SportsNewsScreenState();
}

class _SportsNewsScreenState extends State<SportsNewsScreen>
    with WidgetsBindingObserver {
  static const _categories = ['all', 'football', 'cricket', 'f1'];
  final _search = TextEditingController();
  final _feeds = <String, SportsNewsFeed>{}, _errors = <String, String>{};
  final _loading = <String>{};
  List<Fixture> _fixtures = [];
  int _tab = 0;
  bool _foreground = true, _loadingMatches = false;
  Timer? _timer;
  String get _category => _categories[_tab];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    unawaited(_matches());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) {
        _load();
        unawaited(_matches());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load();
      unawaited(_matches());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final category = _category;
    if (_loading.contains(category)) return;
    setState(() => _loading.add(category));
    try {
      final feed = await SportsNewsService.load(category);
      if (mounted)
        setState(() {
          _feeds[category] = feed;
          _errors.remove(category);
        });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _errors[category] = 'Could not refresh news. Pull down to retry.',
        );
    } finally {
      if (mounted) setState(() => _loading.remove(category));
    }
  }

  Future<void> _matches() async {
    if (_loadingMatches) return;
    _loadingMatches = true;
    try {
      final now = DateTime.now(),
          fixtures = await FeedService().loadFixtures(remote: true);
      final selected = sortFixtures(
        fixtures
            .where(
              (f) =>
                  f.kickoff.isAfter(now.subtract(const Duration(hours: 24))) &&
                  !RegExp(
                    r'ballon|award|ceremony',
                    caseSensitive: false,
                  ).hasMatch('${f.league} ${f.title}'),
            )
            .toList(),
        now,
      ).take(8).toList();
      if (mounted) setState(() => _fixtures = selected);
      await ScoreService.instance.refresh(selected);
    } catch (_) {
    } finally {
      _loadingMatches = false;
    }
  }

  String _age(DateTime date) {
    final d = DateTime.now().difference(date);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${date.toLocal().day}/${date.toLocal().month} · ${d.inDays}d ago';
  }

  bool _today(DateTime date) {
    final d = date.toLocal(), n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  void _watch(Fixture f) {
    if (!f.hasStream) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No stream is available for this match yet.'),
        ),
      );
      return;
    }
    SupportGate.guard(context, () {
      if (mounted)
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              title: f.title,
              url: f.url,
              altUrl: f.hasAlt ? f.altUrl : null,
              isLive: f.phaseAt(DateTime.now()) == MatchPhase.live,
              chatMatch: f.title,
            ),
          ),
        );
    });
  }

  Widget _matchesStrip() => ValueListenableBuilder<Map<String, LiveScore>>(
    valueListenable: ScoreService.instance.scores,
    builder: (context, scores, _) => SizedBox(
      height: 155,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _fixtures.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = _fixtures[i];
          final score = scores[f.id];
          return SizedBox(
            width: 230,
            child: Material(
              color: Ui.panel,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _watch(f),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              score?.statusLabel ??
                                  (f.kickoff.isAfter(DateTime.now())
                                      ? fanClock(f.kickoff)
                                      : 'Score unavailable'),
                              style: TextStyle(
                                color: score?.live == true
                                    ? Ui.green
                                    : Ui.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              f.league,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Ui.dim, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final home in [true, false])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              TeamCrest(
                                logo: home ? f.homeLogo : f.awayLogo,
                                size: 26,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  home ? f.home : f.away,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                score == null
                                    ? '–'
                                    : '${home ? score.home : score.away}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
    ),
  );
  Widget _article(SportsNewsArticle article) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => openInApp(context, article.url, title: article.source),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (article.image != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        article.image!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.newspaper_rounded, size: 15, color: Ui.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${article.source} · ${_age(article.publishedAt)}',
                    style: TextStyle(color: Ui.muted, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Share headline',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.ios_share, size: 18),
                  onPressed: () async {
                    try {
                      await Share.share(
                        '${article.title}\n${article.source}\n${article.url}',
                      );
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final feed = _feeds[_category], query = _search.text.trim().toLowerCase();
    final items = (feed?.items ?? const <SportsNewsArticle>[])
        .where(
          (a) =>
              query.isEmpty ||
              '${a.title} ${a.source}'.toLowerCase().contains(query),
        )
        .toList();
    final today = items.where((a) => _today(a.publishedAt)).toList(),
        earlier = items.where((a) => !_today(a.publishedAt)).toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search sports headlines',
            filled: true,
            fillColor: Ui.panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh news',
            onPressed: _loading.contains(_category) ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          XTabBar(
            labels: const ['All sports', 'Football', 'Cricket', 'F1'],
            index: _tab,
            onTap: (i) {
              setState(() => _tab = i);
              _load();
            },
          ),
          if (_loading.contains(_category))
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_load(), _matches()]);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (query.isEmpty &&
                      (_tab == 0 || _tab == 1) &&
                      _fixtures.isNotEmpty) ...[
                    _heading('Sports'),
                    _matchesStrip(),
                  ],
                  if (feed?.stale == true || _errors.containsKey(_category))
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _errors[_category] ??
                            'Showing saved headlines. Pull down to refresh.',
                        style: TextStyle(color: Ui.muted),
                      ),
                    ),
                  if (query.isNotEmpty)
                    _heading('Search results')
                  else
                    _heading("Today's News"),
                  if (today.isNotEmpty)
                    for (final article in today) _article(article),
                  if (query.isEmpty && today.isEmpty && items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No new headlines for today yet. Here are the latest available stories.',
                        style: TextStyle(color: Ui.muted),
                      ),
                    ),
                  if (earlier.isNotEmpty) ...[
                    if (query.isEmpty) _heading('Latest headlines'),
                    for (final article in earlier) _article(article),
                  ],
                  if (items.isEmpty && !_loading.contains(_category))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 48,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            query.isEmpty
                                ? Icons.newspaper_outlined
                                : Icons.search_off,
                            size: 44,
                            color: Ui.dim,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            query.isNotEmpty
                                ? 'No recent headlines match your search.'
                                : feed?.unavailable == true
                                ? 'News sources are temporarily unavailable. Pull down to retry.'
                                : 'Headlines will appear here when available.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ui.muted),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Headlines from BBC Sport and Sky Sports. Tap a story to read the original article.',
                      style: TextStyle(color: Ui.dim, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
