import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart' hide Text;

import '../services/ui_translator.dart';

/// Drop-in replacement for Flutter's `Text`. Files import this instead of
/// Flutter's `Text` (`import 'package:flutter/material.dart' hide Text;`), so
/// every fixed piece of text in the app is shown in the phone's language
/// without touching each screen. Text the app builds from live data (names,
/// scores, posts) is never translated.
class Text extends StatelessWidget {
  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  m.Text _build(String? shown) => shown == null
      ? m.Text.rich(
          textSpan!,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        )
      : m.Text(
          shown,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return _build(null);
    final shown = UiTranslator.text(d);
    // A translation is still being fetched: repaint when it arrives.
    if (shown == d && UiTranslator.isPending(d)) {
      return ValueListenableBuilder<int>(
        valueListenable: UiTranslator.version,
        builder: (_, _, _) => _build(UiTranslator.text(d)),
      );
    }
    return _build(shown);
  }
}
