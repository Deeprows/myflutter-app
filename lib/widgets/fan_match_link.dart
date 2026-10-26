import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/fixture.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../services/support_gate.dart';
import '../screens/player_screen.dart';
import '../screens/fan_widgets.dart';
import 'match_chat.dart';

class FanMatchLink extends StatelessWidget {
  final String snapshot, text;
  const FanMatchLink({super.key, required this.snapshot, required this.text});
  Fixture? get fixture {
    try {
      return Fixture.tryParse(jsonDecode(snapshot));
    } catch (_) {
      return null;
    }
  }

  String? get legacyTitle {
    final m = RegExp(r'^⚽ (.+ vs .+)$', multiLine: true).firstMatch(text);
    return m?.group(1)?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final f = fixture, title = f?.title ?? legacyTitle;
    if (title == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ActionChip(
        avatar: const Icon(Icons.sports_soccer, size: 18),
        label: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _TaggedMatch(snapshot: f, title: title),
          ),
        ),
      ),
    );
  }
}

class _TaggedMatch extends StatefulWidget {
  final Fixture? snapshot;
  final String title;
  const _TaggedMatch({required this.snapshot, required this.title});
  @override
  State<_TaggedMatch> createState() => _TaggedMatchState();
}

class _TaggedMatchState extends State<_TaggedMatch> {
  Fixture? _current;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await FeedService().loadFixtures(remote: true);
      // Match key includes kickoff; titles alone are used only for older text tags.
      final f = all
          .where(
            (f) => widget.snapshot != null
                ? FanZoneService.matchKey(f) ==
                      FanZoneService.matchKey(widget.snapshot!)
                : f.title == widget.title,
          )
          .firstOrNull;
      if (mounted) setState(() => _current = f);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not refresh this match. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _watch(Fixture f) {
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

  @override
  Widget build(BuildContext context) {
    final f = _current ?? widget.snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (f != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TeamCrest(logo: f.homeLogo, size: 60),
                      const Text('VS'),
                      TeamCrest(logo: f.awayLogo, size: 60),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (f != null) Text('${f.league} • ${f.kickoff.toLocal()}'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: !_loading && _current?.hasStream == true
                      ? () => _watch(_current!)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Watch match'),
                ),
                if (!_loading && _current?.hasStream != true)
                  Text(
                    _error ??
                        'The stream is not currently available. You can still discuss the match.',
                  ),
              ],
            ),
          ),
          Expanded(child: MatchChat(matchName: widget.title)),
        ],
      ),
    );
  }
}
