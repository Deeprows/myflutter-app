import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/safe_error_message.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fixture.dart';
import '../services/analysis_history.dart';
import '../services/bet_slip_pdf.dart';
import '../services/app_memory.dart';
import '../services/content_sync.dart';
import '../models/live_score.dart';
import '../services/score_service.dart';
import '../services/fan_zone_service.dart';
import '../services/subscription_service.dart';
import '../services/remote_config.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/league_filter.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'fan_profile_screen.dart';
import 'fan_widgets.dart';
import '../models/fan_prediction.dart';
import 'content_shortcut_screen.dart';
import 'prediction_results_screen.dart';
import 'bet_browser_screen.dart';
import 'bet_slip_screen.dart';
import 'fan_zone_screen.dart' show FanZonePage, FanZoneScreen, saveFanPrediction;
import 'remove_ads_screen.dart';
import 'plans_screen.dart';

class AiPredictScreen extends StatefulWidget {
  final bool active;
  const AiPredictScreen({super.key, required this.active});
  @override
  State<AiPredictScreen> createState() => _AiPredictScreenState();
}

class _AiPredictScreenState extends State<AiPredictScreen> {
  List<Fixture> _fixtures = [];

  /// Upcoming matches from other sources (the server's ESPN feed) that are not
  /// in the app's own fixture list. Any league ESPN lists can be picked here.
  /// The user's own saved predictions with their ESPN-verified results.
  List<Map<String, dynamic>> _myPicks = [];
  List<Fixture> _ext = [];
  bool _extLoading = false;
  String? _extError;
  /// Selected league chip ([LeagueFilter.all], [LeagueFilter.national],
  /// [LeagueFilter.women] or a league name) and how many rows are showing.
  String _filter = LeagueFilter.all;
  int _shown = 20;

  /// Matchups the user typed in themselves. Teams are resolved on the server.
  final List<Fixture> _custom = [];
  final TextEditingController _typed = TextEditingController();
  bool _typedWomen = false;
  final ScrollController _scroll = ScrollController();
  final ScrollMemory _scrollMemory = ScrollMemory('ai_predict_scroll');
  final Set<String> _selected = {};
  final Map<String, BetSlipPick> _slipSelections = {}; // selectable AI Picks for the printable slip
  final Set<String> _dailyFreePicks = {};
  bool _dailyPicksLoaded = false;
  bool _weeklyPremium = false;
  final Map<String, Map<String, dynamic>> _results = {};
  final Map<String, String> _failures = {};

