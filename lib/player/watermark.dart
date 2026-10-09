import 'package:flutter/material.dart';

/// Small, quiet brand mark shown on the player pages.
class Watermark extends StatelessWidget {
  const Watermark({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        'Deeprowss',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: Colors.white.withValues(alpha: .38),
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    );
  }
}
