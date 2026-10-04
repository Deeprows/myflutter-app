import 'package:flutter/material.dart';

import '../models/highlight.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

const _palettes = <List<Color>>[
  [Color(0xFF3A0F1E), Color(0xFF13111F)],
  [Color(0xFF0F2A3A), Color(0xFF0E1420)],
  [Color(0xFF1F2E12), Color(0xFF0D1510)],
  [Color(0xFF2E1B3F), Color(0xFF110F1E)],
  [Color(0xFF3A2A0F), Color(0xFF16110C)],
  [Color(0xFF0F3A33), Color(0xFF0B1517)],
];

class HighlightCard extends StatelessWidget {
  final Highlight item;
  final VoidCallback onTap;
  const HighlightCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = _palettes[item.name.hashCode.abs() % _palettes.length];
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(Ui.radius),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Ui.radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(Ui.radius)),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: pal,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Monogram(initialsOf(item.home)),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('VS',
                                    style: TextStyle(
                                        color: Ui.muted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2)),
                              ),
                              _Monogram(
                                  item.away.isEmpty ? '' : initialsOf(item.away)),
                            ],
                          ),
                        ),
                        if (item.competition != null)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .45),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                item.competition!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Ui.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Ui.red.withValues(alpha: .5),
                                    blurRadius: 12)
                              ],
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.date == null ? 'Highlights' : 'Highlights · ${shortDate(item.date!)}',
                      style: const TextStyle(
                          color: Ui.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final String text;
  const _Monogram(this.text);

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: .5)),
    );
  }
}
