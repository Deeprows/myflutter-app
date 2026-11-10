import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/fan_widgets.dart';
import '../services/fan_zone_service.dart';
import '../theme/app_theme.dart';
import '../utils/safe_error_message.dart';

/// X-style opinion poll shown inside a post. Before you vote (and while the
/// poll is open) the choices are tappable buttons; after you vote, or once the
/// poll has ended, they turn into result bars with percentages.
class FanPollView extends StatefulWidget {
  /// The post map from the server (needs id, poll_options, poll_ends_at,
  /// poll_counts, poll_mine).
  final Map<String, dynamic> post;

  /// Called after a successful vote so the owner can keep its copy in sync.
  final void Function(Map<String, dynamic> update)? onVoted;
  const FanPollView({super.key, required this.post, this.onVoted});

  /// True when this post carries a poll.
  static bool hasPoll(Map<String, dynamic> post) =>
      '${post['poll_options'] ?? ''}'.isNotEmpty;

  @override
  State<FanPollView> createState() => _FanPollViewState();
}

class _FanPollViewState extends State<FanPollView> {
  late List<String> _options;
  late List<int> _counts;
  int? _mine;
  late int _endsAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FanPollView old) {
    super.didUpdateWidget(old);
    if (!_busy) _load();
  }

  void _load() {
    final p = widget.post;
    try {
      _options = (jsonDecode('${p['poll_options']}') as List)
          .map((e) => '$e')
          .toList();
    } catch (_) {
      _options = [];
    }
    _endsAt = (p['poll_ends_at'] as num?)?.toInt() ?? 0;
    _setCounts(p['poll_counts']);
    final m = p['poll_mine'];
    _mine = m is num ? m.toInt() : null;
  }

  void _setCounts(dynamic raw) {
    _counts = List<int>.filled(_options.length, 0);
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is List) {
        for (final e in list) {
          if (e is Map) {
            final i = (e['i'] as num?)?.toInt() ?? -1;
            final n = (e['n'] as num?)?.toInt() ?? 0;
            if (i >= 0 && i < _counts.length) _counts[i] = n;
          }
        }
      }
    } catch (_) {}
  }

  bool get _ended => DateTime.now().millisecondsSinceEpoch >= _endsAt;
  int get _total => _counts.fold(0, (a, b) => a + b);

  String _timeLeft() {
    if (_ended) return 'Final results';
    final left = Duration(
      milliseconds: _endsAt - DateTime.now().millisecondsSinceEpoch,
    );
    if (left.inDays >= 1) return '${left.inDays}d left';
    if (left.inHours >= 1) return '${left.inHours}h left';
    final m = left.inMinutes < 1 ? 1 : left.inMinutes;
    return '${m}m left';
  }

  Future<void> _vote(int i) async {
    if (_busy || _mine != null || _ended) return;
    setState(() => _busy = true);
    try {
      final r = await FanZoneService.votePoll('${widget.post['id']}', i);
      if (!mounted) return;
      setState(() {
        _setCounts(r['poll_counts']);
        final m = r['poll_mine'];
        _mine = m is num ? m.toInt() : i;
        // Keep the shared post map in sync so scrolling does not reset it.
        widget.post['poll_counts'] = r['poll_counts'];
        widget.post['poll_mine'] = _mine;
      });
      widget.onVoted?.call({
        'poll_counts': r['poll_counts'],
        'poll_mine': _mine,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(safeErrorMessage(e)),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_options.isEmpty) return const SizedBox.shrink();
    final showResults = _mine != null || _ended;
    final total = _total;
    final accent = Ui.red;
    int top = 0;
    for (var i = 1; i < _counts.length; i++) {
      if (_counts[i] > _counts[top]) top = i;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: fanBox(radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _options.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              showResults
                  ? _resultBar(i, total, accent, i == top && total > 0)
                  : _choiceButton(i, accent),
            ],
            const SizedBox(height: 10),
            Text(
              '$total ${total == 1 ? 'vote' : 'votes'} • ${_timeLeft()}',
              style: TextStyle(fontSize: 12.5, color: Ui.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceButton(int i, Color accent) => SizedBox(
    width: double.infinity,
    height: 44,
    child: OutlinedButton(
      onPressed: _busy ? null : () => _vote(i),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: accent.withValues(alpha: .7), width: 1.2),
        foregroundColor: accent,
      ),
      child: Text(
        _options[i],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _resultBar(int i, int total, Color accent, bool leading) {
    final pct = total == 0 ? 0.0 : _counts[i] / total;
    final mine = _mine == i;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        color: Ui.cardDeep,
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                color: leading
                    ? accent.withValues(alpha: .55)
                    : Ui.line.withValues(alpha: .9),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _options[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  leading ? FontWeight.w900 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded, size: 16),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      fontWeight: leading ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
