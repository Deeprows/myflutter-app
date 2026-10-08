import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/analytics_service.dart';
import 'services/download_manager.dart';
import 'services/push_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await ThemeController.load();

  // Free / Premium: reads the saved copy only; the Worker is asked later.
  await SubscriptionService.instance.init();

  await DownloadManager.instance.init();

  // Firebase + background handler first.
  // Failures are recorded, never thrown.
  await PushService.instance.initCore();

  runApp(const FootboliveApp());

  // Analytics never blocks app startup.
  unawaited(
    AnalyticsService.instance.start(),
  );

  // Permission prompt, token and topics; never blocks app start.
  unawaited(
    PushService.instance.init(),
  );
}
