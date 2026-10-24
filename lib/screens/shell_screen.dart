import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../player/mini_player.dart';
import '../player/player_hub_screen.dart';
import '../services/content_sync.dart';
import '../services/notice_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/brand_tag.dart';
import 'fan_zone_screen.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import 'tv_screen.dart';
import '../utils/l10n.dart';

/// The whole app: Football Live, Fan Zone, TV channels and Movies.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBack;
  Timer? _autoRefresh;
  bool _highlightsOpen = false;

  @override
  void initState() {
    super.initState();
    // A notification tap that launched the app, or one tapped while open.
    final pending = PushService.instance.tabRequest.value;
    if (pending != null) {
      _index = pending;
      PushService.instance.tabRequest.value = null;
      if (pending == 1) _openHighlights();
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
  }

  // Highlight notifications still open their original content after tab 1
  // becomes Fan Zone. Wait until the notification target has been assigned.
  void _openHighlights() {
    if (_highlightsOpen) return;
    _highlightsOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const HighlightsScreen()));
      _highlightsOpen = false;
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
                const TvScreen(),
                const MoviesScreen(),
                PlayerHubScreen(active: _index == 4),
              ],
            ),
            // Small brand mark, bottom right, on the Live and Movies screens.
            if (_index == 0 || _index == 3)
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
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.sensors_rounded),
                    label: 'Live'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.groups_outlined),
                    selectedIcon: const Icon(Icons.groups_rounded),
                    label: 'Fan Zone'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.live_tv_outlined),
                    selectedIcon: const Icon(Icons.live_tv_rounded),
                    label: 'TV'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.movie_outlined),
                    selectedIcon: const Icon(Icons.movie_rounded),
                    label: 'Movies'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.video_library_outlined),
                    selectedIcon: const Icon(Icons.video_library_rounded),
                    label: 'Player'.tr,
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
