import 'package:flutter/material.dart';
import '../utils/safe_error_message.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fixture.dart';
import '../services/content_sync.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'fan_widgets.dart';

class AiPredictScreen extends StatefulWidget {
  final bool active;
  const AiPredictScreen({super.key, required this.active});
  @override
  State<AiPredictScreen> createState() => _AiPredictScreenState();
}

class _AiPredictScreenState extends State<AiPredictScreen> {
  List<Fixture> _fixtures = [];

  /// Upcoming matches from other sources (the server's ESPN feed) that are not
  /// in the app's own fixture list.
  List<Fixture> _external = [];

  /// Matchups the user typed in themselves. Teams are resolved on the server.
  final List<Fixture> _custom = [];
  final TextEditingController _typed = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _leagueFilter = '';
  int _extShown = 20;
  bool _extLoading = false;
  String? _extError;
  final Set<String> _selected = {};
  final Map<String, Map<String, dynamic>> _results = {};
  final Map<String, String> _failures = {};
  bool _loading = false, _busy = false;
  String? _error;
  int _done = 0, _total = 0;
  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    ContentSync.tick.removeListener(_sync);
    _typed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Fixture> get _all => [..._custom, ..._fixtures, ..._external];
  static bool _isCustom(Fixture f) => f.id.startsWith('custom:');
  static bool _isExternal(Fixture f) => f.id.startsWith('ext:');

  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  static bool _like(String a, String b) {
    final x = _n(a), y = _n(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x == y ||
        (x.length >= 4 && y.length >= 4 && (x.contains(y) || y.contains(x)));
  }

  /// The same real-world match listed by two sources.
  static bool _sameMatch(Fixture a, Fixture b) =>
      _like(a.home, b.home) &&
      _like(a.away, b.away) &&
      a.kickoff.difference(b.kickoff).abs() < const Duration(hours: 18);

  /// External matches that the app's own list does not already contain.
  List<Fixture> get _extFresh => _external
      .where((e) => !_fixtures.any((f) => _sameMatch(f, e)))
      .toList();

  void _prune() {
    final keys = _all.map(FanZoneService.matchKey).toSet();
    _selected.retainAll(keys);
  }

  Future<void> _load() async {
    if (!mounted || _loading || _busy) return;
    setState(() => _loading = true);
    // Other sources load in parallel and can never break the app's own list.
    final external = _loadExternal();
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
    await external;
    if (mounted) setState(_prune);
  }

  Future<void> _loadExternal() async {
    if (_extLoading) return;
    if (mounted) setState(() => _extLoading = true);
    try {
      final data = await FanZoneService.call(
        'ai-predict/matches',
        timeout: const Duration(seconds: 30),
      );
      final parsed = <Fixture>[];
      for (final m in FanZoneService.rows(data['matches'])) {
        final f = Fixture.tryParse({...m, 'id': 'ext:${m['id']}'});
        if (f != null && f.kickoff.isAfter(DateTime.now())) parsed.add(f);
      }
      parsed.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      if (!mounted) return;
      setState(() {
        _external = parsed;
        _extError = null;
      });
    } catch (e) {
      // The real reason goes to the log; users get a short plain-language line.
      debugPrint('AI Predict: other-league matches failed: $e');
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
      final notDeployed = raw.toLowerCase() == 'not found' ||
          raw.toLowerCase().contains('method not allowed');
      if (mounted) {
        setState(
          () => _extError = notDeployed
              ? 'More matches are not available yet. Please try again later.'
              : (raw.isNotEmpty &&
                        raw.length <= 120 &&
                        !RegExp(r'https?://|worker|secret', caseSensitive: false)
                            .hasMatch(raw)
                    ? raw
                    : 'More matches could not be loaded.'),
        );
      }
    } finally {
      if (mounted) setState(() => _extLoading = false);
    }
  }

  void _select(Fixture f, bool selected) {
    if (_busy) return;
    if (selected && _selected.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select up to 3 matches at a time.')),
      );
      return;
    }
    setState(() {
      final key = FanZoneService.matchKey(f);
      if (selected)
        _selected.add(key);
      else
        _selected.remove(key);
    });
  }

