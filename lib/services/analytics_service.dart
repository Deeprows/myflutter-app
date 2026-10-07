import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  static const _installIdKey = 'analytics_install_id';

  Future<void> trackAppOpen() async {
    final base = AppConfig.feedBase.trim();

    if (base.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      var installId = prefs.getString(_installIdKey);

      if (installId == null || installId.isEmpty) {
        installId = _createInstallId();
        await prefs.setString(_installIdKey, installId);
      }

      await http
          .post(
            Uri.parse('$base/analytics'),
            headers: {
              'content-type': 'application/json',
            },
            body: '''
{
  "event": "app_open",
  "installId": "$installId",
  "appVersion": "${AppConfig.appVersion}",
  "platform": "android"
}
''',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Analytics must never prevent the app from opening.
    }
  }

  String _createInstallId() {
    final random = Random.secure();

    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
