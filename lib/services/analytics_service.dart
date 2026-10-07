import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import '../config.dart';
import 'install_id.dart';

/// Anonymous "app opened" ping sent to the Cloudflare Worker (`POST /analytics`).
///
/// Only a random install id, the app version and the platform are sent. It
/// never throws and never blocks app startup; if [AppConfig.feedBase] is empty
/// or the network is down it silently does nothing.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  bool _sent = false;

  /// Records one `app_open` event per app launch.
  Future<void> trackAppOpen() async {
    if (_sent) return;
    _sent = true;

    final base = AppConfig.feedBase.trim();
    if (base.isEmpty) return;

    try {
      final installId = await InstallId.get();
      final uri = Uri.parse(
        '${base.replaceAll(RegExp(r'/+$'), '')}/analytics',
      );

      await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': 'app_open',
              'installId': installId,
              'appVersion': AppConfig.appVersion,
              'platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Analytics must never affect the app.
    }
  }
}
