import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fixture.dart';
import '../services/content_sync.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'fan_posts_feed.dart';
import 'fan_widgets.dart';
import 'highlights_screen.dart';
import 'movies_screen.dart';
import 'tv_screen.dart';
import 'content_shortcut_screen.dart';

String _error(Object e) => e.toString().replaceFirst('Exception: ', '');

enum FanZonePage { predict, ranks, banter }

class FanZoneScreen extends StatefulWidget {
  final bool active;
  final FanZonePage page;
  final VoidCallback? onPredict;
  const FanZoneScreen({
    super.key,
    required this.active,
    this.page = FanZonePage.predict,
    this.onPredict,
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
  int _rankShown = 20;
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
    super.dispose();
  }

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

  Future<void> _sharePick(Fixture f, int home, int away) async {
    try {
      await Share.share(
        'My Fan Zone prediction: ${f.home} $home - $away ${f.away}\n'
        'Think you can do better? Predict on Deeprowss Fan Zone.',
      );
    } catch (_) {
      _notice('Could not open the share sheet.');
    }
  }

  Future<void> _pick(Fixture f) async {
    if (_saving) return;
    if (_name.isEmpty && !await _profile()) return;
    if (!mounted) return;
    final key = FanZoneService.matchKey(f);
    final picks = FanZoneService.rows(_data['picks']);
    final old = picks.where((p) => p['match_key'] == key).firstOrNull;
    final result = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ui.panel,
      builder: (_) => _PickSheet(
        fixture: f,
        home: (old?['home'] as num?)?.toInt() ?? 0,
        away: (old?['away'] as num?)?.toInt() ?? 0,
        editing: old != null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await FanZoneService.call(
        'pick',
        body: {'key': key, 'home': result[0], 'away': result[1]},
      );
      await _refresh();
      _notice(
        'Prediction locked in: ${result[0]} – ${result[1]}. Good luck!',
        action: 'Share',
        onAction: () => _sharePick(f, result[0], result[1]),
      );
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discussion(String room, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FanDiscussion(
          room: room,
          title: title,
          name: _name,
          myId: _myId,
          onJoin: _profile,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.page) {
      FanZonePage.predict => 'Fan Zone',
      FanZonePage.ranks => 'Ranks',
      FanZonePage.banter => 'Banter',
    };
    final shortcut = switch (widget.page) {
      FanZonePage.predict => 'Highlights',
      FanZonePage.ranks => 'TV',
      FanZonePage.banter => 'Movies',
    };
    final icon = switch (widget.page) {
      FanZonePage.predict => Icons.play_circle_outline_rounded,
      FanZonePage.ranks => Icons.live_tv_outlined,
      FanZonePage.banter => Icons.movie_outlined,
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        toolbarHeight: 62,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              switch (widget.page) {
                FanZonePage.predict => 'Predict scores. Earn points. Level up.',
                FanZonePage.ranks => 'This week\'s best fans',
                FanZonePage.banter => 'Gist, bet slips and live chat',
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Your nickname',
              onPressed: _profile,
              icon: _name.isEmpty
                  ? const Icon(Icons.person_add_alt_1_rounded)
                  : FanAvatar(name: _name, seed: _myId, size: 32),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_failure != null) _failureBanner(),
          Expanded(
            child: switch (widget.page) {
              FanZonePage.predict => _predictions(),
              FanZonePage.ranks => _rankings(),
              FanZonePage.banter => _banter(),
            },
          ),
        ],
      ),
    );
  }

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
    final history = _showAllHistory ? picks : picks.take(5).toList();
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
            const FanSectionTitle('Achievements', icon: Icons.military_tech_rounded),
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
          if (nextUp != null && picks.every((p) => p['match_key'] != FanZoneService.matchKey(nextUp))) ...[
            const FanSectionTitle('Next up', icon: Icons.bolt_rounded),
            _nextUpCard(nextUp, now),
          ],
          if (_fixtures.isNotEmpty) ...[
            const FanSectionTitle('Fixtures', icon: Icons.sports_soccer_rounded),
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
          if (picks.isNotEmpty) ...[
            FanSectionTitle(
              'Your predictions',
              icon: Icons.history_rounded,
              trailing: picks.length > 5
                  ? (_showAllHistory ? 'Show less' : 'Show all ${picks.length}')
                  : null,
              onTrailing: () =>
                  setState(() => _showAllHistory = !_showAllHistory),
            ),
            for (final p in history) _historyCard(p),
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
                        'Pick a nickname, predict scores, climb the weekly table.',
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
        _rule(Icons.check_circle_outline_rounded, '+1', 'Winner or draw', fanBlue),
        _ruleDivider(),
        _rule(Icons.lock_outline_rounded, 'Locks', 'At kickoff', const Color(0xFFFFB300)),
      ],
    ),
  );

