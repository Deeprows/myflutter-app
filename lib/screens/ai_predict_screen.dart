import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fixture.dart';
import '../player/player_hub_screen.dart';
import '../services/content_sync.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'content_shortcut_screen.dart';
import 'fan_widgets.dart';

const _aiViolet = Color(0xFF7C4DFF);

/// What the AI sent back, split into the parts the verdict card shows.
/// The worker asks the model for LEAN / SCORE / CONFIDENCE / WHY / RISKS
/// lines. If an older worker (or a chatty model) sends plain text instead,
/// [structured] is false and the raw text is shown as paragraphs.
class _AiResult {
  final String raw;
  final String lean;
  final int? home;
  final int? away;
  final String confidence;
  final List<String> why;
  final List<String> risks;
  const _AiResult({
    required this.raw,
    this.lean = '',
    this.home,
    this.away,
    this.confidence = '',
    this.why = const [],
    this.risks = const [],
  });

  bool get structured => lean.isNotEmpty || why.isNotEmpty || risks.isNotEmpty;

  static String _clean(String v) =>
      v.replaceAll('*', '').replaceAll('#', '').trim();

  static List<String> _bullets(String block) {
    final out = <String>[];
    for (final line in block.split('\n')) {
      final t = _clean(line.replaceFirst(RegExp(r'^\s*([-•*]|\d+[.)])\s*'), ''));
      if (t.length > 2) out.add(t);
    }
    return out;
  }

