import 'package:flutter/material.dart';

import '../config.dart';
import '../models/channel.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../widgets/link_sheet.dart';
import '../widgets/pitch_painter.dart';
import 'player_screen.dart';

class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  List<Channel> _all = const [];
  bool _loading = true;
  String _query = '';
  ChannelCategory? _cat;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.tvUrl.isNotEmpty) _load(remote: true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false}) async {
    final list = await feed.loadChannels(remote: remote);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  void _open(Channel c) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: c.name,
        subtitle: 'Live TV · ${c.category.label}',
        url: c.url,
        isLive: true,
      ),
    ));
  }

  Map<ChannelCategory, int> get _counts {
    final m = <ChannelCategory, int>{};
    for (final c in _all) {
      m[c.category] = (m[c.category] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = _all.where((c) {
      if (_cat != null && c.category != _cat) return false;
      return q.isEmpty || c.name.toLowerCase().contains(q);
    }).toList();

    final groups = <ChannelCategory, List<Channel>>{};
    for (final c in filtered) {
      groups.putIfAbsent(c.category, () => []).add(c);
    }
    final order = ChannelCategory.values.where(groups.containsKey).toList();
    final counts = _counts;
    final cats = ChannelCategory.values.where(counts.containsKey).toList();
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
              padding: EdgeInsets.fromLTRB(16, top + 16, 8, 12),
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
                      Row(
                        children: [
                          const Expanded(
                            child: Text('TV Channels',
                                style: TextStyle(
                                    fontSize: 26,
                                    height: 1.1,
                                    fontWeight: FontWeight.w900)),
                          ),
                          IconButton(
                            tooltip: 'Play a link',
                            onPressed: () => showLinkSheet(context),
                            icon: const Icon(Icons.add_link_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _loading
                            ? 'Loading…'
                            : '${_all.length} live channels',
                        style: TextStyle(
                            color: Ui.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextField(
                          controller: _search,
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search channels',
                            hintStyle: TextStyle(color: Ui.dim),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: Ui.muted),
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
                  _Pill('All', _all.length, _cat == null,
                      () => setState(() => _cat = null)),
                  for (final c in cats)
                    _Pill(c.label, counts[c]!, _cat == c,
                        () => setState(() => _cat = c),
                        icon: c.icon),
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
                  Text('No channels found',
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else
            for (final cat in order) ...[
              if (_cat == null)
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
                          '${cat.label.toUpperCase()} · ${groups[cat]!.length}',
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
                sliver: SliverList.builder(
                  itemCount: groups[cat]!.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ChannelTile(
                      channel: groups[cat]![i],
                      onTap: () => _open(groups[cat]![i]),
                    ),
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

class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.card, Ui.cardDeep],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.red.withValues(alpha: .22)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Ui.red.withValues(alpha: .25)),
                  ),
                  child: Icon(channel.category.icon,
                      color: Ui.redSoft, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(channel.category.label,
                          style: TextStyle(
                              color: Ui.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Ui.red.withValues(alpha: .3)),
                  ),
                  child: Text('LIVE',
                      style: TextStyle(
                          color: Ui.redSoft,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _Pill(this.label, this.count, this.selected, this.onTap, {this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Ui.muted;
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
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: fg)),
                const SizedBox(width: 6),
                Text('$count',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.white70 : Ui.dim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
