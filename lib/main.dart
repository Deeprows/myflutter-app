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
  // Firebase + background handler first (needed to receive alerts while the
  // app is closed). Failures are recorded, never thrown.
  await PushService.instance.initCore();
  runApp(const FootboliveApp());
  // Permission prompt, token and topics; never blocks app start.
  unawaited(PushService.instance.init());
}
