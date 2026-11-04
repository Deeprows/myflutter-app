import 'package:flutter/material.dart';

import '../models/fan_prediction.dart';
import '../services/auth_service.dart';
import '../services/fan_zone_service.dart';
import '../services/score_service.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'content_shortcut_screen.dart';
import 'fan_widgets.dart';
import 'fan_zone_screen.dart' show FanZonePage, FanZoneScreen;

/// Results board: every prediction the user made, what happened, the points it
/// earned and how that reflects on the Ranks table.
class PredictionResultsScreen extends StatefulWidget {
  const PredictionResultsScreen({super.key});

  @override
  State<PredictionResultsScreen> createState() =>
      _PredictionResultsScreenState();
}

enum _Filter { all, pending, settled }

class _PredictionResultsScreenState extends State<PredictionResultsScreen> {
  List<Map<String, dynamic>> _picks = [];
  Map<String, dynamic>? _me; // my row on the weekly leaderboard
  int? _rank;
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthService.instance.signedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Opening the state also lets the server check any finished matches.
      final data = await FanZoneService.call('state');
      final id = '${data['id'] ?? ''}';
      final board = FanZoneService.rows(data['leaderboard']);
      final at = board.indexWhere((r) => '${r['id']}' == id);
      if (!mounted) return;
      setState(() {
        _picks = FanZoneService.rows(data['picks']).map(_withLive).toList()
          ..sort(
            (a, b) => ((b['kickoff'] as num?) ?? 0).compareTo(
              (a['kickoff'] as num?) ?? 0,
            ),
          );
        _me = at >= 0 ? board[at] : null;
        _rank = at >= 0 ? at + 1 : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Shows the Live screen's full-time score right away while the server
  /// confirms it for the Ranks table.
  Map<String, dynamic> _withLive(Map<String, dynamic> p) {
    if (p['result_home'] != null) return p;
    final key = '${p['match_key']}';
    final cut = key.lastIndexOf('|');
    if (cut < 0) return p;
    final s = ScoreService.instance.scoreFor(key.substring(0, cut));
    if (s == null || !s.finished) return p;
    final clock = s.clock.toUpperCase();
    if (clock.isNotEmpty && clock != 'FT' && clock != 'FULL-TIME') return p;
    return {...p, 'result_home': s.home, 'result_away': s.away, 'provisional': true};
  }

  bool _settled(Map<String, dynamic> p) => p['result_home'] != null;

  void _openRanks() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ContentShortcutScreen(
        title: 'Ranks',
        child: FanZoneScreen(
          active: true,
          page: FanZonePage.ranks,
          embedded: true,
        ),
      ),
    ),
  );

  // ------------------------------------------------------------- summary

  Widget _stat(String value, String label, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Ui.muted)),
      ],
    ),
  );

  Widget _summary() {
    var exact = 0, correct = 0, missed = 0, pending = 0, points = 0;
    for (final p in _picks) {
      if (!_settled(p)) {
        pending++;
        continue;
      }
      final pts = fanPredictionScore(p);
      switch (pts) {
        case 3:
          exact++;
          points += 3;
        case 1:
          correct++;
          points += 1;
        case 0:
          missed++;
        default:
          break; // refunded push
      }
    }
    final week = (_me?['points'] as num?)?.toInt();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF6D4AE0), Color(0xFF1E88C8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR POINTS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      '${week ?? points}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      week != null ? 'this week in Ranks' : 'from settled predictions',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'WEEKLY RANK',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    _rank != null ? '#$_rank' : '—',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _rank != null ? 'on the leaderboard' : 'not on the board yet',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _stat('$exact', 'Exact', const Color(0xFF69F0AE)),
                _stat('$correct', 'Correct', const Color(0xFF82B1FF)),
                _stat('$missed', 'Missed', const Color(0xFFFF8A80)),
                _stat('$pending', 'Pending', Colors.white70),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openRanks,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF3F2BA8),
              ),
              icon: const Icon(Icons.leaderboard_rounded, size: 18),
              label: const Text(
                'See where you stand in Ranks',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- list

  Widget _card(Map<String, dynamic> p) {
    final settled = _settled(p);
    final pts = fanPredictionScore(p);
    final push = fanPredictionPush(p);
    final (Color c, String badge, String effect) = switch (pts) {
      3 => (
        Ui.green,
        '+3 Exact',
        'Exact result: 3 points added to your Ranks.',
      ),
      1 => (
        const Color(0xFF42A5F5),
        '+1 Correct',
        'Right outcome: 1 point added to your Ranks.',
      ),
      0 => (
        const Color(0xFFEF5350),
        '0 Missed',
        'Not this time: no points added to Ranks.',
      ),
      _ =>
        push
            ? (Ui.muted, 'Refunded', 'Goals landed on the line: no change in Ranks.')
            : (
                Ui.muted,
                'Pending',
                'Counts in Ranks once the final score is verified.',
              ),
    };
    final ko = DateTime.fromMillisecondsSinceEpoch(
      ((p['kickoff'] as num?) ?? 0).toInt(),
    );
    final confirming = p['provisional'] == true;
    final note = '${p['result_note'] ?? ''}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: settled && pts != null && pts > 0
              ? c.withValues(alpha: .55)
              : Ui.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: c,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${fanClock(ko)}  •  ${ko.day}/${ko.month}/${ko.year}',
            style: TextStyle(fontSize: 11, color: Ui.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _kv('My prediction', fanPredictionLabel(p)),
              ),
              Expanded(
                child: _kv(
                  'Final score',
                  settled
                      ? '${p['result_home']} – ${p['result_away']}${confirming ? '  (confirming)' : ''}'
                      : 'Not final yet',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                settled ? Icons.leaderboard_rounded : Icons.hourglass_top_rounded,
                size: 14,
                color: c,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  effect,
                  style: TextStyle(fontSize: 12, color: Ui.muted),
                ),
              ),
            ],
          ),
          if (!settled && note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: TextStyle(fontSize: 11, color: Ui.dim)),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TextStyle(fontSize: 11, color: Ui.dim)),
      const SizedBox(height: 2),
      Text(
        v,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _filters() => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final f in _Filter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(switch (f) {
                _Filter.all => 'All (${_picks.length})',
                _Filter.pending =>
                  'Pending (${_picks.where((p) => !_settled(p)).length})',
                _Filter.settled =>
                  'Results (${_picks.where(_settled).length})',
              }),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shown = _picks.where((p) {
      return switch (_filter) {
        _Filter.all => true,
        _Filter.pending => !_settled(p),
        _Filter.settled => _settled(p),
      };
    }).toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text(
          'My results',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Ranks',
            icon: const Icon(Icons.leaderboard_rounded),
            onPressed: _openRanks,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: !AuthService.instance.signedIn
          ? Center(
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
                  );
                  if (mounted) _load();
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in to see your results'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  if (_loading && _picks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_error != null && _picks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  if (!_loading && _error == null && _picks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.how_to_vote_rounded, size: 46, color: Ui.dim),
                          const SizedBox(height: 10),
                          const Text(
                            'No predictions yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Predict a match on AI Predict or in the Thread. Your results and points show up here after the final whistle.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ui.muted),
                          ),
                        ],
                      ),
                    ),
                  if (_picks.isNotEmpty) ...[
                    _summary(),
                    const SizedBox(height: 6),
                    _filters(),
                    const SizedBox(height: 4),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: Text(
                            'Nothing here yet.',
                            style: TextStyle(color: Ui.muted),
                          ),
                        ),
                      ),
                    for (final p in shown) _card(p),
                  ],
                ],
              ),
            ),
    );
  }
}
