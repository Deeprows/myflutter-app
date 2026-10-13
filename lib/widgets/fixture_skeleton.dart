import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder match cards with a moving shimmer. Shown on the Live screen
/// while the fresh fixtures are downloading, so old matches never flash first.
class FixtureSkeletonList extends StatefulWidget {
  final int count;

  const FixtureSkeletonList({super.key, this.count = 6});

  @override
  State<FixtureSkeletonList> createState() => _FixtureSkeletonListState();
}

class _FixtureSkeletonListState extends State<FixtureSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Column(
          children: [
            for (var i = 0; i < widget.count; i++) _SkeletonCard(t: _c.value),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double t;

  const _SkeletonCard({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _Bone(t: t, width: 46, height: 20, radius: 10),
                ),
                const SizedBox(height: 10),
                _TeamRow(t: t),
                const SizedBox(height: 10),
                _TeamRow(t: t),
                const Spacer(),
                _Bone(t: t, width: 96, height: 14, radius: 7),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Center(
            child: _Bone(t: t, width: 40, height: 40, radius: 12),
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final double t;

  const _TeamRow({required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Bone(t: t, width: 30, height: 30, radius: 15),
        const SizedBox(width: 12),
        _Bone(t: t, width: 105, height: 16, radius: 8),
      ],
    );
  }
}

class _Bone extends StatelessWidget {
  final double t;
  final double width;
  final double height;
  final double radius;

  const _Bone({
    required this.t,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final base = Color.alphaBlend(
      Colors.white.withValues(alpha: .07),
      Ui.card,
    );
    final shine = Color.alphaBlend(
      Colors.white.withValues(alpha: .17),
      Ui.card,
    );

    // The bright band slides from left to right, then starts again.
    final x = -1.8 + 3.6 * t;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(x - 0.9, -0.4),
          end: Alignment(x + 0.9, 0.4),
          colors: [base, shine, base],
          stops: const [0.2, 0.5, 0.8],
        ),
      ),
    );
  }
}
