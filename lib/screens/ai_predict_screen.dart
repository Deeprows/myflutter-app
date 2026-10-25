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
  final _stats = TextEditingController();
  List<Fixture> _fixtures = [];
  String? _selected, _error, _analysis, _resultTitle;
  bool _loading = false, _busy = false;

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
    _stats.dispose();
    super.dispose();
  }

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
      if (mounted)
        setState(() => _error = 'Could not load matches. Pull down to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _analyse() async {
    if (_busy) return;
    final fixture = _fixtures
        .where((f) => FanZoneService.matchKey(f) == _selected)
        .firstOrNull;
    if (fixture == null || _stats.text.trim().length < 20) {
      setState(
        () => _error = 'Choose a match and add recent team stats (at least 20 characters).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _analysis = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final data = await FanZoneService.call(
        'ai-predict',
        body: {
          'key': FanZoneService.matchKey(fixture),
          'stats': _stats.text.trim(),
        },
        timeout: const Duration(seconds: 60),
      );
      if (mounted)
        setState(() {
          _analysis = data['analysis'] as String;
          _resultTitle = fixture.title;
        });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: fanBox(
              radius: 20,
              color: Ui.red.withValues(alpha: .12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Ui.red, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Read the match',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a fixture and add recent form, goals or injury news. AI will weigh the information and explain a possible outcome.',
                  style: TextStyle(color: Ui.muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Upcoming match',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No upcoming fixtures yet. Refresh when new matches are added.',
              ),
            ),
          DropdownButtonFormField<String>(
            key: ValueKey(_selected),
            initialValue: _selected,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Select a match',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in _fixtures)
                DropdownMenuItem(
                  value: FanZoneService.matchKey(f),
                  child: Text(
                    f.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _selected = value;
                    _analysis = null;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stats,
            enabled: !_busy,
            minLines: 5,
            maxLines: 10,
            maxLength: 2500,
            onChanged: (_) {
              if (_analysis != null) setState(() => _analysis = null);
            },
            decoration: const InputDecoration(
              labelText: 'Recent stats and context',
              alignLabelWithHint: true,
              hintText: 'Add each team’s last five results, goals scored/conceded, home/away form and known absences. Include the source and date.',
              border: OutlineInputBorder(),
            ),
          ),
          Text(
            'Uses the details you provide. Live stats are not connected. AI can be wrong; no outcome is guaranteed.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _selected == null ? null : _analyse,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_busy ? 'Analysing match…' : 'Analyse match'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_analysis != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: fanBox(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _resultTitle ?? '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _analysis!,
                    style: const TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await Share.share(
                          'Deeprowss AI Predict\n$_resultTitle\n\n$_analysis\n\nBased on user-supplied stats. No guaranteed outcomes.',
                        );
                      } catch (_) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open sharing.'),
                            ),
                          );
                      }
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share analysis'),
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
