import 'package:flutter/material.dart';

import '../player/mini_player.dart';
import '../theme/app_theme.dart';
import 'highlights_screen.dart';
import 'live_screen.dart';
import 'tv_screen.dart';

/// Full content pages keep an explicit way back to the community tab.
///
/// Live Now, TV Channels and Football Highlights draw their own header, so the
/// extra top bar (arrow + title) is not shown on them.
class ContentShortcutScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const ContentShortcutScreen({
    super.key,
    required this.title,
    required this.child,
  });

  bool get _ownHeader =>
      child is LiveScreen || child is TvScreen || child is HighlightsScreen;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: _ownHeader ? null : AppBar(title: Text(title)),
    body: _ownHeader
        ? child
        : MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
    bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
  );
}
