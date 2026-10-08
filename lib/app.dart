import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/start_gate.dart';
import 'services/app_nav.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

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
        home: const StartGate(),
      ),
    );
  }
}
