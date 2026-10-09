import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_nav.dart';
import '../services/background_playback.dart';

import 'audio_handler.dart';
import 'media_entry.dart';

/// App-wide audio queue. Lives outside any screen, so music keeps playing
/// while the person browses other tabs. Sound itself is produced by
/// [AppAudioHandler] (ExoPlayer + Android media session), so it also keeps
/// playing with the screen off and can be controlled from the notification
/// and lock screen.
class MusicPlayer extends ChangeNotifier {
  static final MusicPlayer instance = MusicPlayer._();
  MusicPlayer._();

  List<MediaEntry> queue = [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  bool failed = false;
  bool shuffle = false;
  int repeat = 0; // 0 off, 1 all, 2 one
  Duration duration = Duration.zero;
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  AppAudioHandler? _h;
  int _gen = 0;
  bool _wired = false;
  final _rng = Random();

  MediaEntry? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get active => current != null;

  Future<AppAudioHandler> _handler() async {
    final h = _h ??= await AudioBridge.handler();
    if (!_wired) {
      _wired = true;
      h.player.positionStream.listen((p) {
        if (!h.videoMode && active) position.value = p;
      });
      h.player.playingStream.listen((p) {
        if (h.videoMode || !active) return;
        if (p != playing) {
          playing = p;
          notifyListeners();
        }
      });
    }
    // The video player borrows the same handler, so set the hooks each time.
    h.onNext = next;
    h.onPrevious = previous;
    h.onCompleted = () => _advance(auto: true);
    h.onStop = stop;
    return h;
  }

  Future<void> playQueue(List<MediaEntry> q, int start) async {
    queue = List.of(q);
    await _load(start);
  }

  Future<void> _load(int i) async {
    final gen = ++_gen;
    index = i;
    loading = true;
    failed = false;
    playing = false;
    duration = Duration.zero;
    position.value = Duration.zero;
    notifyListeners();

    final entry = current;
    try {
      final h = await _handler();
      final file = entry == null ? null : await entry.file();
      if (gen != _gen) return;
      if (file == null) return _fail(gen);
      final d = await h.loadFile(
        file.path,
        MediaItem(
          id: entry!.key,
          title: entry.title,
          album: entry.folderName,
          duration: entry.duration > Duration.zero ? entry.duration : null,
        ),
      );
      if (gen != _gen) return;
      duration = d ?? entry.duration;
      loading = false;
      playing = true;
      notifyListeners();
      unawaited(_checkNotificationAccess());
    } catch (_) {
      _fail(gen);
    }
  }

  bool _warned = false;

  /// If Android is hiding our notifications, the media card can never appear.
  /// Say so, with a button straight to the right settings page.
  Future<void> _checkNotificationAccess() async {
    if (_warned) return;
    if (await BackgroundPlayback.notificationsAllowed()) {
      unawaited(BackgroundPlayback.askBatteryExemptionOnce());
      return;
    }
    _warned = true;
    final ctx = AppNav.overlayContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      content: const Text(
          'Notifications are off, so the music card cannot show on the lock screen. Turn them on for Deeprowss.'),
      action: SnackBarAction(label: 'SETTINGS', onPressed: openAppSettings),
    ));
  }

  void _fail(int gen) {
    if (gen != _gen) return;
    loading = false;
    failed = true;
    notifyListeners();
  }

  void _advance({required bool auto}) {
    if (queue.isEmpty || !active) return;
    if (auto && repeat == 2) {
      _h?.restart();
      return;
    }
    int next;
    if (shuffle && queue.length > 1) {
      do {
        next = _rng.nextInt(queue.length);
      } while (next == index);
    } else {
      next = index + 1;
      if (next >= queue.length) {
        if (repeat == 1 || !auto) {
          next = 0;
        } else {
          playing = false;
          notifyListeners();
          return;
        }
      }
    }
    _load(next);
  }

  void next() => _advance(auto: false);

  void previous() {
    if (queue.isEmpty || !active) return;
    if (position.value > const Duration(seconds: 4)) {
      seek(Duration.zero);
      return;
    }
    _load(index <= 0 ? queue.length - 1 : index - 1);
  }

  Future<void> toggle() async {
    final h = _h;
    if (h == null || !active) return;
    if (h.player.playing) {
      await h.pause();
    } else {
      final end = duration > Duration.zero &&
          h.player.position >= duration - const Duration(milliseconds: 300);
      if (end) {
        await h.restart();
      } else {
        unawaited(h.play());
      }
    }
  }

  Future<void> seek(Duration d) async => _h?.seek(d);

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = (repeat + 1) % 3;
    notifyListeners();
  }

  /// Ends playback and removes the notification.
  Future<void> stop() async {
    _gen++;
    final wasActive = active;
    queue = [];
    index = -1;
    playing = false;
    loading = false;
    position.value = Duration.zero;
    notifyListeners();
    final h = _h;
    if (wasActive && h != null && !h.videoMode) await h.release();
  }
}
