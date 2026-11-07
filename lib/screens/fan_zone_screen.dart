import '../models/fan_prediction.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fixture.dart';
import '../services/content_sync.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../services/support_gate.dart';
import '../widgets/status_pill.dart';
import '../services/remote_config.dart';
import 'player_screen.dart';
import 'notifications_screen.dart';
import 'prediction_results_screen.dart';
import '../theme/app_theme.dart';
import 'fan_posts_feed.dart';
import 'fan_profile_screen.dart';
import 'fan_widgets.dart';
import 'match_rooms_screen.dart';
import 'highlights_screen.dart';
import 'movies_screen.dart';
import 'tv_screen.dart';
import 'content_shortcut_screen.dart';
import 'sports_news_screen.dart';
import '../services/auth_service.dart';
import '../utils/safe_error_message.dart';

String _error(Object e) => safeErrorMessage(e);

enum FanZonePage { predict, ranks, banter, rooms }

class FanZoneScreen extends StatefulWidget {
  final bool active;
  final FanZonePage page;
  final VoidCallback? onPredict, onOpenMenu, onExit;

  /// Hides the app bar when this page is shown inside another screen that
  /// already has one (e.g. Ranks opened from the Predict page).
  final bool embedded;

  /// Thread tab in the main shell: profile avatar and a Predict button in
  /// the header (Movies now has its own bottom tab).
  final bool threadHeader;

  /// Opened as a pushed page: show a normal back button instead of the avatar.
  final bool pushed;

  const FanZoneScreen({
    super.key,
    required this.active,
    this.page = FanZonePage.predict,
    this.onPredict,
    this.onOpenMenu,
    this.onExit,
    this.embedded = false,
    this.threadHeader = false,
    this.pushed = false,
  });
  @override
  State<FanZoneScreen> createState() => _FanZoneScreenState();
}

