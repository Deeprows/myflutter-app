import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/channel.dart';
import '../services/favorites_service.dart';
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
import '../utils/l10n.dart';

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
const _cardHeight = 46.0; // wide pill buttons: round logo + channel name
const _rowCardWidth = 160.0;

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
  bool _favOnly = false; // showing only the starred channels
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
    FavoriteChannels.instance.keys.addListener(_onFav);
    FavoriteChannels.instance.load();
  }

  void _onFav() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleFav(Channel c) async {
    final added = await FavoriteChannels.instance.toggle(c);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
        content: Text(
            added ? 'Added to favourites'.tr : 'Removed from favourites'.tr),
      ));
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

  @override
  void dispose() {
    ContentSync.tick.removeListener(_onSync);
    FavoriteChannels.instance.keys.removeListener(_onFav);
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
              title: Text('All countries'.tr),
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
    setState(() {
      _cat = c;
      _favOnly = false;
    });
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

    // Starred channels (from every country / category), filtered by search.
    final favKeys = FavoriteChannels.instance.keys.value;
    final allFavs = _all
        .where((c) => favKeys.contains(FavoriteChannels.keyOf(c)))
        .toList();
    final favs = allFavs
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .toList();

    final filtered = _favOnly
        ? favs
        : base.where((c) {
            if (_cat != null && c.category != _cat) return false;
            return q.isEmpty || c.name.toLowerCase().contains(q);
          }).toList();

    final groups = <ChannelCategory, List<Channel>>{};
    for (final c in filtered) {
      groups.putIfAbsent(c.category, () => []).add(c);
    }

    // Rows (Netflix style) when browsing everything; a grid when a category
    // is picked or the user is searching.
    final showRows = !_favOnly && _cat == null && q.isEmpty;
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
                  _Pill('All'.tr, base.length, _cat == null && !_favOnly,
                      () => _selectCat(null)),
                  if (allFavs.isNotEmpty || _favOnly)
                    _Pill('Favourites'.tr, allFavs.length, _favOnly,
                        () => setState(() {
                              _favOnly = true;
                              _cat = null;
                            }),
                        icon: Icons.star_rounded),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _favOnly && q.isEmpty
                          ? 'No favourite channels yet. Tap the star on any channel to save it here.'
                              .tr
                          : 'No channels found'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            )
          else if (showRows)
            ..._rows(groups, favs)
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
                  fav: favKeys.contains(FavoriteChannels.keyOf(filtered[i])),
                  onFav: () => _toggleFav(filtered[i]),
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
                  Expanded(
                    child: Text('TV Channels'.tr,
                        style: const TextStyle(
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
                    hintText: 'Search channels'.tr,
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

  List<Widget> _rows(
          Map<ChannelCategory, List<Channel>> groups, List<Channel> favs) =>
      [
        if (favs.isNotEmpty)
          ..._row(
            null,
            favs,
            title: 'Favourites'.tr,
            icon: Icons.star_rounded,
            onMore: () => setState(() => _favOnly = true),
          ),
        for (final cat in _categoryOrder)
          if (groups.containsKey(cat)) ..._row(cat, groups[cat]!),
      ];

  /// One category: header (tap = open the whole category) + a horizontal
  /// strip of cards ending with a "See all" tile.
  List<Widget> _row(
    ChannelCategory? cat,
    List<Channel> list, {
    String? title,
    IconData? icon,
    VoidCallback? onMore,
  }) {
    final rowTitle = title ?? cat!.label;
    final rowIcon = icon ?? cat!.icon;
    final seeAll = onMore ?? () => _selectCat(cat);
    final favKeys = FavoriteChannels.instance.keys.value;
    final shown = list.length > _rowPreview ? _rowPreview : list.length;
    final more = list.length > shown;
    return [
      SliverToBoxAdapter(
        child: InkWell(
          onTap: more ? seeAll : null,
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
                  child: Icon(rowIcon, size: 17, color: Ui.redSoft),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(rowTitle,
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
                  icon: rowIcon,
                  onTap: seeAll,
                );
              }
              return _ChannelCard(
                width: _rowCardWidth,
                channel: list[i],
                onTap: () => _open(list[i]),
                fav: favKeys.contains(FavoriteChannels.keyOf(list[i])),
                onFav: () => _toggleFav(list[i]),
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
  final bool fav;
  final VoidCallback onFav;
  const _ChannelCard({
    required this.channel,
    required this.onTap,
    required this.onFav,
    this.fav = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: _cardHeight,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Ui.red.withValues(alpha: .8), width: 1.2),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 2, 0),
              child: Row(
                children: [
                  _Logo(channel: channel),
                  const SizedBox(width: 6),
                  Expanded(child: _MarqueeText(channel.name)),
                  // Star: bookmark / un-bookmark this channel.
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      splashRadius: 16,
                      tooltip: fav
                          ? 'Remove from favourites'.tr
                          : 'Add to favourites'.tr,
                      onPressed: onFav,
                      icon: Icon(
                        fav ? Icons.star_rounded : Icons.star_border_rounded,
                        color: fav ? const Color(0xFFFFC107) : Ui.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round channel logo with an accent ring (like the reference design), or a
/// category icon when there is no logo or it fails to load.
class _Logo extends StatelessWidget {
  final Channel channel;
  const _Logo({required this.channel});

  static const _size = 32.0;

  @override
  Widget build(BuildContext context) {
    final url = channel.logo ?? '';
    final icon = Icon(channel.category.icon, color: Ui.redSoft, size: 17);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: url.isEmpty ? Ui.red.withValues(alpha: .16) : Colors.white,
        border: Border.all(color: Ui.red, width: 1.3),
      ),
      child: url.isEmpty
          ? Center(child: icon)
          : ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(2.5),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  cacheWidth: 120,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Center(child: icon),
                ),
              ),
            ),
    );
  }
}

/// Channel name, centred. A name too long for the button slowly scrolls
/// sideways (with soft faded edges) so it can still be read in full.
class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText(this.text);

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  static const _style =
      TextStyle(fontSize: 13.5, height: 1.1, fontWeight: FontWeight.w800);

  final _scroll = ScrollController();
  bool _alive = true;
  bool _running = false;

  @override
  void dispose() {
    _alive = false;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loop() async {
    if (_running) return;
    _running = true;
    while (_alive) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!_alive || !_scroll.hasClients) break;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) break;
      await _scroll.animateTo(
        max,
        duration: Duration(milliseconds: (max * 28).round().clamp(900, 9000)),
        curve: Curves.linear,
      );
      if (!_alive || !_scroll.hasClients) break;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!_alive || !_scroll.hasClients) break;
      _scroll.jumpTo(0);
    }
    _running = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final overflows = painter.width > box.maxWidth;
        if (!overflows) {
          return Center(
            child: Text(widget.text,
                maxLines: 1, softWrap: false, style: _style),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loop());
        });
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [
              Color(0x00FFFFFF),
              Colors.white,
              Colors.white,
              Color(0x00FFFFFF),
            ],
            stops: [0, .08, .92, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                heightFactor: 1,
                child: Text(widget.text,
                    maxLines: 1, softWrap: false, style: _style),
              ),
            ),
          ),
        );
      },
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
      width: 118,
      height: _cardHeight,
      child: Material(
        color: Ui.red.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.red.withValues(alpha: .5), width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_circle_right_rounded,
                    size: 24, color: Ui.redSoft),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
