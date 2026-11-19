import 'package:flutter/services.dart';

/// Android Google Cast sender bridge. Discovery and session lifecycle are
/// handled by Google's Cast Framework; no DLNA assumptions are made here.
class GoogleCastService {
  GoogleCastService._();
  static const MethodChannel _channel = MethodChannel('footbolive/google_cast');

  static Future<bool> get available async {
    try { return await _channel.invokeMethod<bool>('isAvailable') ?? false; }
    on PlatformException { return false; }
  }

  static Future<void> showPicker() => _channel.invokeMethod<void>('showPicker');

  static Future<bool> load({required String url, required String title,
    required String contentType, required bool live}) async {
    try {
      return await _channel.invokeMethod<bool>('loadMedia', {
        'url': url, 'title': title, 'contentType': contentType, 'live': live,
      }) ?? false;
    } on PlatformException { return false; }
  }

  static Future<void> _safeCall(String method, [Map<String, Object?>? args]) async {
    try { await _channel.invokeMethod<void>(method, args); } on PlatformException { /* Session may have ended. */ }
  }

  static Future<void> play() => _safeCall('play');
  static Future<void> pause() => _safeCall('pause');
  static Future<void> stop() => _safeCall('stop');
  static Future<void> seek(int milliseconds) => _safeCall('seek', {'position': milliseconds});
  static Future<void> setVolume(double volume) => _safeCall('setVolume', {'volume': volume.clamp(0, 1)});
  static Future<Map<dynamic, dynamic>> status() async =>
      await _channel.invokeMapMethod<dynamic, dynamic>('status') ?? {};
}