  factory _AiResult.parse(String text) {
    final raw = text.trim();
    String? line(String key) {
      final m = RegExp(
        '^[\\s*#]*$key[\\s*]*[:\\-][\\s*]*(.+)\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(raw);
      return m == null ? null : _clean(m.group(1)!);
    }

    String block(String key, List<String> stops) {
      final start = RegExp(
        '^[\\s*#]*$key[\\s*]*:[\\s*]*\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(raw);
      if (start == null) {
        // "WHY: first point" on the same line.
        final inline = line(key);
        return inline ?? '';
      }
      var rest = raw.substring(start.end);
      var end = rest.length;
      for (final stop in stops) {
        final m = RegExp(
          '^[\\s*#]*$stop[\\s*]*:',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(rest);
        if (m != null && m.start < end) end = m.start;
      }
      return rest.substring(0, end);
    }

    final lean = line('LEAN') ?? '';
    int? h;
    int? a;
    final scoreText = line('(?:POSSIBLE\\s+)?SCORE') ?? '';
    final sm = RegExp(r'(\d{1,2})\s*[-–:]\s*(\d{1,2})').firstMatch(scoreText);
    if (sm != null) {
      h = int.tryParse(sm.group(1)!);
      a = int.tryParse(sm.group(2)!);
      if (h != null && a != null && (h > 20 || a > 20)) {
        h = null;
        a = null;
      }
    }
    final conf = (line('CONFIDENCE') ?? '').toLowerCase();
    final level = conf.contains('high')
        ? 'High'
        : conf.contains('med')
        ? 'Medium'
        : conf.contains('low')
        ? 'Low'
        : '';
    return _AiResult(
      raw: raw,
      lean: lean,
      home: h,
      away: a,
      confidence: level,
      why: _bullets(block('WHY', ['RISKS', 'UNCERTAINTIES', 'CONFIDENCE'])),
      risks: _bullets(block('RISKS', ['WHY', 'CONFIDENCE'])),
    );
  }

  /// 0 = home, 1 = draw, 2 = away, -1 = no clear lean.
  int side(Fixture f) {
    final l = lean.toLowerCase();
    if (l.isEmpty ||
        l.contains('insufficient') ||
        l.contains('too close') ||
        l.contains('no clear')) {
      return -1;
    }
    if (l.contains('draw')) return 1;
    final hit = l.contains(f.home.toLowerCase());
    final ait = l.contains(f.away.toLowerCase());
    if (hit && !ait) return 0;
    if (ait && !hit) return 2;
    if (l.contains('home')) return 0;
    if (l.contains('away')) return 2;
    return -1;
  }
}

class AiPredictScreen extends StatefulWidget {
  final bool active;
  const AiPredictScreen({super.key, required this.active});
  @override
  State<AiPredictScreen> createState() => _AiPredictScreenState();
}

class _AiPredictScreenState extends State<AiPredictScreen> {
  final _stats = TextEditingController();
  final _notes = TextEditingController();
  final _scroll = ScrollController();
  final _resultKey = GlobalKey();
  List<Fixture> _fixtures = [];
  String? _selected, _error;
  _AiResult? _result;
  Fixture? _resultFixture;
  bool _loading = false, _busy = false, _manual = false, _loadedOnce = false;

  // Last five results per team: 0 = not set, 1 = W, 2 = D, 3 = L.
  final List<int> _homeForm = List<int>.filled(5, 0);
  final List<int> _awayForm = List<int>.filled(5, 0);
  int? _homeFor, _homeAgainst, _awayFor, _awayAgainst;

  static const _thinking = [
    'Reading the form guide…',
    'Weighing goals for and against…',
    'Checking absences and news…',
    'Drafting the verdict…',
  ];
  int _thinkingIndex = 0;
  Timer? _thinkingTimer;

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
    if (widget.active) _load();
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_sync);
    _thinkingTimer?.cancel();
    _stats.dispose();
    _notes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Fixture? get _fixture => _fixtures
      .where((f) => FanZoneService.matchKey(f) == _selected)
      .firstOrNull;

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final fixtures = await FeedService().loadFixtures(remote: true);
      if (!mounted) return;
      setState(() {
        _error = null;
        _fixtures = <String, Fixture>{
          for (final fixture in sortFixtures(fixtures, DateTime.now()))
            if (fixture.kickoff.isAfter(DateTime.now()))
              FanZoneService.matchKey(fixture): fixture,
        }.values.toList();
        if (!_fixtures.any((f) => FanZoneService.matchKey(f) == _selected)) {
          _selected = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load matches. Pull down to retry.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _select(Fixture f) {
    if (_busy) return;
    setState(() {
      _selected = FanZoneService.matchKey(f);
      _result = null;
      _error = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Turning the form builder into the text the AI receives
  // ---------------------------------------------------------------------------

  String _teamLine(
    String team,
    String side,
    List<int> form,
    int? scored,
    int? conceded,
  ) {
    const letters = ['', 'W', 'D', 'L'];
    final results = [
      for (final v in form)
        if (v != 0) letters[v],
    ];
    final bits = <String>[];
    if (results.isNotEmpty) {
      bits.add(
        'last ${results.length} results (most recent first): ${results.join(' ')}',
      );
    }
    if (scored != null) bits.add('goals scored in those games: $scored');
    if (conceded != null) bits.add('goals conceded: $conceded');
    if (bits.isEmpty) return '';
    return '$team ($side): ${bits.join('; ')}.';
  }

  String _composeStats(Fixture f) {
    if (_manual) return _stats.text.trim();
    final parts = <String>[
      _teamLine(f.home, 'home', _homeForm, _homeFor, _homeAgainst),
      _teamLine(f.away, 'away', _awayForm, _awayFor, _awayAgainst),
    ].where((p) => p.isNotEmpty).toList();
    final notes = _notes.text.trim();
    if (notes.isNotEmpty) parts.add('Notes from the user: $notes');
    return parts.join(' ');
  }

  void _startThinking() {
    _thinkingIndex = 0;
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _thinkingIndex = (_thinkingIndex + 1) % _thinking.length);
    });
  }

  Future<void> _analyse() async {
    if (_busy) return;
    final fixture = _fixture;
    final text = fixture == null ? '' : _composeStats(fixture);
    if (fixture == null || text.length < 20) {
      setState(
        () => _error = _manual
            ? 'Choose a match and paste at least 20 characters of stats.'
            : 'Choose a match and add some recent form or notes first.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    _startThinking();
    FocusScope.of(context).unfocus();
    try {
      final data = await FanZoneService.call(
        'ai-predict',
        body: {'key': FanZoneService.matchKey(fixture), 'stats': text},
        timeout: const Duration(seconds: 60),
      );
      if (!mounted) return;
      setState(() {
        _result = _AiResult.parse(data['analysis'] as String);
        _resultFixture = fixture;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _resultKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _thinkingTimer?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  Future<void> _share(_AiResult r, Fixture f) async {
    try {
      await Share.share(
        'Deeprowss AI Predict\n${f.title}\n\n${r.raw}\n\n'
        'Based on user-supplied stats. No guaranteed outcomes.',
      );
    } catch (_) {
      _toast('Could not open sharing.');
    }
  }

  Future<void> _usePick(Fixture f, int home, int away) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use as your Fan Zone pick?'),
        content: Text(
          '${f.home} $home – $away ${f.away}\n\nThis saves it as your prediction. You can still change it in Fan Zone until kickoff.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lock it in'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await FanZoneService.call(
        'pick',
        body: {'key': FanZoneService.matchKey(f), 'home': home, 'away': away},
      );
      _toast('Prediction locked in: $home – $away. Good luck!');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _hero() => FanHero(
    color: _aiViolet,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_aiViolet, Color(0xFF00B0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _aiViolet.withValues(alpha: .5),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'AI Match Analyst',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Pick a match, add the recent form you know, and get a reasoned lean with the risks spelled out.',
          style: TextStyle(color: Ui.muted, height: 1.45, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FanPill(
              text: 'Uses your stats only',
              color: _aiViolet,
              icon: Icons.edit_note_rounded,
            ),
            FanPill(
              text: 'No guaranteed results',
              color: Color(0xFFFFB300),
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stepTitle(int n, String text, {String? hint}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _aiViolet,
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        if (hint != null)
          Text(hint, style: TextStyle(fontSize: 12, color: Ui.dim)),
      ],
    ),
  );

  Widget _matchCard(Fixture f) {
    final on = FanZoneService.matchKey(f) == _selected;
    final now = DateTime.now();
    return GestureDetector(
      onTap: () => _select(f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 188,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: on ? _aiViolet.withValues(alpha: .16) : Ui.card,
          border: Border.all(
            color: on ? _aiViolet : Ui.line,
            width: on ? 1.8 : 1,
          ),
          boxShadow: on
              ? [BoxShadow(color: _aiViolet.withValues(alpha: .3), blurRadius: 16)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    f.league.isEmpty ? 'Football' : f.league,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Ui.muted,
                    ),
                  ),
                ),
                if (on)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: _aiViolet,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TeamCrest(logo: f.homeLogo, size: 38),
                const SizedBox(width: 6),
                Text(
                  'vs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Ui.dim,
                  ),
                ),
                const SizedBox(width: 6),
                TeamCrest(logo: f.awayLogo, size: 38),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              f.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              '${fanDayLabel(f.kickoff, now)} • ${fanClock(f.kickoff)}',
              style: TextStyle(fontSize: 11, color: Ui.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matches() {
    if (_loading && _fixtures.isEmpty) {
      return const FanSkeleton(height: 158);
    }
    if (_loadedOnce && _fixtures.isEmpty) {
      return const FanEmpty(
        icon: Icons.event_busy_rounded,
        title: 'No upcoming fixtures yet',
        message: 'New matches appear here when they are scheduled. Pull down to refresh.',
      );
    }
    return SizedBox(
      height: 158,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [for (final f in _fixtures) _matchCard(f)],
      ),
    );
  }

  Widget _formDot(List<int> form, int i) {
    const letters = ['', 'W', 'D', 'L'];
    final colors = [Ui.dim, Ui.green, const Color(0xFFFFB300), fanAlert];
    final v = form[i];
    final c = colors[v];
    return GestureDetector(
      onTap: _busy
          ? null
          : () => setState(() {
              form[i] = (form[i] + 1) % 4;
              _result = null;
            }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: v == 0 ? Colors.white.withValues(alpha: .05) : c.withValues(alpha: .22),
          border: Border.all(
            color: v == 0 ? Ui.line : c,
            width: v == 0 ? 1 : 2,
          ),
        ),
        child: v == 0
            ? Icon(Icons.add_rounded, size: 16, color: Ui.dim)
            : Text(
                letters[v],
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: c,
                ),
              ),
      ),
    );
  }

  Widget _goalStepper(
    String label,
    int? value,
    void Function(int?) set,
  ) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _busy || value == null
                ? null
                : () => setState(() {
                    set(value <= 0 ? null : value - 1);
                    _result = null;
                  }),
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  value == null ? '–' : '$value',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 10, color: Ui.muted)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _busy || (value ?? -1) >= 30
                ? null
                : () => setState(() {
                    set((value ?? -1) + 1);
                    _result = null;
                  }),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    ),
  );

  Widget _teamForm(
    String team,
    String logo,
    String side,
    List<int> form,
    int? scored,
    int? conceded,
    void Function(int?) setScored,
    void Function(int?) setConceded,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: fanBox(radius: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TeamCrest(logo: logo, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                team,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            FanPill(text: side, color: _aiViolet),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (var i = 0; i < 5; i++) _formDot(form, i)],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('Latest', style: TextStyle(fontSize: 10, color: Ui.dim)),
            const Spacer(),
            Text('Tap a circle: W, D or L', style: TextStyle(fontSize: 10, color: Ui.dim)),
            const Spacer(),
            Text('Oldest', style: TextStyle(fontSize: 10, color: Ui.dim)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _goalStepper('Goals scored', scored, setScored),
            const SizedBox(width: 8),
            _goalStepper('Goals conceded', conceded, setConceded),
          ],
        ),
      ],
    ),
  );

  Widget _formBuilder(Fixture f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _teamForm(
        f.home,
        f.homeLogo,
        'HOME',
        _homeForm,
        _homeFor,
        _homeAgainst,
        (v) => _homeFor = v,
        (v) => _homeAgainst = v,
      ),
      _teamForm(
        f.away,
        f.awayLogo,
        'AWAY',
        _awayForm,
        _awayFor,
        _awayAgainst,
        (v) => _awayFor = v,
        (v) => _awayAgainst = v,
      ),
      TextField(
        controller: _notes,
        enabled: !_busy,
        minLines: 2,
        maxLines: 5,
        maxLength: 600,
        onChanged: (_) {
          if (_result != null) setState(() => _result = null);
        },
        decoration: InputDecoration(
          labelText: 'Absences, news or context (optional)',
          alignLabelWithHint: true,
          hintText: 'Key injuries, suspensions, travel, derby, weather… add the source and date.',
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 28),
            child: Icon(Icons.healing_rounded),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ],
  );

  Widget _manualBuilder() => TextField(
    controller: _stats,
    enabled: !_busy,
    minLines: 5,
    maxLines: 10,
    maxLength: 2500,
    onChanged: (_) {
      if (_result != null) setState(() => _result = null);
    },
    decoration: InputDecoration(
      labelText: 'Recent stats and context',
      alignLabelWithHint: true,
      hintText: 'Add each team’s last five results, goals scored/conceded, home/away form and known absences. Include the source and date.',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  Widget _analyseButton() => Container(
    height: 56,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        colors: _selected == null || _busy
            ? [Ui.card, Ui.card]
            : const [_aiViolet, Color(0xFF00B0FF)],
      ),
      border: Border.all(color: _selected == null ? Ui.line : Colors.transparent),
      boxShadow: _selected == null || _busy
          ? null
          : [BoxShadow(color: _aiViolet.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _busy || _selected == null ? null : _analyse,
        child: Center(
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _thinking[_thinkingIndex],
                        key: ValueKey<int>(_thinkingIndex),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: _selected == null ? Ui.dim : Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _selected == null ? 'Choose a match first' : 'Analyse match',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: _selected == null ? Ui.dim : Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );

  // ----- verdict ---------------------------------------------------------------

  Widget _leanMeter(Fixture f, int side) {
    Widget seg(String label, int index, Alignment align) {
      final on = side == index;
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(index == 0 ? 16 : 6),
              right: Radius.circular(index == 2 ? 16 : 6),
            ),
            color: on ? _aiViolet.withValues(alpha: .85) : Colors.white.withValues(alpha: .06),
            border: Border.all(color: on ? Colors.white54 : Ui.line),
            boxShadow: on
                ? [BoxShadow(color: _aiViolet.withValues(alpha: .5), blurRadius: 16)]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                index == 1 ? Icons.handshake_rounded : Icons.emoji_events_rounded,
                size: 18,
                color: on ? Colors.white : Ui.dim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                  color: on ? Colors.white : Ui.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(f.home, 0, Alignment.centerLeft),
        seg('Draw', 1, Alignment.center),
        seg(f.away, 2, Alignment.centerRight),
      ],
    );
  }

  Widget _confidence(String level) {
    final n = switch (level) {
      'High' => 3,
      'Medium' => 2,
      'Low' => 1,
      _ => 0,
    };
    if (n == 0) return const SizedBox.shrink();
    final c = n == 3 ? Ui.green : n == 2 ? const Color(0xFFFFB300) : fanOrange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIDENCE',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
            color: Ui.muted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 3; i++)
              Container(
                width: 22,
                height: 8,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: i <= n ? c : Colors.white12,
                ),
              ),
            const SizedBox(width: 6),
            Text(
              level,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pointList(String title, IconData icon, Color color, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: fanBox(radius: 20, border: color.withValues(alpha: .3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(item, style: const TextStyle(height: 1.45)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _verdict(_AiResult r, Fixture f) {
    final side = r.side(f);
    final hasScore = r.home != null && r.away != null;
    return Column(
      key: _resultKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FanHero(
          color: _aiViolet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: _aiViolet),
                  const SizedBox(width: 6),
                  Text(
                    'AI VERDICT',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w900,
                      color: Ui.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TeamCrest(logo: f.homeLogo, size: 54),
                        const SizedBox(height: 6),
                        Text(
                          f.home,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: hasScore
                        ? Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .35),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _aiViolet.withValues(alpha: .6)),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${r.home} – ${r.away}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'POSSIBLE SCORE',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: Ui.muted,
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Text(
                              'VS',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Ui.dim,
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TeamCrest(logo: f.awayLogo, size: 54),
                        const SizedBox(height: 6),
                        Text(
                          f.away,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (r.structured) ...[
                const SizedBox(height: 16),
                _leanMeter(f, side),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LEAN',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w800,
                              color: Ui.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.lean.isEmpty ? 'No clear lean' : r.lean,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _confidence(r.confidence),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (r.structured) ...[
          _pointList('Why it leans this way', Icons.check_circle_rounded, Ui.green, r.why),
          _pointList('What could go wrong', Icons.warning_amber_rounded, const Color(0xFFFFB300), r.risks),
        ] else
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(18),
            decoration: fanBox(radius: 20),
            child: SelectableText(r.raw, style: const TextStyle(height: 1.6)),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Ui.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Built only from the stats you supplied. Live stats are not connected. AI can be wrong; no outcome is guaranteed.',
                  style: TextStyle(fontSize: 11.5, color: Ui.muted, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _share(r, f),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share'),
              ),
            ),
            if (hasScore) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _usePick(f, r.home!, r.away!),
                  icon: const Icon(Icons.sports_score_rounded, size: 18),
                  label: const Text('Use as my pick'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixture = _fixture;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 62,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'AI Predict',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              'Form in, verdict out',
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
            tooltip: 'Player',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ContentShortcutScreen(
                  title: 'Player',
                  child: PlayerHubScreen(active: true),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh matches',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _hero(),
            _stepTitle(1, 'Choose a match', hint: _fixtures.isEmpty ? null : '${_fixtures.length} upcoming'),
            _matches(),
            if (fixture != null) ...[
              _stepTitle(2, 'Add the form'),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    FanChip(
                      label: 'Quick form',
                      icon: Icons.tune_rounded,
                      color: _aiViolet,
                      selected: !_manual,
                      onTap: _busy ? null : () => setState(() => _manual = false),
                    ),
                    FanChip(
                      label: 'Paste my own stats',
                      icon: Icons.content_paste_rounded,
                      color: _aiViolet,
                      selected: _manual,
                      onTap: _busy ? null : () => setState(() => _manual = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_manual) _manualBuilder() else _formBuilder(fixture),
              _stepTitle(3, 'Get the verdict'),
            ],
            _analyseButton(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: fanBox(
                  radius: 14,
                  color: Theme.of(context).colorScheme.error.withValues(alpha: .12),
                  border: Theme.of(context).colorScheme.error.withValues(alpha: .4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            if (_result != null && _resultFixture != null) ...[
              const SizedBox(height: 24),
              _verdict(_result!, _resultFixture!),
            ],
          ],
        ),
      ),
    );
  }
}
