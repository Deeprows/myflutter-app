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

class AiPredictScreen extends StatefulWidget {
  final bool active;
  const AiPredictScreen({super.key, required this.active});
  @override
  State<AiPredictScreen> createState() => _AiPredictScreenState();
}

class _AiPredictScreenState extends State<AiPredictScreen> {
  List<Fixture> _fixtures = [];
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
    super.dispose();
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
        _selected.retainAll(_fixtures.map(FanZoneService.matchKey));
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load matches. Pull down to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _analyse() async {
    if (_busy || _selected.isEmpty) return;
    final queue = _fixtures
        .where((f) => _selected.contains(FanZoneService.matchKey(f)))
        .toList();
    setState(() {
      _busy = true;
      _done = 0;
      _total = queue.length;
    });
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
          body: {'key': key},
          timeout: const Duration(seconds: 120),
        );
        if (!mounted) return;
        setState(() => _results[key] = data);
      } catch (e) {
        if (!mounted) return;
        var message = e.toString().replaceFirst('Exception: ', '');
        if (message.contains('setup needed:'))
          message =
              'Automatic analysis is being configured. Please contact the administrator.';
        setState(() => _failures[key] = message);
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

  Widget _form(String title, Map<String, dynamic> form) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      '${form['source'] ?? 'API-Football'} · ${form['wins']}W · ${form['draws']}D · ${form['losses']}L | ${form['goalsFor']} scored / ${form['goalsAgainst']} conceded',
    ),
    children: [
      for (final match in FanZoneService.rows(form['matches']))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: match['result'] == 'W'
                ? Ui.green.withValues(alpha: .2)
                : Ui.card,
            child: Text('${match['result']}'),
          ),
          title: Text(
            '${match['opponent']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${_date(match['date'])} · ${match['venue']}'),
          trailing: Text('${match['goalsFor']}–${match['goalsAgainst']}'),
        ),
    ],
  );
  Widget _result(Fixture f, Map<String, dynamic> data) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(18),
    decoration: fanBox(radius: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Recent results: ${data['dataSource'] ?? 'Verified match results'} · Analysis ${_date(data['generatedAt'])}',
          style: TextStyle(color: Ui.muted, fontSize: 12),
        ),
        _form(
          '${f.home} · last ${data['home']['played']}',
          Map<String, dynamic>.from(data['home'] as Map),
        ),
        _form(
          '${f.away} · last ${data['away']['played']}',
          Map<String, dynamic>.from(data['away'] as Map),
        ),
        const SizedBox(height: 12),
        SelectableText(
          '${data['analysis']}',
          style: const TextStyle(height: 1.6),
        ),
        const SizedBox(height: 10),
        Text(
          'Historical form is a limited sample, not a guaranteed outcome. Injuries, lineups and odds are not included.',
          style: TextStyle(color: Ui.muted, fontSize: 12),
        ),
        TextButton.icon(
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
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Share analysis'),
        ),
      ],
    ),
  );
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
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading || _busy ? null : _load,
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF713DDA), Color(0xFF007FAD)],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
                SizedBox(height: 10),
                Text(
                  'You choose. AI analyses.',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Select up to 3 matches. We fetch up to 5 recent completed results for each team and analyse form, goals and possible outcomes automatically.',
                  style: TextStyle(color: Colors.white, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_loading && _fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No upcoming matches yet. Pull down to refresh.'),
            ),
          for (final f in _fixtures)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(f.title),
              subtitle: Text(
                '${f.league} · ${fanClock(f.kickoff)} · ${_date(f.kickoff.toIso8601String())}',
              ),
              value: _selected.contains(FanZoneService.matchKey(f)),
              onChanged: _busy ? null : (v) => _select(f, v ?? false),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _selected.isEmpty ? null : _analyse,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _busy
                  ? 'Fetching results & analysing… $_done/$_total'
                  : 'Analyse ${_selected.length} selected match${_selected.length == 1 ? '' : 'es'}',
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          for (final f in _fixtures.where(
            (f) => _selected.contains(FanZoneService.matchKey(f)),
          )) ...[
            if (_failures.containsKey(FanZoneService.matchKey(f)))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '${f.title}: ${_failures[FanZoneService.matchKey(f)]}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_results.containsKey(FanZoneService.matchKey(f)))
              _result(f, _results[FanZoneService.matchKey(f)]!),
          ],
        ],
      ),
    ),
  );
}
