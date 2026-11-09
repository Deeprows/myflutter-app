import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Remembers where the user was (last tab, feed view, scroll positions) so reopening the app puts them back there.
/// Loaded once at start-up, so reads are instant and the first screen is already the right one.
/// Each account has its own memory on the device.
class AppMemory {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
  }

  static String _key(String name) =>
      'app_memory_v1_${AuthService.instance.user?.id ?? 'guest'}_$name';

  static int? getInt(String name) => _prefs?.getInt(_key(name));
  static double? getDouble(String name) => _prefs?.getDouble(_key(name));
  static String? getString(String name) => _prefs?.getString(_key(name));

  static void setInt(String name, int value) =>
      unawaited(_prefs?.setInt(_key(name), value) ?? Future<bool>.value(false));
  static void setDouble(String name, double value) => unawaited(
    _prefs?.setDouble(_key(name), value) ?? Future<bool>.value(false),
  );
  static void setString(String name, String value) => unawaited(
    _prefs?.setString(_key(name), value) ?? Future<bool>.value(false),
  );
}

/// Saves a list's scroll position (after the user stops scrolling) and puts it back once its content has loaded.
class ScrollMemory {
  final String name;
  Timer? _timer;
  bool _restored = false;

  ScrollMemory(this.name);

  /// Call from a scroll listener.
  void save(double offset) {
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 400),
      () => AppMemory.setDouble(name, offset),
    );
  }

  /// Forget the saved position (the list was reset, for example a new filter).
  void reset() {
    _timer?.cancel();
    AppMemory.setDouble(name, 0);
  }

  /// Once, after the first real content is on screen.
  void restoreOnce(ScrollController Function() controller, bool Function() mounted) {
    if (_restored) return;
    _restored = true;
    final saved = AppMemory.getDouble(name);
    if (saved == null || saved <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = controller();
      if (!mounted() || !c.hasClients) return;
      c.jumpTo(saved.clamp(0.0, c.position.maxScrollExtent));
    });
  }

  void dispose() => _timer?.cancel();
}


/// Remembers which page was open on top of a tab (a post, a match-room chat, an analysis) so it can be reopened
/// after the app was closed. A page registers itself when it opens and clears itself when it closes, so only a
/// page that was still open when the app died is brought back — once, at the next launch.
class PageMemory {
  static Map<String, dynamic>? _launch;

  /// Reads what was open last time. Called once, when the main screen starts.
  static void captureLaunch() {
    _launch = null;
    final text = AppMemory.getString('page');
    if (text == null || text.isEmpty) return;
    try {
      final raw = jsonDecode(text);
      if (raw is Map) _launch = Map<String, dynamic>.from(raw);
    } catch (_) {}
  }

  /// The page to bring back, if it is of [type]. Returns it only once.
  static Map<String, dynamic>? consume(String type) {
    final l = _launch;
    if (l == null || l['type'] != type) return null;
    _launch = null;
    return l;
  }

  static void open(String type, String id, [Map<String, dynamic> extra = const {}]) =>
      AppMemory.setString('page', jsonEncode({'type': type, 'id': id, ...extra}));

  static void close(String type, String id) {
    final text = AppMemory.getString('page');
    if (text == null || text.isEmpty) return;
    try {
      final raw = jsonDecode(text);
      if (raw is Map && raw['type'] == type && raw['id'] == id) {
        AppMemory.setString('page', '');
      }
    } catch (_) {}
  }
}
