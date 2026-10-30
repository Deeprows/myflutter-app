import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/mini_player.dart';
import '../services/content_sync.dart';
import '../services/notice_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/brand_tag.dart';
import 'fan_zone_screen.dart';
import 'fan_profile_screen.dart';
import '../services/auth_service.dart';
import 'ai_predict_screen.dart';
import 'content_shortcut_screen.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import '../utils/l10n.dart';

/// Live, predictions, weekly ranks, community posts and AI analysis.
class ShellScreen extends StatefulWidget {
  final VoidCallback? onHome;
  const ShellScreen({super.key, this.onHome});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int _index = 0;
  // Bottom bar order: Live, Home, Predict, AI Predict, Profile.
  // Ranks (index 2) now lives on the Predict page instead of the bottom bar.
  static const _order = [0, 3, 1, 4, 5];
  bool _profilePrompting = false;
  int _profileRev = 0;
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

  // The first time a person taps Home, show their profile editor. After that
  // it never appears again; they use the Profile tab to edit later.
  Future<void> _maybeShowFirstProfile() async {
    if (_profilePrompting) return;
    final uid = AuthService.instance.user?.id ?? '';
    if (uid.isEmpty) return;
    _profilePrompting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'profile_setup_seen_$uid';
      if (prefs.getBool(key) ?? false) return;
      if (!mounted) return;
      final result = await showFirstTimeProfileEditor(context, uid);
      if (result == null) return; // could not open (offline): ask next time
      await prefs.setBool(key, true);
      if (result && mounted) {
        setState(() => _profileRev++);
        ContentSync.request(force: true);
      }
    } catch (_) {
    } finally {
      _profilePrompting = false;
    }
  }

  void _onBack() {
    final state = _scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) {
      state.closeDrawer();
      return;
    }
    if (widget.onHome != null) {
      widget.onHome!();
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
        drawer: FootboliveDrawer(onHome: widget.onHome),
        extendBody: false,
        body: Stack(
          children: [
            IndexedStack(
              index: _index,
              children: [
                const LiveScreen(),
                FanZoneScreen(active: _index == 1),
                // Index 2 (Ranks) is no longer a tab; keep the slot so the
                // other indexes (and notification targets) stay the same.
                const SizedBox.shrink(),
                FanZoneScreen(active: _index == 3, page: FanZonePage.banter),
                AiPredictScreen(active: _index == 4),
                FanProfileScreen(
                  key: ValueKey(
                    'profile-${AuthService.instance.user?.id ?? ''}-$_profileRev',
                  ),
                  userId: AuthService.instance.user?.id ?? '',
                ),
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
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
                    (states) {
                      final on = states.contains(WidgetState.selected);
                      return TextStyle(
                        fontSize: 11,
                        height: 1.0,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? Ui.red : Ui.dim,
                      );
                    },
                  ),
                  iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
                    (states) => IconThemeData(
                      size: 26,
                      color: states.contains(WidgetState.selected)
                          ? Ui.red
                          : Ui.dim,
                    ),
                  ),
                ),
                child: NavigationBar(
                height: 72,
                backgroundColor: Ui.bg,
                indicatorColor: Colors.transparent,
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: _order.contains(_index)
                    ? _order.indexOf(_index)
                    : 0,
                onDestinationSelected: (i) {
                  final target = _order[i];
                  setState(() => _index = target);
                  if (target == 3) _maybeShowFirstProfile();
                },
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
                    icon: const Icon(Icons.auto_awesome_outlined),
                    selectedIcon: const Icon(Icons.auto_awesome_rounded),
                    label: 'AI Predict'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.person_outline_rounded),
                    selectedIcon: const Icon(Icons.person_rounded),
                    label: 'Profile'.tr,
                  ),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
