import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Slim fixture card: league tag on top, both teams on the sides, kick-off
/// time and date (in the viewer's own timezone) in the middle and the
/// countdown / live / ended line at the bottom.
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

    final String status;
    switch (phase) {
      case MatchPhase.upcoming:
        status = 'Starts in ${countdownText(f.kickoff.difference(now))}';
      case MatchPhase.live:
        status = 'Live · ${_ms(now.difference(f.kickoff))}';
      case MatchPhase.ended:
        status = 'Ended';
    }
    final statusColor = live
        ? Ui.red
        : ended
            ? Ui.dim
            : Colors.white;

    final BoxDecoration deco = BoxDecoration(
      color: Ui.cardDeep,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: live
            ? Ui.red.withValues(alpha: .8)
            : ended
                ? Colors.white.withValues(alpha: .10)
                : Ui.red.withValues(alpha: .40),
        width: live ? 1.4 : 1,
      ),
      boxShadow: live
          ? [
              BoxShadow(
                color: Ui.red.withValues(alpha: .18),
                blurRadius: 12,
                spreadRadius: 1,
              )
            ]
          : null,
    );

    return Opacity(
      opacity: ended ? .72 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: deco,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.league.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        f.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _Team(
                            flag: f.homeFlag,
                            name: f.home,
                            muted: ended,
                            alignEnd: false),
                      ),
                      SizedBox(
                        width: 104,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtTime12(kickoff),
                              style: TextStyle(
                                color: ended ? Ui.dim : Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              fmtDateNum(kickoff),
                              style: TextStyle(
                                color: ended ? Ui.dim : Ui.redSoft,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              tzShort(kickoff),
                              style: TextStyle(
                                color: Ui.dim,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Team(
                            flag: f.awayFlag,
                            name: f.away,
                            muted: ended,
                            alignEnd: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (live) ...[
                        Icon(Icons.sensors_rounded, size: 13, color: Ui.red),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (!f.hasStream && !ended) ...[
                        const SizedBox(width: 8),
                        Text('· Stream soon',
                            style: TextStyle(
                                color: Ui.dim,
                                fontSize: 10.5,
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

String _ms(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

class _Team extends StatelessWidget {
  final String flag;
  final String name;
  final bool muted;
  final bool alignEnd;
  const _Team({
    required this.flag,
    required this.name,
    required this.muted,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .06),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: Text(
            flag.isEmpty ? '⚽' : flag,
            style: const TextStyle(fontSize: 19, height: 1.1),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
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
