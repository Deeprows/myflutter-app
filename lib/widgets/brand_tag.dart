import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small brand mark for the bottom-right corner of the Live and Movies
/// screens. Follows the active theme colour and never takes taps.
class BrandTag extends StatelessWidget {
  const BrandTag({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Ui.red.withValues(alpha: .45), width: .8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_soccer_rounded,
                  size: 8, color: Ui.redSoft.withValues(alpha: .9)),
              const SizedBox(width: 3),
              Text(
                'Deeprowss',
                style: TextStyle(
                  fontSize: 8,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: .8,
                  decoration: TextDecoration.none,
                  color: Colors.white.withValues(alpha: .72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
