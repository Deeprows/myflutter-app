import 'package:flutter/services.dart';

/// Shows real Android notifications (status bar / tray) even while the app is
/// open, and reports taps on them. Implemented in MainActivity by
/// tool/patch_main_activity.py (channel "footbolive/notify").
class NativeNotifier {
  static const _channel = MethodChannel('footbolive/notify');
  static bool _hooked = false;

  /// [onTap] receives the JSON payload of a tapped notification.
  static void listen(void Function(String payload) onTap) {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap' && call.arguments is String) {
        onTap(call.arguments as String);
      }
      return null;
    });
  }

  /// Payload of the notification that launched the app (cold start), once.
  static Future<String?> launchPayload() async {
    try {
      return await _channel.invokeMethod<String>('launchPayload');
    } catch (_) {
      return null;
    }
  }

  /// False when it could not be shown (no permission / old native code).
  static Future<bool> show({
    required String title,
    required String body,
    required String channel,
    required String payload,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'title': title,
            'body': body,
            'channel': channel,
            'payload': payload,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
