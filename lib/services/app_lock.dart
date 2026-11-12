import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/audio_handler.dart';
import '../theme/app_theme.dart';
import 'background_playback.dart';

/// In-app lock (child lock). A 4-digit PIN is asked every time the app is
/// opened, and again after the app has been in the background for longer
/// than the chosen time.
///
/// The PIN and the recovery answer are never saved as text: only a salted,
/// repeatedly hashed copy is kept. This is a child lock, not a vault.
/// A notification shown on top of the lock screen.
class LockBanner {
  final String title;
  final String body;
  const LockBanner(this.title, this.body);
}

class AppLock with WidgetsBindingObserver {
  AppLock._();
  static final AppLock instance = AppLock._();

  static const _kOn = 'app_lock_enabled';
  static const _kSalt = 'app_lock_salt';
  static const _kPin = 'app_lock_pin';
  static const _kQuestion = 'app_lock_question';
  static const _kAnswer = 'app_lock_answer';
  static const _kTimeout = 'app_lock_timeout';
  static const _kFails = 'app_lock_fails';
  static const _kUntil = 'app_lock_until';
  static const _kTheme = 'app_lock_theme';

  /// Choices for "lock again after": seconds (0 = every time the app leaves
  /// the screen).
  static const timeoutChoices = <int>[0, 30, 60, 300];

  /// True while the lock screen must cover the app.
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// True when the user has switched App Lock on.
  final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Theme of the lock screen itself. CR7 until the user picks another one;
  /// it does not change the theme of the rest of the app.
  final ValueNotifier<int> themeIndex =
      ValueNotifier(Palettes.all.indexOf(Palettes.cr7));
  Palette get palette => Palettes.all[themeIndex.value];

  /// Notification waiting to be shown over the lock screen.
  final ValueNotifier<LockBanner?> banner = ValueNotifier(null);
  Timer? _bannerTimer;

  int timeoutSeconds = 30;
  String question = '';

  SharedPreferences? _prefs;
  String _salt = '';
  String _pinHash = '';
  String _answerHash = '';
  int _fails = 0;
  int _until = 0; // epoch ms until which attempts are refused
  DateTime? _pausedAt;
  bool _observing = false;