  Widget _ruleDivider() =>
      Container(width: 1, height: 34, color: Ui.line);

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

  Widget _team(String name, String logo, {double size = 58}) => Expanded(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: .06),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: TeamCrest(logo: logo, size: size),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            height: 1.15,
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _team(f.home, f.homeLogo, size: 64),
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      fanClock(f.kickoff),
                      style: const TextStyle(
                        fontSize: 24,
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
              _team(f.away, f.awayLogo, size: 64),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: pick != null ? Ui.green.withValues(alpha: .5) : Ui.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _team(f.home, f.homeLogo),
                    SizedBox(
                      width: 88,
                      child: pick != null
                          ? Column(
                              children: [
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
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
                                      '${pick['home']} – ${pick['away']}',
                                      style: TextStyle(
                                        fontSize: 24,
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
                                const SizedBox(height: 10),
                                Text(
                                  'VS',
                                  style: TextStyle(
                                    fontSize: 22,
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: !_saving && _failure == null
                            ? () => _pick(f)
                            : null,
                        icon: Icon(
                          pick == null
                              ? Icons.sports_soccer_rounded
                              : Icons.edit_rounded,
                          size: 18,
                        ),
                        label: Text(pick == null ? 'Predict score' : 'Edit pick'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (pick != null)
                      IconButton.outlined(
                        tooltip: 'Share my pick',
                        onPressed: () => _sharePick(
                          f,
                          (pick['home'] as num).toInt(),
                          (pick['away'] as num).toInt(),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                      ),
                    IconButton.outlined(
                      tooltip: 'Match chat',
                      onPressed: () => _discussion(key, f.title),
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
                      : 'Your pick: ${pick['home']} – ${pick['away']}',
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
            onPressed: () => _discussion(key, f.title),
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
      1 => (fanBlue, '+1 Winner'),
      0 => (fanAlert, '0 Missed'),
      _ => (Ui.muted, 'Pending'),
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
                              _scoreChip('You', '${p['home']} – ${p['away']}', Ui.muted),
                              if (settled) ...[
                                const SizedBox(width: 8),
                                _scoreChip(
                                  'Final',
                                  '${p['result_home']} – ${p['result_away']}',
                                  color,
                                ),
                              ] else ...[
                                const SizedBox(width: 8),
                                Text(
                                  'awaiting result',
                                  style: TextStyle(fontSize: 11, color: Ui.dim),
                                ),
                              ],
                            ],
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

  Widget _rankings() {
    final rows = FanZoneService.rows(_data['leaderboard']);
    final myId = _data['id'];
    final rank = rows.indexWhere((r) => r['id'] == myId);
    final week = (_data['week'] as num?)?.toInt();
    Duration? resets;
    if (week != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(week + 604800000)
          .difference(DateTime.now());
      if (!d.isNegative) resets = d;
    }
    final top = rows.take(3).toList();
    final rest = rows.length > 3 ? rows.sublist(3) : <Map<String, dynamic>>[];
    final shownRest = rest.take(_rankShown).toList();
    final leaderPoints = rows.isEmpty ? 1 : ((rows.first['points'] as num?)?.toInt() ?? 1);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _ranksHero(rows, rank, resets),
          if (!_loadedOnce && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: FanSkeleton(height: 220),
            ),
          if (_loadedOnce && rows.isEmpty)
            FanEmpty(
              icon: Icons.emoji_events_outlined,
              title: 'No ranked fans yet',
              message:
                  'Rankings start once this week\'s matches are confirmed. Make your picks to be first on the board.',
              action: Builder(
                builder: (tabContext) => FilledButton.icon(
                  onPressed: widget.onPredict,
                  icon: const Icon(Icons.sports_score_rounded, size: 18),
                  label: const Text('Make predictions'),
                ),
              ),
            ),
          if (top.isNotEmpty) ...[
            const FanSectionTitle('Top of the table', icon: Icons.emoji_events_rounded),
            _podium(top, myId),
          ],
          if (rest.isNotEmpty) ...[
            const FanSectionTitle('The chasing pack', icon: Icons.groups_rounded),
            for (var i = 0; i < shownRest.length; i++)
              _rankRow(i + 4, shownRest[i], myId, leaderPoints),
            if (rest.length > shownRest.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _rankShown += 20),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('Show ${rest.length - shownRest.length} more'),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Text(
            'Ranked by points, then fewer settled picks. Nicknames may be shared; the short ID identifies each fan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Ui.dim, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _ranksHero(
    List<Map<String, dynamic>> rows,
    int rank,
    Duration? resets,
  ) {
    final mine = rank >= 0 ? rows[rank] : null;
    final myPoints = (mine?['points'] as num?)?.toInt() ?? 0;
    String gap = '';
    if (rank > 0) {
      final above = (rows[rank - 1]['points'] as num?)?.toInt() ?? 0;
      final diff = above - myPoints;
      gap = diff <= 0
          ? 'Level on points with #$rank'
          : '$diff pt${diff == 1 ? '' : 's'} behind #$rank';
    } else if (rank == 0) {
      gap = 'You lead the table. Defend it!';
    }
    return FanHero(
      color: fanGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fanGold.withValues(alpha: .18),
                  border: Border.all(color: fanGold.withValues(alpha: .6)),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: fanGold,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weekly top 100',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Points reset every week. Everyone starts level.',
                      style: TextStyle(color: Ui.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: fanGold.withValues(alpha: .22)),
            ),
            child: mine == null
                ? Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 20, color: Ui.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your rank shows once a confirmed result puts you in the top 100.',
                          style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR RANK',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w800,
                              color: Ui.muted,
                            ),
                          ),
                          FanCountUp(
                            value: rank + 1,
                            style: const TextStyle(
                              fontSize: 40,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              color: fanGold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$myPoints points',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (gap.isNotEmpty)
                              Text(
                                gap,
                                style: TextStyle(color: Ui.muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (resets != null) ...[
            const SizedBox(height: 12),
            FanPill(
              text: 'Resets in ${fanCountdown(resets)}',
              color: fanGold,
              icon: Icons.timer_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _podium(List<Map<String, dynamic>> top, dynamic myId) {
    Map<String, dynamic>? at(int i) => i < top.length ? top[i] : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
      decoration: fanBox(radius: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _spot(2, at(1), 84, myId)),
          Expanded(child: _spot(1, at(0), 112, myId)),
          Expanded(child: _spot(3, at(2), 64, myId)),
        ],
      ),
    );
  }

  Widget _spot(int rank, Map<String, dynamic>? r, double height, dynamic myId) {
    if (r == null) return const SizedBox.shrink();
    final name = '${r['name']}';
    final me = r['id'] == myId;
    final points = (r['points'] as num?)?.toInt() ?? 0;
    final medal = rank == 1
        ? fanGold
        : rank == 2
        ? const Color(0xFFB0BEC5)
        : const Color(0xFFCD7F32);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          const Icon(Icons.workspace_premium_rounded, color: fanGold, size: 30)
        else
          const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: medal, width: 2.5),
            boxShadow: [
              BoxShadow(color: medal.withValues(alpha: .4), blurRadius: 16),
            ],
          ),
          child: FanAvatar(
            name: name,
            seed: '${r['id']}',
            size: rank == 1 ? 62 : 50,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            me ? '$name (you)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: me ? Ui.redSoft : null,
            ),
          ),
        ),
        const SizedBox(height: 4),
        FanLevelPill(fanLevelFor(points)),
        const SizedBox(height: 8),
        Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: medal.withValues(alpha: .45)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [medal.withValues(alpha: .42), medal.withValues(alpha: .04)],
            ),
          ),
          child: Column(
            children: [
              Text(
                '$rank',
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: medal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$points pts',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rankRow(int rank, Map<String, dynamic> r, dynamic myId, int leader) {
    final me = r['id'] == myId;
    final name = '${r['name']}';
    final points = (r['points'] as num?)?.toInt() ?? 0;
    final level = fanLevelFor(points);
    final share = leader <= 0 ? 0.0 : (points / leader).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: fanBox(
        radius: 16,
        color: me ? Ui.red.withValues(alpha: .13) : null,
        border: me ? Ui.red.withValues(alpha: .55) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: me ? Ui.redSoft : Ui.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FanAvatar(name: name, seed: '${r['id']}', size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        me ? '$name (you)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(level.icon, size: 13, color: level.color),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 4,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      me ? Ui.red : level.color,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fan ${fanShortId(r['id'])} • ${r['played']} settled',
                  style: TextStyle(fontSize: 11, color: Ui.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              Text('pts', style: TextStyle(fontSize: 10, color: Ui.muted)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BANTER TAB
  // ---------------------------------------------------------------------------

  Widget _banter() => FanPostsFeed(
    active: widget.active,
    onJoin: () async {
      if (_name.isNotEmpty) return true;
      return _profile();
    },
    onOpenLounge: () => _discussion('lounge', 'Fan lounge'),
    fixtures: _fixtures,
    onOpenMatch: (f) => _discussion(FanZoneService.matchKey(f), f.title),
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

class _PickSheet extends StatefulWidget {
  final Fixture fixture;
  final int home, away;
  final bool editing;
  const _PickSheet({
    required this.fixture,
    required this.home,
    required this.away,
    required this.editing,
  });
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late int _home = widget.home;
  late int _away = widget.away;

  static const _quick = [
    [1, 0],
    [2, 0],
    [2, 1],
    [3, 1],
    [1, 1],
    [0, 0],
    [2, 2],
    [0, 1],
    [0, 2],
    [1, 2],
    [1, 3],
  ];

  String get _verdict {
    final f = widget.fixture;
    if (_home == _away) return 'You predict a draw';
    return _home > _away
        ? 'You predict ${f.home} to win'
        : 'You predict ${f.away} to win';
  }

  Widget _stepper(
    String name,
    String logo,
    int value,
    void Function(int) set,
  ) => Expanded(
    child: Column(
      children: [
        TeamCrest(logo: logo, size: 52),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        IconButton.filledTonal(
          onPressed: value >= 20 ? null : () => set(value + 1),
          icon: const Icon(Icons.add_rounded),
        ),
        Container(
          width: 84,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Ui.red.withValues(alpha: .35)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Ui.red.withValues(alpha: .22), Ui.cardDeep],
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Text(
              '$value',
              key: ValueKey<int>(value),
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: value <= 0 ? null : () => set(value - 1),
          icon: const Icon(Icons.remove_rounded),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.editing
                  ? 'Edit your prediction'
                  : 'Predict the final score',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${f.league.isEmpty ? 'Football' : f.league} • locks at ${fanClock(f.kickoff)}',
              style: TextStyle(color: Ui.muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stepper(
                  f.home,
                  f.homeLogo,
                  _home,
                  (v) => setState(() => _home = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 126),
                  child: Text(
                    '–',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Ui.dim,
                    ),
                  ),
                ),
                _stepper(
                  f.away,
                  f.awayLogo,
                  _away,
                  (v) => setState(() => _away = v),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FanPill(text: _verdict, color: Ui.green, icon: Icons.bolt_rounded),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _quick)
                  ChoiceChip(
                    label: Text('${s[0]} – ${s[1]}'),
                    selected: _home == s[0] && _away == s[1],
                    onSelected: (_) => setState(() {
                      _home = s[0];
                      _away = s[1];
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, [_home, _away]),
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: Text(
                  widget.editing ? 'Update prediction' : 'Lock in prediction',
                ),
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
  const _FanDiscussion({
    required this.room,
    required this.title,
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
              FanAvatar(name: name, seed: '${m['user_id']}', size: 28),
              const SizedBox(width: 6),
            ],
            Flexible(child: bubble),
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
                              message: 'Be the first to share your thoughts on this one.',
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
