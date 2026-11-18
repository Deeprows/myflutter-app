import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Keeps video/audio playing when the app is minimised or the screen is
/// locked. Starts an Android foreground service (media notification) while a
/// player page is open, so the system doesn't freeze or kill the app. The
/// native side is added by tool/patch_background_playback.py.
class BackgroundPlayback {
  static const _channel = MethodChannel('footbolive/playback');
  static final List<VoidCallback> _stopHandlers = [];
  static bool _hooked = false;

  /// True while the in-app PIN lock covers the app. Play buttons on the
  /// notification / lock screen are ignored meanwhile.
  static bool locked = false;

  /// True while a TV is playing the stream (see CastService). The service
  /// and its CPU / Wi-Fi locks then stay on even when no player page is open,
  /// and notification buttons control the TV through [castHook].
  static bool castActive = false;

  /// Handles notification / lock-screen buttons while casting. Returns true
  /// when it dealt with the action.
  static bool Function(String action)? castHook;

  static String _lastTitle = 'Deeprowss';
  static bool _castHold = false;
  static String? _note;

  /// Pauses the player page that is on screen (used when App Lock engages).
  static void pauseForLock() => _onPause?.call();

  // Handlers of the player page that is on screen (the latest one wins).
  static VoidCallback? _onPlay;
  static VoidCallback? _onPause;
  static void Function(int seconds)? _onSeekBy;

  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'action':
          if (castHook?.call('${call.arguments}') == true) return null;
          switch (call.arguments) {
            case 'play':
              if (!locked) _onPlay?.call();
            case 'pause':
              _onPause?.call();
            case 'rewind':
              _onSeekBy?.call(-10);
            case 'forward':
              _onSeekBy?.call(10);
            case 'stop':
              _fireStop();
          }
        case 'stopRequested': // older native code
          _fireStop();
      }
      return null;
    });
  }

  static void _fireStop() {
    for (final h in List.of(_stopHandlers)) {
      h();
    }
  }

  /// Android 13+ never shows a notification (media controls included) until
  /// the person allows it. Without this the audio keeps playing in the
  /// background but the tray / lock screen player is missing. Safe to call
  /// often: it only asks while the permission is still undecided.
  static Future<bool> ensureNotificationPermission() async {
    try {
      var s = await Permission.notification.status;
      if (s.isDenied) s = await Permission.notification.request();
      return s.isGranted || s.isProvisional;
    } catch (_) {
      return true;
    }
  }

  /// True when the system will actually show our notifications. Android 13+
  /// hides the media card (tray and lock screen) while this is false.
  static Future<bool> notificationsAllowed() async {
    try {
      final s = await Permission.notification.status;
      return s.isGranted || s.isProvisional || s.isLimited;
    } catch (_) {
      return true;
    }
  }

  /// Call when a player page opens. [onStopRequested] runs when the user taps
  /// Stop on the notification. [onPlay] / [onPause] / [onSeekBy] handle the
  /// other notification and lock-screen buttons (seek is +-10 seconds).
  static Future<void> start(
    String title,
    VoidCallback onStopRequested, {
    VoidCallback? onPlay,
    VoidCallback? onPause,
    void Function(int seconds)? onSeekBy,
  }) async {
    _hook();
    if (!_stopHandlers.contains(onStopRequested)) {
      _stopHandlers.add(onStopRequested);
    }
    _onPlay = onPlay;
    _onPause = onPause;
    _onSeekBy = onSeekBy;
    _lastTitle = title;
    await ensureNotificationPermission();
    try {
      await _channel.invokeMethod<bool>(
          'start', {'title': title, 'playing': true, 'note': _note});
    } catch (_) {}
  }

  /// Starts (or keeps) the foreground service for a cast session, without
  /// touching the handlers of the player page that is open.
  static Future<void> startCasting(String title, String note) async {
    _hook();
    _castHold = true;
    _note = note;
    await ensureNotificationPermission();
    try {
      await _channel.invokeMethod<bool>(
          'start', {'title': 'Casting: $title', 'playing': true, 'note': note});
    } catch (_) {}
  }

  /// Casting ended. The service stops too unless a player page still needs it.
  static Future<void> stopCasting() async {
    _castHold = false;
    _note = null;
    if (_stopHandlers.isEmpty) {
      try {
        await _channel.invokeMethod<bool>('stop');
      } catch (_) {}
      return;
    }
    // The notification's Stop button also ends the service: bring it back for
    // the player page that is still open.
    try {
      await _channel.invokeMethod<bool>(
          'start', {'title': _lastTitle, 'playing': true, 'note': null});
    } catch (_) {}
  }

  /// Phone media volume, 0.0 - 1.0.
  static Future<double> getVolume() async {
    try {
      return (await _channel.invokeMethod<double>('getVolume')) ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setVolume(double value) async {
    try {
      await _channel.invokeMethod<bool>(
          'setVolume', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  /// Android 17+ asks before an app may talk to devices on the home Wi-Fi
  /// (needed to find TVs). Older Android versions ignore this.
  static Future<void> requestLocalNetwork() async {
    try {
      await _channel.invokeMethod<bool>('localNetwork');
    } catch (_) {}
  }

  /// Wi-Fi multicast lock, needed on some phones to hear TVs answer a search.
  static Future<void> setMulticast(bool on) async {
    try {
      await _channel.invokeMethod<bool>('multicast', {'on': on});
    } catch (_) {}
  }

  /// Tells the notification whether the video is really playing, so the
  /// button shows Pause or Play correctly.
  static Future<void> setPlaying(bool playing, {bool fromCast = false}) async {
    // While a TV plays, the phone's own (paused) player must not flip the
    // notification to "Paused".
    if (castActive && !fromCast) return;
    try {
      await _channel.invokeMethod<bool>('update', {'playing': playing});
    } catch (_) {}
  }

  /// Call when that player page closes. The service ends with the last one.
  static Future<void> stop(VoidCallback onStopRequested) async {
    _stopHandlers.remove(onStopRequested);
    if (_stopHandlers.isNotEmpty || _castHold) return;
    _onPlay = null;
    _onPause = null;
    _onSeekBy = null;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  /// Web pages pause their video when they think the tab is hidden. This
  /// makes the page believe it is always visible.
  static const keepVisibleJs = '''
(function(){try{
if(window.__dwBg)return;window.__dwBg=1;
function def(o,k,v){try{Object.defineProperty(o,k,{configurable:true,get:function(){return v}})}catch(e){}}
def(document,'hidden',false);def(document,'webkitHidden',false);
def(document,'visibilityState','visible');def(document,'webkitVisibilityState','visible');
var stop=function(e){e.stopImmediatePropagation()};
document.addEventListener('visibilitychange',stop,true);
document.addEventListener('webkitvisibilitychange',stop,true);
}catch(e){}})();
''';

  /// Run when the app goes to the background: remembers which videos play.
  static const rememberPlayingJs = '''
(function(){try{window.__dwWas=[].slice.call(document.querySelectorAll('video')).filter(function(v){return !v.paused&&!v.ended})}catch(e){}})();
''';

  /// Run shortly after: restarts any of those videos the page paused.
  static const resumePlayingJs = '''
(function(){try{(window.__dwWas||[]).forEach(function(v){if(v.paused){var p=v.play();if(p&&p.catch)p.catch(function(){})}})}catch(e){}})();
''';
}