  static final RegExp _vs = RegExp(
    r'\s+(?:vs\.?|v|x|-|–|—)\s+',
    caseSensitive: false,
  );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addCustom() {
    if (_busy) return;
    final parts = _typed.text.trim().split(_vs).map((e) => e.trim()).toList();
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
    final key = FanZoneService.matchKey(f);
    if (!_selected.contains(key) && _selected.length >= _maxPicks) {
      _snack('Select up to 3 matches at a time.');
      return;
    }
    setState(() {
      if (existing.isEmpty) _custom.insert(0, f);
      _selected.add(key);
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
    if (_isCustom(f)) {
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
    if ((_isCustom(f) || _isExternal(f)) &&
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

  static const _maxPicks = 3;

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

  Widget _result(Fixture f, Map<String, dynamic> data) => Container(
    margin: const EdgeInsets.only(top: 14),
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
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: Color(0xFFB39DFF),
            ),
            const SizedBox(width: 6),
            const Text(
              'AI ANALYSIS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
                color: Color(0xFFB39DFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          '${data['analysis']}',
          style: const TextStyle(height: 1.55, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Text(
          'Historical form is a limited sample, not a guaranteed outcome. Injuries, lineups and odds are not included.',
          style: TextStyle(color: Ui.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              try {
                await Share.share(
                  'Deeprowss AI Predict\n${f.title}\n\n${data['analysis']}\n\nSource: ${data['dataSource'] ?? 'Verified recent results'}. Outcomes are uncertain.',
                );
              } catch (_) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open sharing.')),
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
                'Pick up to 3 matches from our list or other leagues, or type your own. We study the last 5 results of each team: form, goals and likely outcomes.',
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
          onTap: _busy ? null : () => _select(f, !on),
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

  Widget _leagueChips(List<String> leagues, String active) {
    const accent = Color(0xFF8E6BFF);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final l in ['', ...leagues])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(l.isEmpty ? 'All' : l),
                selected: active == l,
                selectedColor: accent.withValues(alpha: .28),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _leagueFilter = l;
                  _extShown = 20;
                }),
              ),
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

  List<Widget> _moreMatches() {
    final fresh = _extFresh;
    final counts = <String, int>{};
    for (final f in fresh) {
      if (f.league.isNotEmpty) counts[f.league] = (counts[f.league] ?? 0) + 1;
    }
    final leagues = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final active = leagues.contains(_leagueFilter) ? _leagueFilter : '';
    final shown = fresh
        .where((f) => active.isEmpty || f.league == active)
        .toList();
    final visible = shown.take(_extShown).toList();
    return [
      const SizedBox(height: 18),
      Row(
        children: [
          const Text(
            'MORE MATCHES · OTHER LEAGUES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
              color: Color(0xFFB39DFF),
            ),
          ),
          const Spacer(),
          if (_extLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Fixtures from other sources that are not in our list. You can analyse them too.',
        style: TextStyle(fontSize: 11.5, color: Ui.muted),
      ),
      const SizedBox(height: 10),
      if (_extError != null && fresh.isEmpty)
        Row(
          children: [
            Expanded(child: Text(_extError!)),
            TextButton(
              onPressed: _extLoading ? null : _loadExternal,
              child: const Text('Retry'),
            ),
          ],
        ),
      if (leagues.length > 1) ...[
        _leagueChips(leagues, active),
        const SizedBox(height: 10),
      ],
      for (final f in visible) _matchTile(f),
      if (shown.length > visible.length)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _extShown += 20),
            child: Text('Show more (${shown.length - visible.length})'),
          ),
        ),
      if (!_extLoading && _extError == null && fresh.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No other upcoming matches found right now.',
            style: TextStyle(color: Ui.muted),
          ),
        ),
    ];
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
                      text: '${_selected.length}/$_maxPicks selected',
                      color: _selected.isEmpty
                          ? Ui.muted
                          : const Color(0xFF8E6BFF),
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loading && _fixtures.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: LinearProgressIndicator(),
                  )
                else if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!),
                  ),
                if (!_loading && _fixtures.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No upcoming matches in our list yet. Try the other leagues below, or type a match above.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final f in _fixtures) _matchTile(f),
                ..._moreMatches(),
              ],
            ),
          ),
        ),
        _actionBar(),
      ],
    ),
  );
}
