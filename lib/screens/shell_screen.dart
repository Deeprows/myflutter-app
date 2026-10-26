import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../player/mini_player.dart';
import '../services/content_sync.dart';
import '../services/notice_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/brand_tag.dart';
import 'fan_zone_screen.dart';
import 'ai_predict_screen.dart';
import 'content_shortcut_screen.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import '../utils/l10n.dart';

/// Live, predictions, weekly ranks, community posts and AI analysis.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int _index = 0;
  // Bottom bar order: Live, Home (feed), Predict, Ranks, AI. The numbers are
  // positions in the IndexedStack, kept so push-notification tabs still work.
  static const _order = [0, 3, 1, 2, 4];
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBack;
  Timer? _autoRefresh;
  bool _highlightsOpen = false;
  bool _moviesOpen = false;

  @override
  void initState() {
    super.initState();
    // A notification tap that launched the app, or one tapped while open.
    final pending = PushService.instance.tabRequest.value;
    if (pending != null) {
      _index = pending;
      PushService.instance.tabRequest.value = null;
      if (pending == 1) _openHighlights();
      if (pending == 3) _openMovies();
    }
    PushService.instance.tabRequest.addListener(_openRequestedTab);

    // Keep every list current without the person having to pull down.
    WidgetsBinding.instance.addObserver(this);
    _autoRefresh = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ContentSync.request(),
    );

    // notice.json: pop up once per notice id, a moment after the app opens.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) NoticeService.instance.showOnStart(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ContentSync.request(force: true);
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.tabRequest.removeListener(_openRequestedTab);
    super.dispose();
  }

  void _openRequestedTab() {
    final tab = PushService.instance.tabRequest.value;
    if (tab == null) return;
    PushService.instance.tabRequest.value = null;
    if (mounted && tab != _index) setState(() => _index = tab);
    if (tab == 1) _openHighlights();
    if (tab == 3) _openMovies();
  }

  // Highlight notifications still open their original content after tab 1
  // becomes Fan Zone. Wait until the notification target has been assigned.
  void _openHighlights() {
    if (_highlightsOpen) return;
    _highlightsOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ContentShortcutScreen(
            title: 'Highlights',
            child: HighlightsScreen(),
          ),
        ),
      );
      _highlightsOpen = false;
    });
  }

  void _openMovies() {
    if (_moviesOpen) return;
    _moviesOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ContentShortcutScreen(
              title: 'Movies',
              child: MoviesScreen(),
            ),
          ),
        );
      } finally {
        _moviesOpen = false;
      }
    });
  }

  void _onBack() {
    final state = _scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) {
      state.closeDrawer();
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Tap back more to exit'.tr),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const FootboliveDrawer(),
        extendBody: false,
        body: Stack(
          children: [
            IndexedStack(
              index: _index,
              children: [
                const LiveScreen(),
                FanZoneScreen(active: _index == 1),
                FanZoneScreen(
                  active: _index == 2,
                  page: FanZonePage.ranks,
                  onPredict: () => setState(() => _index = 1),
                ),
                FanZoneScreen(active: _index == 3, page: FanZonePage.banter),
                AiPredictScreen(active: _index == 4),
              ],
            ),
            // Small brand mark on Live.
            if (_index == 0)
              const Positioned(right: 8, bottom: 6, child: BrandTag()),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Ui.line)),
              ),
              child: NavigationBar(
                height: 62,
                backgroundColor: Ui.bg,
                indicatorColor: Colors.transparent,
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                selectedIndex: _order.contains(_index) ? _order.indexOf(_index) : 0,
                onDestinationSelected: (i) =>
                    setState(() => _index = _order[i]),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.sensors_rounded),
                    label: 'Live'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: 'Home'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.sports_soccer_outlined),
                    selectedIcon: const Icon(Icons.sports_soccer_rounded),
                    label: 'Predict'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.leaderboard_outlined),
                    selectedIcon: const Icon(Icons.leaderboard_rounded),
                    label: 'Ranks'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.auto_awesome_outlined),
                    selectedIcon: const Icon(Icons.auto_awesome_rounded),
                    label: 'AI Predict'.tr,
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
