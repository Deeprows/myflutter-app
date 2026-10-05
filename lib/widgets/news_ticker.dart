import 'package:flutter/material.dart';

import '../models/ticker.dart';
import '../theme/app_theme.dart';

/// Slim, continuously scrolling message bar. Content comes from
/// assets/data/ticker.json (or AppConfig.tickerUrl).
class NewsTicker extends StatefulWidget {
  final TickerData data;
  const NewsTicker({super.key, required this.data});

  @override
  State<NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<NewsTicker>
    with SingleTickerProviderStateMixin {
  static const _textStyle =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.1);
  static const _gap = 56.0; // space between messages

  late final AnimationController _c = AnimationController(vsync: this);
  String _key = '';
  double _unit = 0; // width of one full pass of all messages

  String get _text => widget.data.items.join('   •   ');

  /// Measures the text, then (re)starts the loop at the right speed.
  void _prepare(double viewport) {
    final key = '${widget.data.items.join('|')}@${widget.data.speed}';
    if (key == _key) return;
    _key = key;
    final tp = TextPainter(
      text: TextSpan(text: _text, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _unit = tp.width + _gap;
    final ms = (_unit / widget.data.speed * 1000).round().clamp(1000, 600000);
    _c
      ..duration = Duration(milliseconds: ms)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.data.visible) return const SizedBox.shrink();

    return Container(
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: Ui.red.withValues(alpha: .12),
        border: Border.all(color: Ui.red.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            alignment: Alignment.center,
            child: Icon(Icons.campaign_rounded, size: 15, color: Ui.redSoft),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(13)),
              child: LayoutBuilder(builder: (context, box) {
                _prepare(box.maxWidth);
                // Enough copies to always cover the width while looping.
                final copies = (box.maxWidth / _unit).ceil() + 2;
                return ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, .04, .94, 1],
                  ).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Transform.translate(
                        offset: Offset(-_c.value * _unit, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < copies; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: _gap),
                                child: Text(_text,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: _textStyle),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