  /// Per result: the market chip chosen on the match's page. [_rev] makes the
  /// pushed match page rebuild when a chip is tapped.
  final Map<String, String> _market = {};
  final ValueNotifier<int> _rev = ValueNotifier<int>(0);
  bool _loading = false, _busy = false;
  String? _error;
  int _done = 0, _total = 0;
  // Bumped to cancel the analysis that is running: its loop and any answer
  // still on the way are then ignored.
  int _run = 0;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _scrollMemory.save(_scroll.offset));
    _loadDailyFreePicks();
    _loadHistory();
    _refreshWeeklyPremium();
    ContentSync.tick.addListener(_sync);
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant AiPredictScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  void _sync() {
    if (widget.active && !_busy) _load();
  }

  void _openProfile() {
    final id = AuthService.instance.user?.id ?? '';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            id.isEmpty ? const AuthScreen() : FanProfileScreen(userId: id),
      ),
    );
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_sync);
    _typed.dispose();
    _scrollMemory.dispose();
    _scroll.dispose();
    _rev.dispose();
    super.dispose();
  }

  List<Fixture> get _all => [..._custom, ..._fixtures, ..._ext];
  static bool _isCustom(Fixture f) => f.id.startsWith('custom:');
  static bool _isExternal(Fixture f) => f.id.startsWith('ext:');

  /// Matches read straight from ESPN by the app (when the server's list is
  /// unavailable). They are analysed by team names, like typed matchups.
  static bool _isWeb(Fixture f) => f.id.startsWith('web:');

  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  void _prune() {
    final keys = _all.map(FanZoneService.matchKey).toSet();
    _selected.retainAll(keys);
  }

  Future<void> _load({bool fresh = false}) async {
    if (!mounted || _loading || _busy) return;
    setState(() => _loading = true);
    try {
      final fixtures = await FeedService().loadFixtures(remote: true);
      if (!mounted) return;
      setState(() {
        _fixtures = <String, Fixture>{
          for (final f in sortFixtures(fixtures, DateTime.now()))
            if (f.kickoff.isAfter(DateTime.now()))
              FanZoneService.matchKey(f): f,
        }.values.toList();
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load matches. Pull down to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadExt(fresh: fresh);
    unawaited(_loadMyPicks());
    if (mounted) {
      setState(_prune);
      // Back to where the user was scrolled, once the match list is on screen.
      _scrollMemory.restoreOnce(() => _scroll, () => mounted);
    }
  }

  /// Loading the state also makes the server check any finished matches.
  Future<void> _loadMyPicks() async {
    if (!AuthService.instance.signedIn) return;
    try {
      final data = await FanZoneService.call('state');
      if (!mounted) return;
      setState(() => _myPicks = FanZoneService.rows(data['picks']).take(40).toList());
    } catch (_) {}
  }

  /// A pick with the Live screen's full-time score filled in, so the result
  /// shows straight away while the server confirms it for the Ranks table.
  Map<String, dynamic> _withLiveResult(Map<String, dynamic> p) {
    if (p['result_home'] != null) return p;
    final key = '${p['match_key']}';
    for (final f in _fixtures) {
      if (FanZoneService.matchKey(f) != key) continue;
      final s = ScoreService.instance.scoreFor(f.id);
      if (s == null || !s.finished) return p;
      final clock = s.clock.toUpperCase();
      if (clock.isNotEmpty && clock != 'FT' && clock != 'FULL-TIME') return p;
      return {...p, 'result_home': s.home, 'result_away': s.away, 'provisional': true};
    }
    return p;
  }

  Widget _myPredictions() => ValueListenableBuilder<Map<String, LiveScore>>(
    valueListenable: ScoreService.instance.scores,
    builder: (context, _, _) => _myPredictionsCard(),
  );

  Widget _myPredictionsCard() {
    if (_myPicks.isEmpty) return const SizedBox.shrink();
    final all = _myPicks.map(_withLiveResult).toList();
    final shown = all.take(5).toList();
    final pending = all.where((p) => fanPredictionScore(p) == null && !fanPredictionPush(p)).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Ui.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MY PREDICTIONS',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w900, color: _lt(const Color(0xFFB39DFF), const Color(0xFF6A4CD6))),
                  ),
                ),
                if (pending > 0)
                  Text('$pending awaiting final score', style: TextStyle(fontSize: 11, color: Ui.muted)),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in shown) _myPickRow(p),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PredictionResultsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_rounded, size: 16),
                  label: const Text('All results'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ContentShortcutScreen(
                        title: 'Ranks',
                        child: FanZoneScreen(active: true, page: FanZonePage.ranks, embedded: true),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.leaderboard_rounded, size: 16),
                  label: const Text('See Ranks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "My pick: …  •  Final 2–1", plus the server's reason when a finished
  /// match is still waiting for a verified score.
  String _pickSubtitle(Map<String, dynamic> p, bool settled) {
    final mine = 'My pick: ${fanPredictionLabel(p)}';
    if (settled) {
      final sure = p['provisional'] == true ? ' (confirming…)' : '';
      return '$mine  •  Final ${p['result_home']}–${p['result_away']}$sure';
    }
    final note = '${p['result_note'] ?? ''}';
    final kickoff = ((p['kickoff'] as num?) ?? 0).toInt();
    final late = DateTime.now().millisecondsSinceEpoch > kickoff + 3 * 3600000;
    return note.isNotEmpty && late ? '$mine\n$note' : mine;
  }

  Widget _myPickRow(Map<String, dynamic> p) {
    final pts = fanPredictionScore(p);
    final push = fanPredictionPush(p);
    final (Color c, String badge) = switch (pts) {
      3 => (Ui.green, '+3 Exact'),
      1 => (const Color(0xFF42A5F5), '+1 Correct'),
      0 => (const Color(0xFFEF5350), '0 Missed'),
      _ => (Ui.muted, push ? 'Refunded' : 'Pending'),
    };
    final settled = p['result_home'] != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text(
                  _pickSubtitle(p, settled),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Ui.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c)),
          ),
        ],
      ),
    );
  }

  /// Upcoming matches from ESPN across all leagues, so any match can be picked
  /// and analysed (not just the ones in the app's own list).
  Future<void> _loadExt({bool fresh = false}) async {
    if (!mounted || _extLoading) return;
    setState(() {
      _extLoading = true;
      _extError = null;
    });
    try {
      final data = await FanZoneService.call(
        'ai-predict/matches',
        query: fresh ? {'fresh': '1'} : null,
      );
      final own = {for (final f in _fixtures) '${_n(f.home)}|${_n(f.away)}'};
      final list = <Fixture>[];
      for (final m in FanZoneService.rows(data['matches'])) {
        final id = '${m['id'] ?? ''}';
        final kickoff = DateTime.tryParse('${m['kickoff'] ?? ''}');
        final home = '${m['home'] ?? ''}', away = '${m['away'] ?? ''}';
        if (id.isEmpty || kickoff == null || home.isEmpty || away.isEmpty) {
          continue;
        }
        if (!kickoff.isAfter(DateTime.now())) continue;
        // Already in the app's own list: don't show the same match twice.
        if (own.contains('${_n(home)}|${_n(away)}')) continue;
        list.add(
          Fixture(
            id: 'ext:$id',
            home: home,
            away: away,
            homeLogo: '${m['homeLogo'] ?? ''}',
            awayLogo: '${m['awayLogo'] ?? ''}',
            league: '${m['league'] ?? ''}'.trim().isNotEmpty
                ? '${m['league']}'
                : LeagueFilter.guessLeague(
                    '${m['leagueName'] ?? m['competition'] ?? m['slug'] ?? ''}',
                  ),
            kickoff: kickoff,
            gender: '${m['gender'] ?? ''}',
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _ext = list;
      });
    } catch (e) {
      // The server's list is unavailable: read the matches from ESPN directly.
      try {
        final direct = await _loadExtDirect();
        if (direct.isNotEmpty && mounted) {
          setState(() {
            _ext = direct;
            _extError = null;
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        final why = safeErrorMessage(e);
        setState(
          () => _extError = why.isEmpty || why.length > 220
              ? 'Could not load more matches. Pull to retry.'
              : 'Could not load more matches: $why',
        );
      }
    } finally {
      if (mounted) setState(() => _extLoading = false);
    }
  }

  static Map<String, String>? _leagueCatalogue;

  /// ESPN's list of soccer competitions (id -> name), read once per session.
  Future<Map<String, String>> _espnLeagueCatalogue() async {
    if (_leagueCatalogue != null) return _leagueCatalogue!;
    final out = <String, String>{};
    for (final url in const [
      'https://site.api.espn.com/apis/site/v2/sports/soccer/leagues',
      'https://site.web.api.espn.com/apis/site/v2/sports/soccer/leagues',
    ]) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(r.bodyBytes));
        void walk(dynamic n) {
          if (n is Map) {
            final id = n['id'], name = '${n['name'] ?? n['midsizeName'] ?? ''}'.trim();
            if (id != null && name.isNotEmpty && (n.containsKey('slug') || n.containsKey('abbreviation'))) {
              out['$id'] = name;
            }
            n.values.forEach(walk);
          } else if (n is List) {
            n.forEach(walk);
          }
        }
        walk(data);
        if (out.isNotEmpty) break;
      } catch (_) {}
    }
    return _leagueCatalogue = out;
  }

  /// Upcoming matches for the next 10 days from ESPN's public all-soccer
  /// scoreboard, read by the phone itself.
  Future<List<Fixture>> _loadExtDirect() async {
    String ymd(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now().toUtc();
    // One request per day, exactly like the Live screen's score lookups.
    Future<List<dynamic>> day(int offset) async {
      final d = ymd(now.add(Duration(days: offset)));
      const base =
          'https://site.api.espn.com/apis/site/v2/sports/soccer/all/scoreboard';
      for (final q in ['?dates=$d&limit=500', '?dates=$d']) {
        try {
          final r = await http
              .get(Uri.parse('$base$q'))
              .timeout(const Duration(seconds: 10));
          if (r.statusCode != 200) continue;
          final data = jsonDecode(utf8.decode(r.bodyBytes));
          if (data is Map && data['events'] is List) {
            // The feed names each competition once in "leagues"; every event carries its id inside "uid".
            final names = <String, String>{};
            if (data['leagues'] is List) {
              for (final l in data['leagues'] as List) {
                if (l is! Map) continue;
                final name = '${l['name'] ?? l['midsizeName'] ?? l['abbreviation'] ?? ''}'.trim();
                if (name.isEmpty) continue;
                if (l['id'] != null) names['${l['id']}'] = name;
                final m = RegExp(r'(?:^|~)l:(\d+)').firstMatch('${l['uid'] ?? ''}');
                if (m != null) names[m.group(1)!] = name;
              }
            }
            for (final ev in data['events'] as List) {
              if (ev is! Map || '${ev['leagueName'] ?? ''}'.isNotEmpty) continue;
              final m = RegExp(r'(?:^|~)l:(\d+)').firstMatch('${ev['uid'] ?? ''}');
              final name = m == null ? null : names[m.group(1)!];
              if (name != null) ev['leagueName'] = name;
            }
            return data['events'] as List;
          }
        } catch (_) {}
      }
      return const <dynamic>[];
    }

    // League-id -> name catalogue, used when a day's feed does not name a competition.
    final catalogue = await _espnLeagueCatalogue();
    final parts = await Future.wait([for (var i = 0; i <= 10; i++) day(i)]);
    final own = {for (final f in _fixtures) '${_n(f.home)}|${_n(f.away)}'};
    final seen = <String>{};
    final out = <Fixture>[];
    for (final e in parts.expand((x) => x)) {
      if (e is! Map) continue;
      final comps = e['competitions'];
      final comp = comps is List && comps.isNotEmpty && comps.first is Map
          ? comps.first as Map
          : null;
      final state = ((e['status'] ?? comp?['status']) as Map?)?['type']?['state'];
      final kickoff = DateTime.tryParse('${e['date'] ?? ''}');
      if (comp == null || state != 'pre' || kickoff == null) continue;
      if (!kickoff.isAfter(DateTime.now())) continue;
      final cs = comp['competitors'];
      if (cs is! List) continue;
      Map? team(String side) {
        for (final c in cs) {
          if (c is Map && c['homeAway'] == side && c['team'] is Map) {
            return c['team'] as Map;
          }
        }
        return null;
      }

      final h = team('home'), a = team('away');
      final home = '${h?['displayName'] ?? ''}', away = '${a?['displayName'] ?? ''}';
      if (home.isEmpty || away.isEmpty) continue;
      final key = '${_n(home)}|${_n(away)}';
      if (own.contains(key) || !seen.add('$key|${kickoff.toIso8601String().substring(0, 10)}')) {
        continue;
      }
      var league = '${(e['leagueName'] ?? (comp['league'] is Map ? comp['league']['name'] : null)) ?? ''}'.trim();
      if (league.isEmpty) {
        final m = RegExp(r'(?:^|~)l:(\d+)').firstMatch('${e['uid'] ?? ''}');
        league = (m == null ? null : catalogue[m.group(1)!]) ?? '';
      }
      if (league.isEmpty) {
        league = LeagueFilter.guessLeague(
          '${e['season'] is Map ? e['season']['slug'] ?? '' : ''} ${e['name'] ?? ''} ${comp['notes'] is List && (comp['notes'] as List).isNotEmpty ? (comp['notes'] as List).first['headline'] ?? '' : ''}',
        );
      }
      out.add(
        Fixture(
          id: 'web:${e['id']}',
          home: home,
          away: away,
          homeLogo: '${h?['logo'] ?? ''}',
          awayLogo: '${a?['logo'] ?? ''}',
          league: league.isEmpty ? 'Other leagues' : league,
          kickoff: kickoff.toLocal(),
        ),
      );
    }
    out.sort((x, y) => x.kickoff.compareTo(y.kickoff));
    return out.take(600).toList();
  }

  /// Every upcoming match that can be picked: the app's own list first, then
  /// everything ESPN lists (all leagues and national teams).
  List<Fixture> get _upcoming => [..._fixtures, ..._ext];

  /// The chip that is really applied. A league that has no matches after a
  /// refresh falls back to "All" instead of showing an empty list.
  String _activeFilter(List<Fixture> all) {
    if (_filter == LeagueFilter.all) return _filter;
    return all.any((f) => LeagueFilter.matches(f, _filter))
        ? _filter
        : LeagueFilter.all;
  }

  void _setFilter(String value) => setState(() {
    _filter = value;
    _shown = 20;
  });

  static String _filterName(String f) {
    if (f == LeagueFilter.all) return 'All';
    if (f == LeagueFilter.national) return 'National teams';
    if (f == LeagueFilter.women) return 'Women';
    return f;
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    IconData? icon,
  }) {
    const accent = Color(0xFF8E6BFF);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 15),
        label: Text(
          count == null ? label : '$label · $count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        selected: selected,
        selectedColor: accent.withValues(alpha: .28),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      ),
    );
  }

  /// One scrolling row of filters: All, National teams, Women, a league
  /// finder, then each league that has upcoming matches.
  Widget _filterBar(List<Fixture> all, String active) {
    final leagues = LeagueFilter.leaguesOf(all);
    final national = all.where(LeagueFilter.isNational).length;
    final women = all.where((f) => f.isWomen).length;
    final shownLeagues = leagues.take(24).toList();
    // A league picked from the finder stays visible in the row.
    if (!LeagueFilter.isSpecial(active) &&
        !shownLeagues.any((e) => e.key == active)) {
      final hit = leagues.where((e) => e.key == active);
      if (hit.isNotEmpty) shownLeagues.insert(0, hit.first);
    }
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            label: 'All',
            count: all.length,
            selected: active == LeagueFilter.all,
            onTap: () => _setFilter(LeagueFilter.all),
          ),
          if (national > 0)
            _filterChip(
              label: 'National teams',
              count: national,
              icon: Icons.flag_rounded,
              selected: active == LeagueFilter.national,
              onTap: () => _setFilter(LeagueFilter.national),
            ),
          if (women > 0)
            _filterChip(
              label: 'Women',
              count: women,
              selected: active == LeagueFilter.women,
              onTap: () => _setFilter(LeagueFilter.women),
            ),
          if (leagues.length > 6)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.search_rounded, size: 16),
                label: const Text(
                  'Find league',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => _openLeagueSheet(all, active),
              ),
            ),
          for (final e in shownLeagues)
            _filterChip(
              label: e.key,
              count: e.value,
              selected: active == e.key,
              onTap: () => _setFilter(e.key),
            ),
        ],
      ),
    );
  }

  Future<void> _openLeagueSheet(List<Fixture> all, String active) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeagueSheet(
        leagues: LeagueFilter.leaguesOf(all),
        total: all.length,
        active: active,
      ),
    );
    if (picked != null && mounted) _setFilter(picked);
  }

  /// League filter chips, then the upcoming matches under the chosen chip.
  /// The app's own matches and ESPN's matches share one list, so the chips
  /// filter both.
  List<Widget> _upcomingList() {
    final all = _upcoming;
    final active = _activeFilter(all);
    var list = all.where((f) => LeagueFilter.matches(f, active)).toList();
    // Inside a league the order is simply by kick-off time.
    if (active != LeagueFilter.all) {
      list.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    }
    final left = list.length - _shown;
    return [
      if (all.isNotEmpty) ...[
        _filterBar(all, active),
        const SizedBox(height: 10),
      ],
      if (_extLoading)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (_extError != null && _ext.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(child: Text(_extError!)),
              TextButton(onPressed: _loadExt, child: const Text('Retry')),
            ],
          ),
        ),
      if (list.isEmpty && all.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'No upcoming matches for ${_filterName(active)}.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      for (final f in list.take(_shown)) _matchTile(f),
      if (left > 0)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _shown += 20),
            child: Text('Show more ($left left)'),
          ),
        ),
    ];
  }

  static const _maxPicks = 3;
  static const _dailyPicksDayKey = 'ai_predict_free_picks_day';
  static const _dailyPicksListKey = 'ai_predict_free_picks_list';

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshWeeklyPremium() async {
    if (!AuthService.instance.signedIn) return;
    final active = await FanZoneService.hasWeeklyPremium();
    if (mounted && active != _weeklyPremium) {
      setState(() => _weeklyPremium = active);
    }
  }

  Future<void> _loadDailyFreePicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDay = prefs.getString(_dailyPicksDayKey);
      final picks = savedDay == _todayKey
          ? (prefs.getStringList(_dailyPicksListKey) ?? const <String>[])
          : const <String>[];
      if (savedDay != _todayKey) {
        await prefs.setString(_dailyPicksDayKey, _todayKey);
        await prefs.setStringList(_dailyPicksListKey, const <String>[]);
      }
      if (!mounted) return;
      setState(() {
        _dailyFreePicks
          ..clear()
          ..addAll(picks);
        _dailyPicksLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _dailyPicksLoaded = true);
    }
  }

  Future<void> _saveDailyFreePick(String key) async {
    _dailyFreePicks.add(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dailyPicksDayKey, _todayKey);
      await prefs.setStringList(
        _dailyPicksListKey,
        _dailyFreePicks.toList(),
      );
    } catch (_) {}
  }

  Future<bool> _showPremiumUpgrade() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionService.instance.visible
            ? const PlansScreen()
            : const RemoveAdsScreen(),
      ),
    );
    if (!mounted) return false;
    await SubscriptionService.instance.refresh(force: true);
    await _refreshWeeklyPremium();
    return SubscriptionService.instance.isPremium || _weeklyPremium;
  }

  Future<bool> _select(Fixture f, bool selected) async {
    if (_busy) return false;
    final key = FanZoneService.matchKey(f);
    if (!selected) {
      setState(() => _selected.remove(key));
      return true;
    }
    if (_selected.contains(key)) return true;

    if (!_dailyPicksLoaded) await _loadDailyFreePicks();
    if (!mounted) return false;

    final premium = SubscriptionService.instance.isPremium ||
        _weeklyPremium || await FanZoneService.hasWeeklyPremium();
    if (premium && !_weeklyPremium && mounted) setState(() => _weeklyPremium = true);
    // A free pick is used when a match is analysed, not when it is selected.
    // Matches already analysed today can be analysed again for free; the
    // rest (analysed + currently selected) may not go over the daily limit.
    if (!premium && !_dailyFreePicks.contains(key)) {
      final waiting = _selected.where((k) => !_dailyFreePicks.contains(k)).length;
      if (_dailyFreePicks.length >= _maxPicks) {
        _snack('You have used your 3 free AI analyses for today. Upgrade to Premium for more.');
        await _showPremiumUpgrade();
        if (!mounted || !SubscriptionService.instance.isPremium) return false;
      } else if (_dailyFreePicks.length + waiting >= _maxPicks) {
        _snack('Free users can analyse $_maxPicks matches a day. Unselect a match to pick another, or upgrade to Premium.');
        return false;
      }
    }
    if (!mounted) return false;
    setState(() => _selected.add(key));
    return true;
  }

  static final RegExp _vs = RegExp(
    r'\s+(?:vs\.?|versus|against|v|x|-|–|—)\s+|\s*[×/|]\s*',
    caseSensitive: false,
  );

  /// Team names come out clean: no quotes, brackets or stray punctuation.
  static String _cleanTeam(String s) => s
      .replaceAll(RegExp('["“”‘’`«»()\\[\\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.,;:!?-]+|[\s.,;:!?-]+$'), '');

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCustom() async {
    if (_busy) return;
    final parts = _typed.text
        .trim()
        .split(_vs)
        .map(_cleanTeam)
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length != 2 ||
        parts.any((e) => e.length < 2 || e.length > 60)) {
      _snack('Type two teams like: Arsenal vs Chelsea');
      return;
    }
    // "Chelsea Women vs Leeds Women", "(W)" or the Men/Women switch all mean a
    // women's match; otherwise it is a men's match.
    final women = _typedWomen ||
        parts.any((e) => Fixture(
              id: 'x',
              home: e,
              away: 'x',
              kickoff: DateTime.utc(2099),
            ).isWomen);
    final id = 'custom:${_n(parts[0])}|${_n(parts[1])}${women ? '|w' : ''}';
    final existing = _custom.where((c) => c.id == id).toList();
    final f = existing.isNotEmpty
        ? existing.first
        : Fixture(
            id: id,
            home: parts[0],
            away: parts[1],
            league: 'Typed by you',
            // Typed matchups have no fixed kick-off; this only keeps the key stable.
            kickoff: DateTime.utc(2099),
            gender: women ? 'women' : 'men',
          );
    final added = await _select(f, true);
    if (!added || !mounted) return;
    setState(() {
      if (existing.isEmpty) _custom.insert(0, f);
      _typed.clear();
      _typedWomen = false;
    });
    FocusScope.of(context).unfocus();
  }

  // ---------------------------------------------------------------------------
  // ANALYSIS HISTORY — opened analyses are saved on the device for 24 hours
  // (or until removed, if the user keeps one) so they can be reopened without re-analysing.
  // ---------------------------------------------------------------------------

  List<AiHistoryEntry> _history = [];
  bool _historyExpanded = false;

  Future<void> _loadHistory() async {
    final list = await AiHistory.load();
    if (!mounted) return;
    setState(() => _history = list);
    // The analysis page that was open when the app last closed comes back.
    if (widget.active) {
      final pg = PageMemory.consume('analysis');
      if (pg != null) {
        for (final e in list) {
          if (e.key == '${pg['id']}') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openHistory(e);
            });
            break;
          }
        }
      }
    }
  }

  Future<void> _remember(Fixture f, String key, Map<String, dynamic> data) async {
    // A typed matchup is saved with the real clubs the server resolved.
    final fixture = _all.firstWhere(
      (x) => FanZoneService.matchKey(x) == key,
      orElse: () => f,
    );
    try {
      final list = await AiHistory.save(fixture, key, data);
      if (mounted) setState(() => _history = list);
    } catch (_) {}
  }

  Future<void> _toggleKeep(AiHistoryEntry e) async {
    final list = await AiHistory.setKept(e.key, !e.kept);
    if (!mounted) return;
    setState(() => _history = list);
    _snack(
      e.kept
          ? 'Will clear 24 hours after it was analysed.'
          : 'Kept. It stays until you remove it.',
    );
  }

  Future<void> _deleteHistory(AiHistoryEntry e) async {
    final list = await AiHistory.remove(e.key);
    if (mounted) setState(() => _history = list);
  }

  /// Reopens a saved analysis on its own page, with nothing to re-run.
  void _openHistory(AiHistoryEntry e) {
    _results.putIfAbsent(e.key, () => e.data);
    _openMatchPage(e.fixture, e.key);
  }

  static String _left(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  List<Widget> _historySection() {
    final items = _history.where((e) => !e.expired).toList();
    if (items.isEmpty) return const [];
    final shown = _historyExpanded ? items : items.take(3).toList();
    return [
      const SizedBox(height: 18),
      Row(
        children: [
          Icon(Icons.history_rounded, size: 15, color: Ui.muted),
          const SizedBox(width: 6),
          Text(
            'RECENT ANALYSES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
              color: _lt(const Color(0xFFB39DFF), const Color(0xFF6A4CD6)),
            ),
          ),
          const Spacer(),
          Text(
            'Cleared after 24h unless kept',
            style: TextStyle(fontSize: 10.5, color: Ui.muted),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final e in shown) _historyTile(e),
      if (items.length > 3)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _historyExpanded = !_historyExpanded),
            child: Text(
              _historyExpanded ? 'Show less' : 'Show all ${items.length}',
            ),
          ),
        ),
    ];
  }

  Widget _historyTile(AiHistoryEntry e) {
    final f = e.fixture;
    final pick = _resolve(e.data, 'AI pick');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Ui.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openHistory(e),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: e.kept ? _accent.withValues(alpha: .55) : Ui.line,
              ),
            ),
            child: Row(
              children: [
                TeamCrest(logo: f.homeLogo, size: 32),
                const SizedBox(width: 3),
                TeamCrest(logo: f.awayLogo, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.genderTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.kept
                            ? 'Kept · ${pick.title}'
                            : 'Clears in ${_left(e.remaining)} · ${pick.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: Ui.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: e.kept ? 'Stop keeping' : 'Keep',
                  onPressed: () => _toggleKeep(e),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    e.kept ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 21,
                    color: e.kept ? _accent : Ui.muted,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _deleteHistory(e),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 20, color: Ui.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Closes one analysis card: removes its result and deselects the match.
  void _dismissResult(String key) {
    setState(() {
      _selected.remove(key);
      _results.remove(key);
      _failures.remove(key);
    });
  }

  void _removeCustom(Fixture f) {
    if (_busy) return;
    final key = FanZoneService.matchKey(f);
    setState(() {
      _custom.removeWhere((c) => c.id == f.id);
      _selected.remove(key);
      _results.remove(key);
      _failures.remove(key);
    });
  }

  Map<String, dynamic> _bodyFor(Fixture f) {
    if (_isExternal(f)) return {'ext': f.id.substring(4)};
    if (_isCustom(f) || _isWeb(f)) {
      return {
        'custom': {
          'home': f.home,
          'away': f.away,
          'gender': f.isWomen ? 'women' : 'men',
        },
      };
    }
    return {'key': FanZoneService.matchKey(f)};
  }

  /// Matches from other sources and typed matchups get the server's own
  /// plain-language reason (e.g. "Be more specific: Real Madrid, Real
  /// Sociedad"); the app's own fixtures keep the generic wording.
  String _failText(Fixture f, Object e) {
    var message = safeErrorMessage(e);
    final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (raw.contains('setup needed')) {
      return 'Automatic analysis is being configured. Please contact the administrator.';
    }
    if ((_isCustom(f) || _isExternal(f) || _isWeb(f)) &&
        e is Exception &&
        raw.isNotEmpty &&
        raw.length <= 240 &&
        !RegExp(
          r'https?://|/fan/|worker|secret|api.?key|binding|exception',
          caseSensitive: false,
        ).hasMatch(raw)) {
      message = raw;
    }
    return message;
  }

  Future<void> _analyse() async {
    if (_busy || _selected.isEmpty) return;
    final queue = _all
        .where((f) => _selected.contains(FanZoneService.matchKey(f)))
        .toList();
    final run = ++_run;
    setState(() {
      _busy = true;
      _done = 0;
      _total = queue.length;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    for (final f in queue) {
      final key = FanZoneService.matchKey(f);
      if (!mounted || run != _run) return;
      setState(() {
        _results.remove(key);
        _failures.remove(key);
      });
      try {
        final data = await FanZoneService.call(
          'ai-predict',
          body: _bodyFor(f),
          timeout: const Duration(seconds: 120),
        );
        // Stopped while waiting: drop this answer.
        if (!mounted || run != _run) return;
        // The free daily pick is used now, by a finished analysis.
        if (!(SubscriptionService.instance.isPremium || _weeklyPremium)) {
          unawaited(_saveDailyFreePick(key));
        }
        setState(() {
          _results[key] = data;
          // Show the real clubs (and crests) the server resolved for a typed matchup.
          final info = data['fixture'];
          final i = _custom.indexWhere((c) => c.id == f.id);
          if (i >= 0 && info is Map) {
            final h = '${info['home'] ?? ''}'.trim();
            final a = '${info['away'] ?? ''}'.trim();
            if (h.isNotEmpty && a.isNotEmpty) {
              _custom[i] = Fixture(
                id: f.id,
                home: h,
                away: a,
                homeLogo: '${info['homeLogo'] ?? ''}',
                awayLogo: '${info['awayLogo'] ?? ''}',
                // The server names the competition when both clubs share one.
                league: '${info['league'] ?? ''}'.isNotEmpty &&
                        '${info['league']}' != 'Your matchup'
                    ? '${info['league']}'
                    : f.league,
                kickoff: f.kickoff,
                gender: f.gender,
              );
            }
          }
        });
        unawaited(_remember(f, key, data));
      } catch (e) {
        if (!mounted || run != _run) return;
        setState(() => _failures[key] = _failText(f, e));
      }
      if (mounted && run == _run) setState(() => _done++);
    }
    if (mounted && run == _run) setState(() => _busy = false);
  }

  /// Stops the analysis that is running. Matches already analysed keep their
  /// result; the one in progress and the ones still waiting stay selected and
  /// use no free pick (a pick is used only by a finished analysis).
  void _stopAnalysis() {
    if (!_busy) return;
    _run++;
    setState(() {
      _busy = false;
      _done = 0;
      _total = 0;
    });
    _snack('Analysis stopped.');
  }

  /// Clears every picked match so others can be chosen.
  void _unselectAll() {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      for (final k in _selected) {
        _results.remove(k);
        _failures.remove(k);
      }
      _selected.clear();
    });
  }

  final Set<String> _refreshing = <String>{};

  /// Re-runs one analysis with fresh provider data (bypasses the server's saved player/coach data).
  Future<void> _refreshOne(Fixture f) async {
    final key = FanZoneService.matchKey(f);
    if (_busy || _refreshing.contains(key)) return;
    setState(() => _refreshing.add(key));
    try {
      final data = await FanZoneService.call(
        'ai-predict',
        body: {..._bodyFor(f), 'fresh': true},
        timeout: const Duration(seconds: 120),
      );
      if (!mounted) return;
      setState(() {
        _results[key] = data;
        _failures.remove(key);
      });
      unawaited(_remember(f, key, data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_failText(f, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing.remove(key));
    }
  }

  String _date(dynamic value) {
    final date = value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : DateTime.tryParse('$value');
    if (date == null) return '';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _resultColor(String r) => r == 'W'
      ? Ui.green
      : r == 'L'
      ? const Color(0xFFEF5350)
      : const Color(0xFFFFB300);

  Widget _formDots(Map<String, dynamic> form) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final m in FanZoneService.rows(form['matches']))
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(right: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _resultColor('${m['result']}').withValues(alpha: .2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _resultColor('${m['result']}').withValues(alpha: .6),
            ),
          ),
          child: Text(
            '${m['result']}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _resultColor('${m['result']}'),
            ),
          ),
        ),
    ],
  );

  Widget _stat(String label, Object? value) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Ui.muted)),
      ],
    ),
  );

  Widget _form(String logo, String title, Map<String, dynamic> form) =>
      Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Ui.text.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.line),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            leading: TeamCrest(logo: logo, size: 34),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _formDots(form),
              ),
            ),
            children: [
              Row(
                children: [
                  _stat('Won', form['wins']),
                  _stat('Drawn', form['draws']),
                  _stat('Lost', form['losses']),
                  _stat('Scored', form['goalsFor']),
                  _stat('Conceded', form['goalsAgainst']),
                ],
              ),
              const SizedBox(height: 6),
              for (final match in FanZoneService.rows(form['matches']))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _resultColor(
                            '${match['result']}',
                          ).withValues(alpha: .2),
                        ),
                        child: Text(
                          '${match['result']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _resultColor('${match['result']}'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${match['opponent']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${_date(match['date'])} · ${match['venue']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Ui.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${match['goalsFor']}–${match['goalsAgainst']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // CHARTS
  // ---------------------------------------------------------------------------

  static const _homeColor = Color(0xFF8E6BFF);
  static const _awayColor = Color(0xFF26C6DA);

  List<Map<String, dynamic>> _matchesOf(Map form) =>
      FanZoneService.rows(form['matches']);

  num _count(Map form, bool Function(Map<String, dynamic>) test) =>
      _matchesOf(form).where(test).length;

  Widget _cmpRow(String label, num h, num a, {int decimals = 0}) {
    String fmt(num v) => v.toStringAsFixed(decimals);
    final total = h + a;
    final hf = total <= 0 ? .5 : (h / total).toDouble();
    final left = (hf * 1000).round().clamp(40, 960);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  fmt(h),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 11.5),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  fmt(a),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: left,
                    child: const ColoredBox(color: _homeColor),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: 1000 - left,
                    child: const ColoredBox(color: _awayColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Ui.isLight ? Ui.bg : Ui.text.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Ui.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w900,
            color: Ui.muted,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _legend(Fixture f) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _homeColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            f.home,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            f.away,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _awayColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ),
  );

  Widget _comparison(Fixture f, Map data) {
    final h = Map<String, dynamic>.from(data['home'] as Map);
    final a = Map<String, dynamic>.from(data['away'] as Map);
    final hp = (h['played'] as num?)?.toInt() ?? 0;
    final ap = (a['played'] as num?)?.toInt() ?? 0;
    double per(num v, int n) => n == 0 ? 0 : v / n;
    final extras = data['extras'] is Map ? data['extras'] as Map : null;
    final hc = extras?['home'] is Map ? (extras!['home'] as Map)['cards'] : null;
    final ac = extras?['away'] is Map ? (extras!['away'] as Map)['cards'] : null;
    int pts(Map m) => ((m['wins'] as num?) ?? 0).toInt() * 3 +
        ((m['draws'] as num?) ?? 0).toInt();

    return _panel(
      title: 'Head to head form',
      child: Column(
        children: [
          _legend(f),
          _cmpRow('Points (last 5)', pts(h), pts(a)),
          _cmpRow('Wins', (h['wins'] as num?) ?? 0, (a['wins'] as num?) ?? 0),
          _cmpRow(
            'Goals scored per match',
            per((h['goalsFor'] as num?) ?? 0, hp),
            per((a['goalsFor'] as num?) ?? 0, ap),
            decimals: 1,
          ),
          _cmpRow(
            'Goals conceded per match',
            per((h['goalsAgainst'] as num?) ?? 0, hp),
            per((a['goalsAgainst'] as num?) ?? 0, ap),
            decimals: 1,
          ),
          _cmpRow(
            'Clean sheets',
            _count(h, (m) => m['goalsAgainst'] == 0),
            _count(a, (m) => m['goalsAgainst'] == 0),
          ),
          _cmpRow(
            'Both teams scored',
            _count(h, (m) => (m['goalsFor'] as num) > 0 && (m['goalsAgainst'] as num) > 0),
            _count(a, (m) => (m['goalsFor'] as num) > 0 && (m['goalsAgainst'] as num) > 0),
          ),
          _cmpRow(
            'Over 2.5 goals',
            _count(h, (m) => (m['goalsFor'] as num) + (m['goalsAgainst'] as num) > 2.5),
            _count(a, (m) => (m['goalsFor'] as num) + (m['goalsAgainst'] as num) > 2.5),
          ),
          if (hc is Map && ac is Map) ...[
            _cmpRow(
              'Yellow cards per match',
              per((hc['yellow'] as num?) ?? 0, ((hc['matches'] as num?) ?? 0).toInt()),
              per((ac['yellow'] as num?) ?? 0, ((ac['matches'] as num?) ?? 0).toInt()),
              decimals: 1,
            ),
            _cmpRow(
              'Red cards (last 5)',
              (hc['red'] as num?) ?? 0,
              (ac['red'] as num?) ?? 0,
            ),
            if (hc['corners'] != null && ac['corners'] != null)
              _cmpRow(
                'Corners per match',
                per((hc['corners'] as num?) ?? 0, ((hc['matches'] as num?) ?? 0).toInt()),
                per((ac['corners'] as num?) ?? 0, ((ac['matches'] as num?) ?? 0).toInt()),
                decimals: 1,
              ),
          ],
        ],
      ),
    );
  }

  /// Scored (team colour) and conceded (red) goals for the last matches,
  /// oldest on the left.
  Widget _goalsChart(String name, Color color, Map form) {
    final matches = _matchesOf(form).reversed.toList();
    var top = 3;
    for (final m in matches) {
      final gf = (m['goalsFor'] as num).toInt();
      final ga = (m['goalsAgainst'] as num).toInt();
      if (gf > top) top = gf;
      if (ga > top) top = ga;
    }
    const maxH = 64.0;
    Widget bar(int v, Color c) => Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$v', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Container(
          width: 11,
          height: v == 0 ? 2 : (v / top) * maxH,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in matches)
                Column(
                  children: [
                    SizedBox(
                      height: maxH + 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar((m['goalsFor'] as num).toInt(), color),
                          const SizedBox(width: 3),
                          bar((m['goalsAgainst'] as num).toInt(), const Color(0xFFEF5350)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _resultColor('${m['result']}').withValues(alpha: .2),
                      ),
                      child: Text(
                        '${m['result']}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _resultColor('${m['result']}'),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goals(Fixture f, Map data) => _panel(
    title: 'Goals in last 5 matches',
    child: Column(
      children: [
        _goalsChart(f.home, _homeColor, data['home'] as Map),
        const SizedBox(height: 8),
        _goalsChart(f.away, _awayColor, data['away'] as Map),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 9, height: 9, color: Ui.muted),
            const SizedBox(width: 5),
            Text('Scored', style: TextStyle(color: Ui.muted, fontSize: 11)),
            const SizedBox(width: 14),
            Container(width: 9, height: 9, color: const Color(0xFFEF5350)),
            const SizedBox(width: 5),
            Text('Conceded', style: TextStyle(color: Ui.muted, fontSize: 11)),
          ],
        ),
      ],
    ),
  );

  Widget _injuriesPanel(Fixture f, Map data) {
    final extras = data['extras'] is Map ? data['extras'] as Map : null;
    if (extras == null) return const SizedBox.shrink();
    List? listOf(String side) {
      final m = extras[side];
      return m is Map && m['injuries'] is List ? m['injuries'] as List : null;
    }

    final home = listOf('home'), away = listOf('away');
    if (home == null && away == null) return const SizedBox.shrink();

    Widget team(String name, Color color, List? list) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (list == null)
            Text('Not available', style: TextStyle(color: Ui.muted, fontSize: 12))
          else if (list.isEmpty)
            Text('No injuries reported', style: TextStyle(color: Ui.muted, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in list.whereType<Map>())
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF5350).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFEF5350).withValues(alpha: .35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.healing_rounded, size: 12, color: Color(0xFFEF5350)),
                        const SizedBox(width: 5),
                        Text(
                          '${i['player']}${'${i['reason'] ?? ''}'.isEmpty ? '' : ' · ${i['reason']}'}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );

    return _panel(
      title: 'Injuries & absences',
      child: Column(
        children: [
          team(f.home, _homeColor, home),
          team(f.away, _awayColor, away),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AI PICKS, ODDS AND LINEUPS
  // ---------------------------------------------------------------------------

  Color _confColor(String c) => switch (c) {
    'high' => const Color(0xFF66BB6A),
    'medium' => const Color(0xFFFFB74D),
    _ => Ui.muted,
  };

  Widget _oddChip(String label, Object? odd) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Ui.text.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Ui.muted, fontSize: 12)),
        const SizedBox(width: 8),
        Text(
          '$odd',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );

  Widget _oddsPanel(Fixture f, Map data) {
    final extras = data['extras'] is Map ? data['extras'] as Map : null;
    final odds = extras?['odds'] is Map ? extras!['odds'] as Map : null;
    if (odds == null) return const SizedBox.shrink();
    final w = odds['winner'] is Map ? odds['winner'] as Map : null;
    final g = odds['goals25'] is Map ? odds['goals25'] as Map : null;
    final b = odds['btts'] is Map ? odds['btts'] as Map : null;
    final c = odds['corners'] is Map ? odds['corners'] as Map : null;
    final k = odds['cards'] is Map ? odds['cards'] as Map : null;

    Widget winner() {
      final h = (w!['home'] as num).toDouble();
      final d = (w['draw'] as num).toDouble();
      final a = (w['away'] as num).toDouble();
      final t = 1 / h + 1 / d + 1 / a;
      Widget col(String label, double odd, Color color) => Expanded(
        child: Column(
          children: [
            Text(
              '${(100 / odd / t).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Ui.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 2),
            Text(
              odd.toStringAsFixed(2),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
      return Row(
        children: [
          col(f.home, h, _homeColor),
          col('Draw', d, Ui.muted),
          col(f.away, a, _awayColor),
        ],
      );
    }

    return _panel(
      title: 'Odds · ${odds['bookmaker'] ?? 'Bookmaker'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (w != null) ...[
            winner(),
            const SizedBox(height: 4),
            Text(
              'Percentages are what the odds imply, not an AI estimate.',
              style: TextStyle(color: Ui.dim, fontSize: 10.5),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (g != null) ...[
                _oddChip('Over 2.5', g['over']),
                _oddChip('Under 2.5', g['under']),
              ],
              if (b != null) ...[
                _oddChip('BTTS Yes', b['yes']),
                _oddChip('BTTS No', b['no']),
              ],
              if (c != null) ...[
                _oddChip('Corners over ${c['line']}', c['over']),
                _oddChip('under ${c['line']}', c['under']),
              ],
              if (k != null) ...[
                _oddChip('Cards over ${k['line']}', k['over']),
                _oddChip('under ${k['line']}', k['under']),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineupsPanel(Fixture f, Map data) {
    final extras = data['extras'] is Map ? data['extras'] as Map : null;
    Map? lineupOf(String side) {
      final m = extras?[side];
      return m is Map && m['lineup'] is Map ? m['lineup'] as Map : null;
    }

    final home = lineupOf('home'), away = lineupOf('away');
    if (home == null && away == null) return const SizedBox.shrink();

    Widget team(String name, Color color, Map? l) {
      if (l == null) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '$name: lineup not available',
            style: TextStyle(color: Ui.muted, fontSize: 12),
          ),
        );
      }
      final players = FanZoneService.rows(l['players']);
      String line(String pos, String label) {
        final names = players
            .where((p) => '${p['pos']}' == pos)
            .map((p) => '${p['name']}')
            .toList();
        return names.isEmpty ? '' : '$label  ${names.join(', ')}';
      }

      final rows = [
        line('G', 'GK'),
        line('D', 'DEF'),
        line('M', 'MID'),
        line('F', 'FWD'),
      ].where((e) => e.isNotEmpty).toList();
      final confirmed = l['source'] == 'confirmed';
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if ('${l['formation']}'.isNotEmpty)
                  Text(
                    '${l['formation']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
            Text(
              confirmed ? 'Confirmed XI' : 'Probable XI (from last match)',
              style: TextStyle(
                color: confirmed ? const Color(0xFF66BB6A) : Ui.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(r, style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
          ],
        ),
      );
    }

    return _panel(
      title: 'Possible lineups',
      child: Column(
        children: [
          team(f.home, _homeColor, home),
          team(f.away, _awayColor, away),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPREHENSIVE AI ANALYSIS — sectioned, modern presentation
  // ---------------------------------------------------------------------------

  static const _aiViolet = Color(0xFF8B70FF);
  static const _aiVioletSoft = Color(0xFFB39DFF);
  static const _aiVerdict = Color(0xFF48D597);

  static final RegExp _aiHeadingRe = RegExp(
    r'^(?:\d+[\.\)]\s*)?(MATCH OVERVIEW|RECENT FORM|ATTACK\s+(?:vs\.?|VS\.?|and|&)\s+DEFEN[CS]E|TACTICAL MATCH-?UP|TEAM NEWS(?:\s*&\s*LINEUPS)?|ODDS(?:\s*&\s*MARKET VIEW)?|AI VERDICT|VERDICT)\b(.*)$',
  );
  static final RegExp _aiGenericHeadingRe = RegExp(r"^(?:\d+[\.\)]\s*)?[A-Z][A-Z0-9 &\-/']{5,38}:?$");

  /// Short community post: only the match overview and the verdict, never the
  /// full multi-section analysis.
  String _communitySummary(String raw, Fixture f) {
    final cleaned = raw
        .replaceAll('**', '')
        .replaceAll('##', '')
        .replaceAll('###', '')
        .trim();
    final blocks = <String, List<String>>{};
    final loose = <String>[];
    String? cur;
    for (final l in cleaned.split('\n')) {
      final line = l.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^PICKS\s*$', caseSensitive: false).hasMatch(line)) break;
      final m = _aiHeadingRe.firstMatch(line);
      if (m != null) {
        cur = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
        var rest =
            (m.group(2) ?? '').replaceFirst(RegExp(r'^[\s:\-–—]+'), '').trim();
        // "MATCH OVERVIEW and likely game pattern": the words after the title are
        // a sub-heading, not the start of the text, so they are not posted.
        if (rest.isNotEmpty && RegExp(r'^[a-zà-ÿ]').hasMatch(rest)) rest = '';
        final list = blocks.putIfAbsent(cur, () => <String>[]);
        if (rest.isNotEmpty) list.add(rest);
        continue;
      }
      if (_aiGenericHeadingRe.hasMatch(line)) {
        cur = '_other';
        continue;
      }
      if (cur == null) {
        loose.add(line);
      } else {
        blocks.putIfAbsent(cur, () => <String>[]).add(line);
      }
    }
    String clip(Iterable<String>? parts, int max) {
      var t = (parts ?? const <String>[])
          .join(' ')
          .replaceAll(RegExp(r'^[•\-\*]\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.length <= max) return t;
      t = t.substring(0, max);
      final stop = t.lastIndexOf(RegExp(r'[.!?]\s'));
      if (stop > max ~/ 2) return t.substring(0, stop + 1);
      final sp = t.lastIndexOf(' ');
      return '${sp > 0 ? t.substring(0, sp) : t}…';
    }

    final overview = clip(blocks['MATCH OVERVIEW'], 260);
    final verdict = clip(blocks['AI VERDICT'] ?? blocks['VERDICT'], 240);
    final out = StringBuffer('AI Predict: ${f.genderTitle}');
    if (overview.isEmpty && verdict.isEmpty) {
      final fallback = clip(loose.isNotEmpty ? loose : cleaned.split('\n'), 420);
      if (fallback.isNotEmpty) out.write('\n\n$fallback');
    } else {
      if (overview.isNotEmpty) out.write('\n\n$overview');
      if (verdict.isNotEmpty) out.write('\n\nVerdict: $verdict');
    }
    out.write('\n\nAI analysis is informational; outcomes are uncertain.');
    return out.toString();
  }

  IconData _aiIconFor(String title) {
    final t = title.toUpperCase();
    if (t.contains('OVERVIEW')) return Icons.sports_soccer_rounded;
    if (t.contains('FORM')) return Icons.show_chart_rounded;
    if (t.contains('ATTACK')) return Icons.flash_on_rounded;
    if (t.contains('TACTIC')) return Icons.track_changes_rounded;
    if (t.contains('NEWS') || t.contains('LINEUP')) return Icons.groups_rounded;
    if (t.contains('ODDS')) return Icons.insights_rounded;
    if (t.contains('VERDICT')) return Icons.verified_rounded;
    return Icons.auto_awesome_rounded;
  }

  /// Splits the generated read into headed sections and renders each as a
  /// clean card. The original wording is kept; only the presentation changes.
  Widget _formattedAiAnalysis(String raw, {Fixture? fixture, Map? data}) {
    var cleaned = raw.replaceAll('**', '').replaceAll('##', '').replaceAll('###', '').trim();

    // Optional PICKS block (rendered as pick cards, as before).
    final picks = <String>[];
    final picksMatch = RegExp(r'^\s*PICKS\s*$', multiLine: true, caseSensitive: false).firstMatch(cleaned);
    if (picksMatch != null) {
      final tail = cleaned.substring(picksMatch.end);
      cleaned = cleaned.substring(0, picksMatch.start).trim();
      String? cur;
      for (final l in tail.split('\n')) {
        final line = l.trim();
        if (line.isEmpty) continue;
        if (RegExp(r'^\d+\.\s+').hasMatch(line)) {
          if (cur != null) picks.add(cur.trim());
          cur = line;
        } else if (cur != null) {
          cur = '$cur\n$line';
        }
      }
      if (cur != null) picks.add(cur.trim());
    }

    // No PICKS block in the text: show the match's picks anyway.
    if (picks.isEmpty && data != null) {
      final ps = _sortedPicks(data);
      for (var i = 0; i < ps.length; i++) {
        final p = ps[i];
        final reason = '${p['reason'] ?? ''}'.trim();
        picks.add('${i + 1}. ${p['market']}: ${p['pick']} (${'${p['confidence']}'.toUpperCase()})'
            '${reason.isEmpty ? '' : '\nReason: $reason'}');
      }
    }

    // Parse sections.
    final sections = <({String title, String sub, List<String> lines})>[];
    String? title;
    String sub = '';
    var lines = <String>[];
    void flush() {
      if (title != null || lines.isNotEmpty) {
        sections.add((title: title ?? 'SUMMARY', sub: sub, lines: lines));
      }
      title = null;
      sub = '';
      lines = <String>[];
    }

    for (final l in cleaned.split('\n')) {
      final line = l.trim();
      if (line.isEmpty) continue;
      final m = _aiHeadingRe.firstMatch(line);
      if (m != null) {
        flush();
        title = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
        var rest = (m.group(2) ?? '').trim();
        rest = rest.replaceFirst(RegExp(r'^[,\-–—:]+\s*'), '').trim();
        // A heading line may also carry body text after a colon.
        final colon = rest.indexOf(':');
        if (colon > 0 && colon < 60) {
          final body = rest.substring(colon + 1).trim();
          rest = rest.substring(0, colon).trim();
          if (body.isNotEmpty) lines.add(body);
        }
        sub = rest.isEmpty ? '' : rest[0].toUpperCase() + rest.substring(1);
        continue;
      }
      if (_aiGenericHeadingRe.hasMatch(line) && line.contains(' ')) {
        flush();
        title = line.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').replaceAll(':', '').trim();
        continue;
      }
      lines.add(line);
    }
    flush();

    if (sections.isEmpty && picks.isEmpty) {
      return SelectableText(cleaned, style: const TextStyle(height: 1.6, fontSize: 13.5));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++)
          _aiSectionCard(
            i + 1,
            sections[i].title,
            sections[i].sub,
            sections[i].lines,
            // Team news is shown only from verified provider data, never from the AI's own memory of squads.
            body: sections[i].title.contains('TEAM NEWS')
                ? ((fixture != null && data != null
                          ? _teamNewsBody(fixture, data, sections[i].lines)
                          : null) ??
                      _teamNewsUnavailable())
                : null,
          ),
        if (picks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 5),
            decoration: BoxDecoration(
              color: const Color(0xFF171A32),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _aiViolet.withValues(alpha: .28)),
            ),
            child: _DarkText(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome_rounded, color: _aiVioletSoft, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'AI PICKS',
                      style: TextStyle(
                        color: Color(0xFFCEC1FF),
                        fontSize: 11.5,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < picks.length; i++) _aiPickAnalysisCard(i + 1, picks[i], fixture: fixture),
              ],
            )),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TEAM NEWS — built from the provider data (names, stats, absences, XI),
  // so it is complete even when the AI text is short.
  // ---------------------------------------------------------------------------

  Widget _teamNewsUnavailable() => Text(
    'Verified team news (injuries, key players, lineups) is not available for this match, so none is shown. '
    'Squads change often and we only show what the data provider confirms.',
    style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.4),
  );

  Widget? _teamNewsBody(Fixture f, Map data, List<String> aiLines) {
    final extras = data['extras'] is Map ? data['extras'] as Map : null;
    if (extras == null) return null;
    Map? sideOf(String k) => extras[k] is Map ? extras[k] as Map : null;
    final home = sideOf('home'), away = sideOf('away');
    bool has(Map? m) =>
        m != null &&
        (m['players'] is List && (m['players'] as List).isNotEmpty ||
            m['injuries'] is List && (m['injuries'] as List).isNotEmpty ||
            m['lineup'] is Map ||
            m['cards'] is Map ||
            '${m['coach'] ?? ''}'.isNotEmpty);
    if (!has(home) && !has(away)) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _teamNewsSide(f.home, _homeColor, home),
        const SizedBox(height: 16),
        _teamNewsSide(f.away, _awayColor, away),
        const SizedBox(height: 4),
        Text(
          'Squad stats are for the current season. Absences and lineups come from the data provider and can change before kick-off.',
          style: TextStyle(color: Ui.dim, fontSize: 10.5, height: 1.35),
        ),
      ],
    );
  }

  Widget _tnLabel(String text, {IconData? icon, Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 7),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color ?? Ui.muted),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: color ?? Ui.muted,
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _teamNewsSide(String name, Color color, Map? m) {
    final players = FanZoneService.rows(m?['players']);
    final injuries = m?['injuries'] is List ? FanZoneService.rows(m!['injuries']) : null;
    final lineup = m?['lineup'] is Map ? m!['lineup'] as Map : null;
    final cards = m?['cards'] is Map ? m!['cards'] as Map : null;
    final coach = '${m?['coach'] ?? ''}'.trim();
    final injuredNames = {
      for (final i in injuries ?? const <Map<String, dynamic>>[])
        '${i['player']}'.toLowerCase(),
    };

    String posShort(String p) => switch (p) {
      'Goalkeeper' => 'GK',
      'Defender' => 'DEF',
      'Midfielder' => 'MID',
      'Attacker' => 'FWD',
      _ => '—',
    };
    String n(dynamic v) => v == null ? '–' : '$v';

    Widget cell(String t, double w, {bool bold = false, Color? c, TextAlign a = TextAlign.center}) =>
        SizedBox(
          width: w,
          child: Text(
            t,
            textAlign: a,
            style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: c),
          ),
        );

    Widget playerRow(Map<String, dynamic> p) {
      final out = injuredNames.contains('${p['player']}'.toLowerCase());
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                posShort('${p['position']}'),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${p['player']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (out) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.healing_rounded, size: 13, color: Color(0xFFEF5350)),
                  ],
                ],
              ),
            ),
            cell(n(p['apps']), 30),
            cell(n(p['goals']), 28, bold: true),
            cell(n(p['assists']), 28, bold: true),
            cell(p['rating'] == null ? '–' : (p['rating'] as num).toStringAsFixed(1), 38),
          ],
        ),
      );
    }

    Widget headerRow() => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const SizedBox(width: 34),
          const Expanded(child: SizedBox()),
          for (final h in const [('APP', 30.0), ('G', 28.0), ('A', 28.0), ('RTG', 38.0)])
            SizedBox(
              width: h.$2,
              child: Text(
                h.$1,
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted, fontSize: 9.5, letterSpacing: .8, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );

    Widget chip(String text, Color c, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
        ],
      ),
    );

    final keyOut = [
      for (final p in players)
        if (injuredNames.contains('${p['player']}'.toLowerCase())) '${p['player']}',
    ];

    final lineupPlayers = lineup == null ? <Map<String, dynamic>>[] : FanZoneService.rows(lineup['players']);
    String xiLine(String pos, String label) {
      final names = lineupPlayers
          .where((p) => '${p['pos']}' == pos)
          .map((p) => p['number'] == null ? '${p['name']}' : '${p['number']} ${p['name']}')
          .toList();
      return names.isEmpty ? '' : '$label   ${names.join(' · ')}';
    }

    final xi = [
      xiLine('G', 'GK'),
      xiLine('D', 'DEF'),
      xiLine('M', 'MID'),
      xiLine('F', 'FWD'),
    ].where((e) => e.isNotEmpty).toList();
    final confirmed = lineup?['source'] == 'confirmed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              if (lineup != null && '${lineup['formation']}'.isNotEmpty)
                Text('${lineup['formation']}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
          if (coach.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 11),
              child: Text('Head coach: $coach', style: TextStyle(color: Ui.muted, fontSize: 11.5)),
            ),

          _tnLabel('Injuries & suspensions', icon: Icons.healing_rounded, color: const Color(0xFFEF5350)),
          if (injuries == null)
            Text('Not available from the provider.', style: TextStyle(color: Ui.muted, fontSize: 12))
          else if (injuries.isEmpty)
            Text('No injuries or suspensions reported.', style: TextStyle(color: Ui.muted, fontSize: 12))
          else ...[
            if (keyOut.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Key player${keyOut.length > 1 ? 's' : ''} doubtful or out: ${keyOut.join(', ')}',
                  style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12, fontWeight: FontWeight.w800, height: 1.3),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in injuries)
                  chip(
                    [
                      '${i['player']}',
                      if ('${i['reason'] ?? ''}'.isNotEmpty) '${i['reason']}'
                      else if ('${i['type'] ?? ''}'.isNotEmpty) '${i['type']}',
                    ].join(' · '),
                    '${i['type']}'.toLowerCase().contains('missing')
                        ? const Color(0xFFEF5350)
                        : const Color(0xFFFFB74D),
                    '${i['type']}'.toLowerCase().contains('missing')
                        ? Icons.block_rounded
                        : Icons.help_outline_rounded,
                  ),
              ],
            ),
          ],

          _tnLabel('Key players · season', icon: Icons.star_rounded, color: const Color(0xFFFFC46B)),
          if (players.isEmpty)
            Text('Player stats are not available.', style: TextStyle(color: Ui.muted, fontSize: 12))
          else ...[
            headerRow(),
            for (final p in players) playerRow(p),
          ],

          if (cards != null) ...[
            _tnLabel('Discipline · last ${cards['matches']} matches', icon: Icons.style_rounded),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _oddChip('Yellow cards', cards['yellow']),
                _oddChip('Red cards', cards['red']),
                if (cards['fouls'] != null) _oddChip('Fouls', cards['fouls']),
                if (cards['corners'] != null) _oddChip('Corners won', cards['corners']),
              ],
            ),
          ],

          _tnLabel(
            lineup == null
                ? 'Lineup'
                : confirmed
                ? 'Confirmed XI'
                : 'Probable XI · from last match',
            icon: Icons.groups_rounded,
            color: confirmed ? const Color(0xFF66BB6A) : null,
          ),
          if (xi.isEmpty)
            Text('Lineup not available yet.', style: TextStyle(color: Ui.muted, fontSize: 12))
          else
            for (final r in xi)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(r, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
        ],
      ),
    );
  }

  Widget _aiSectionCard(int number, String title, String sub, List<String> lines, {Widget? body}) {
    final verdict = title.contains('VERDICT');
    final accent = verdict ? _aiVerdict : _aiViolet;
    final titleColor = verdict ? _lt(const Color(0xFF8FF0C2), const Color(0xFF1E8E5A)) : _lt(const Color(0xFFD2C7FF), const Color(0xFF4B33B8));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(
              alpha: Ui.isLight ? (verdict ? .10 : .04) : (verdict ? .16 : .10),
            ),
            Ui.isLight ? Ui.bg : Ui.text.withValues(alpha: .025),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: verdict ? .38 : .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent.withValues(alpha: .25)),
                ),
                child: Icon(_aiIconFor(title), size: 17, color: verdict ? _aiVerdict : _aiVioletSoft),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        height: 1.2,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w300,
                          letterSpacing: .2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                number.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: Ui.text.withValues(alpha: .22),
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: .35), Colors.white.withValues(alpha: 0)],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (body != null)
            body
          else
            for (final l in lines) _aiBodyLine(l, verdict: verdict),
        ],
      ),
    );
  }

  Widget _aiBodyLine(String line, {bool verdict = false}) {
    final t = line.trim();

    // Recent form strip, e.g. "Recent form: L-W-L"
    final form = RegExp(r'^(?:recent\s+)?form\s*:\s*([WDL](?:\s*[-–,]?\s*[WDL]){0,9})\s*$', caseSensitive: false).firstMatch(t);
    if (form != null) {
      final results = RegExp(r'[WDLwdl]').allMatches(form.group(1)!).map((m) => m.group(0)!.toUpperCase()).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Row(
          children: [
            Text(
              'FORM',
              style: TextStyle(color: Ui.muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            for (final r in results)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (r == 'W'
                          ? const Color(0xFF48D597)
                          : r == 'D'
                              ? const Color(0xFFFFC46B)
                              : const Color(0xFFFF6B6B))
                      .withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (r == 'W'
                            ? const Color(0xFF48D597)
                            : r == 'D'
                                ? const Color(0xFFFFC46B)
                                : const Color(0xFFFF6B6B))
                        .withValues(alpha: .45),
                  ),
                ),
                child: Text(
                  r,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: r == 'W'
                        ? _lt(const Color(0xFF7CE8B5), const Color(0xFF1B7F52))
                        : r == 'D'
                            ? _lt(const Color(0xFFFFD58F), const Color(0xFF9A6200))
                            : _lt(const Color(0xFFFF9A9A), const Color(0xFFC62828)),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Team / sub label, e.g. "Manchester City:"
    if (RegExp(r'^[^:]{1,40}:$').hasMatch(t)) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: _aiViolet,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.substring(0, t.length - 1),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .3),
              ),
            ),
          ],
        ),
      );
    }

    // Short stat rows, e.g. "Played 3 matches, won 1, lost 2"
    if (RegExp(r'^(Played|Scored|Conceded|Won|Lost|Drawn|Goals|Average|Avg|Clean)\b', caseSensitive: false).hasMatch(t) &&
        t.length < 70) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: _aiVioletSoft.withValues(alpha: .7), shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                t,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                  color: Ui.text.withValues(alpha: .86),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Numbered / bulleted lines
    final bullet = RegExp(r'^(?:[-•*]|\d+[\.\)])\s+(.*)$').firstMatch(t);
    if (bullet != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: _aiVioletSoft, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                bullet.group(1)!,
                style: TextStyle(fontSize: 13.5, height: 1.55, color: Ui.text.withValues(alpha: .84)),
              ),
            ),
          ],
        ),
      );
    }

    // Paragraph
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectableText(
        t,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.62,
          fontWeight: verdict ? FontWeight.w500 : FontWeight.w400,
          color: Ui.text.withValues(alpha: verdict ? .94 : .82),
        ),
      ),
    );
  }

  Widget _aiPickAnalysisCard(int number, String source, {Fixture? fixture}) {
    final text = source.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
    final reasonIndex = text.toLowerCase().indexOf('reason:');
    final pickText = reasonIndex >= 0 ? text.substring(0, reasonIndex).trim() : text;
    final reason = reasonIndex >= 0
        ? text.substring(reasonIndex + 'reason:'.length).trim()
        : '';
    final colon = pickText.indexOf(':');
    final market = colon > 0 ? pickText.substring(0, colon).trim() : 'Prediction';
    final selection = colon > 0 ? pickText.substring(colon + 1).trim() : pickText;
    final split = BetSlipPick.splitConfidence(selection);
    final confidence = split.confidence;
    final confidenceColor = switch (confidence) {
      'HIGH' => const Color(0xFF48D597),
      'MEDIUM' => const Color(0xFFFFC46B),
      'LOW' => const Color(0xFF9EABC0),
      _ => Ui.muted,
    };
    final cleanSelection = split.pick;
    final matchKey = fixture == null ? 'unknown-match' : FanZoneService.matchKey(fixture);
    final slipKey = '$matchKey|${market.toLowerCase()}|${cleanSelection.toLowerCase()}';
    final selectedOnSlip = _slipSelections.containsKey(slipKey);

    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: fixture == null ? null : () {
        setState(() {
          if (selectedOnSlip) {
            _slipSelections.remove(slipKey);
          } else {
            _slipSelections[slipKey] = BetSlipPick(
              market: market, pick: cleanSelection, confidence: confidence ?? 'N/A',
              matchTitle: fixture.genderTitle, league: fixture.league, kickoff: fixture.kickoff.year >= 2090 ? null : fixture.kickoff,
            );
          }
        });
        _rev.value++;
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF222746),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: selectedOnSlip ? const Color(0xFF8B70FF) : Colors.white.withValues(alpha: .075), width: selectedOnSlip ? 1.6 : 1),
      ),
      child: _DarkText(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF8065E8).withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$number', style: const TextStyle(color: Color(0xFFD2C7FF), fontSize: 12, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  market,
                  style: TextStyle(color: const Color(0xFF9EABC0), fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              if (confidence != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: confidenceColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: confidenceColor.withValues(alpha: .3)),
                  ),
                  child: Text(confidence, style: TextStyle(color: confidenceColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .5)),
                ),
              const SizedBox(width: 7),
              Icon(selectedOnSlip ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: selectedOnSlip ? const Color(0xFFB39DFF) : const Color(0xFF9EABC0), size: 19),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            cleanSelection,
            style: const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withValues(alpha: .07)),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFB39DFF)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: SelectableText(
                    reason,
                    style: TextStyle(color: const Color(0xFF9EABC0), fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ],
      )),
      ),
    );
  }

  Widget _fullAnalysis(Fixture f, Map<String, dynamic> data) => Container(
    margin: const EdgeInsets.only(top: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFF713DDA).withValues(alpha: Ui.isLight ? .22 : .45),
      ),
      // Light theme: a clean white card with only a whisper of violet so the
      // text stays sharp. Dark theme keeps the richer tint.
      color: Ui.isLight ? Ui.card : null,
      gradient: Ui.isLight
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF713DDA).withValues(alpha: .22),
                Ui.card,
              ],
            ),
    ),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TeamCrest(logo: f.homeLogo, size: 34),
            const SizedBox(width: 4),
            TeamCrest(logo: f.awayLogo, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                f.genderTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${data['dataSource'] ?? 'Verified match results'} · ${_date(data['generatedAt'])}',
          style: TextStyle(color: Ui.muted, fontSize: 11),
        ),
        _form(
          f.homeLogo,
          '${f.home} · last ${data['home']['played']}',
          Map<String, dynamic>.from(data['home'] as Map),
        ),
        _form(
          f.awayLogo,
          '${f.away} · last ${data['away']['played']}',
          Map<String, dynamic>.from(data['away'] as Map),
        ),
        _comparison(f, data),
        _goals(f, data),
        _oddsPanel(f, data),
        _lineupsPanel(f, data),
        _injuriesPanel(f, data),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8, bottom: 6),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8B70FF), Color(0xFF5B3FD0)],
                ),
              ),
              child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
            ),
            title: Text(
              'COMPREHENSIVE AI ANALYSIS',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: _lt(const Color(0xFFCEC1FF), const Color(0xFF5B3FD0)),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Form · tactics · team news · lineups · odds · verdict',
                style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w300, letterSpacing: .2),
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _formattedAiAnalysis('${data['analysis']}', fixture: f, data: data),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          data['extras'] is Map
              ? 'Historical form is a limited sample, not a guaranteed outcome. Injuries, cards, lineups and odds come from the data provider and may be incomplete or change before kick-off.'
              : 'Historical form is a limited sample, not a guaranteed outcome. Injuries, cards, lineups and odds are not available for this match, so picks use recent form only.',
          style: TextStyle(color: Ui.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _refreshing.contains(FanZoneService.matchKey(f))
                    ? null
                    : () => _refreshOne(f),
                icon: _refreshing.contains(FanZoneService.matchKey(f))
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  _refreshing.contains(FanZoneService.matchKey(f))
                      ? 'Refreshing…'
                      : 'Refresh analysis',
                ),
              ),
              TextButton.icon(
            onPressed: () async {
              final analysis = 'Deeprowss AI Predict\n${f.genderTitle}\n\n'
                  '${'${data['analysis']}'.replaceAll('**', '')}\n\n'
                  'Source: ${data['dataSource'] ?? 'Verified recent results'}. '
                  'AI analysis is informational; outcomes are uncertain.';
              final summary = _communitySummary('${data['analysis']}', f);
              final action = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: const Text('Post to Community Trend'),
                      subtitle: const Text('Post the summary with a match link (photo optional)'),
                      onTap: () => Navigator.pop(ctx, 'post'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: const Text('Printable bet slip'),
                      subtitle: const Text('PDF of the picks from this analysis'),
                      onTap: () => Navigator.pop(ctx, 'slip'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: const Text('Share outside Deeprowss'),
                      subtitle: const Text('Includes the app download link'),
                      onTap: () => Navigator.pop(ctx, 'external'),
                    ),
                  ]),
                ),
              );
              if (!mounted || action == null) return;
              try {
                if (action == 'slip') {
                  final picks = <BetSlipPick>[
                    for (final p in _sortedPicks(data))
                      if (p is Map && '${p['pick'] ?? ''}'.trim().isNotEmpty)
                        BetSlipPick(
                          market: '${p['market'] ?? ''}',
                          pick: BetSlipPick.splitConfidence('${p['pick']}').pick,
                          confidence: '${p['confidence'] ?? ''}'.trim().isNotEmpty
                              ? '${p['confidence']}'
                              : (BetSlipPick.splitConfidence('${p['pick']}').confidence ?? ''),
                        ),
                  ];
                  if (picks.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('This analysis has no picks to put on a slip.'),
                        ),
                      );
                    }
                    return;
                  }
                  await BetSlipPdf.print(
                    matchTitle: f.genderTitle,
                    league: f.league,
                    kickoff: f.kickoff.year >= 2090 ? null : f.kickoff,
                    picks: picks,
                  );
                } else if (action == 'post') {
                  final draft = await showModalBottomSheet<_ShareDraft>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) => _CommunityShareSheet(initialText: summary),
                  );
                  if (!mounted || draft == null) return;
                  await FanZoneService.publish(
                    kind: 'prediction',
                    text: draft.text,
                    image: draft.image,
                    matchFixture: {
                      'id': f.id,
                      'home': f.home,
                      'away': f.away,
                      'homeLogo': f.homeLogo,
                      'awayLogo': f.awayLogo,
                      'league': f.league,
                      'kickoff': f.kickoff.toIso8601String(),
                      'duration': f.durationMin,
                      'scoreLeague': f.scoreLeague,
                    },
                  );
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('AI analysis posted to Community Trend.')),
                  );
                } else {
                  final download = RemoteConfig.instance.shareLink;
                  await Share.share(
                    '$analysis\n\nView more predictions on Deeprowss: $download',
                  );
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(safeErrorMessage(e))),
                );
              }
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Share analysis'),
          ),
            ],
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // TOP PICK CARD
  // ---------------------------------------------------------------------------

  static const _accent = Color(0xFF21E07A);
  static const _chips = ['AI pick', 'Over 1.5', 'Over 2.5', 'BTTS', 'Under 2.5'];

  /// How often a goals market landed in the last matches of both teams.
  /// This is a plain hit rate from the verified results, not an AI estimate.
  ({int hits, int total, int pct})? _rate(Map data, String market) {
    final all = [..._matchesOf(data['home'] as Map), ..._matchesOf(data['away'] as Map)];
    if (all.isEmpty) return null;
    bool test(Map<String, dynamic> m) {
      final gf = (m['goalsFor'] as num), ga = (m['goalsAgainst'] as num);
      final t = gf + ga;
      return switch (market) {
        'Over 1.5' => t > 1.5,
        'Over 2.5' => t > 2.5,
        'Under 2.5' => t < 2.5,
        'BTTS' => gf > 0 && ga > 0,
        'No BTTS' => !(gf > 0 && ga > 0),
        _ => false,
      };
    }

    final hits = all.where(test).length;
    return (hits: hits, total: all.length, pct: (hits / all.length * 100).round());
  }

  /// The goals market an AI pick refers to, when it can be checked against form.
  String? _goalsMarketOf(Map<String, dynamic> p) {
    final market = '${p['market']}', pick = '${p['pick']}'.toLowerCase();
    if (market == 'Over/Under 2.5 goals') {
      return pick.contains('under') ? 'Under 2.5' : 'Over 2.5';
    }
    if (market == 'Both teams to score') {
      return pick.startsWith('no') ? 'No BTTS' : 'BTTS';
    }
    if (market == 'Over/Under 1.5 goals' && !pick.contains('under')) {
      return 'Over 1.5';
    }
    return null;
  }

  int _confRank(String c) => switch (c) { 'high' => 3, 'medium' => 2, _ => 1 };

  List<Map<String, dynamic>> _sortedPicks(Map data) {
    final picks = FanZoneService.rows(data['picks']);
    final indexed = [for (var i = 0; i < picks.length; i++) (i, picks[i])];
    indexed.sort((a, b) {
      final c = _confRank('${b.$2['confidence']}').compareTo(_confRank('${a.$2['confidence']}'));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return _withFormPicks(data, [for (final e in indexed) e.$2]);
  }

  /// Every match gets AI picks. When the server sends fewer than three (or
  /// none), the list is topped up with the goals markets that landed most
  /// often in the verified recent matches of both teams. Server picks always
  /// stay first and a market the server already picked is never contradicted.
  List<Map<String, dynamic>> _withFormPicks(
    Map data,
    List<Map<String, dynamic>> picks,
  ) {
    const want = 3;
    if (picks.length >= want) return picks;
    final candidates = <({String market, String pick, String key})>[
      (market: 'Over/Under 1.5 goals', pick: 'Over 1.5', key: 'Over 1.5'),
      (market: 'Over/Under 2.5 goals', pick: 'Over 2.5', key: 'Over 2.5'),
      (market: 'Over/Under 2.5 goals', pick: 'Under 2.5', key: 'Under 2.5'),
      (market: 'Both teams to score', pick: 'Yes', key: 'BTTS'),
      (market: 'Both teams to score', pick: 'No', key: 'No BTTS'),
    ];
    final taken = {for (final p in picks) '${p['market']}'};
    final scored = <({String market, String pick, ({int hits, int total, int pct}) r})>[];
    for (final c in candidates) {
      if (taken.contains(c.market)) continue;
      ({int hits, int total, int pct})? r;
      try {
        r = _rate(data, c.key);
      } catch (_) {
        r = null;
      }
      if (r == null || r.total == 0 || r.pct < 50) continue;
      scored.add((market: c.market, pick: c.pick, r: r));
    }
    scored.sort((a, b) => b.r.pct.compareTo(a.r.pct));
    final out = [...picks];
    for (final c in scored) {
      if (out.length >= want) break;
      // One pick per market: never both Over and Under (or Yes and No).
      if (out.any((p) => '${p['market']}' == c.market)) continue;
      out.add({
        'market': c.market,
        'pick': c.pick,
        'confidence': c.r.pct >= 70 ? 'high' : (c.r.pct >= 55 ? 'medium' : 'low'),
        'reason': 'Hit in ${c.r.hits} of ${c.r.total} recent matches of both teams.',
      });
    }
    return out;
  }

  Color _ringColor(double v) => v >= .65
      ? _accent
      : v >= .45
      ? const Color(0xFFFFB74D)
      : const Color(0xFFEF5350);

  Widget _ring(double value, String center, {double size = 72, Color? color}) {
    final c = color ?? _ringColor(value);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: size * .09,
              strokeCap: StrokeCap.round,
              backgroundColor: Ui.text.withValues(alpha: .10),
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
          Text(
            center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * .27),
          ),
        ],
      ),
    );
  }

  Widget _crestColumn(String logo, String name, String side) => Expanded(
    child: Column(
      children: [
        TeamCrest(logo: logo, size: 52),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.15),
        ),
        const SizedBox(height: 2),
        Text(
          side,
          style: TextStyle(color: Ui.muted, fontSize: 10, letterSpacing: 1.1),
        ),
      ],
    ),
  );

  Widget _marketChips(String key, String selected) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _chips.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final c = _chips[i], on = c == selected;
        return InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () {
            setState(() => _market[key] = c);
            _rev.value++;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _accent : Ui.text.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? _accent : Ui.line),
            ),
            child: Text(
              c,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: on ? const Color(0xFF05140B) : Ui.muted,
              ),
            ),
          ),
        );
      },
    ),
  );

  /// What the ring and text show for the chosen market chip.
  ({double value, String center, String label, String title, String sub, Color? color}) _resolve(
    Map<String, dynamic> data,
    String chosen,
  ) {
    final picks = _sortedPicks(data);
    var selected = chosen;
    final top = picks.isEmpty ? null : picks.first;
    if (selected == 'AI pick' && top != null) {
      final gm = _goalsMarketOf(top);
      final r = gm == null ? null : _rate(data, gm);
      final conf = '${top['confidence']}';
      return (
        value: r != null ? r.pct / 100 : _confRank(conf) / 3,
        center: r != null ? '${r.pct}%' : conf.toUpperCase(),
        label: 'AI PREDICTION · ${'${top['market']}'.toUpperCase()}',
        title: '${top['pick']}',
        sub: r != null
            ? 'Hit in ${r.hits} of ${r.total} recent matches · ${conf.toUpperCase()} confidence'
            : '${top['reason']}',
        color: r == null ? _confColor(conf) : null,
      );
    }
    if (selected == 'AI pick') {
      // No AI picks came back: show the strongest goals market from form.
      selected = _chips.skip(1).reduce(
        (a, b) => (_rate(data, a)?.pct ?? 0) >= (_rate(data, b)?.pct ?? 0) ? a : b,
      );
    }
    final r = _rate(data, selected);
    return (
      value: (r?.pct ?? 0) / 100,
      center: '${r?.pct ?? 0}%',
      label: 'FORM HIT RATE',
      title: selected == 'BTTS' ? 'Both teams to score' : '$selected goals',
      sub: r == null
          ? 'Not enough results'
          : 'Hit in ${r.hits} of ${r.total} recent matches of both teams',
      color: null,
    );
  }

  /// The user's own prediction: verified against the ESPN final score and
  /// counted in the Ranks table.
  Widget _savePrediction(Fixture f) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () async {
            try {
              final label = await saveFanPrediction(context, f);
              if (label != null) {
                _snack('Prediction saved: $label. Points appear in Ranks after the final whistle.');
                unawaited(_loadMyPicks());
              }
            } catch (e) {
              _snack(safeErrorMessage(e));
            }
          },
          icon: const Icon(Icons.how_to_vote_rounded, size: 18),
          label: const Text(
            'Make my own prediction',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Checked against the ESPN final score. Points go to the Ranks table.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Ui.muted),
        ),
      ],
    ),
  );

  Widget _topPick(Fixture f, Map<String, dynamic> data) {
    final key = FanZoneService.matchKey(f);
    final v = _resolve(data, _market[key] ?? 'AI pick');
    final value = v.value, center = v.center, label = v.label, title = v.title, sub = v.sub;
    final color = v.color;

    final typed = f.kickoff.year >= 2099;
    final now = DateTime.now();
    final k = f.kickoff.toLocal();

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _accent.withValues(alpha: .28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_lt(const Color(0xFF0F3D26), const Color(0xFFDDF3E6)), Ui.card],
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: .10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marketChips(key, _market[key] ?? 'AI pick'),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 14, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'TOP PICK · ${f.league.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 10.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Ui.text.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  typed ? 'YOUR MATCHUP' : 'UPCOMING',
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 10,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _crestColumn(f.homeLogo, f.home, 'HOME'),
              SizedBox(
                width: 84,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      typed ? 'VS' : fmtTime(k),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    if (!typed)
                      Text(
                        dayLabel(k, now),
                        style: TextStyle(color: Ui.muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              _crestColumn(f.awayLogo, f.away, 'AWAY'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _lt(Colors.black.withValues(alpha: .28), Ui.text.withValues(alpha: .05)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.text.withValues(alpha: .06)),
            ),
            child: Row(
              children: [
                _ring(value, center, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The other AI picks as compact rows with a small ring each.
  Widget _picksList(Map<String, dynamic> data) {
    final picks = _sortedPicks(data);
    if (picks.length < 2) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ui.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MORE AI PICKS',
            style: TextStyle(
              color: Ui.muted,
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final p in picks.skip(1)) _pickRow(data, p),
          Text(
            'Opinions from recent form and the data in the full analysis, not guaranteed outcomes.',
            style: TextStyle(color: Ui.dim, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _pickRow(Map<String, dynamic> data, Map<String, dynamic> p) {
    final conf = '${p['confidence']}';
    final gm = _goalsMarketOf(p);
    final r = gm == null ? null : _rate(data, gm);
    final value = r != null ? r.pct / 100 : _confRank(conf) / 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ring(
            value,
            r != null ? '${r.pct}%' : conf.substring(0, 1).toUpperCase(),
            size: 46,
            color: r == null ? _confColor(conf) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['market']}',
                  style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${p['pick']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p['reason']}',
                  style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact card on the AI Predict page; tapping opens the match's own page.
  Widget _result(Fixture f, Map<String, dynamic> data) {
    final key = FanZoneService.matchKey(f);
    final v = _resolve(data, 'AI pick');
    final typed = f.kickoff.year >= 2099;
    final k = f.kickoff.toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openMatchPage(f, key),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withValues(alpha: .28)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_lt(const Color(0xFF0F3D26), const Color(0xFFDDF3E6)), Ui.card],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 13, color: _accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.league.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      typed ? 'YOUR MATCHUP' : '${dayLabel(k, DateTime.now())} · ${fmtTime(k)}',
                      style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    // Removes this analysis and deselects the match, so no scrolling down to untick it.
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy ? null : () => _dismissResult(key),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: Ui.muted,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TeamCrest(logo: f.homeLogo, size: 38),
                    const SizedBox(width: 4),
                    TeamCrest(logo: f.awayLogo, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.genderTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _lt(Colors.black.withValues(alpha: .28), Ui.text.withValues(alpha: .05)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _ring(v.value, v.center, size: 54, color: v.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOP PICK',
                              style: TextStyle(
                                color: Ui.muted,
                                fontSize: 10,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              v.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Full page for one analysed match: top pick card, more picks and the full analysis.
  void _openMatchPage(Fixture f, String key) {
    // Remembered so the page comes back if the app is closed while it is open.
    PageMemory.open('analysis', key);
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _rev,
          builder: (ctx, _, _) {
            final data = _results[key];
            return Scaffold(
              backgroundColor: Ui.bg,
              appBar: AppBar(
                title: Text(
                  f.genderTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                actions: [
                  // Same Bet Hub shortcut as the AI Predict page: opens the
                  // browser with its pages still open; minimising it returns
                  // to this analysis page.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(ctx)
                          .push(MaterialPageRoute<void>(
                              builder: (_) => const BetBrowserScreen()))
                          .then((_) => _rev.value++),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8E6BFF), Color(0xFFFF5C8A)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (BetBrowserScreen.hasOpenPages)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF48D597),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const Icon(Icons.local_fire_department_rounded,
                                size: 15, color: Colors.white),
                            const SizedBox(width: 4),
                            const Text(
                              'Bet Hub',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: data == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                      children: [
                        _topPick(f, data),
                        if (!_isCustom(f) && !_isWeb(f)) _savePrediction(f),
                        _picksList(data),
                        _fullAnalysis(f, data),
                      ],
                    ),
              bottomNavigationBar: _slipSelections.isNotEmpty ? _betSlipBar() : null,
            );
          },
        ),
      ),
    )
        .then((_) => PageMemory.close('analysis', key));
  }

  void _openBetSlipPreview() {
    if (_slipSelections.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BetSlipScreen(
        entries: _slipSelections.entries.toList(),
        onRemove: (key) {
          setState(() => _slipSelections.remove(key));
          _rev.value++;
        },
        onPrint: _printSelectedSlip,
        onClear: () {
          setState(_slipSelections.clear);
          _rev.value++;
        },
      ),
    ));
  }

  Widget _betSlipBar() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: Ui.card, border: Border(top: BorderSide(color: Ui.line))),
      child: Row(children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openBetSlipPreview,
          child: Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF8B70FF).withValues(alpha: .15), borderRadius: BorderRadius.circular(10)), child: Text('${_slipSelections.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8B70FF)))),
        ),
        const SizedBox(width: 10),
        Expanded(child: InkWell(
          onTap: _openBetSlipPreview,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Text('MY BET SLIP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), Text('${_slipSelections.length} selections · tap to preview', style: TextStyle(color: Ui.muted, fontSize: 10))]),
        )),
        TextButton(onPressed: () { setState(_slipSelections.clear); _rev.value++; }, child: const Text('Clear')),
        const SizedBox(width: 4),
        FilledButton.icon(onPressed: _printSelectedSlip, icon: const Icon(Icons.print_rounded, size: 17), label: const Text('Print')),
      ]),
    ),
  );

  Future<void> _printSelectedSlip() async {
    final picks = _slipSelections.values.toList();
    if (picks.isEmpty) return;
    try {
      await BetSlipPdf.printSelected(picks: picks);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(safeErrorMessage(e))));
    }
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF713DDA), Color(0xFF007FAD)],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF713DDA).withValues(alpha: .28),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .18),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You choose. AI analyses.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Pick up to 3 matches from our list, or type your own. We study the last 5 results of each team: form, goals and likely outcomes.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _matchTile(Fixture f) {
    final key = FanZoneService.matchKey(f);
    final on = _selected.contains(key);
    const accent = Color(0xFF8E6BFF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () { _select(f, !on); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: on ? accent.withValues(alpha: .14) : Ui.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on ? accent.withValues(alpha: .8) : Ui.line,
                width: on ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                TeamCrest(logo: f.homeLogo, size: 36),
                const SizedBox(width: 4),
                TeamCrest(logo: f.awayLogo, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.genderTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.league.isEmpty ? 'Football' : f.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Ui.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _isCustom(f)
                                ? Icons.edit_rounded
                                : Icons.schedule_rounded,
                            size: 12,
                            color: Ui.dim,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _isCustom(f)
                                  ? 'Teams are verified when analysing'
                                  : '${fanClock(f.kickoff)} · ${_date(f.kickoff.toIso8601String())}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: Ui.dim),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_isCustom(f))
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                    onPressed: _busy ? null : () => _removeCustom(f),
                    icon: Icon(Icons.close_rounded, size: 18, color: Ui.dim),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? accent : Colors.transparent,
                    border: Border.all(
                      color: on ? accent : Ui.dim,
                      width: 1.6,
                    ),
                  ),
                  child: on
                      ? Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Ui.text,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Slim one-line box: type "Arsenal vs Chelsea" and add it to the picks.
  Widget _typeBox() {
    const accent = Color(0xFF8E6BFF);
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: Ui.dim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _typed,
              enabled: !_busy,
              maxLength: 130,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addCustom(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'Type a match, e.g. Arsenal vs Chelsea',
                hintStyle: TextStyle(fontSize: 13.5, color: Ui.dim),
              ),
            ),
          ),
          Tooltip(
            message: 'Tap to search women\'s teams',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy ? null : () => setState(() => _typedWomen = !_typedWomen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: (_typedWomen ? accent : Ui.dim).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Women',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _typedWomen ? accent : Ui.dim,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add match',
            onPressed: _busy ? null : _addCustom,
            icon: const Icon(Icons.add_circle_rounded, color: accent),
          ),
        ],
      ),
    );
  }

  /// Analyses (and failures) for the matches that are currently selected.
  List<Widget> _resultWidgets() {
    final out = <Widget>[];
    for (final f in _all.where(
      (f) => _selected.contains(FanZoneService.matchKey(f)),
    )) {
      final key = FanZoneService.matchKey(f);
      if (_failures.containsKey(key)) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${f.genderTitle}: ${_failures[key]}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
      }
      if (_results.containsKey(key)) out.add(_result(f, _results[key]!));
    }
    return out;
  }

  Widget _actionBar() {
    final n = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Ui.bg,
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (n > 0 && !_busy)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _unselectAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.deselect_rounded, size: 16, color: Ui.muted),
                label: Text(
                  'Unselect all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Ui.muted,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _AnalyseButton(
                  busy: _busy,
                  done: _done,
                  total: _total,
                  count: n,
                  onPressed: _analyse,
                ),
              ),
              if (_busy) ...[
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Stop analysis',
                  child: SizedBox(
                    height: 50,
                    child: Material(
                      color: const Color(0xFFE5484D).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _stopAnalysis,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stop_rounded,
                                  color: Color(0xFFFF6B6B), size: 22),
                              SizedBox(width: 4),
                              Text(
                                'Stop',
                                style: TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text(
        'AI Predict',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context)
                .push(
                  MaterialPageRoute<void>(builder: (_) => const BetBrowserScreen()),
                )
                .then((_) {
              if (mounted) setState(() {});
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8E6BFF), Color(0xFFFF5C8A)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Green dot: pages are still open in the minimised browser.
                  if (BetBrowserScreen.hasOpenPages)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF48D597),
                        shape: BoxShape.circle,
                      ),
                    ),
                  const Icon(Icons.local_fire_department_rounded,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 4),
                  const Text(
                    'Bet Hub',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.person_outline_rounded),
          onPressed: _openProfile,
        ),
        IconButton(
          tooltip: 'Refresh matches',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading || _busy ? null : () => _load(fresh: true),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(fresh: true),
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _hero(),
                const SizedBox(height: 12),
                _typeBox(),
                if (_custom.isNotEmpty) const SizedBox(height: 10),
                for (final f in _custom) _matchTile(f),
                ..._resultWidgets(),
                ..._historySection(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'UPCOMING MATCHES',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: _lt(const Color(0xFFB39DFF), const Color(0xFF6A4CD6)),
                      ),
                    ),
                    const Spacer(),
                    FanPill(
                      text: (SubscriptionService.instance.isPremium || _weeklyPremium)
                          ? '${_selected.length} selected · Premium'
                          : '${_selected.length}/$_maxPicks selected · ${(_maxPicks - _dailyFreePicks.length).clamp(0, _maxPicks)} left today',
                      color: _selected.isEmpty
                          ? Ui.muted
                          : const Color(0xFF8E6BFF),
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!),
                  ),
                if (!_loading && _fixtures.isEmpty && _ext.isEmpty && !_extLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No upcoming matches in our list yet. Type a match above.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ..._upcomingList(),
              ],
            ),
          ),
        ),
        _actionBar(),
        if (_slipSelections.isNotEmpty) _betSlipBar(),
      ],
    ),
  );
}


