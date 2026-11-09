import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';
import 'fan_widgets.dart';

/// "Match Room" tab: every live match chat as a card, plus the all-day fan
/// lounge. Cards use the same look as the "Live match rooms" sheet.
class MatchRoomsView extends StatelessWidget {
  final List<Fixture> fixtures;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenLounge;
  final void Function(Fixture) onOpenMatch;

  /// Lets the owner remember and restore the scroll position.
  final ScrollController? controller;

  const MatchRoomsView({
    super.key,
    this.controller,
    required this.fixtures,
    required this.loading,
    required this.onRefresh,
    required this.onOpenLounge,
    required this.onOpenMatch,
  });

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    mainAxisExtent: 158,
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final live = <Fixture>[];
    final upcoming = <Fixture>[];
    final ended = <Fixture>[];
    for (final f in fixtures) {
      switch (f.phaseAt(now)) {
        case MatchPhase.live:
          live.add(f);
        case MatchPhase.upcoming:
          upcoming.add(f);
        case MatchPhase.ended:
          ended.add(f);
      }
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(child: _header(live.length)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        sliver: SliverToBoxAdapter(
          child: SizedBox(
            height: 124,
            child: _RoomCard(
              lead: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fanOrange.withValues(alpha: .2),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: fanOrange,
                  size: 22,
                ),
              ),
              title: 'Fan lounge'.tr,
              subtitle: 'Open to every fan, all day'.tr,
              color: fanOrange,
              status: const FanPill(text: 'OPEN', color: fanOrange),
              onTap: onOpenLounge,
            ),
          ),
        ),
      ),
    ];

    void section(String title, List<Fixture> list, {Widget? dot}) {
      if (list.isEmpty) return;
      slivers.add(SliverToBoxAdapter(child: _sectionTitle(title.tr, list.length, dot)));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: _grid,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final f = list[i];
                return _RoomCard(
                  lead: _crests(f),
                  title: f.title,
                  subtitle: f.league.isEmpty ? 'Match chat'.tr : f.league,
                  color: Ui.redSoft,
                  status: _status(f, now),
                  onTap: () => onOpenMatch(f),
                );
              },
              childCount: list.length,
            ),
          ),
        ),
      );
    }

    section('Live now', live, dot: const FanLiveDot());
    section('Starting soon', upcoming.take(30).toList());
    section('Finished', ended.take(12).toList());

    if (fixtures.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Icon(Icons.groups_rounded, size: 40, color: Ui.dim),
                      const SizedBox(height: 10),
                      Text(
                        'No match rooms yet. They open when fixtures are posted.'
                            .tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Ui.muted, height: 1.4),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 28)));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  Widget _header(int liveCount) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Ui.red.withValues(alpha: .16),
          ),
          child: Icon(Icons.groups_rounded, color: Ui.red, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live match rooms'.tr,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Pick a match and chat with fans'.tr,
                style: TextStyle(fontSize: 12.5, color: Ui.muted),
              ),
            ],
          ),
        ),
        if (liveCount > 0)
          FanPill(text: '$liveCount LIVE', color: fanAlert),
      ],
    ),
  );

  Widget _sectionTitle(String title, int count, Widget? dot) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
    child: Row(
      children: [
        if (dot != null) ...[dot, const SizedBox(width: 8)],
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Ui.muted,
          ),
        ),
      ],
    ),
  );

  static Widget _crests(Fixture f) => SizedBox(
    width: 62,
    height: 32,
    child: Stack(
      children: [
        TeamCrest(logo: f.homeLogo, size: 32),
        Positioned(left: 26, child: TeamCrest(logo: f.awayLogo, size: 32)),
      ],
    ),
  );

  static Widget _status(Fixture f, DateTime now) {
    final phase = f.phaseAt(now);
    if (phase == MatchPhase.live) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FanLiveDot(),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: fanAlert,
            ),
          ),
        ],
      );
    }
    if (phase == MatchPhase.upcoming) {
      return FanPill(
        text: fanDayLabel(f.kickoff, now) == 'Today'
            ? fanClock(f.kickoff)
            : fanDayLabel(f.kickoff, now),
        color: Ui.muted,
        icon: Icons.schedule_rounded,
      );
    }
    return FanPill(text: 'FT', color: Ui.dim);
  }
}

class _RoomCard extends StatelessWidget {
  final Widget lead, status;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoomCard({
    required this.lead,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: .4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: .26), Ui.card],
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    lead,
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: status,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Ui.muted),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.forum_rounded, size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(
                      'Join chat'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
