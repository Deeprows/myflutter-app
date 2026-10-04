import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/fixture.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/fixture_card.dart';
import '../widgets/link_sheet.dart';
import '../widgets/pitch_painter.dart';
import 'player_screen.dart';

enum _Filter { all, live, upcoming, ended }

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<Fixture> _fixtures = const [];
  bool _loading = true;
  _Filter _filter = _Filter.all;

  final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  Timer? _timer;
  String _sig = '';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      _now.value = n;
      final s = _signature(n);
      if (s != _sig && mounted) setState(() => _sig = s);
    });
    _load().then((_) {
      if (AppConfig.fixturesUrl.isNotEmpty) _load(remote: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _now.dispose();
    super.dispose();
  }

  String _signature(DateTime n) =>
      _fixtures.map((f) => f.phaseAt(n).index).join();

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadFixtures(remote: remote);
    if (!mounted) return;
    setState(() {
      _fixtures = list;
      _loading = false;
      _sig = _signature(DateTime.now());
    });
  }

  void _open(Fixture f) {
    if (!f.hasStream) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stream for this match yet')),
      );
      return;
    }
    final now = DateTime.now();
    final phase = f.phaseAt(now);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: f.title,
        subtitle:
            '${longDate(f.kickoff.toLocal())} · ${fmtTime(f.kickoff.toLocal())}'
            '${f.league.isEmpty ? '' : ' · ${f.league}'}',
        url: f.url,
        altUrl: f.hasAlt ? f.altUrl : null,
        isLive: phase == MatchPhase.live,
      ),
    ));
  }

  bool _passes(Fixture f, DateTime now) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.live:
        return f.phaseAt(now) == MatchPhase.live;
      case _Filter.upcoming:
        return f.phaseAt(now) == MatchPhase.upcoming;
      case _Filter.ended:
        return f.phaseAt(now) == MatchPhase.ended;
    }
  }

  List<Widget> _items(DateTime now) {
    final sorted = sortFixtures(_fixtures, now).where((f) => _passes(f, now));
    final out = <Widget>[];
    String? last;
    for (final f in sorted) {
      final phase = f.phaseAt(now);
      final day = dayLabel(f.kickoff.toLocal(), now);
      final key = phase == MatchPhase.live
          ? 'LIVE NOW'
          : phase == MatchPhase.upcoming
              ? 'UPCOMING · $day'
              : 'FINISHED · $day';
      if (key != last) {
        out.add(_SectionLabel(text: key, live: phase == MatchPhase.live));
        last = key;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ValueListenableBuilder<DateTime>(
          valueListenable: _now,
          builder: (_, n, __) =>
              FixtureCard(fixture: f, now: n, onTap: () => _open(f)),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final live = _fixtures.where((f) => f.phaseAt(now) == MatchPhase.live).length;
    final upcoming =
        _fixtures.where((f) => f.phaseAt(now) == MatchPhase.upcoming).length;
    final ended = _fixtures.length - live - upcoming;
    final items = _items(now);

    return RefreshIndicator(
      color: Ui.red,
      backgroundColor: Ui.panel,
      onRefresh: () => _load(remote: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              live: live,
              upcoming: upcoming,
              onLink: () => showLinkSheet(context),
              onRefresh: () async {
                await _load(remote: true);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Fixtures updated')));
              },
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  _FilterChip('All', _fixtures.length, _filter == _Filter.all,
                      () => setState(() => _filter = _Filter.all)),
                  _FilterChip('Live', live, _filter == _Filter.live,
                      () => setState(() => _filter = _Filter.live),
                      accent: true),
                  _FilterChip('Upcoming', upcoming,
                      _filter == _Filter.upcoming,
                      () => setState(() => _filter = _Filter.upcoming)),
                  _FilterChip('Ended', ended, _filter == _Filter.ended,
                      () => setState(() => _filter = _Filter.ended)),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: Ui.red)),
            )
          else if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(
                icon: Icons.sports_soccer_rounded,
                text: 'No matches here right now',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList(delegate: SliverChildListDelegate(items)),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int live;
  final int upcoming;
  final VoidCallback onLink;
  final VoidCallback onRefresh;
  const _Header({
    required this.live,
    required this.upcoming,
    required this.onLink,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final today = longDate(DateTime.now());
    final summary = live > 0
        ? '$live live now · $upcoming coming up'
        : upcoming > 0
            ? '$upcoming match${upcoming == 1 ? '' : 'es'} coming up'
            : 'No matches scheduled';

    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ui.red.withValues(alpha: .20), Ui.bg],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: 1,
              child: CustomPaint(painter: PitchPainter()),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Menu',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Ui.red,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Ui.red.withValues(alpha: .45),
                            blurRadius: 16)
                      ],
                    ),
                    child: const Icon(Icons.sports_soccer_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'FOOTBOLIVE',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play a link',
                    onPressed: onLink,
                    icon: const Icon(Icons.add_link_rounded),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Football Live',
                  style: TextStyle(
                      fontSize: 26,
                      height: 1.1,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(today,
                  style: const TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(summary,
                  style: const TextStyle(
                      color: Ui.redSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool live;
  const _SectionLabel({required this.text, required this.live});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: live ? Ui.red : Ui.dim,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: live ? Colors.white : Ui.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;
  const _FilterChip(this.label, this.count, this.selected, this.onTap,
      {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? Ui.red.withValues(alpha: .16) : Ui.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected || (accent && count > 0)
                      ? Ui.red
                      : Ui.line,
                  width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 18),
                  const SizedBox(width: 4),
                ],
                Text('$label ($count)',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : Ui.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 44, color: Ui.dim),
        const SizedBox(height: 10),
        Text(text,
            style: const TextStyle(
                color: Ui.muted, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
