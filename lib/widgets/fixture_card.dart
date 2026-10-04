import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Fixture card in the Footbolive style: status pill, both teams with flags,
/// kick-off time and a live countdown. Border/glow colour follows the phase.
class FixtureCard extends StatelessWidget {
  final Fixture fixture;
  final DateTime now;
  final VoidCallback onTap;

  const FixtureCard({
    super.key,
    required this.fixture,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final phase = f.phaseAt(now);
    final live = phase == MatchPhase.live;
    final ended = phase == MatchPhase.ended;
    final kickoff = f.kickoff.toLocal();

    final BoxDecoration deco = BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: live
            ? Ui.red.withValues(alpha: .65)
            : ended
                ? Colors.white.withValues(alpha: .07)
                : Ui.red.withValues(alpha: .28),
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: live
            ? [Ui.red.withValues(alpha: .15), Ui.cardDeep]
            : ended
                ? [const Color(0x08FFFFFF), const Color(0x03FFFFFF)]
                : [Ui.card, Ui.cardDeep],
      ),
      boxShadow: live
          ? [
              BoxShadow(
                color: Ui.red.withValues(alpha: .18),
                blurRadius: 14,
                spreadRadius: 1,
              )
            ]
          : null,
    );

    final String clock;
    final String statusText;
    switch (phase) {
      case MatchPhase.upcoming:
        clock = _hms(f.kickoff.difference(now));
        statusText = 'Upcoming';
      case MatchPhase.live:
        clock = _hms(now.difference(f.kickoff));
        statusText = 'Live';
      case MatchPhase.ended:
        clock = fmtTime(kickoff);
        statusText = 'Ended';
    }
    final statusColor = live
        ? Ui.red
        : ended
            ? Ui.dim
            : Ui.redSoft;

    return Opacity(
      opacity: ended ? .7 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: deco,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Ui.radius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.league.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        f.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _Team(
                            flag: f.homeFlag, name: f.home, muted: ended),
                      ),
                      SizedBox(
                        width: 70,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              live
                                  ? Icons.sensors_rounded
                                  : Icons.circle,
                              size: live ? 16 : 6,
                              color: statusColor,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Team(
                            flag: f.awayFlag, name: f.away, muted: ended),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        clock,
                        style: TextStyle(
                          color: ended ? Ui.dim : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (!f.hasStream) ...[
                        const SizedBox(width: 8),
                        Text('· Stream soon',
                            style: TextStyle(
                                color: Ui.dim,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
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

String _hms(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

class _Team extends StatelessWidget {
  final String flag;
  final String name;
  final bool muted;
  const _Team({required this.flag, required this.name, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .05),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Text(
            flag.isEmpty ? '⚽' : flag,
            style: const TextStyle(fontSize: 22, height: 1.1),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          name,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted ? const Color(0xFF858B95) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
