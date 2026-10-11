import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/start_gate.dart';
import 'services/app_nav.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_watermark.dart';

class FootboliveApp extends StatelessWidget {
  const FootboliveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeController.index,
      builder: (_, _, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        navigatorKey: AppNav.key,
        scaffoldMessengerKey: PushService.messengerKey,
        theme: buildTheme(),
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const ThemeWatermark(),
          ],
        ),
        home: const StartGate(),
      ),
    );
  }
}
