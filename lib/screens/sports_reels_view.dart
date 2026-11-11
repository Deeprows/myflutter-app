import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/sports_reels_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';

/// Full-height vertical reels (swipe up for the next one) built from trending
/// sports Shorts. Only the reel on screen has a live player.
class SportsReelsView extends StatefulWidget {
  const SportsReelsView({super.key});
  @override
  State<SportsReelsView> createState() => _SportsReelsViewState();
}

class _SportsReelsViewState extends State<SportsReelsView> {
  static const _chips = [
    ('all', 'Trending'),
    ('football', 'Football'),
    ('cricket', 'Cricket'),
    ('f1', 'F1'),
    ('other', 'More sports'),
  ];
  final _page = PageController();
  final _feeds = <String, SportsReelsFeed>{};
  String _cat = 'all';
  bool _loading = false, _failed = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (_loading || (!force && _feeds.containsKey(_cat))) return;
    final cat = _cat;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final feed = await SportsReelsService.load(cat);
      if (mounted) setState(() => _feeds[cat] = feed);
    } catch (_) {
      if (mounted && _cat == cat) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String cat) {
    if (cat == _cat) return;
    setState(() {
      _cat = cat;
      _index = 0;
    });
    if (_page.hasClients) _page.jumpToPage(0);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _feeds[_cat]?.items ?? const <SportsReel>[];
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            children: [
              for (final c in _chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: _cat == c.$1,
                    onSelected: (_) => _pick(c.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isNotEmpty
              ? PageView.builder(
                  controller: _page,
                  scrollDirection: Axis.vertical,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _ReelPage(
                    key: ValueKey('${items[i].id}-${i == _index}'),
                    reel: items[i],
                    active: i == _index,
                  ),
                )
              : Center(
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_circle_outline,
                                  size: 48, color: Ui.dim),
                              const SizedBox(height: 12),
                              Text(
                                _failed
                                    ? 'Could not load reels. Check your connection.'
                                    : 'No trending reels right now.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Ui.muted),
                              ),
                              TextButton(
                                onPressed: () => _load(force: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _ReelPage extends StatefulWidget {
  final SportsReel reel;
  final bool active;
  const _ReelPage({super.key, required this.reel, required this.active});
  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  WebViewController? _web;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  void _start() {
    final id = widget.reel.id;
    final html = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head><body>
<iframe src="https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&controls=0&loop=1&playlist=$id&rel=0&modestbranding=1&fs=0"
 allow="autoplay; encrypted-media" referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>''';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
          // Stay on the embed; never let the page navigate away.
          onNavigationRequest: (r) => r.url.startsWith('about:') ||
                  r.url.startsWith('https://www.youtube.com/embed/') ||
                  r.url.startsWith('https://www.youtube-nocookie.com/embed/')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadHtmlString(html, baseUrl: 'https://www.youtube.com');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        CachedNetworkImage(
          imageUrl: r.thumb,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        ),
        if (_web != null)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _ready ? 1 : 0,
            child: WebViewWidget(controller: _web!),
          ),
        // Title strip at the bottom; touches elsewhere go to the player.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 28, 8, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.channel,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open on YouTube',
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  onPressed: () =>
                      openInApp(context, r.watchUrl, title: r.channel),
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share, color: Colors.white),
                  onPressed: () async {
                    try {
                      await Share.share('${r.title}\n${r.watchUrl}');
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