class _FanZoneScreenState extends State<FanZoneScreen>
    with WidgetsBindingObserver {
  final _feed = FeedService();
  List<Fixture> _fixtures = [];
  Map<String, dynamic> _data = {};
  String? _failure;
  bool _busy = false;
  bool _saving = false;
  bool _foreground = true;
  bool _loadedOnce = false;
  bool _openOnly = false;
  bool _showAllHistory = false;
  String _league = '';
  String _day = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContentSync.tick.addListener(_sync);
    if (widget.active) _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _sync());
  }

  @override
  void didUpdateWidget(covariant FanZoneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _sync();
  }

  void _sync() {
    if (widget.active && _foreground) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ContentSync.tick.removeListener(_sync);
    _timer?.cancel();
    _roomsTrigger.dispose();
    super.dispose();
  }

  final ValueNotifier<int> _roomsTrigger = ValueNotifier<int>(0);

  /// Header action: icon with its name written underneath.
  Widget _labeled(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool bold = false,
  }) => InkResponse(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  void _openRanks() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ContentShortcutScreen(
        title: 'Ranks',
        child: FanZoneScreen(
          active: true,
          page: FanZonePage.ranks,
          embedded: true,
        ),
      ),
    ),
  );

  String get _name => (_data['name'] ?? '').toString();
  String get _myId => (_data['id'] ?? '').toString();

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Load independently so fixture viewing still works during backend setup.
      final fixtures = await _feed.loadFixtures(remote: true);
      if (!mounted) return;
      setState(() => _fixtures = sortFixtures(fixtures, DateTime.now()));
      final data = await FanZoneService.call('state');
      if (mounted) {
        setState(() {
          _data = data;
          _failure = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failure = _error(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _notice(String text, {String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
  }

  Future<bool> _profile() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (_) => _NicknameSheet(initial: _name),
    );
    if (name == null || !mounted) return false;
    try {
      await FanZoneService.call('profile', body: {'name': name});
      if (!mounted) return false;
      setState(() => _data['name'] = name);
      await _refresh();
      return true;
    } catch (e) {
      _notice(_error(e));
      return false;
    }
  }

  Future<void> _pick(Fixture f) async {
    if (_saving) return;
    if (_name.isEmpty && !await _profile()) return;
    if (!mounted) return;
    final key = FanZoneService.matchKey(f);
    final picks = FanZoneService.rows(_data['picks']);
    final old = picks.where((p) => p['match_key'] == key).firstOrNull;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (_) => _PickSheet(
        fixture: f,
        home: (old?['home'] as num?)?.toInt() ?? 0,
        away: (old?['away'] as num?)?.toInt() ?? 0,
        editing: old != null,
        market: old == null ? 'result' : old['market'] as String? ?? 'score',
        selection: old == null ? '1' : old['selection'] as String? ?? '',
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await FanZoneService.call('pick', body: {'key': key, ...result});
      await _refresh();
      _notice(
        'Prediction saved: ${fanPredictionLabel(result)}. Good luck!',
        action: 'Share',
        onAction: () => Share.share(
          'My prediction: ${f.title}: ${fanPredictionLabel(result)}. Join me on Deeprowss!',
        ),
      );
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openProfile(String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FanProfileScreen(userId: id)),
    );
    if (mounted) _refresh();
  }

  void _discussion(String room, String title, {Fixture? match}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FanDiscussion(
          room: room,
          title: title,
          match: match,
          name: _name,
          myId: _myId,
          onJoin: _profile,
        ),
      ),
    );
  }

  void _openPredictionMatch(Fixture f) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: f.title,
          subtitle: '${f.league.isEmpty ? 'Football' : f.league} • ${fanClock(f.kickoff)}',
          url: f.url,
          altUrl: f.hasAlt ? f.altUrl : null,
              moreUrls: f.moreUrls,
          isLive: f.phaseAt(DateTime.now()) == MatchPhase.live,
          chatMatch: f.title,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.page == FanZonePage.rooms) return _roomsPage();
    final title = switch (widget.page) {
      FanZonePage.predict => 'Predict',
      FanZonePage.ranks => 'Ranks',
      FanZonePage.banter => 'Deeprowss',
      FanZonePage.rooms => 'Match Room',
    };
    final shortcut = switch (widget.page) {
      FanZonePage.predict => 'Highlights',
      FanZonePage.ranks => 'TV',
      FanZonePage.banter => 'Movies',
      FanZonePage.rooms => 'Match Room',
    };
    final icon = switch (widget.page) {
      FanZonePage.predict => Icons.play_circle_outline_rounded,
      FanZonePage.ranks => Icons.live_tv_outlined,
      FanZonePage.banter => Icons.movie_outlined,
      FanZonePage.rooms => Icons.groups_rounded,
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: widget.pushed ? null : 0,
        toolbarHeight: 62,
        leadingWidth: widget.pushed ? null : (widget.threadHeader ? 66 : 60),
        leading: widget.pushed
            ? null
            : widget.threadHeader
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkResponse(
                  onTap: () {
                    final id = AuthService.instance.user?.id ?? _myId;
                    if (_name.isEmpty && id.isEmpty) {
                      _profile();
                    } else if (id.isNotEmpty) {
                      _openProfile(id);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _name.isEmpty
                          ? const Icon(Icons.person_add_alt_1_rounded, size: 24)
                          : FanAvatar(
                              name: _name,
                              seed: _myId,
                              size: 26,
                              imageUrl: FanZoneService.avatarUrl(
                                _myId,
                                _data['avatar_at'],
                              ),
                            ),
                      const SizedBox(height: 2),
                      const Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            tooltip: widget.onOpenMenu != null
                ? 'Account menu'
                : 'Your public profile',
            onPressed: widget.onOpenMenu ??
                () {
                  final id = AuthService.instance.user?.id ?? _myId;
                  if (id.isNotEmpty) _openProfile(id);
                },
            icon: _name.isEmpty
                ? const Icon(Icons.person_add_alt_1_rounded)
                : FanAvatar(
                    name: _name,
                    seed: _myId,
                    size: 34,
                    imageUrl: FanZoneService.avatarUrl(
                      _myId,
                      _data['avatar_at'],
                    ),
                  ),
          ),
        ),
        centerTitle: widget.page == FanZonePage.banter,
        title: widget.threadHeader
            ? null
            : widget.page == FanZonePage.banter
            ? const Text(
                'Deeprowss',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    switch (widget.page) {
                      FanZonePage.predict =>
                        'Pick winners, draws or goals. Earn points.',
                      FanZonePage.ranks => 'Points count as matches end',
                      FanZonePage.banter => 'Deeprowss community',
                      FanZonePage.rooms => 'Live match chats',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Ui.muted,
                    ),
                  ),
                ],
              ),
        actions: [
          if (widget.page == FanZonePage.banter && !widget.threadHeader)
            IconButton(
              tooltip: 'Explore sports news',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SportsNewsScreen(),
                ),
              ),
            ),
          if (widget.threadHeader) ...[
            _labeled(Icons.leaderboard_rounded, 'Ranks', _openRanks),
            const NotificationBell(label: 'Alerts'),
            _labeled(
              Icons.fact_check_rounded,
              'My Results',
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PredictionResultsScreen(),
                ),
              ),
            ),
            _labeled(
              Icons.sports_soccer_rounded,
              'Predict',
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FanZoneScreen(
                    active: true,
                    page: FanZonePage.predict,
                    pushed: true,
                  ),
                ),
              ),
            ),
          ],
          if (widget.page == FanZonePage.predict)
            _labeled(
              Icons.leaderboard_rounded,
              'Ranks',
              _openRanks,
              bold: true,
            ),
          if (widget.onExit != null)
            IconButton(
              tooltip: 'Choose experience',
              onPressed: widget.onExit,
              icon: const Icon(Icons.apps_rounded),
            ),
          if (!widget.threadHeader && widget.page != FanZonePage.predict)
          IconButton(
            tooltip: shortcut,
            icon: Icon(icon),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ContentShortcutScreen(
                  title: shortcut,
                  child: switch (widget.page) {
                    FanZonePage.predict => const HighlightsScreen(),
                    FanZonePage.ranks => const TvScreen(),
                    FanZonePage.banter => const MoviesScreen(),
                    FanZonePage.rooms => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy
                ? null
                : () {
                    _refresh();
                    ContentSync.request(force: true);
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_failure != null) _failureBanner(),
          Expanded(
            child: switch (widget.page) {
              FanZonePage.predict => _predictions(),
              FanZonePage.ranks => _rankings(),
              FanZonePage.banter => _banter(),
              FanZonePage.rooms => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  // Match Room tab: live match rooms as cards (own page, no app bar).
  Widget _roomsPage() => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (_failure != null) _failureBanner(),
          Expanded(
            child: MatchRoomsView(
              fixtures: _fixtures,
              loading: !_loadedOnce,
              onRefresh: _refresh,
              onOpenLounge: () => _discussion('lounge', 'Fan lounge'),
              onOpenMatch: (f) =>
                  _discussion(FanZoneService.matchKey(f), f.title, match: f),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _failureBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    decoration: fanBox(
      color: Theme.of(context).colorScheme.error.withValues(alpha: .12),
      border: Theme.of(context).colorScheme.error.withValues(alpha: .4),
      radius: 14,
    ),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(_failure!, style: const TextStyle(fontSize: 13))),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // PREDICT TAB
  // ---------------------------------------------------------------------------

  Widget _predictions() {
    final picks = FanZoneService.rows(_data['picks']);
    final stats = FanStats.from(picks);
    final now = DateTime.now();
    final leagues = <String>{
      for (final f in _fixtures)
        if (f.league.isNotEmpty) f.league,
    }.toList()..sort();
    final byLeague = _fixtures
        .where((f) => _league.isEmpty || f.league == _league)
        .toList();

    // Open matches, grouped by day (the day strip lets the fan jump to one).
    final openAll = byLeague.where((f) => now.isBefore(f.kickoff)).toList()
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final dayCounts = <String, int>{};
    for (final f in openAll) {
      final label = fanDayLabel(f.kickoff, now);
      dayCounts[label] = (dayCounts[label] ?? 0) + 1;
    }
    final activeDay = dayCounts.containsKey(_day) ? _day : '';
    final open = openAll
        .where(
          (f) => activeDay.isEmpty || fanDayLabel(f.kickoff, now) == activeDay,
        )
        .toList();
    final started = _openOnly
        ? <Fixture>[]
        : byLeague.where((f) => !now.isBefore(f.kickoff)).toList();
    final groups = <String, List<Fixture>>{};
    for (final f in open) {
      groups.putIfAbsent(fanDayLabel(f.kickoff, now), () => []).add(f);
    }
    // Pending predictions are not listed; only settled ones (and pushes).
    final settledPicks = picks
        .where((p) => fanPickPoints(p) != null || fanPredictionPush(p))
        .toList();
    final history = _showAllHistory ? settledPicks : settledPicks.take(5).toList();
    final pending = picks.where((p) => fanPickPoints(p) == null).length;
    final nextUp = openAll.firstOrNull;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _hero(stats, pending),
          const SizedBox(height: 14),
          _rules(),
          if (_name.isNotEmpty) ...[
            const FanSectionTitle(
              'Achievements',
              icon: Icons.military_tech_rounded,
            ),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final b in fanBadgesFor(stats)) FanBadgeTile(b),
                ],
              ),
            ),
          ],
          if (nextUp != null &&
              picks.every(
                (p) => p['match_key'] != FanZoneService.matchKey(nextUp),
              )) ...[
            const FanSectionTitle('Next up', icon: Icons.bolt_rounded),
            _nextUpCard(nextUp, now),
          ],
          if (_fixtures.isNotEmpty) ...[
            const FanSectionTitle(
              'Fixtures',
              icon: Icons.sports_soccer_rounded,
            ),
            _days(dayCounts, activeDay, openAll.length),
            const SizedBox(height: 10),
            _filters(leagues),
          ],
          if (!_loadedOnce && _fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Column(
                children: [FanSkeleton(height: 190), FanSkeleton(height: 190)],
              ),
            ),
          if (_loadedOnce && byLeague.isEmpty)
            FanEmpty(
              icon: Icons.event_busy_rounded,
              title: 'No fixtures to predict',
              message: _league.isEmpty
                  ? 'New matches appear here as soon as they are scheduled. Pull down to refresh.'
                  : 'No matches in $_league right now. Try another league.',
              action: _league.isEmpty
                  ? null
                  : OutlinedButton(
                      onPressed: () => setState(() => _league = ''),
                      child: const Text('Show all leagues'),
                    ),
            ),
          const SizedBox(height: 12),
          for (final entry in groups.entries) ...[
            _dayHeader(entry.key, entry.value.length),
            for (final f in entry.value) _fixture(f, picks, now),
          ],
          if (_loadedOnce && open.isEmpty && byLeague.isNotEmpty && _openOnly)
            const FanEmpty(
              icon: Icons.lock_clock_rounded,
              title: 'Nothing open right now',
              message:
                  'Every match has kicked off. Check back for new fixtures.',
            ),
          if (started.isNotEmpty) ...[
            const FanSectionTitle(
              'Started or finished',
              icon: Icons.lock_clock_rounded,
            ),
            for (final f in started) _closedFixture(f, picks),
          ],
          if (settledPicks.isNotEmpty) ...[
            FanSectionTitle(
              'Your predictions',
              icon: Icons.history_rounded,
              trailing: settledPicks.length > 5
                  ? (_showAllHistory
                        ? 'Show less'
                        : 'Show all ${settledPicks.length}')
                  : null,
              onTrailing: () =>
                  setState(() => _showAllHistory = !_showAllHistory),
            ),
            for (final p in history) _historyCard(p),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PredictionResultsScreen(),
                  ),
                ),
                icon: const Icon(Icons.fact_check_rounded, size: 18),
                label: const Text('Open my results board'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayHeader(String label, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
    child: Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w900,
            color: Ui.redSoft,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: Ui.line, height: 1)),
        const SizedBox(width: 10),
        Text(
          '$count ${count == 1 ? 'match' : 'matches'}',
          style: TextStyle(fontSize: 11, color: Ui.dim),
        ),
      ],
    ),
  );

  Widget _hero(FanStats stats, int pending) {
    final level = fanLevelFor(stats.points);
    final next = fanNextLevel(stats.points);
    final progress = next == null
        ? 1.0
        : ((stats.points - level.min) / (next.min - level.min))
              .clamp(0.0, 1.0)
              .toDouble();
    final toNext = next == null ? 0 : next.min - stats.points;
    return FanHero(
      color: _name.isEmpty ? Ui.red : level.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _name.isEmpty
                  ? Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .08),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.person_rounded, size: 32),
                    )
                  : FanLevelAvatar(
                      name: _name,
                      seed: _myId,
                      progress: progress,
                      color: level.color,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name.isEmpty ? 'Know football? Prove it.' : _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_name.isEmpty)
                      Text(
                        'Make your predictions and climb the league table.',
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FanLevelPill(level),
                          Text(
                            '#${fanShortId(_myId)}',
                            style: TextStyle(color: Ui.dim, fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_name.isEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _profile,
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('Join the Fan Zone'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    next == null
                        ? 'Top level reached. You are a Fan Zone Legend!'
                        : '$toNext more point${toNext == 1 ? '' : 's'} to reach ${next.name}',
                    style: TextStyle(fontSize: 12, color: Ui.muted),
                  ),
                ),
                if (pending > 0)
                  FanPill(
                    text: '$pending awaiting result',
                    color: fanBlue,
                    icon: Icons.hourglass_bottom_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FanStatTile(
                  icon: Icons.stars_rounded,
                  value: stats.points,
                  label: 'Points',
                  color: fanGold,
                ),
                FanStatTile(
                  icon: Icons.track_changes_rounded,
                  value: stats.exact,
                  label: 'Exact',
                  color: Ui.green,
                ),
                FanStatTile(
                  icon: Icons.percent_rounded,
                  value: stats.accuracy,
                  label: 'Accuracy',
                  color: fanBlue,
                  empty: stats.settled == 0,
                ),
                FanStatTile(
                  icon: Icons.local_fire_department_rounded,
                  value: stats.streak,
                  label: 'Streak',
                  color: fanOrange,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rules() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: fanBox(radius: 18),
    child: Row(
      children: [
        _rule(Icons.track_changes_rounded, '+3', 'Exact score', Ui.green),
        _ruleDivider(),
        _rule(
          Icons.check_circle_outline_rounded,
          '+1',
          'Winner or draw',
          fanBlue,
        ),
        _ruleDivider(),
        _rule(
          Icons.lock_outline_rounded,
          'Locks',
          'At kickoff',
          const Color(0xFFFFB300),
        ),
      ],
    ),
  );

  Widget _ruleDivider() => Container(width: 1, height: 34, color: Ui.line);

  Widget _rule(IconData icon, String big, String small, Color color) =>
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  big,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(small, style: TextStyle(fontSize: 10, color: Ui.muted)),
              ],
            ),
          ],
        ),
      );

  Widget _days(Map<String, int> counts, String active, int total) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        FanChip(
          label: 'All',
          icon: Icons.calendar_view_week_rounded,
          badge: '$total',
          selected: active.isEmpty,
          onTap: () => setState(() => _day = ''),
        ),
        for (final e in counts.entries) ...[
          const SizedBox(width: 8),
          FanChip(
            label: e.key,
            badge: '${e.value}',
            selected: active == e.key,
            onTap: () => setState(() => _day = e.key),
          ),
        ],
      ],
    ),
  );

  Widget _filters(List<String> leagues) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        FanChip(
          label: 'Open only',
          icon: Icons.lock_open_rounded,
          color: Ui.green,
          selected: _openOnly,
          onTap: () => setState(() => _openOnly = !_openOnly),
        ),
        const SizedBox(width: 8),
        FanChip(
          label: 'All leagues',
          icon: Icons.public_rounded,
          color: fanBlue,
          selected: _league.isEmpty,
          onTap: () => setState(() => _league = ''),
        ),
        for (final l in leagues) ...[
          const SizedBox(width: 8),
          FanChip(
            label: l,
            color: fanBlue,
            selected: _league == l,
            onTap: () => setState(() => _league = l),
          ),
        ],
      ],
    ),
  );

  Widget _team(String name, String logo, {double size = 42}) => Expanded(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: .06),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: TeamCrest(logo: logo, size: size),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            height: 1.1,
          ),
        ),
      ],
    ),
  );

  /// The soonest match gets a bigger card with a live countdown line.
  Widget _nextUpCard(Fixture f, DateTime now) {
    final until = f.kickoff.difference(now);
    return FanHero(
      color: const Color(0xFFFFB300),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.league.isEmpty ? 'Football' : f.league,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Ui.muted,
                  ),
                ),
              ),
              FanPill(
                text: until.inMinutes < 1
                    ? 'Kicking off'
                    : 'Locks in ${fanCountdown(until)}',
                color: const Color(0xFFFFB300),
                icon: Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _team(f.home, f.homeLogo, size: 50),
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      fanClock(f.kickoff),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      fanDayLabel(f.kickoff, now),
                      style: TextStyle(fontSize: 12, color: Ui.muted),
                    ),
                  ],
                ),
              ),
              _team(f.away, f.awayLogo, size: 50),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: !_saving && _failure == null ? () => _pick(f) : null,
              icon: const Icon(Icons.sports_score_rounded, size: 18),
              label: const Text('Predict this match'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixture(Fixture f, List<Map<String, dynamic>> picks, DateTime now) {
    final key = FanZoneService.matchKey(f);
    final pick = picks.where((p) => p['match_key'] == key).firstOrNull;
    final until = f.kickoff.difference(now);
    final soon = until.inHours < 24;
    final accent = pick != null ? Ui.green : Ui.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: pick != null ? Ui.green.withValues(alpha: .5) : Ui.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: .20), Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 15, color: Ui.redSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    f.league.isEmpty ? 'Football' : f.league,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Ui.muted,
                    ),
                  ),
                ),
                FanPill(
                  text: soon
                      ? 'Locks in ${fanCountdown(until)}'
                      : fanClock(f.kickoff),
                  color: soon ? const Color(0xFFFFB300) : Ui.muted,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _team(f.home, f.homeLogo),
                    SizedBox(
                      width: 76,
                      child: pick != null
                          ? Column(
                              children: [
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Ui.green.withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Ui.green.withValues(alpha: .5),
                                    ),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      fanPredictionLabel(pick),
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        color: Ui.green,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'YOUR PICK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: Ui.muted,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'VS',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Ui.dim,
                                  ),
                                ),
                                Text(
                                  fanClock(f.kickoff),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Ui.muted,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    _team(f.away, f.awayLogo),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: !_saving && _failure == null
                            ? () => _pick(f)
                            : null,
                        icon: Icon(
                          pick == null
                              ? Icons.sports_soccer_rounded
                              : Icons.edit_rounded,
                          size: 18,
                        ),
                        label: Text(
                          pick == null ? 'Make prediction' : 'Edit pick',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (pick != null)
                      IconButton.outlined(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Share my pick',
                        onPressed: () => Share.share(
                          'My prediction: ${f.title}: ${fanPredictionLabel(pick)}. Join me on Deeprowss!',
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                      ),
                    IconButton.outlined(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Match chat',
                      onPressed: () => _openPredictionMatch(f),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _closedFixture(Fixture f, List<Map<String, dynamic>> picks) {
    final key = FanZoneService.matchKey(f);
    final pick = picks.where((p) => p['match_key'] == key).firstOrNull;
    final live = f.phaseAt(DateTime.now()) == MatchPhase.live;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: fanBox(
        radius: 16,
        border: live ? fanAlert.withValues(alpha: .45) : null,
      ),
      child: Row(
        children: [
          TeamCrest(logo: f.homeLogo, size: 32),
          const SizedBox(width: 4),
          TeamCrest(logo: f.awayLogo, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  pick == null
                      ? '${f.league.isEmpty ? 'Football' : f.league} • picks locked'
                      : 'Your pick: ${fanPredictionLabel(pick)}',
                  style: TextStyle(fontSize: 12, color: Ui.muted),
                ),
              ],
            ),
          ),
          if (live)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FanLiveDot(),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: fanAlert,
                  ),
                ),
              ],
            )
          else
            Icon(Icons.lock_outline_rounded, size: 16, color: Ui.dim),
          IconButton(
            tooltip: 'Match chat',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openPredictionMatch(f),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> p) {
    final points = fanPickPoints(p);
    final (Color color, String badge) = switch (points) {
      3 => (Ui.green, '+3 Exact'),
      1 => (fanBlue, '+1 Correct'),
      0 => (fanAlert, '0 Missed'),
      _ => (Ui.muted, fanPredictionPush(p) ? 'Push / refunded' : 'Pending'),
    };
    final settled = p['result_home'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: fanBox(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _scoreChip(
                                'You',
                                fanPredictionLabel(p),
                                Ui.muted,
                              ),
                              if (settled) ...[
                                const SizedBox(width: 8),
                                _scoreChip(
                                  'Final',
                                  '${p['result_home']} – ${p['result_away']}',
                                  color,
                                ),
                              ] else ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Checking final score automatically',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Ui.dim,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (!settled &&
                              (_data['result_sync'] as Map?)?['status'] ==
                                  'unavailable')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Score provider unavailable. Retrying automatically.',
                                style: TextStyle(fontSize: 11, color: Ui.dim),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FanPill(text: badge, color: color),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreChip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Ui.dim)),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // RANKS TAB
  // ---------------------------------------------------------------------------

  bool _moreRanks = false;
  Future<void> _loadMoreRanks() async {
    if (_moreRanks || _data['board_next'] == null) return;
    setState(() => _moreRanks = true);
    try {
      final page = await FanZoneService.call(
        'leaderboard',
        query: {'offset': '${_data['board_next']}'},
      );
      if (!mounted) return;
      if (page['week'] != _data['week']) {
        await _refresh();
        return;
      }
      setState(() {
        final rows = FanZoneService.rows(_data['leaderboard']);
        final ids = rows.map((r) => r['id']).toSet();
        _data['leaderboard'] = [
          ...rows,
          ...FanZoneService.rows(
            page['leaderboard'],
          ).where((r) => !ids.contains(r['id'])),
        ];
        _data['board_next'] = page['board_next'];
      });
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _moreRanks = false);
    }
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _weekLabel(dynamic ms) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      (ms as num).toInt(),
      isUtc: true,
    );
    final end = start.add(const Duration(days: 6));
    return '${start.day} ${_monthNames[start.month - 1]} – '
        '${end.day} ${_monthNames[end.month - 1]}';
  }

  /// The top three the admin published for a finished week.
  Widget _weekWinners(Map<String, dynamic> week, {required bool latest}) {
    const medals = ['🥇', '🥈', '🥉'];
    final winners = FanZoneService.rows(week['winners']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: fanBox(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latest
                      ? 'Weekly winners · ${_weekLabel(week['week'])}'
                      : _weekLabel(week['week']),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in winners)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    medals[(((w['rank'] as num?) ?? 1).toInt() - 1)
                        .clamp(0, 2)
                        .toInt()],
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${w['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${w['points']} pts',
                    style: TextStyle(
                      color: Ui.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _winnerCards() {
    final weeks = FanZoneService.rows(_data['winners']);
    if (weeks.isEmpty) return const [];
    return [
      _weekWinners(weeks.first, latest: true),
      if (weeks.length > 1)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Earlier weeks',
              style: TextStyle(color: Ui.muted, fontWeight: FontWeight.w800),
            ),
            children: [
              for (final w in weeks.skip(1)) _weekWinners(w, latest: false),
            ],
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  // ---------------------------------------------------------------- ranks

  static const _gold = Color(0xFFFFC857);
  static const _silver = Color(0xFFC0C7D1);
  static const _bronze = Color(0xFFCD8B5A);
  static const _tick = Color(0xFF1D9BF0);

  bool _isPremiumRow(Map<String, dynamic> r) =>
      r['is_premium'] == 1 || r['is_premium'] == true;

  Widget _rankAvatar(Map<String, dynamic> r, double size) => FanAvatar(
    name: '${r['name']}',
    seed: '${r['id']}',
    size: size,
    imageUrl: FanZoneService.avatarUrl('${r['id']}', r['avatar_at']),
  );

  Widget _nameWithTick(Map<String, dynamic> r, {double size = 14, TextAlign? align}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '${r['name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
          ),
        ),
        if (_isPremiumRow(r)) ...[
          const SizedBox(width: 3),
          Icon(Icons.verified_rounded, color: _tick, size: size + 1),
        ],
      ],
    );
  }

  Widget _prizeBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_gold.withValues(alpha: .22), _gold.withValues(alpha: .06)],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gold.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        const Icon(Icons.emoji_events_rounded, color: _gold, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top 3 win Premium every week',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
              ),
              const SizedBox(height: 2),
              Text(
                '7 days of Premium + blue tick',
                style: TextStyle(color: Ui.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ---- Premier League style table -------------------------------------------

  static const double _colStat = 30;
  static const double _colPts = 40;

  int _n(Map<String, dynamic> r, List<String> keys) {
    for (final k in keys) {
      final v = r[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  Widget _tableHead() {
    TextStyle st({bool strong = false}) => TextStyle(
      color: strong ? Colors.white : Ui.muted,
      fontSize: 11.5,
      fontWeight: FontWeight.w900,
      letterSpacing: .4,
    );
    Widget cell(String t, double w, {bool strong = false}) => SizedBox(
      width: w,
      child: Text(t, textAlign: TextAlign.center, style: st(strong: strong)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      decoration: BoxDecoration(
        color: Ui.cardDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Ui.line)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          SizedBox(width: 34, child: Text('#', textAlign: TextAlign.center, style: st())),
          const SizedBox(width: 6),
          Expanded(child: Text('FAN', style: st())),
          cell('P', _colStat),
          cell('W', _colStat),
          cell('L', _colStat),
          cell('PTS', _colPts, strong: true),
        ],
      ),
    );
  }

  Widget _tableRow(int index, Map<String, dynamic> r, String myId, {required bool last}) {
    final mine = '${r['id']}' == myId;
    final pos = index + 1;
    final w = _n(r, const ['won', 'w']);
    final l = _n(r, const ['lost', 'l']);
    final p = w + l;
    // Prize zone: the top three win Premium every week.
    final zone = pos == 1 ? _gold : (pos == 2 ? _silver : (pos == 3 ? _bronze : null));
    Widget stat(int v, {bool dim = false}) => SizedBox(
      width: _colStat,
      child: Text(
        '$v',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: dim ? Ui.dim : null,
        ),
      ),
    );
    return Material(
      color: mine ? Ui.red.withValues(alpha: .12) : Colors.transparent,
      child: InkWell(
        onTap: () => _openProfile('${r['id']}'),
        child: Container(
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: Ui.line.withValues(alpha: .6))),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: zone ?? Colors.transparent),
                const SizedBox(width: 2),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$pos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: zone ?? Ui.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        _rankAvatar(r, 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _nameWithTick(r, size: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                stat(p, dim: true),
                stat(w),
                stat(l, dim: true),
                SizedBox(
                  width: _colPts,
                  child: Text(
                    '${r['points'] ?? 0}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableLegend() {
    Widget item(String k, String v) => Padding(
      padding: const EdgeInsets.only(right: 14, bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k ',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
            ),
            TextSpan(text: v, style: TextStyle(color: Ui.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
    return Wrap(
      children: [
        item('P', 'Played'),
        item('W', 'Won'),
        item('L', 'Lost'),
        item('PTS', 'Points'),
      ],
    );
  }

  Widget _leagueTable(List<Map<String, dynamic>> rows, String myId) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
      ),
      child: Column(
        children: [
          _tableHead(),
          for (var i = 0; i < rows.length; i++)
            _tableRow(i, rows[i], myId, last: i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _pointsPill(String emoji, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Ui.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Ui.line),
    ),
    child: Text(
      '$emoji  $label',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  void _showRankRules() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How the table works',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final line in const [
                'Everyone starts on 0. Points land when a match ends and the final score is confirmed.',
                'Exact score = 3 pts. Right outcome or market = 1 pt. Missed = 0.',
                'Pushes do not count.',
                'Ties: points, then wins, then fewer losses, then account ID. P = played, W = won, L = lost.',
                'Tap any fan to open their profile.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 10),
                        child: Icon(Icons.circle, size: 6, color: Ui.red),
                      ),
                      Expanded(
                        child: Text(
                          line,
                          style: TextStyle(color: Ui.muted, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankings() {
    final rows = FanZoneService.rows(_data['leaderboard']);
    final myId = '${_data['id']}';
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fan League',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'How the table works',
                onPressed: _showRankRules,
                icon: Icon(Icons.info_outline_rounded, color: Ui.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _prizeBanner(),
          const SizedBox(height: 16),
          if (rows.isEmpty && _loadedOnce)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'No fans on the table yet',
                  style: TextStyle(color: Ui.muted),
                ),
              ),
            )
          else ...[
            _leagueTable(rows, myId),
            const SizedBox(height: 10),
            _tableLegend(),
          ],
          if (_data['board_next'] != null)
            TextButton(
              onPressed: _moreRanks ? null : _loadMoreRanks,
              child: Text(_moreRanks ? 'Loading…' : 'Show more fans'),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pointsPill('🎯', 'Exact score +3'),
              _pointsPill('✅', 'Right outcome +1'),
              _pointsPill('❌', 'Missed 0'),
            ],
          ),
          const SizedBox(height: 18),
          ..._winnerCards(),
        ],
      ),
    );
  }

  Widget _banter() => FanPostsFeed(
    active: widget.active,
    viewerName: _name,
    viewerAvatarAt: _data['avatar_at'],
    onJoin: () async {
      if (_name.isNotEmpty) return true;
      return _profile();
    },
    onOpenLounge: () => _discussion('lounge', 'Fan lounge'),
    fixtures: _fixtures,
    onOpenMatch: (f) =>
        _discussion(FanZoneService.matchKey(f), f.title, match: f),
    roomsTrigger: _roomsTrigger,
  );
}

// -----------------------------------------------------------------------------
// NICKNAME SHEET
// -----------------------------------------------------------------------------

class _NicknameSheet extends StatefulWidget {
  final String initial;
  const _NicknameSheet({required this.initial});
  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  late final _input = TextEditingController(text: widget.initial);
  String? _problem;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final v = _input.text.trim();
    if (v.length < 3 || v.length > 30) {
      setState(() => _problem = 'Use 3 to 30 characters.');
      return;
    }
    if (RegExp(r'[\u0000-\u001f<>]').hasMatch(v)) {
      setState(() => _problem = 'Remove special characters like < and >.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, v, __) =>
                  FanAvatar(name: v.text, seed: v.text, size: 72),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.initial.isEmpty ? 'Choose your nickname' : 'Change nickname',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Your name and rank are public. Your profile is linked to your Gmail account. Log in on another device to recover your nickname, predictions and posts.',
            style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            maxLength: 30,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
            decoration: InputDecoration(
              hintText: 'e.g. GoalMachine10',
              errorText: _problem,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save nickname'),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SCORE PICKER SHEET
// -----------------------------------------------------------------------------

/// Saves the signed-in user's prediction for [f] (asks for a Fan Zone name
/// first if needed). The server verifies the result against the ESPN final
/// score and the points appear in the Ranks table. Returns the saved
/// prediction label, or null if the user closed the sheet.
Future<String?> saveFanPrediction(BuildContext context, Fixture f) async {
  final data = await FanZoneService.call('state');
  if (!context.mounted) return null;
  if ('${data['name'] ?? ''}'.isEmpty) {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (_) => const _NicknameSheet(initial: ''),
    );
    if (name == null) return null;
    await FanZoneService.call('profile', body: {'name': name});
    if (!context.mounted) return null;
  }
  final key = FanZoneService.matchKey(f);
  final old = FanZoneService.rows(
    data['picks'],
  ).where((p) => p['match_key'] == key).firstOrNull;
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Ui.panel,
    builder: (_) => _PickSheet(
      fixture: f,
      home: (old?['home'] as num?)?.toInt() ?? 0,
      away: (old?['away'] as num?)?.toInt() ?? 0,
      editing: old != null,
      market: old == null ? 'result' : old['market'] as String? ?? 'score',
      selection: old == null ? '1' : old['selection'] as String? ?? '',
    ),
  );
  if (result == null) return null;
  await FanZoneService.call('pick', body: {'key': key, ...result});
  return fanPredictionLabel(result);
}

class _PickSheet extends StatefulWidget {
  final Fixture fixture;
  final int home, away;
  final bool editing;
  final String market, selection;
  const _PickSheet({
    required this.fixture,
    required this.home,
    required this.away,
    required this.editing,
    required this.market,
    required this.selection,
  });
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late int _home = widget.home, _away = widget.away;
  late String _market = widget.market, _selection = widget.selection;
  static const markets = {
    'result': 'Straight win / Draw',
    'double_chance': 'Double chance',
    'totals': 'Over / Under goals',
    'btts': 'Both teams to score',
    'score': 'Correct score',
  };
  Map<String, String> get choices => switch (_market) {
    'result' => {
      '1': '${widget.fixture.home} win',
      'X': 'Draw',
      '2': '${widget.fixture.away} win',
    },
    'double_chance' => {
      '1X': 'Home or draw',
      'X2': 'Away or draw',
      '12': 'Either team wins',
    },
    'btts' => {'yes': 'Yes', 'no': 'No'},
    'totals' => {
      for (final line in [
        '0.5',
        '1',
        '1.5',
        '2',
        '2.5',
        '3',
        '3.5',
        '4',
        '4.5',
      ])
        for (final side in ['over', 'under'])
          '${side}_$line': '${side == 'over' ? 'Over' : 'Under'} $line goals',
    },
    _ => {},
  };
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.fixture.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '90-minute result. Predictions lock at kickoff.',
              style: TextStyle(color: Ui.muted),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _market,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Prediction market'),
              items: markets.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _market = v!;
                _selection = choices.isEmpty ? '' : choices.keys.first;
              }),
            ),
            const SizedBox(height: 16),
            if (_market == 'score')
              Row(
                children: [
                  for (final home in [true, false])
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            home ? widget.fixture.home : widget.fixture.away,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () => setState(() {
                                  if (home && _home > 0) _home--;
                                  if (!home && _away > 0) _away--;
                                }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(
                                '${home ? _home : _away}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() {
                                  if (home && _home < 20) _home++;
                                  if (!home && _away < 20) _away++;
                                }),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in choices.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _selection == e.key,
                      onSelected: (_) => setState(() => _selection = e.key),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            const Text(
              'Exact score: 3 points; correct outcome or market: 1 point. Integer goal lines are refunded if the total equals the line.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _market != 'score' && !choices.containsKey(_selection)
                  ? null
                  : () => Navigator.pop(context, <String, dynamic>{
                      'home': _home,
                      'away': _away,
                      'market': _market,
                      'selection': _market == 'score' ? '' : _selection,
                    }),
              icon: const Icon(Icons.lock_outline),
              label: Text(
                widget.editing ? 'Update prediction' : 'Save prediction',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// LIVE CHAT ROOM (match rooms and the fan lounge)
// -----------------------------------------------------------------------------

class _FanDiscussion extends StatefulWidget {
  final String room, title, name, myId;
  final Future<bool> Function() onJoin;

  /// The match this room belongs to (null for the fan lounge): shown as a
  /// card at the top so people can jump from the chat to watching it.
  final Fixture? match;
  const _FanDiscussion({
    required this.room,
    required this.title,
    this.match,
    required this.name,
    required this.myId,
    required this.onJoin,
  });
  @override
  State<_FanDiscussion> createState() => _FanDiscussionState();
}

class _FanDiscussionState extends State<_FanDiscussion>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  Set<String> _blocked = {};
  String? _failure;
  bool _loading = false, _sending = false, _joined = false, _foreground = true;
  bool _loadedOnce = false;
  String _myId = '';
  Timer? _poll;

  static const _reactions = ['🔥', '⚽', '👏', '😂', '😤', '🙌', '💀'];

  @override
  void initState() {
    super.initState();
    _joined = widget.name.isNotEmpty;
    _myId = widget.myId;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_foreground) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final blocked = await FanZoneService.blocked();
      final data = await FanZoneService.call(
        'messages',
        query: {'room': widget.room},
      );
      if (_myId.isEmpty) {
        // The state call knows who "me" is; use it so own bubbles align right.
        try {
          final state = await FanZoneService.call('state');
          _myId = (state['id'] ?? '').toString();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _messages = FanZoneService.rows(data['messages']);
          _blocked = blocked;
          _failure = null;
          _loadedOnce = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failure = _error(e);
          _loadedOnce = true;
        });
      }
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
        );
    }
  }

  Future<void> _send() async {
    if (_sending || _input.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await FanZoneService.call(
        'message',
        body: {'room': widget.room, 'text': _input.text.trim()},
      );
      if (!mounted) return;
      _input.clear();
      await _refresh();
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _react(String emoji) {
    final t = _input.text;
    _input.value = TextEditingValue(
      text: '$t$emoji',
      selection: TextSelection.collapsed(offset: t.length + emoji.length),
    );
  }

  Future<void> _action(String action, Map<String, dynamic> message) async {
    try {
      if (action == 'block') {
        await FanZoneService.block(message['user_id'].toString());
        if (mounted) {
          setState(() => _blocked.add(message['user_id'].toString()));
        }
        _notice('Fan blocked on this device.');
      } else {
        if (!_joined) {
          if (!await widget.onJoin()) return;
          if (mounted) setState(() => _joined = true);
        }
        await FanZoneService.call(
          'report',
          body: {'id': message['id'], 'reason': 'Inappropriate content'},
        );
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(_error(e));
    }
  }

  void _menu(Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report abuse'),
              onTap: () {
                Navigator.pop(ctx);
                _action('report', m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('Block fan'),
              subtitle: const Text('Hides their messages on this device'),
              onTap: () {
                Navigator.pop(ctx);
                _action('block', m);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = _myId.isNotEmpty && m['user_id'] == _myId;
    final name = '${m['name']}';
    final at = DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt());
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final textColor = mine ? Ui.palette.onAccent : onSurface;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * .74,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: mine ? Ui.red : Ui.card,
        border: mine ? null : Border.all(color: Ui.line),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fanColor('${m['user_id']}'),
                ),
              ),
            ),
          Text(
            '${m['text']}',
            style: TextStyle(fontSize: 15, height: 1.3, color: textColor),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              fanClock(at),
              style: TextStyle(
                fontSize: 10,
                color: textColor.withValues(alpha: .65),
              ),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      onLongPress: mine ? null : () => _menu(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Row(
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FanProfileScreen(userId: '${m['user_id']}'),
                  ),
                ),
                child: FanAvatar(name: name, seed: '${m['user_id']}', size: 28),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }

  void _watchMatch(Fixture f) {
    SupportGate.guard(context, () {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            title: f.title,
            subtitle:
                '${f.league.isEmpty ? 'Football' : f.league} • ${fanClock(f.kickoff)}',
            url: f.url,
            altUrl: f.hasAlt ? f.altUrl : null,
            moreUrls: f.moreUrls,
            isLive: f.phaseAt(DateTime.now()) == MatchPhase.live,
            chatMatch: f.title,
          ),
        ),
      );
    });
  }

  /// The exact match this room is about, with a button to watch it.
  Widget _matchCard(Fixture f) {
    final phase = f.phaseAt(DateTime.now());
    final canWatch = f.hasStream && phase != MatchPhase.ended;
    return InkWell(
      onTap: canWatch ? () => _watchMatch(f) : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Ui.line),
        ),
        child: Row(
          children: [
            TeamCrest(logo: f.homeLogo, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      StatusPill(phase: phase),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${f.league.isEmpty ? 'Football' : f.league} • ${fanClock(f.kickoff)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Ui.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TeamCrest(logo: f.awayLogo, size: 38),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canWatch ? () => _watchMatch(f) : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                phase == MatchPhase.ended ? 'Ended' : 'Watch',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _messages
        .where((m) => !_blocked.contains(m['user_id']))
        .toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Ui.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Live chat',
                  style: TextStyle(fontSize: 12, color: Ui.muted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_blocked.isNotEmpty)
            IconButton(
              tooltip: 'Unblock all fans',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () async {
                await FanZoneService.unblockAll();
                if (mounted) setState(() => _blocked = {});
              },
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.match != null) _matchCard(widget.match!),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Ui.card,
              child: Text(
                'Friendly banter only. Long-press a message to report abuse or block a fan.',
                style: TextStyle(fontSize: 12, color: Ui.muted),
              ),
            ),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: _loadedOnce
                          ? const FanEmpty(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Start the conversation!',
                              message:
                                  'Be the first to share your thoughts on this one.',
                            )
                          : const CircularProgressIndicator(),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: visible.length,
                      itemBuilder: (context, i) =>
                          _bubble(visible[visible.length - 1 - i]),
                    ),
            ),
            if (!_joined)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (await widget.onJoin() && mounted) {
                        setState(() => _joined = true);
                      }
                    },
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Choose a nickname to join'),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final e in _reactions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _react(e),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: fanBox(radius: 20),
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 300,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Share your football gist…',
                          filled: true,
                          fillColor: Ui.card,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Ui.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Ui.line),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
