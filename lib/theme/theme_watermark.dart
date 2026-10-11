import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Faint diagonal name across the whole app for the football-icon themes
/// (Messi 10, CR7). Draws nothing for the other themes and never takes taps.
class ThemeWatermark extends StatelessWidget {
  const ThemeWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Ui.palette.watermark;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Center(
            child: Transform.rotate(
              angle: -0.42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 84,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      decoration: TextDecoration.none,
                      color: Ui.red.withValues(alpha: .08),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
