import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Twitter / X style building blocks shared by the football community
/// (feed, post cards, threads).

/// Full-width tab strip with an underline under the selected tab.
class XTabBar extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;
  const XTabBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Ui.bg,
      border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == index
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: i == index ? Colors.white : Ui.muted,
                      ),
                    ),
                    const SizedBox(height: 11),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 4,
                      width: i == index ? 56 : 0,
                      decoration: BoxDecoration(
                        color: Ui.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Thin line between posts.
class XDivider extends StatelessWidget {
  final double thickness;
  const XDivider({super.key, this.thickness = .6});
  @override
  Widget build(BuildContext context) =>
      Container(height: thickness, color: Ui.line);
}

/// Thick gap between feed sections (like the grey band on X).
class XSectionGap extends StatelessWidget {
  const XSectionGap({super.key});
  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    decoration: BoxDecoration(
      color: Ui.cardDeep,
      border: Border.symmetric(
        horizontal: BorderSide(color: Ui.line, width: .6),
      ),
    ),
  );
}

/// Bold section heading ("Match rooms", "Trending").
class XSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  const XSectionHeader(this.title, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Ui.red),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

/// Reply / like / share button: icon with a small count.
class XAction extends StatelessWidget {
  final IconData icon;
  final int? count;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;
  const XAction({
    super.key,
    required this.icon,
    this.count,
    this.color,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? (color ?? Ui.red) : Ui.dim;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.18 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 19, color: c),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 5),
              Text(
                _short(count!),
                style: TextStyle(
                  fontSize: 12.5,
                  color: c,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _short(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Text with #hashtags and @mentions coloured like on X.
List<InlineSpan> xRichSpans(String text, {TextStyle? base}) {
  final style = base ?? const TextStyle();
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'([#@][\p{L}\p{N}_]+)', unicode: true);
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    spans.add(
      TextSpan(
        text: m.group(0),
        style: style.copyWith(color: Ui.redSoft, fontWeight: FontWeight.w600),
      ),
    );
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}
