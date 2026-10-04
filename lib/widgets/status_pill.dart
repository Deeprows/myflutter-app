import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../theme/app_theme.dart';
import 'live_dot.dart';

class StatusPill extends StatelessWidget {
  final MatchPhase phase;
  const StatusPill({super.key, required this.phase});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color fg;
    late final Color bg;
    late final Color border;
    switch (phase) {
      case MatchPhase.live:
        label = 'LIVE';
        fg = Colors.white;
        bg = Ui.red;
        border = Colors.white.withValues(alpha: .14);
      case MatchPhase.upcoming:
        label = 'UPCOMING';
        fg = Ui.redSoft;
        bg = Ui.red.withValues(alpha: .10);
        border = Ui.red.withValues(alpha: .25);
      case MatchPhase.ended:
        label = 'ENDED';
        fg = Ui.dim;
        bg = const Color(0x1A858C98);
        border = const Color(0x29858C98);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
        boxShadow: phase == MatchPhase.live
            ? [BoxShadow(color: Ui.red.withValues(alpha: .35), blurRadius: 12)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (phase == MatchPhase.live) ...[
            const LiveDot(size: 6),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