  /// Reads the saved state. Call once before runApp. When the lock is on,
  /// the app starts locked.
  Future<void> init() async {
    final p = _prefs = await SharedPreferences.getInstance();
    _salt = p.getString(_kSalt) ?? '';
    _pinHash = p.getString(_kPin) ?? '';
    _answerHash = p.getString(_kAnswer) ?? '';
    question = p.getString(_kQuestion) ?? '';
    timeoutSeconds = p.getInt(_kTimeout) ?? 30;
    _fails = p.getInt(_kFails) ?? 0;
    _until = p.getInt(_kUntil) ?? 0;
    final t = p.getInt(_kTheme) ?? Palettes.all.indexOf(Palettes.cr7);
    themeIndex.value = t.clamp(0, Palettes.all.length - 1);
    enabled.value = (p.getBool(_kOn) ?? false) && _pinHash.isNotEmpty;
    locked.value = enabled.value;
    BackgroundPlayback.locked = locked.value;
    if (!_observing) {
      locked.addListener(_onLockedChanged);
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  // ------------------------------------------------------------- hashing

  String _hash(String value) {
    var bytes = utf8.encode('$_salt:$value');
    for (var i = 0; i < 300; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64.encode(bytes);
  }

  static String _normalise(String answer) => answer.trim().toLowerCase();

  String _newSalt() {
    final r = Random.secure();
    return base64.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  // ------------------------------------------------------------- lockout

  /// Seconds left before another attempt is allowed (0 = allowed now).
  int get lockoutSeconds {
    final left = _until - DateTime.now().millisecondsSinceEpoch;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  Future<void> _recordFail() async {
    _fails++;
    // After 5 wrong tries: wait 30 s, then 60 s, 120 s ... (max 15 min).
    if (_fails >= 5) {
      final steps = (_fails - 5) ~/ 5;
      final secs = min(30 * pow(2, steps).toInt(), 900);
      _until = DateTime.now().millisecondsSinceEpoch + secs * 1000;
    }
    await _prefs?.setInt(_kFails, _fails);
    await _prefs?.setInt(_kUntil, _until);
  }

  Future<void> _clearFails() async {
    _fails = 0;
    _until = 0;
    await _prefs?.remove(_kFails);
    await _prefs?.remove(_kUntil);
  }

  // ------------------------------------------------------------- actions

  /// Checks the PIN. Wrong tries are counted; too many cause a short wait.
  Future<bool> check(String pin) async {
    if (lockoutSeconds > 0 || _pinHash.isEmpty) return false;
    if (_hash(pin) == _pinHash) {
      await _clearFails();
      return true;
    }
    await _recordFail();
    return false;
  }

  /// Right PIN opens the app.
  Future<bool> unlockWithPin(String pin) async {
    final ok = await check(pin);
    if (ok) locked.value = false;
    return ok;
  }

  /// Switches the lock on with a new PIN and a recovery question.
  Future<void> enable({
    required String pin,
    required String question,
    required String answer,
  }) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    _salt = _newSalt();
    _pinHash = _hash(pin);
    _answerHash = _hash(_normalise(answer));
    this.question = question;
    await p.setString(_kSalt, _salt);
    await p.setString(_kPin, _pinHash);
    await p.setString(_kAnswer, _answerHash);
    await p.setString(_kQuestion, question);
    await p.setBool(_kOn, true);
    await _clearFails();
    enabled.value = true;
  }

  /// Changes the PIN only (recovery question stays).
  Future<void> changePin(String pin) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    // Same salt, so the saved recovery answer keeps working.
    _pinHash = _hash(pin);
    await p.setString(_kPin, _pinHash);
    await _clearFails();
  }

  /// Switches the lock off and forgets everything.
  Future<void> disable() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    for (final k in [_kOn, _kSalt, _kPin, _kAnswer, _kQuestion]) {
      await p.remove(k);
    }
    await _clearFails();
    _salt = _pinHash = _answerHash = question = '';
    enabled.value = false;
    locked.value = false;
  }

  /// Forgot PIN: the right recovery answer switches the lock off (it can be
  /// turned on again with a new PIN from Settings).
  Future<bool> recoverWithAnswer(String answer) async {
    if (lockoutSeconds > 0 || _answerHash.isEmpty) return false;
    if (_hash(_normalise(answer)) == _answerHash) {
      await disable();
      return true;
    }
    await _recordFail();
    return false;
  }

  Future<void> setTimeout(int seconds) async {
    timeoutSeconds = seconds;
    await (_prefs ??= await SharedPreferences.getInstance())
        .setInt(_kTimeout, seconds);
  }

  Future<void> setTheme(int i) async {
    themeIndex.value = i.clamp(0, Palettes.all.length - 1);
    await (_prefs ??= await SharedPreferences.getInstance())
        .setInt(_kTheme, themeIndex.value);
  }

  /// Shows a notification over the lock screen. Returns false (and does
  /// nothing) when the app is not locked.
  bool showBanner(String title, String body) {
    if (!locked.value) return false;
    banner.value = LockBanner(title, body);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 8), dismissBanner);
    return true;
  }

  void dismissBanner() {
    _bannerTimer?.cancel();
    banner.value = null;
  }

  /// "Lock now".
  void lockNow() {
    if (enabled.value) locked.value = true;
  }

  // ------------------------------------------------------------ playback

  /// When the lock engages, everything that is playing stops: music, video
  /// sound handed to the background service, and the video / web player page
  /// that is open.
  void _onLockedChanged() {
    BackgroundPlayback.locked = locked.value;
    if (!locked.value) {
      dismissBanner();
      return;
    }
    try {
      BackgroundPlayback.pauseForLock();
    } catch (_) {}
    try {
      AudioBridge.current?.pause();
    } catch (_) {}
  }

  // ------------------------------------------------------------ lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final t = _pausedAt;
      _pausedAt = null;
      if (enabled.value &&
          !locked.value &&
          t != null &&
          DateTime.now().difference(t).inSeconds >= timeoutSeconds) {
        locked.value = true;
      }
    }
  }

  /// Android back button: while locked it must not reach the screens
  /// underneath.
  @override
  Future<bool> didPopRoute() async => locked.value;
}
