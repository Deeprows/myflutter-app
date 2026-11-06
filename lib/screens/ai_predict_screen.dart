import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/safe_error_message.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fixture.dart';
import '../services/content_sync.dart';
import '../models/live_score.dart';
import '../services/score_service.dart';
import '../services/fan_zone_service.dart';
import '../services/subscription_service.dart';
import '../services/remote_config.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'fan_profile_screen.dart';
import 'fan_widgets.dart';
import '../models/fan_prediction.dart';
import 'content_shortcut_screen.dart';
import 'prediction_results_screen.dart';
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
  String _extLeague = 'All';
  int _extShown = 15;

  /// Matchups the user typed in themselves. Teams are resolved on the server.
  final List<Fixture> _custom = [];
  final TextEditingController _typed = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Set<String> _selected = {};
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
  @override
  void initState() {
    super.initState();
    _loadDailyFreePicks();
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

  Future<void> _load() async {
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
    await _loadExt();
    unawaited(_loadMyPicks());
    if (mounted) setState(_prune);
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
                const Expanded(
                  child: Text(
                    'MY PREDICTIONS',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w900, color: Color(0xFFB39DFF)),
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
  Future<void> _loadExt() async {
    if (!mounted || _extLoading) return;
    setState(() {
      _extLoading = true;
      _extError = null;
    });
    try {
      final data = await FanZoneService.call('ai-predict/matches');
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
            league: '${m['league'] ?? ''}',
            kickoff: kickoff,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _ext = list;
        if (_extLeague != 'All' && !list.any((f) => f.league == _extLeague)) {
          _extLeague = 'All';
        }
      });
    } catch (e) {
      // The server's list is unavailable: read the matches from ESPN directly.
      try {
        final direct = await _loadExtDirect();
        if (direct.isNotEmpty && mounted) {
          setState(() {
            _ext = direct;
            _extError = null;
            if (_extLeague != 'All' &&
                !direct.any((f) => f.league == _extLeague)) {
              _extLeague = 'All';
            }
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        final why = e.toString().replaceFirst('Exception: ', '');
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
            return data['events'] as List;
          }
        } catch (_) {}
      }
      return const <dynamic>[];
    }

    final parts = await Future.wait([for (var i = 0; i <= 8; i++) day(i)]);
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
      final league = '${(e['leagueName'] ?? (comp['league'] is Map ? comp['league']['name'] : null)) ?? ''}';
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
    return out.take(300).toList();
  }

  /// ESPN matches with a league filter and a "show more" button.
  List<Widget> _extSection() {
    if (_ext.isEmpty && !_extLoading && _extError == null) return const [];
    final leagues = <String>{for (final f in _ext) f.league}.toList()..sort();
    final shown = _extLeague == 'All'
        ? _ext
        : _ext.where((f) => f.league == _extLeague).toList();
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          const Expanded(
            child: Text(
              'MORE MATCHES · ALL LEAGUES',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
                color: Color(0xFFB39DFF),
              ),
            ),
          ),
          if (_extLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (leagues.length > 1)
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final l in ['All', ...leagues])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l, style: const TextStyle(fontSize: 12)),
                    selected: _extLeague == l,
                    onSelected: (_) => setState(() {
                      _extLeague = l;
                      _extShown = 15;
                    }),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 10),
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
      for (final f in shown.take(_extShown)) _matchTile(f),
      if (shown.length > _extShown)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _extShown += 15),
            child: Text('Show more (${shown.length - _extShown} left)'),
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
    if (!premium && !_dailyFreePicks.contains(key) &&
        _dailyFreePicks.length >= _maxPicks) {
      _snack('You have used your 3 free AI match selections for today. Upgrade to Premium for more selections.');
      await _showPremiumUpgrade();
      if (!mounted || !SubscriptionService.instance.isPremium) return false;
    }

    if (!SubscriptionService.instance.isPremium) {
      await _saveDailyFreePick(key);
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
    final id = 'custom:${_n(parts[0])}|${_n(parts[1])}';
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
          );
    final added = await _select(f, true);
    if (!added || !mounted) return;
    setState(() {
      if (existing.isEmpty) _custom.insert(0, f);
      _typed.clear();
    });
    FocusScope.of(context).unfocus();
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
        'custom': {'home': f.home, 'away': f.away},
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
      if (!mounted) return;
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
        if (!mounted) return;
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
                league: f.league,
                kickoff: f.kickoff,
              );
            }
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _failures[key] = _failText(f, e));
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) setState(() => _busy = false);
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
          color: Colors.white.withValues(alpha: .04),
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
      color: Colors.white.withValues(alpha: .04),
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
      color: Colors.white.withValues(alpha: .06),
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
  Widget _formattedAiAnalysis(String raw) {
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
          _aiSectionCard(i + 1, sections[i].title, sections[i].sub, sections[i].lines),
        if (picks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 5),
            decoration: BoxDecoration(
              color: const Color(0xFF171A32),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _aiViolet.withValues(alpha: .28)),
            ),
            child: Column(
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
                for (var i = 0; i < picks.length; i++) _aiPickAnalysisCard(i + 1, picks[i]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _aiSectionCard(int number, String title, String sub, List<String> lines) {
    final verdict = title.contains('VERDICT');
    final accent = verdict ? _aiVerdict : _aiViolet;
    final titleColor = verdict ? const Color(0xFF8FF0C2) : const Color(0xFFD2C7FF);

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
            accent.withValues(alpha: verdict ? .16 : .10),
            Colors.white.withValues(alpha: .025),
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
                  color: Colors.white.withValues(alpha: .22),
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
                        ? const Color(0xFF7CE8B5)
                        : r == 'D'
                            ? const Color(0xFFFFD58F)
                            : const Color(0xFFFF9A9A),
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
                  color: Colors.white.withValues(alpha: .86),
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
                style: TextStyle(fontSize: 13.5, height: 1.55, color: Colors.white.withValues(alpha: .84)),
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
          color: Colors.white.withValues(alpha: verdict ? .94 : .82),
        ),
      ),
    );
  }

  Widget _aiPickAnalysisCard(int number, String source) {
    final text = source.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
    final reasonIndex = text.toLowerCase().indexOf('reason:');
    final pickText = reasonIndex >= 0 ? text.substring(0, reasonIndex).trim() : text;
    final reason = reasonIndex >= 0
        ? text.substring(reasonIndex + 'reason:'.length).trim()
        : '';
    final colon = pickText.indexOf(':');
    final market = colon > 0 ? pickText.substring(0, colon).trim() : 'Prediction';
    final selection = colon > 0 ? pickText.substring(colon + 1).trim() : pickText;
    final confidenceMatch = RegExp(r'\((high|medium|low)\)', caseSensitive: false).firstMatch(selection);
    final confidence = confidenceMatch?.group(1)?.toUpperCase();
    final confidenceColor = switch (confidence) {
      'HIGH' => const Color(0xFF48D597),
      'MEDIUM' => const Color(0xFFFFC46B),
      'LOW' => const Color(0xFF9EABC0),
      _ => Ui.muted,
    };
    final cleanSelection = selection.replaceAll(RegExp(r'\s*\((high|medium|low)\)', caseSensitive: false), '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF222746),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Column(
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
                  style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w800),
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
                    style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fullAnalysis(Fixture f, Map<String, dynamic> data) => Container(
    margin: const EdgeInsets.only(top: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF713DDA).withValues(alpha: .45)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF713DDA).withValues(alpha: .22), Ui.card],
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
                f.title,
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
            title: const Text(
              'COMPREHENSIVE AI ANALYSIS',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: Color(0xFFCEC1FF),
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
                child: _formattedAiAnalysis('${data['analysis']}'),
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
          child: TextButton.icon(
            onPressed: () async {
              final analysis = 'Deeprowss AI Predict\\n${f.title}\\n\\n'
                  '${'${data['analysis']}'.replaceAll('**', '')}\\n\\n'
                  'Source: ${data['dataSource'] ?? 'Verified recent results'}. '
                  'AI analysis is informational; outcomes are uncertain.';
              final action = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: const Text('Post to Community Trend'),
                      subtitle: const Text('Publish this analysis with a match link'),
                      onTap: () => Navigator.pop(ctx, 'post'),
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
                if (action == 'post') {
                  await FanZoneService.publish(
                    kind: 'prediction',
                    text: '$analysis\\n\\nOpen this match in Deeprowss AI Predict: ${f.title}',
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
                    '$analysis\\n\\nView more predictions on Deeprowss: $download',
                  );
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                );
              }
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Share analysis'),
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
    return [for (final e in indexed) e.$2];
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
              backgroundColor: Colors.white.withValues(alpha: .10),
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
              color: on ? _accent : Colors.white.withValues(alpha: .06),
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
              _snack(e.toString().replaceFirst('Exception: ', ''));
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
          colors: [const Color(0xFF0F3D26), Ui.card],
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
                  color: Colors.white.withValues(alpha: .08),
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
              color: Colors.black.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .06)),
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
                colors: [const Color(0xFF0F3D26), Ui.card],
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
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TeamCrest(logo: f.homeLogo, size: 38),
                    const SizedBox(width: 4),
                    TeamCrest(logo: f.awayLogo, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.title,
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
                    color: Colors.black.withValues(alpha: .28),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _rev,
          builder: (ctx, _, _) {
            final data = _results[key];
            return Scaffold(
              backgroundColor: Ui.bg,
              appBar: AppBar(
                title: Text(
                  f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
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
            );
          },
        ),
      ),
    );
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
                        f.title,
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
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Colors.white,
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
              '${f.title}: ${_failures[key]}',
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
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: _total == 0 ? null : (_done / _total).clamp(0.0, 1.0),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                disabledBackgroundColor: Ui.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _busy || n == 0 ? null : _analyse,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(
                _busy
                    ? 'Analysing… $_done/$_total'
                    : n == 0
                    ? 'Select matches to analyse'
                    : 'Analyse $n match${n == 1 ? '' : 'es'}',
              ),
            ),
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
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.person_outline_rounded),
          onPressed: _openProfile,
        ),
        IconButton(
          tooltip: 'Refresh matches',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading || _busy ? null : _load,
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'UPCOMING MATCHES',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFB39DFF),
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
                for (final f in _fixtures) _matchTile(f),
                ..._extSection(),
              ],
            ),
          ),
        ),
        _actionBar(),
      ],
    ),
  );
}
