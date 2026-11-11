import 'package:flutter/material.dart';

import '../services/bet_slip_pdf.dart';

/// The bet slip as one dark, bookmaker-style card: a green marker on the left
/// and, per selection, the match, its kick-off and a Pick / Market / Confidence
/// box. This exact widget is what gets captured as the image people share or
/// post to the community, so it always draws in its own dark colours.
class BetSlipCard extends StatelessWidget {
  const BetSlipCard({
    super.key,
    required this.entries,
    this.onRemove,
  });

  final List<MapEntry<String, BetSlipPick>> entries;

  /// Shows a small remove button per selection (left out when capturing).
  final ValueChanged<String>? onRemove;

  static const _bg = Color(0xFF272B34);
  static const _rowLine = Color(0xFF30343E);
  static const _box = Color(0xFF363B47);
  static const _muted = Color(0xFF9AA0AD);
  static const _green = Color(0xFF2DD36F);
  static const _ash = Color(0xFF8E939F); // tick marks

  static String _when(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  static Color _confColor(String c) {
    final u = c.toUpperCase();
    if (u.contains('HIGH')) return _green;
    if (u.contains('MEDIUM')) return const Color(0xFFFFC46B);
    return _muted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          for (final e in entries) _row(e),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF713DDA), Color(0xFF007FAD)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI BET SLIP',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${entries.length} ${entries.length == 1 ? 'selection' : 'selections'} · Deeprowss AI Predict',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _teams(String title) {
    final parts = title.split(RegExp(r'\s+vs\.?\s+', caseSensitive: false));
    const white = TextStyle(color: Colors.white, fontSize: 15);
    if (parts.length == 2) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: parts[0], style: white),
          const TextSpan(text: '  v  ', style: TextStyle(color: _muted, fontSize: 13)),
          TextSpan(text: parts[1], style: white),
        ]),
      );
    }
    return Text(title.isEmpty ? 'Football match' : title, style: white);
  }

  Widget _row(MapEntry<String, BetSlipPick> entry) {
    final p = entry.value;
    final when = _when(p.kickoff);
    final meta = [if (p.league.isNotEmpty) p.league, if (when.isNotEmpty) when].join(' | ');
    final conf = _confColor(p.confidence);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _rowLine))),
      padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 22, right: 12),
            decoration: const BoxDecoration(color: _ash, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meta.isNotEmpty)
                  Text(meta, style: const TextStyle(color: _muted, fontSize: 13)),
                const SizedBox(height: 6),
                _teams(p.matchTitle),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(color: _box, borderRadius: BorderRadius.circular(3)),
                  child: Stack(
                    children: [
                      const Positioned(
                        right: 4,
                        top: 4,
                        bottom: 4,
                        child: Icon(Icons.emoji_events_rounded, size: 52, color: Color(0xFF3F5A50)),
                      ),
                      Column(
                        children: [
                          _kv('Pick', p.pick, check: true),
                          _kv('Market', p.market),
                          _kv('Confidence', p.confidence.toUpperCase(), color: conf),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove selection',
              visualDensity: VisualDensity.compact,
              onPressed: () => onRemove!(entry.key),
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool check = false, Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(k + ':', textAlign: TextAlign.right,
                  style: const TextStyle(color: _muted, fontSize: 15)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: v, style: TextStyle(color: color, fontSize: 15)),
                if (check)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_rounded, color: _ash, size: 18),
                    ),
                  ),
              ])),
            ),
          ],
        ),
      );

  Widget _footer() => Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _rowLine))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: const Text(
          'AI predictions are informational and are not guaranteed outcomes.',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      );
}
