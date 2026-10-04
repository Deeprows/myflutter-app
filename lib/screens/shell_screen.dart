import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'movies_screen.dart';
import 'tv_screen.dart';

/// The whole app: Football Live, Highlights, TV channels and Movies.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowFirstLaunchCopyright(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const FootboliveDrawer(),
      extendBody: false,
      body: IndexedStack(
        index: _index,
        children: const [
          LiveScreen(),
          HighlightsScreen(),
          TvScreen(),
          MoviesScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Ui.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.sensors_rounded),
              label: 'Live',
            ),
            NavigationDestination(
              icon: Icon(Icons.play_circle_outline_rounded),
              selectedIcon: Icon(Icons.play_circle_rounded),
              label: 'Highlights',
            ),
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined),
              selectedIcon: Icon(Icons.live_tv_rounded),
              label: 'TV',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie_rounded),
              label: 'Movies',
            ),
          ],
        ),
      ),
    );
  }
}
