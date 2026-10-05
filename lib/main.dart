import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/download_manager.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await ThemeController.load();
  await DownloadManager.instance.init();
  runApp(const FootboliveApp());
  // Firebase push notifications; never blocks or crashes app start.
  unawaited(PushService.instance.init());
}
