import 'package:flutter/material.dart';

import '../config.dart';
import '../models/channel.dart';
import '../services/feed_service.dart';
import '../services/support_gate.dart';
import '../services/content_sync.dart';
import '../services/nexus_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_refresh.dart';
import '../widgets/link_sheet.dart';
import '../widgets/pitch_painter.dart';
import 'native_player_screen.dart';
import 'player_screen.dart';

/// Display order of the category rows / pills.
const _categoryOrder = [
  ChannelCategory.sports,
  ChannelCategory.news,
  ChannelCategory.movies,
  ChannelCategory.entertainment,
  ChannelCategory.music,
  ChannelCategory.kids,
  ChannelCategory.documentary,
  ChannelCategory.lifestyle,
  ChannelCategory.religious,
  ChannelCategory.general,
  ChannelCategory.other,
];

const _rowPreview = 14; // cards per category row before "See all"
const _cardHeight = 156.0;
const _rowCardWidth = 148.0;

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
  String? _country; // ISO code filter, null = all
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (AppConfig.tvUrl.isNotEmpty || NexusService.enabled) {
        _load(remote: true);
      }
    });
    ContentSync.tick.addListener(_onSync);
  }

  void _onSync() {
    if (!_loading) _load(remote: true);
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_onSync);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool remote = false, bool force = false}) async {
    final list = await feed.loadChannels(remote: remote, force: force);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  void _open(Channel c) {
    SupportGate.guard(context, () {
      if (mounted) _openNow(c);
    });
  }

  void _openNow(Channel c) {
    // HLS / DASH / video links: native player (real Referer + User-Agent).
    // Embed pages (and anything it can't handle) keep using the web player.
    if (AppConfig.nativeTvPlayer && nativePlayable(c.url)) {
      final alt = (c.altUrl ?? '').trim();
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NativePlayerScreen(
          title: c.name,
          subtitle: 'Live TV · ${c.category.label}',
          streams: [
            NativeStream(c.url, referer: c.referer, userAgent: c.userAgent),
            if (alt.isNotEmpty && nativePlayable(alt))
              NativeStream(alt,
                  referer: c.altReferer, userAgent: c.altUserAgent),
          ],
        ),
      ));
      return;
    }

    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: c.name,
        subtitle: 'Live TV · ${c.category.label}',
        url: c.url,
        referer: c.referer,
        userAgent: c.userAgent,
        altUrl: c.altUrl,
        altReferer: c.altReferer,
        altUserAgent: c.altUserAgent,
        isLive: true,
      ),
    ));
  }

  /// Country code -> channel count, biggest first.
  List<MapEntry<String, int>> get _countries {
    final m = <String, int>{};
    for (final c in _all) {
      final k = c.country;
      if (k != null && k.length == 2) m[k] = (m[k] ?? 0) + 1;
    }
    return m.entries.toList()
      ..sort((a, b) {
        final d = b.value.compareTo(a.value);
        return d != 0 ? d : a.key.compareTo(b.key);
      });
  }

  static String _flagOf(String code) =>
      Channel(name: '', url: '', category: ChannelCategory.other, country: code)
          .flag;

  Future<void> _pickCountry() async {
    final list = _countries;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Ui.panel,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .7,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('All countries'),
              selected: _country == null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final e in list)
              ListTile(
                leading: Text(_flagOf(e.key),
                    style: const TextStyle(fontSize: 22)),
                title: Text(e.key),
                trailing:
                    Text('${e.value}', style: TextStyle(color: Ui.muted)),
                selected: _country == e.key,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked.isEmpty ? null : picked);
  }

  void _selectCat(ChannelCategory? c) {
    setState(() => _cat = c);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    // Country filter applies everywhere (rows, pills, counts).
    final base = _country == null
        ? _all
        : _all.where((c) => c.country == _country).toList();

    final counts = <ChannelCategory, int>{};
    for (final c in base) {
      counts[c.category] = (counts[c.category] ?? 0) + 1;
    }
    final cats = _categoryOrder.where(counts.containsKey).toList();

    final filtered = base.where((c) {
      if (_cat != null && c.category != _cat) return false;
      return q.isEmpty || c.name.toLowerCase().contains(q);
    }).toList();

    final groups = <ChannelCategory, List<Channel>>{};
    for (final c in filtered) {
      groups.putIfAbsent(c.category, () => []).add(c);
    }

    // Rows (Netflix style) when browsing everything; a grid when a category
    // is picked or the user is searching.
    final showRows = _cat == null && q.isEmpty;
    final top = MediaQuery.of(context).padding.top;

    return AppRefresh(
      onRefresh: () async {
        await _load(remote: true, force: true);
        return !feed.lastRemoteFailed;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _header(top, base.length)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                children: [
                  _Pill('All', base.length, _cat == null,
                      () => _selectCat(null)),
                  for (final c in cats)
                    _Pill(c.label, counts[c]!, _cat == c,
                        () => _selectCat(c),
                        icon: c.icon),
                ],
              ),
            ),
          ),
          if (_countries.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar:
                        Icon(Icons.public_rounded, size: 16, color: Ui.muted),
                    label: Text(
                      _country == null
                          ? 'All countries'
                          : '${_flagOf(_country!)} $_country',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    backgroundColor: Ui.card,
                    side: BorderSide(color: Ui.line),
                    onPressed: _pickCountry,
                  ),
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
                  const SizedBox(height: 10),
                  Text('No channels found',
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            )
          else if (showRows)
            ..._rows(groups)
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: _cardHeight,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _ChannelCard(
                  channel: filtered[i],
                  onTap: () => _open(filtered[i]),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _header(double top, int shown) {
    return Container(
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
          const Positioned.fill(child: CustomPaint(painter: PitchPainter())),
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
                _loading ? 'Loading…' : '$shown live channels',
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
                      borderSide:
                          BorderSide(color: Ui.red.withValues(alpha: .7)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(Map<ChannelCategory, List<Channel>> groups) => [
        for (final cat in _categoryOrder)
          if (groups.containsKey(cat)) ..._row(cat, groups[cat]!),
      ];

  /// One category: header (tap = open the whole category) + a horizontal
  /// strip of cards ending with a "See all" tile.
  List<Widget> _row(ChannelCategory cat, List<Channel> list) {
    final shown = list.length > _rowPreview ? _rowPreview : list.length;
    final more = list.length > shown;
    return [
      SliverToBoxAdapter(
        child: InkWell(
          onTap: more ? () => _selectCat(cat) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(cat.icon, size: 17, color: Ui.redSoft),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(cat.label,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w900)),
                ),
                Text('${list.length}',
                    style: TextStyle(
                        color: Ui.dim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
                if (more) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: Ui.muted),
                ],
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown + (more ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == shown) {
                return _SeeAllCard(
                  label: 'See all ${list.length}',
                  icon: cat.icon,
                  onTap: () => _selectCat(cat),
                );
              }
              return _ChannelCard(
                width: _rowCardWidth,
                channel: list[i],
                onTap: () => _open(list[i]),
              );
            },
          ),
        ),
      ),
    ];
  }
}

