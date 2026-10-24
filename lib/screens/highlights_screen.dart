import 'package:flutter/material.dart';

import '../config.dart';
import '../models/highlight.dart';
import '../models/push_target.dart';
import '../services/feed_service.dart';
import '../services/push_service.dart';
import '../services/support_gate.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/app_refresh.dart';
import '../utils/format.dart';
import '../widgets/highlight_card.dart';
import '../widgets/pitch_painter.dart';
import 'player_screen.dart';
import '../utils/l10n.dart';

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
  bool _listMode = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.highlightsUrl.isNotEmpty) _load(remote: true);
    });
    PushService.instance.target.addListener(_onTarget);
    ContentSync.tick.addListener(_onSync);
  }

  void _onSync() {
    if (_loading) {
      // First load still running: try again shortly instead of skipping.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && !_loading) _load(remote: true);
      });
      return;
    }
    _load(remote: true);
  }

  // ---- a tapped notification that points at one highlight ------------------

  void _onTarget() {
    final t = PushService.instance.target.value;
    if (t == null || t.kind != 'highlights' || _loading) return;
    if (!_openTarget(t)) _load(remote: true);
  }

  bool _openTarget(PushTarget t) {
    for (final h in _all) {
      if (h.url.trim() == t.url) {
        PushService.instance.target.value = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _open(h);
        });
        return true;
      }
    }
    return false;
  }

  void _afterLoad({required bool last}) {
    final t = PushService.instance.target.value;
    if (t == null || t.kind != 'highlights') return;
    if (!_openTarget(t) && last) PushService.instance.target.value = null;
  }

  @override
  void dispose() {
    PushService.instance.target.removeListener(_onTarget);
    ContentSync.tick.removeListener(_onSync);
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
    _afterLoad(last: remote || AppConfig.highlightsUrl.isEmpty);
  }

  List<MapEntry<String, int>> get _competitions {
    final counts = <String, int>{};
    for (final h in _all) {
      final c = h.competition;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).toList();
  }

  void _open(Highlight h) {
    SupportGate.guard(context, () {
      if (!mounted) return;
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
    });
  }

  /// Lays the filtered highlights out as: a featured banner for the newest
  /// one, then one section per day. Inside a day, an odd leftover becomes a
  /// full-width row and the rest sit two per line, so no half-empty rows.
  List<_Row> _rows(List<Highlight> filtered, bool featured) {
    final rows = <_Row>[];
    var rest = filtered;
    if (featured && filtered.isNotEmpty) {
      rows.add(_Row.hero(filtered.first));
      rest = filtered.sublist(1);
    }
    final now = DateTime.now();
    final groups = <String, List<Highlight>>{};
    for (final h in rest) {
      final key = h.date == null ? 'Earlier' : dayLabel(h.date!, now);
      groups.putIfAbsent(key, () => []).add(h);
    }
    for (final e in groups.entries) {
      rows.add(_Row.header(e.key, e.value.length));
      final items = e.value;
      if (_listMode) {
        for (final h in items) {
          rows.add(_Row.wide(h));
        }
        continue;
      }
      var i = 0;
      if (items.length.isOdd) {
        rows.add(_Row.wide(items.first));
        i = 1;
      }
      for (; i < items.length; i += 2) {
        rows.add(_Row.pair(items[i], items[i + 1]));
      }
    }
    return rows;
  }

  Widget _buildRow(_Row r) {
    switch (r.kind) {
      case _RowKind.header:
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: Ui.red,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.label.toUpperCase(),
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                '${r.count}',
                style: TextStyle(
                  color: Ui.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      case _RowKind.hero:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SizedBox(
            height: 210,
            child: HighlightCard(
              item: r.items.first,
              style: HighlightCardStyle.hero,
              onTap: () => _open(r.items.first),
            ),
          ),
        );
      case _RowKind.wide:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SizedBox(
            height: 96,
            child: HighlightCard(
              item: r.items.first,
              style: HighlightCardStyle.wide,
              onTap: () => _open(r.items.first),
            ),
          ),
        );
      case _RowKind.pair:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SizedBox(
            height: 196,
            child: Row(
              children: [
                for (var i = 0; i < r.items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: HighlightCard(
                      item: r.items[i],
                      onTap: () => _open(r.items[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  Widget _roundButton(IconData icon, String tip, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: Material(
          color: Ui.card,
          shape: CircleBorder(side: BorderSide(color: Ui.line)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 20),
            ),
          ),
        ),
      );

  Widget _header(double top) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 10, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ui.red.withValues(alpha: .20), Ui.bg],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: PitchPainter())),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (canPop) ...[
                    _roundButton(
                      Icons.arrow_back_rounded,
                      'Back',
                      () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Football Highlights'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _loading
                              ? 'Loading…'
                              : '${_all.length} match replays and goals',
                          style: TextStyle(
                            color: Ui.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _roundButton(
                    _listMode
                        ? Icons.grid_view_rounded
                        : Icons.view_agenda_outlined,
                    _listMode ? 'Grid view' : 'List view',
                    () => setState(() => _listMode = !_listMode),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search teams or competitions'.tr,
                  hintStyle: TextStyle(color: Ui.dim),
                  prefixIcon: Icon(Icons.search_rounded, color: Ui.muted),
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                    borderSide: BorderSide(color: Ui.red.withValues(alpha: .7)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skeleton() {
    Widget block(double h) => Expanded(
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: Ui.card,
              borderRadius: BorderRadius.circular(Ui.radius),
              border: Border.all(color: Ui.line),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(children: [block(210)]),
          const SizedBox(height: 14),
          Row(children: [block(196), const SizedBox(width: 10), block(196)]),
          const SizedBox(height: 10),
          Row(children: [block(196), const SizedBox(width: 10), block(196)]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = _all.where((h) {
      if (_comp != null && h.competition != _comp) return false;
      return q.isEmpty || h.name.toLowerCase().contains(q);
    }).toList();
    final rows = _rows(filtered, q.isEmpty);
    final mq = MediaQuery.of(context);

    // A Scaffold gives the page its Material text style (without it the text
    // is drawn with the yellow debug underline) and a SnackBar host.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppRefresh(
        onRefresh: () async {
          await _load(remote: true);
          return !feed.lastRemoteFailed;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(mq.padding.top)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  children: [
                    _Pill(
                      'All'.tr,
                      _comp == null,
                      () => setState(() => _comp = null),
                      count: _all.length,
                    ),
                    for (final c in _competitions)
                      _Pill(
                        c.key,
                        _comp == c.key,
                        () => setState(() => _comp = c.key),
                        count: c.value,
                      ),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverToBoxAdapter(child: _skeleton())
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 44, color: Ui.dim),
                    const SizedBox(height: 10),
                    Text(
                      'No highlights found'.tr,
                      style: TextStyle(
                        color: Ui.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_query.isNotEmpty || _comp != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _query = '';
                            _comp = null;
                          });
                        },
                        child: Text('Clear filters'.tr),
                      ),
                    ],
                  ],
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _buildRow(rows[i]),
                  childCount: rows.length,
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: 24 + mq.padding.bottom)),
          ],
        ),
      ),
    );
  }
}

enum _RowKind { header, hero, wide, pair }

/// One line of the feed: a day header, the featured banner, a full-width
/// card, or two half-width cards side by side.
class _Row {
  final _RowKind kind;
  final String label;
  final int count;
  final List<Highlight> items;
  const _Row.header(this.label, this.count)
      : kind = _RowKind.header,
        items = const [];
  _Row.hero(Highlight h)
      : kind = _RowKind.hero,
        label = '',
        count = 1,
        items = [h];
  _Row.wide(Highlight h)
      : kind = _RowKind.wide,
        label = '',
        count = 1,
        items = [h];
  _Row.pair(Highlight a, Highlight b)
      : kind = _RowKind.pair,
        label = '',
        count = 2,
        items = [a, b];
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  const _Pill(this.label, this.selected, this.onTap, {this.count});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Ui.palette.onAccent : Ui.muted;
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
              border: Border.all(
                color: selected ? Colors.transparent : Ui.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: fg.withValues(alpha: .65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
