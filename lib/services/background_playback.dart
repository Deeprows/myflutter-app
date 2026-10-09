import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps video/audio playing when the app is minimised or the screen is
/// locked. Starts an Android foreground service (media notification) while a
/// player page is open, so the system doesn't freeze or kill the app. The
/// native side is added by tool/patch_background_playback.py.
class BackgroundPlayback {
  static const _channel = MethodChannel('footbolive/playback');
  static final List<VoidCallback> _stopHandlers = [];
  static bool _hooked = false;

  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      // "Stop" tapped in the notification.
      if (call.method == 'stopRequested') {
        for (final h in List.of(_stopHandlers)) {
          h();
        }
      }
      return null;
    });
  }

  /// Call when a player page opens. [onStopRequested] runs when the user taps
  /// Stop on the notification.
  static Future<void> start(String title, VoidCallback onStopRequested) async {
    _hook();
    if (!_stopHandlers.contains(onStopRequested)) {
      _stopHandlers.add(onStopRequested);
    }
    try {
      await _channel.invokeMethod<bool>('start', {'title': title});
    } catch (_) {}
  }

  /// Call when that player page closes. The service ends with the last one.
  static Future<void> stop(VoidCallback onStopRequested) async {
    _stopHandlers.remove(onStopRequested);
    if (_stopHandlers.isNotEmpty) return;
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
