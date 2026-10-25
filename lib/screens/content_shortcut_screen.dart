import 'package:flutter/material.dart';

import '../player/mini_player.dart';
import '../theme/app_theme.dart';

/// Full content pages keep an explicit way back to the community tab.
class ContentShortcutScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const ContentShortcutScreen({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(title: Text(title)),
    body: MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: child,
    ),
    bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
  );
}
