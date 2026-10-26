import 'dart:async';
import 'package:flutter/material.dart';
import '../player/mini_player.dart';
import '../services/auth_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'ai_predict_screen.dart';
import 'fan_profile_screen.dart';
import 'fan_zone_screen.dart';

/// A separate social experience; all navigation destinations are functional.
class CommunityShellScreen extends StatefulWidget {
  final VoidCallback onHome;
  const CommunityShellScreen({super.key, required this.onHome});
  @override
  State<CommunityShellScreen> createState() => _CommunityShellScreenState();
}

class _CommunityShellScreenState extends State<CommunityShellScreen>
    with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  int _index = 0;
  Timer? _sync;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ContentSync.request(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ContentSync.request(force: true);
  }

  @override
  void dispose() {
    _sync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _menu() => _scaffold.currentState?.openDrawer();
  void _back() {
    if (_scaffold.currentState?.isDrawerOpen == true) {
      _scaffold.currentState!.closeDrawer();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    widget.onHome();
  }

  @override
  Widget build(BuildContext context) {
    final id = AuthService.instance.user?.id ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: _scaffold,
        backgroundColor: Ui.bg,
        drawer: FootboliveDrawer(onHome: widget.onHome),
        body: IndexedStack(
          index: _index,
          children: [
            FanZoneScreen(
              active: _index == 0,
              page: FanZonePage.banter,
              onOpenMenu: _menu,
              onExit: widget.onHome,
            ),
            FanZoneScreen(
              active: _index == 1,
              page: FanZonePage.predict,
              onOpenMenu: _menu,
              onExit: widget.onHome,
            ),
            FanZoneScreen(
              active: _index == 2,
              page: FanZonePage.ranks,
              onPredict: () => setState(() => _index = 1),
              onOpenMenu: _menu,
              onExit: widget.onHome,
            ),
            AiPredictScreen(active: _index == 3),
            _index == 4 && id.isNotEmpty
                ? FanProfileScreen(userId: id)
                : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Ui.line, width: .6)),
              ),
              child: NavigationBar(
                height: 64,
                backgroundColor: Ui.bg,
                indicatorColor: Colors.transparent,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sports_score_outlined),
                    selectedIcon: Icon(Icons.sports_score_rounded),
                    label: 'Predict',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.leaderboard_outlined),
                    selectedIcon: Icon(Icons.leaderboard_rounded),
                    label: 'Ranks',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome_rounded),
                    label: 'AI Predict',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
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
