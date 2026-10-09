import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

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

    return Opacity(
      opacity: ended ? .72 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: Ui.cardDeep,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: live
                  ? Ui.red.withValues(alpha: .78)
                  : ended
                      ? Colors.white.withValues(alpha: .08)
                      : Ui.red.withValues(alpha: .34),
              width: live ? 1.2 : 1,
            ),
            boxShadow: live
                ? [
                    BoxShadow(
                      color: Ui.red.withValues(alpha: .14),
                      blurRadius: 9,
                      spreadRadius: .5,
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.league.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        f.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),

                  if (f.league.isNotEmpty)
                    const SizedBox(height: 3),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _Team(
                          name: f.home,
                          muted: ended,
                          alignEnd: false,
                        ),
                      ),

                      SizedBox(
                        width: 86,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtTime12(kickoff),
                              style: TextStyle(
                                color: ended ? Ui.dim : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              fmtDateNum(kickoff),
                              style: TextStyle(
                                color: ended ? Ui.dim : Ui.redSoft,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              tzShort(kickoff),
                              style: TextStyle(
                                color: Ui.dim,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: _Team(
                          name: f.away,
                          muted: ended,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (live) ...[
                        Icon(Icons.sensors_rounded, size: 11, color: Ui.red),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (!f.hasStream && !ended) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· Stream soon',
                          style: TextStyle(
                            color: Ui.dim,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
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
  final String name;
  final bool muted;
  final bool alignEnd;

  const _Team({
    required this.name,
    required this.muted,
    required this.alignEnd,
  });

  String get _crestAsset {
    switch (name.toLowerCase().trim()) {
      case 'malaga':
      case 'málaga':
        return 'assets/clubs/malaga.png';
      case 'espanyol':
      case 'rcd espanyol':
        return 'assets/clubs/espanyol.png';
      case 'borussia dortmund':
      case 'dortmund':
        return 'assets/clubs/dortmund.png';
      case 'werder bremen':
        return 'assets/clubs/werder_bremen.png';
      case 'lens':
      case 'rc lens':
        return 'assets/clubs/lens.png';
      case 'lyon':
      case 'olympique lyonnais':
        return 'assets/clubs/lyon.png';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _crestAsset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          width: 29,
          height: 29,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .05),
            border: Border.all(
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
          child: asset.isEmpty
              ? const Icon(
                  Icons.sports_soccer_rounded,
                  size: 20,
                  color: Colors.white70,
                )
              : Image.asset(
                  asset,
                  width: 23,
                  height: 23,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.sports_soccer_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
        ),

        const SizedBox(height: 1),

        Text(
          name,
          maxLines: 1,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted ? const Color(0xFF858B95) : Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}
