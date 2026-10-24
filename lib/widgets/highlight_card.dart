import 'package:flutter/material.dart';

import '../models/highlight.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/l10n.dart';

const _palettes = <List<Color>>[
  [Color(0xFF3A0F1E), Color(0xFF13111F)],
  [Color(0xFF0F2A3A), Color(0xFF0E1420)],
  [Color(0xFF1F2E12), Color(0xFF0D1510)],
  [Color(0xFF2E1B3F), Color(0xFF110F1E)],
  [Color(0xFF3A2A0F), Color(0xFF16110C)],
  [Color(0xFF0F3A33), Color(0xFF0B1517)],
];

/// How a highlight is laid out.
///  * compact - half-width tile for the two-column grid
///  * wide    - full-width row: small thumbnail on the left, details right
///  * hero    - big featured banner for the newest highlight
enum HighlightCardStyle { compact, wide, hero }

bool _isNew(Highlight h) {
  final d = h.date;
  if (d == null) return false;
  final diff = DateTime.now().difference(d);
  return !diff.isNegative && diff.inHours < 36;
}

class HighlightCard extends StatelessWidget {
  final Highlight item;
  final VoidCallback onTap;
  final HighlightCardStyle style;
  const HighlightCard({
    super.key,
    required this.item,
    required this.onTap,
    this.style = HighlightCardStyle.compact,
  });

  List<Color> get _pal =>
      _palettes[item.name.hashCode.abs() % _palettes.length];

  Widget _shell(Widget child, BorderRadius radius) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: InkWell(onTap: onTap, borderRadius: radius, child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case HighlightCardStyle.hero:
        return _hero();
      case HighlightCardStyle.wide:
        return _wide();
      case HighlightCardStyle.compact:
        return _compact();
    }
  }

  // ---------------------------------------------------------------------------
  // COMPACT (grid tile)
  // ---------------------------------------------------------------------------

  Widget _compact() {
    final radius = BorderRadius.circular(Ui.radius);
    return _shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Thumb(
              item: item,
              colors: _pal,
              crest: 42,
              play: 30,
              radius:
                  const BorderRadius.vertical(top: Radius.circular(Ui.radius)),
              tags: [if (_isNew(item)) _Tag('New'.tr.toUpperCase(), Ui.red)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.competition ?? 'Highlights'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      radius,
    );
  }

  // ---------------------------------------------------------------------------
  // WIDE (full-width row)
  // ---------------------------------------------------------------------------

  Widget _wide() {
    final radius = BorderRadius.circular(Ui.radius);
    final meta = [
      if (item.competition != null) item.competition!,
      if (item.date != null) shortDate(item.date!),
    ].join(' · ');
    return _shell(
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 124,
            child: _Thumb(
              item: item,
              colors: _pal,
              crest: 34,
              play: 0,
              radius: const BorderRadius.horizontal(
                left: Radius.circular(Ui.radius),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isNew(item))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _Tag('New'.tr.toUpperCase(), Ui.red),
                    ),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta.isEmpty ? 'Highlights'.tr : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Ui.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _PlayDot(34)),
          ),
        ],
      ),
      radius,
    );
  }

  // ---------------------------------------------------------------------------
  // HERO (featured banner)
  // ---------------------------------------------------------------------------

  Widget _hero() {
    final radius = BorderRadius.circular(20);
    final meta = [
      'Highlights'.tr,
      if (item.competition != null) item.competition!,
      if (item.date != null) shortDate(item.date!),
    ].join(' · ');
    return _shell(
      ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Thumb(
              item: item,
              colors: _pal,
              crest: 62,
              play: 0,
              radius: radius,
              align: const Alignment(0, -.3),
              tags: [
                _Tag('Latest'.tr.toUpperCase(), const Color(0xFFFFC107),
                    dark: true),
                if (item.competition != null)
                  _Tag(item.competition!, Colors.black.withValues(alpha: .5)),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 28, 14, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: .82)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _PlayDot(48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      radius,
    );
  }
}

// -----------------------------------------------------------------------------
// PARTS
// -----------------------------------------------------------------------------

class _Thumb extends StatelessWidget {
  final Highlight item;
  final List<Color> colors;
  final double crest;

  /// Size of the play button drawn bottom-right (0 = none).
  final double play;
  final BorderRadius radius;
  final Alignment align;
  final List<Widget> tags;
  const _Thumb({
    required this.item,
    required this.colors,
    required this.crest,
    required this.play,
    required this.radius,
    this.align = Alignment.center,
    this.tags = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: align,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Monogram(initialsOf(item.home), crest),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: crest > 50 ? 12 : 7),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: Ui.muted,
                        fontSize: crest > 50 ? 12 : 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _Monogram(
                    item.away.isEmpty ? '' : initialsOf(item.away),
                    crest,
                  ),
                ],
              ),
            ),
            if (tags.isNotEmpty)
              Positioned(
                left: 10,
                top: 10,
                right: 10,
                child: Wrap(spacing: 6, runSpacing: 4, children: tags),
              ),
            if (play > 0)
              Positioned(right: 8, bottom: 8, child: _PlayDot(play)),
          ],
        ),
      ),
    );
  }
}

class _PlayDot extends StatelessWidget {
  final double size;
  const _PlayDot(this.size);

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Ui.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Ui.red.withValues(alpha: .5), blurRadius: 12),
          ],
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Ui.palette.onAccent,
          size: size * .66,
        ),
      );
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool dark;
  const _Tag(this.text, this.color, {this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: dark ? Colors.black : Colors.white,
            fontSize: 9.5,
            letterSpacing: .4,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _Monogram extends StatelessWidget {
  final String text;
  final double size;
  const _Monogram(this.text, this.size);

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * .32,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
          color: Colors.white,
        ),
      ),
    );
  }
}
