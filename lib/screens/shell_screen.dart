import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';

import '../player/mini_player.dart';
import '../services/app_memory.dart';
import '../services/content_sync.dart';
import '../services/notice_service.dart';
import '../services/manual_ad_service.dart';
import '../services/subscription_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/brand_tag.dart';
import 'fan_thread_screen.dart';
import 'fan_zone_screen.dart';
import 'fan_profile_screen.dart';
import '../services/auth_service.dart';
import 'ai_predict_screen.dart';
import 'auth_screen.dart';
import 'content_shortcut_screen.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import 'tv_screen.dart';
import 'search_screen.dart';
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
  // Bottom bar order: Live, Thread, AI Predict, Match Room, Profile, Search.
  // Stack slots keep their old numbers so notification targets still work:
  // 0 Live, 3 Thread, 4 AI Predict, 6 TV, 8 Search, 9 Profile. Movies (7) is
  // no longer a tab: it opens from the TV Channels header. Predict (1) opens
  // from the Thread header; Highlights from the Live header.
  static const _order = [0, 3, 4, 6, 9, 8];
  static const _tvTab = 6;
  static const _searchTab = 8;
  static const _profileTab = 9;
  final Set<int> _visited = {0};
  bool _profilePrompting = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBack;
  Timer? _autoRefresh;
  Timer? _manualAdTimer;
  bool _manualAdShowing = false;
  bool _highlightsOpen = false;
  bool _moviesOpen = false;

  @override
  void initState() {
    super.initState();
    // Which page (if any) was open on top of the tab when the app last closed.
    PageMemory.captureLaunch();
    final lastPost = PageMemory.consume('post');
    if (lastPost != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FanThreadScreen(postId: '${lastPost['id']}'),
          ),
        );
      });
    }
    // Reopen on the tab the user was last on.
    final savedTab = AppMemory.getInt('tab');
    if (savedTab != null && _order.contains(savedTab)) {
      _index = savedTab;
      _visited.add(savedTab);
    }
    // A notification tap that launched the app, or one tapped while open.
    final pending = PushService.instance.tabRequest.value;
    if (pending != null) {
      _index = _tabFor(pending);
      _visited.add(_index);
      AppMemory.setInt('tab', _index);
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

    // Telegram invite repeats on app opening until the user taps Join.
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (mounted) await _showTelegramInvite();
      if (mounted) NoticeService.instance.showOnStart(context);
      if (mounted) _scheduleManualAd();
    });
  }

  Future<void> _showTelegramInvite() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('telegram_join_clicked') == true || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Theme(
        // The card is always dark, so everything inside uses the dark theme
        // (otherwise light-theme text colours can leak in as dark-on-dark).
        data: ThemeData.dark(useMaterial3: true),
        child: Dialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF36AEEA), Color(0xFF1677D2)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.telegram_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 18),
              Text('Join Deeprowss on Telegram',
                textAlign: TextAlign.center,
                style: const TextStyle(inherit: false, color: Colors.white, fontSize: 22, height: 1.25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              const Text('Get updates, new features, match alerts and announcements from our official community.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB8C4D6), height: 1.45)),
              const SizedBox(height: 22),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF229ED9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.telegram_rounded),
                  label: const Text('JOIN TELEGRAM', style: TextStyle(fontWeight: FontWeight.w900)),
                  onPressed: () async {
                    final uri = Uri.parse(AppConfig.joinUrl);
                    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                      await prefs.setBool('telegram_join_clicked', true);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    }
                  },
                )),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Maybe later', style: TextStyle(color: Color(0xFF9AA8BC))),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _scheduleManualAd() {
    _manualAdTimer?.cancel();
    if (!mounted || SubscriptionService.instance.isPremium) return;
    // Telegram's dialog has now appeared and been dismissed; wait two minutes.
    _manualAdTimer = Timer(const Duration(minutes: 2), () async {
      await _showManualAd();
      if (!mounted) return;
      // Repeat every ten minutes, independently of the existing support ad.
      _manualAdTimer = Timer.periodic(const Duration(minutes: 10), (_) {
        _showManualAd();
      });
    });
  }

  Future<void> _showManualAd() async {
    if (!mounted || _manualAdShowing || SubscriptionService.instance.isPremium) return;
    _manualAdShowing = true;
    try {
      await ManualAdService.instance.show(context);
    } finally {
      _manualAdShowing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ContentSync.request(force: true);
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _manualAdTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.tabRequest.removeListener(_openRequestedTab);
    super.dispose();
  }

  void _openRequestedTab() {
    final tab = PushService.instance.tabRequest.value;
    if (tab == null) return;
    PushService.instance.tabRequest.value = null;
    final target = _tabFor(tab);
    if (mounted && target != _index) {
      setState(() {
        _index = target;
        _visited.add(target);
      });
      AppMemory.setInt('tab', target);
    }
    if (tab == 1) _openHighlights();
    if (tab == 3) _openMovies();
  }

  // Old notification tab numbers -> the tabs that exist now.
  int _tabFor(int tab) {
    switch (tab) {
      case 3:
      case 1:
      case 2:
      case 5:
        return 0; // Highlights and Movies open on top of Live
      default:
        return tab;
    }
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

  // Movie notifications open the Movies page on top of the current tab.
  void _openMovies() {
    if (_moviesOpen) return;
    _moviesOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ContentShortcutScreen(
            title: 'Movies',
            child: MoviesScreen(),
          ),
        ),
      );
      _moviesOpen = false;
    });
  }

  Widget _profilePage() {
    final id = AuthService.instance.user?.id ?? '';
    if (id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Profile'.tr)),
        body: Center(
          child: FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
              );
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in'),
          ),
        ),
      );
    }
    return FanProfileScreen(key: ValueKey(id), userId: id, embedded: true);
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
      if (result && mounted) ContentSync.request(force: true);
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

  /// One bottom-bar item: icon over a single-line label. The label shrinks
  /// to fit its slot and ignores the phone's font scale, so long names such
  /// as "Match Room" never wrap or break mid-word.
  Widget _navItem(IconData icon, String label, bool selected) {
    final color = selected
        ? Ui.red
        : (Ui.isLight ? const Color(0xFF3B4250) : Ui.navOff);
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<NavigationDestination> _navDestinations() {
    final items = <(IconData, IconData, String)>[
      (Icons.sensors_rounded, Icons.sensors_rounded, 'Live'.tr),
      (Icons.forum_rounded, Icons.forum_rounded, 'Thread'.tr),
      (Icons.auto_awesome_rounded, Icons.auto_awesome_rounded, 'AI Predict'.tr),
      (Icons.groups_rounded, Icons.groups_rounded, 'Match Room'.tr),
      (Icons.person_rounded, Icons.person_rounded, 'Profile'.tr),
      (Icons.search_rounded, Icons.search_rounded, 'Search'.tr),
    ];
    return [
      for (final it in items)
        NavigationDestination(
          icon: _navItem(it.$1, it.$3, false),
          selectedIcon: _navItem(it.$2, it.$3, true),
          label: it.$3,
        ),
    ];
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
                // Slots 1, 2 and 5 are no longer tabs; kept so the other
                // indexes (and notification targets) stay the same.
                const SizedBox.shrink(),
                const SizedBox.shrink(),
                FanZoneScreen(
                  active: _index == 3,
                  page: FanZonePage.banter,
                  threadHeader: true,
                ),
                AiPredictScreen(active: _index == 4),
                const SizedBox.shrink(),
                // Match Room: live match rooms as cards.
                _visited.contains(_tvTab)
                    ? FanZoneScreen(
                        active: _index == _tvTab,
                        page: FanZonePage.rooms,
                        embedded: true,
                      )
                    : const SizedBox.shrink(),
                // Slot 7 (Movies) is no longer a tab.
                const SizedBox.shrink(),
                _visited.contains(_searchTab)
                    ? const SearchScreen()
                    : const SizedBox.shrink(),
                _visited.contains(_profileTab)
                    ? _profilePage()
                    : const SizedBox.shrink(),
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
                        fontSize: 10,
                        height: 1.0,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                        color: on ? Ui.red : Ui.navOff,
                      );
                    },
                  ),
                  iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
                    (states) => IconThemeData(
                      size: 26,
                      color: states.contains(WidgetState.selected)
                          ? Ui.red
                          : Ui.navOff,
                    ),
                  ),
                ),
                child: NavigationBar(
                height: 72,
                backgroundColor: Ui.isLight ? Ui.panel : Ui.bg,
                indicatorColor: Colors.transparent,
                // Labels are drawn by _navItem (auto-shrinking, one line).
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysHide,
                selectedIndex: _order.contains(_index)
                    ? _order.indexOf(_index)
                    : 0,
                onDestinationSelected: (i) {
                  final target = _order[i];
                  setState(() {
                    _index = target;
                    _visited.add(target);
                  });
                  AppMemory.setInt('tab', target);
                  if (target == 3) _maybeShowFirstProfile();
                },
                destinations: _navDestinations(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
