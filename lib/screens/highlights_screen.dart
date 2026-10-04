import 'package:flutter/material.dart';

import '../config.dart';
import '../models/highlight.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/highlight_card.dart';
import '../widgets/pitch_painter.dart';
import 'player_screen.dart';

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key});

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  List<Highlight> _all = const [];
  bool _loading = true;
  String _query = '';
  String? _comp;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.highlightsUrl.isNotEmpty) _load(remote: true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadHighlights(remote: remote);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<String> get _competitions {
    final counts = <String, int>{};
    for (final h in _all) {
      final c = h.competition;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(6).toList();
  }

  void _open(Highlight h) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: h.title,
        subtitle: [
          'Highlights',
          if (h.competition != null) h.competition!,
          if (h.date != null) longDate(h.date!),
        ].join(' · '),
        url: h.url,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    final filtered = _all.where((h) {
      if (_comp != null && h.competition != _comp) return false;
      return q.isEmpty || h.name.toLowerCase().contains(q);
    }).toList();

    // Group by day (list is already newest first).
    final groups = <String, List<Highlight>>{};
    for (final h in filtered) {
      final key = h.date == null ? 'Earlier' : dayLabel(h.date!, now);
      groups.putIfAbsent(key, () => []).add(h);
    }

    final top = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: Ui.red,
      backgroundColor: Ui.panel,
      onRefresh: () => _load(remote: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(16, top + 16, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Ui.red.withValues(alpha: .20), Ui.bg],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                      child: CustomPaint(painter: PitchPainter())),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Football Highlights',
                          style: TextStyle(
                              fontSize: 26,
                              height: 1.1,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        _loading
                            ? 'Loading…'
                            : '${_all.length} match replays and goals',
                        style: TextStyle(
                            color: Ui.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search teams or competitions',
                          hintStyle: TextStyle(color: Ui.dim),
                          prefixIcon:
                              Icon(Icons.search_rounded, color: Ui.muted),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: Ui.card,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Ui.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Ui.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Ui.red.withValues(alpha: .7)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                children: [
                  _Pill('All', _comp == null, () => setState(() => _comp = null)),
                  for (final c in _competitions)
                    _Pill(c, _comp == c, () => setState(() => _comp = c)),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: Ui.red)),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded, size: 44, color: Ui.dim),
                  SizedBox(height: 10),
                  Text('No highlights found',
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else
            for (final e in groups.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(
                            color: Ui.red,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.key.toUpperCase(),
                        style: TextStyle(
                            color: Ui.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisExtent: 192,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => HighlightCard(
                      item: e.value[i],
                      onTap: () => _open(e.value[i]),
                    ),
                    childCount: e.value.length,
                  ),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? Ui.red : Ui.card,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: selected ? Colors.transparent : Ui.line),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : Ui.muted)),
          ),
        ),
      ),
    );
  }
}
