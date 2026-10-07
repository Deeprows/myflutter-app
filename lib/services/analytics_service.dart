import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  static const String _endpoint =
      'https://deeprowss-feed.deeprows.workers.dev/analytics';

  static const String _installIdKey = 'deeprowss_install_id';

  static Future<void> appOpened() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      var installId = prefs.getString(_installIdKey);

      if (installId == null || installId.isEmpty) {
        installId = _generateInstallId();
        await prefs.setString(_installIdKey, installId);
      }

      await http.post(
        Uri.parse(_endpoint),
        headers: {
          'content-type': 'application/json',
          'x-install-id': installId,
          'x-app-version': 'dev',
          'x-platform': 'android',
        },
        body: jsonEncode({
          'event': 'app_open',
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Analytics must never prevent the app from starting.
    }
  }

  static String _generateInstallId() {
    final random = Random.secure();

    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
