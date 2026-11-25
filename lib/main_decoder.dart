import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'decoder_app.dart';
import 'services/ad_unlock.dart';
import 'services/app_memory.dart';
import 'services/auth_service.dart';
import 'services/download_manager.dart';
import 'services/locale_service.dart';
import 'services/push_service.dart';
import 'services/remote_config.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

/// Independent Decoder entry point. It reuses the existing TV, Movies,
/// Decoder and Premium services without loading the sports/community shell.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await ThemeController.load();
  await AppMemory.init();
  await AppLocale.load();
  await RemoteConfig.instance.init();
  await SubscriptionService.instance.init();
  await AdUnlock.instance.load();
  await DownloadManager.instance.init();
  await PushService.instance.initCore();
  unawaited(AuthService.instance.restore());
  runApp(const DecoderApp());
}