// ------------------------------------------------------------------ cards

class _ChannelCard extends StatelessWidget {
  final Channel channel;
  final VoidCallback onTap;
  final double? width;
  const _ChannelCard({required this.channel, required this.onTap, this.width});

  @override
  Widget build(BuildContext context) {
    final quality = channel.qualityLabel;
    final meta = [
      if (channel.flag.isNotEmpty) channel.flag,
      if (channel.country != null && channel.flag.isNotEmpty)
        channel.country!
      else
        channel.category.label,
    ].join(' ');

    return SizedBox(
      width: width,
      height: _cardHeight,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Ui.card, Ui.cardDeep],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ui.red.withValues(alpha: .20)),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo area.
                SizedBox(
                  height: 92,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Ui.red.withValues(alpha: .20),
                              Ui.red.withValues(alpha: .04),
                            ],
                          ),
                        ),
                      ),
                      Center(child: _Logo(channel: channel)),
                      const Positioned(top: 8, left: 8, child: _LivePill()),
                      if (quality.isNotEmpty)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _Badge(quality),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Ui.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Channel logo on a light tile (most logos are made for light backgrounds),
/// or a category icon / initial when there is no logo or it fails to load.
class _Logo extends StatelessWidget {
  final Channel channel;
  const _Logo({required this.channel});

  @override
  Widget build(BuildContext context) {
    final url = channel.logo ?? '';
    final fallback = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Ui.red.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.red.withValues(alpha: .3)),
      ),
      child: Icon(channel.category.icon, color: Ui.redSoft, size: 26),
    );
    if (url.isEmpty) return fallback;
    return Container(
      width: 74,
      height: 54,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        cacheWidth: 160,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(channel.category.icon,
            color: Colors.black45, size: 24),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: Ui.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text('LIVE',
              style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
              color: Colors.white)),
    );
  }
}

class _SeeAllCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SeeAllCard(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: _cardHeight,
      child: Material(
        color: Ui.red.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.red.withValues(alpha: .3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_circle_right_rounded,
                    size: 32, color: Ui.redSoft),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Ui.redSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
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