Color _lt(Color dark, Color light) => Ui.isLight ? light : dark;

/// Bottom sheet listing every league / national competition with matches,
/// with a search box.
class _LeagueSheet extends StatefulWidget {
  final List<MapEntry<String, int>> leagues;
  final int total;
  final String active;
  const _LeagueSheet({
    required this.leagues,
    required this.total,
    required this.active,
  });
  @override
  State<_LeagueSheet> createState() => _LeagueSheetState();
}

class _LeagueSheetState extends State<_LeagueSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = [
      for (final e in widget.leagues)
        if (q.isEmpty || e.key.toLowerCase().contains(q)) e,
    ];
    final height = MediaQuery.of(context).size.height * .72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search league or competition',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (q.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('All leagues'),
                      trailing: Text('${widget.total}'),
                      selected: widget.active == LeagueFilter.all,
                      onTap: () => Navigator.pop(context, LeagueFilter.all),
                    ),
                  for (final e in rows)
                    ListTile(
                      leading: Icon(
                        LeagueFilter.isNationalLeague(e.key)
                            ? Icons.flag_rounded
                            : Icons.emoji_events_outlined,
                      ),
                      title: Text(e.key),
                      trailing: Text('${e.value}'),
                      selected: widget.active == e.key,
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No league found.')),
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

/// Forces light text and icons on the intentionally dark AI panels, so they
/// stay readable when the app is using a light theme.
class _DarkText extends StatelessWidget {
  final Widget child;
  const _DarkText({required this.child});

  @override
  Widget build(BuildContext context) => IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: child,
        ),
      );
}


