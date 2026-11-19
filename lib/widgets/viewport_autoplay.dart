import 'package:flutter/material.dart';

/// Tells [onVisible] how much of this widget is inside the scroll viewport
/// (0.0 - 1.0) whenever the list scrolls or the layout changes.
/// No extra package needed: it listens to the nearest [Scrollable].
class ViewportWatcher extends StatefulWidget {
  final Widget child;
  final ValueChanged<double> onVisible;
  const ViewportWatcher({super.key, required this.child, required this.onVisible});
  @override
  State<ViewportWatcher> createState() => _ViewportWatcherState();
}

class _ViewportWatcherState extends State<ViewportWatcher> {
  ScrollPosition? _pos;
  double _last = -1;
  bool _queued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_check);
      _pos = p;
      _pos?.addListener(_check);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ViewportWatcher old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _pos?.removeListener(_check);
    super.dispose();
  }

  void _schedule() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) _check();
    });
  }

  void _check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final vp = scrollable?.context.findRenderObject();
    double frac;
    if (vp is RenderBox && vp.hasSize) {
      final top = box.localToGlobal(Offset.zero, ancestor: vp).dy;
      final h = box.size.height;
      if (h <= 0) return;
      final visible = (top + h).clamp(0.0, vp.size.height) - top.clamp(0.0, vp.size.height);
      frac = (visible / h).clamp(0.0, 1.0);
    } else {
      frac = 1; // not inside a scrollable (e.g. full-screen viewer)
    }
    if ((frac - _last).abs() < 0.04 && !(frac == 0 && _last != 0)) return;
    _last = frac;
    widget.onVisible(frac);
  }

  @override
  Widget build(BuildContext context) {
    // Layout can change without scrolling (video resizes), so re-check.
    _schedule();
    return widget.child;
  }
}

/// Only one video plays at a time (several WebViews would drain the phone).
/// The card that is most visible (>= [minFraction]) wins; the rest pause.
class AutoPlayCoordinator {
  AutoPlayCoordinator._();
  static const double minFraction = 0.6;
  static final Map<Object, double> _fractions = {};
  static final ValueNotifier<Object?> winner = ValueNotifier<Object?>(null);

  static void report(Object owner, double fraction) {
    if (fraction <= 0) {
      _fractions.remove(owner);
    } else {
      _fractions[owner] = fraction;
    }
    _elect();
  }

  static void remove(Object owner) {
    _fractions.remove(owner);
    _elect();
  }

  static void _elect() {
    Object? best;
    var bestF = minFraction;
    // Keep the current winner while it is still reasonably visible so videos
    // don't flip back and forth while two cards are both on screen.
    final cur = winner.value;
    if (cur != null && (_fractions[cur] ?? 0) >= minFraction) {
      best = cur;
      bestF = _fractions[cur]! + 0.15;
    }
    _fractions.forEach((o, f) {
      if (f > bestF) {
        best = o;
        bestF = f;
      }
    });
    if (winner.value != best) winner.value = best;
  }
}
