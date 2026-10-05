import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- Firebase
// Same Firebase project the Deeprowss website uses (deeprows-4d37c), so the
// web and the app share one backend. These values come from the Footbolive
// firebase-messaging-sw.js. They are public client identifiers, not secrets.
//
// For the most reliable setup, add an Android app (package
// com.deeprows.footbolive) in the Firebase console and pass its App ID at
// build time:  --dart-define=FIREBASE_ANDROID_APP_ID=1:227439941748:android:...
// (the GitHub workflow reads it from the repo variable FIREBASE_ANDROID_APP_ID).
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');

FirebaseOptions get _options => FirebaseOptions(
  apiKey: 'AIzaSyBs9eSquNu2drJjM3vqFGDX1QU-VE1_F7U',
  appId: _androidAppId,
  messagingSenderId: '227439941748',
  projectId: 'deeprows-4d37c',
  storageBucket: 'deeprows-4d37c.firebasestorage.app',
);

/// Runs in a background isolate when a message arrives while the app is not
/// running. Notification messages are shown by Android itself; this only
/// makes sure Firebase is initialised for any future data handling.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: _options);
}

/// Everything the user can subscribe to. `id` is the FCM topic name, so it
/// must match what the server publishes to (see PUSH_SETUP.md).
enum PushTopic {
  kickoff(
    'kickoff',
    'Live match alerts',
    '5 minutes before kick-off and when the match starts',
    Icons.sports_soccer_rounded,
  ),
  highlights(
    'highlights',
    'New highlights',
    'When a new match highlight is added',
    Icons.play_circle_rounded,
  ),
  movies(
    'movies',
    'New movies',
    'When a new movie is added',
    Icons.movie_rounded,
  );

  const PushTopic(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  String get prefKey => 'push_topic_$id';
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// Lets the service show a banner while the app is open.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Set to a bottom-tab index (0 Live, 1 Highlights, 3 Movies) when a
  /// notification is tapped; ShellScreen switches tab and clears it.
  final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  Future<void>? _initFuture;
  bool _ready = false;
  bool get isReady => _ready;

  /// Tab to open for a notification's data payload.
  static int? tabFor(Map<String, dynamic> data) {
    switch ((data['tab'] ?? data['type'] ?? '').toString()) {
      case 'live':
      case 'kickoff':
        return 0;
      case 'highlights':
        return 1;
      case 'movies':
        return 3;
    }
    return null;
  }

  /// Safe to call many times; the work runs once.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      await Firebase.initializeApp(options: _options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      final messaging = FirebaseMessaging.instance;

      // Shows the Android 13+ permission prompt (no-op on older versions).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onOpened(initial);

      _ready = true;
      await syncTopics();
      messaging.onTokenRefresh.listen((_) => syncTopics());
    } catch (e, st) {
      debugPrint('Push init failed: $e\n$st');
    }
  }

  // ------------------------------------------------------------- topics

  Future<bool> isEnabled(PushTopic t) async =>
      (await SharedPreferences.getInstance()).getBool(t.prefKey) ?? true;

  /// Applies the saved choices to FCM (everything is on by default).
  Future<void> syncTopics() async {
    if (!_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final messaging = FirebaseMessaging.instance;
    for (final t in PushTopic.values) {
      try {
        if (prefs.getBool(t.prefKey) == false) {
          await messaging.unsubscribeFromTopic(t.id);
        } else {
          await messaging.subscribeToTopic(t.id);
        }
      } catch (e) {
        debugPrint('Topic ${t.id} sync failed: $e');
      }
    }
  }

  Future<void> setEnabled(PushTopic t, bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(t.prefKey, on);
    if (!_ready) return;
    if (on) {
      await FirebaseMessaging.instance.subscribeToTopic(t.id);
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic(t.id);
    }
  }

  // --------------------------------------------------------- permission

  Future<bool> notificationsAllowed() async {
    if (!_ready) return false;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized;
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized;
  }

  Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ handlers

  /// App is open: Android does not draw a tray notification, so show a banner.
  void _onForeground(RemoteMessage m) {
    final title = (m.notification?.title ?? m.data['title'] ?? '').toString();
    final body = (m.notification?.body ?? m.data['body'] ?? '').toString();
    if (title.isEmpty && body.isEmpty) return;
    final tab = tabFor(m.data);
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        action: tab == null
            ? null
            : SnackBarAction(
                label: 'OPEN',
                onPressed: () => tabRequest.value = tab,
              ),
      ));
  }

  /// User tapped a notification (app was in background or closed).
  void _onOpened(RemoteMessage m) {
    final tab = tabFor(m.data);
    if (tab != null) tabRequest.value = tab;
  }
}
