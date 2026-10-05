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
            '${longDate(f.kickoff.toLocal())} · ${fmtTime(f.kickoff.toLocal())} '
            '${tzShort(f.kickoff.toLocal())}'
            '${f.league.isEmpty ? '' : ' · ${f.league}'}',
        url: f.url,
        altUrl: f.hasAlt ? f.altUrl : null,
        isLive: phase == MatchPhase.live,
        chatMatch: f.title,
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
          builder: (_, n, _) =>
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
                if (!context.mounted) return;
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
            SliverFillRemaining(
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
    final now = DateTime.now();
    final today = longDate(now);
    final zone = '${tzShort(now)} · ${gmtOffset(now)}';

    Widget round(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Material(
            color: Colors.white.withValues(alpha: .07),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tip,
              onPressed: onTap,
              icon: Icon(icon, size: 22),
            ),
          ),
        );

    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ui.red.withValues(alpha: .24), Ui.bg],
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
                  Builder(
                    builder: (ctx) =>
                        round(Icons.menu_rounded, 'Menu', () => Scaffold.of(ctx).openDrawer()),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'DEEPROWSS',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  round(Icons.add_link_rounded, 'Play a link', onLink),
                  round(Icons.refresh_rounded, 'Refresh', onRefresh),
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Ui.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Live Events',
                        style: TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 13, color: Ui.muted),
                        const SizedBox(width: 6),
                        Text(today,
                            style: TextStyle(
                                color: Ui.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Ui.line),
                      ),
                      child: Text('Times in $zone',
                          style: TextStyle(
                              color: Ui.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      icon: Icons.sensors_rounded,
                      label: 'Live now',
                      value: live,
                      accent: live > 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      icon: Icons.schedule_rounded,
                      label: 'Coming up',
                      value: upcoming,
                      accent: false,
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
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final bool accent;
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent ? Ui.red.withValues(alpha: .16) : Ui.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: accent ? Ui.red.withValues(alpha: .7) : Ui.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: accent ? Ui.redSoft : Ui.muted),
          const SizedBox(width: 10),
          Text('$value',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Ui.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
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
            style: TextStyle(
                color: Ui.muted, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