/// The "Analyse" button. While working it shows progress itself: a purple fill that grows with each finished
/// match (and creeps forward during the current one), a moving shine and a spinner.
class _AnalyseButton extends StatefulWidget {
  const _AnalyseButton({
    required this.busy,
    required this.done,
    required this.total,
    required this.count,
    required this.onPressed,
  });

  final bool busy;
  final int done, total, count;
  final VoidCallback onPressed;

  @override
  State<_AnalyseButton> createState() => _AnalyseButtonState();
}

class _AnalyseButtonState extends State<_AnalyseButton> with TickerProviderStateMixin {
  static const _purple = Color(0xFF7C4DFF);
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  // Eases toward (but never reaches) the end of the match being analysed, so the bar always moves.
  late final AnimationController _creep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 45),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _start();
  }

  void _start() {
    _shine.repeat();
    _creep.forward(from: 0);
  }

  @override
  void didUpdateWidget(_AnalyseButton old) {
    super.didUpdateWidget(old);
    if (widget.busy && !old.busy) {
      _start();
    } else if (!widget.busy && old.busy) {
      _shine.stop();
      _creep.stop();
    } else if (widget.busy && widget.done != old.done) {
      _creep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    _creep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    final enabled = !busy && widget.count > 0;
    final label = busy
        ? 'Analysing… ${widget.done}/${widget.total}'
        : widget.count == 0
        ? 'Select matches to analyse'
        : 'Analyse ${widget.count} match${widget.count == 1 ? '' : 'es'}';
    final fg = busy || enabled ? Colors.white : Ui.muted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: enabled
                ? _purple
                : busy
                ? _purple.withValues(alpha: .22)
                : Ui.card,
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (busy)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_shine, _creep]),
                        builder: (context, _) {
                          final total = widget.total == 0 ? 1 : widget.total;
                          final inFlight = Curves.easeOut.transform(_creep.value) * 0.9;
                          final progress = ((widget.done + inFlight) / total).clamp(0.0, 1.0);
                          final t = _shine.value;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress < 0.04 ? 0.04 : progress,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment(-2 + 4 * t, 0),
                                    end: Alignment(-1 + 4 * t, 0),
                                    colors: [
                                      _purple,
                                      Color.lerp(_purple, Colors.white, .35)!,
                                      _purple,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      else
                        Icon(Icons.auto_awesome_rounded, size: 20, color: fg),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _ShareDraft {
  final String text;
  final Uint8List? image;
  const _ShareDraft(this.text, this.image);
}

/// Lets the fan review the summary and optionally attach one photo before it
/// is posted to the community.
class _CommunityShareSheet extends StatefulWidget {
  final String initialText;
  const _CommunityShareSheet({required this.initialText});

  @override
  State<_CommunityShareSheet> createState() => _CommunityShareSheetState();
}

class _CommunityShareSheetState extends State<_CommunityShareSheet> {
  late final TextEditingController _text;
  Uint8List? _image;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: false,
        withReadStream: true,
        allowMultiple: false,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 4 * 1024 * 1024) {
        throw Exception('Choose a JPG or PNG smaller than 4 MB.');
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readStream!) {
          if (buffer.length + chunk.length > 4 * 1024 * 1024) {
            throw Exception('Choose an image smaller than 4 MB.');
          }
          buffer.add(chunk);
        }
        bytes = buffer.takeBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read this image. Choose another photo.');
      }
      if (mounted) setState(() => _image = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text.text.trim();
    return Padding(
      // Keep the Post button clear of the phone's navigation bar; when the
      // keyboard is open it already sits above it.
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 +
            (MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom
                : MediaQuery.of(context).viewPadding.bottom),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Post summary to Community Trend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 8,
              minLines: 4,
              maxLength: 600,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: 'Only this summary is shared, not the full analysis.',
              ),
            ),
            const SizedBox(height: 8),
            if (_image != null)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _image!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Remove image',
                    onPressed: () => setState(() => _image = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_picking ? 'Opening…' : 'Add image (optional)'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: text.isEmpty
                  ? null
                  : () => Navigator.pop(context, _ShareDraft(text, _image)),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}
