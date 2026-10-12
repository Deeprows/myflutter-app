import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../services/background_playback.dart';

/// The real background player: ExoPlayer (just_audio) behind an Android media
/// session (audio_service). This is what gives a lock-screen / notification
/// player with play, pause, next, previous and a seek bar, and what keeps the
/// music alive when the app is minimised or the screen is off (wake lock +
/// foreground service are handled by the two packages).
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// True while a video's sound is being carried in the background.
  bool videoMode = false;

  void Function()? onNext;
  void Function()? onPrevious;
  void Function()? onCompleted;
  void Function()? onStop;

  bool _completedFired = false;

  AppAudioHandler() {
    player.playbackEventStream.listen((_) => _broadcast(), onError: (_) {});
    // Play / pause changes must reach the notification straight away, even
    // when no other playback event fires (this is what makes the card show up
    // and switch its play/pause button while the app is minimised or locked).
    player.playingStream.listen((_) => _broadcast(), onError: (_) {});
    player.positionDiscontinuityStream.listen((_) => _broadcast(), onError: (_) {});
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && !_completedFired) {
        _completedFired = true;
        onCompleted?.call();
      }
    });
  }

  void _broadcast() {
    final playing = player.playing;
    playbackState.add(PlaybackState(
      controls: [
        if (!videoMode) MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        if (!videoMode) MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: videoMode ? const [0, 1] : const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: 0,
    ));
  }

  /// Posts the notification card again (same track, same state). Used when
  /// the app is minimised or comes back, so the card shows up on the
  /// notification tray and lock screen even if the system dropped it.
  void refreshCard() {
    if (player.processingState == ProcessingState.idle) return;
    final item = mediaItem.value;
    if (item == null) return;
    mediaItem.add(item);
    _broadcast();
  }

  /// Loads one local file and starts playing it. Returns its duration.
  Future<Duration?> loadFile(
    String path,
    MediaItem item, {
    Duration? start,
    bool video = false,
  }) async {
    videoMode = video;
    _completedFired = false;
    mediaItem.add(item);
    final d = await player.setAudioSource(
      AudioSource.uri(Uri.file(path)),
      initialPosition: start,
    );
    // Keep the card's duration / seek bar in step with the real file length.
    if (item.duration == null && d != null) {
      mediaItem.add(item.copyWith(duration: d));
    }
    unawaited(player.play());
    _broadcast();
    return d;
  }

  /// Plays the current track again from the start (repeat one).
  Future<void> restart() async {
    _completedFired = false;
    await player.seek(Duration.zero);
    unawaited(player.play());
  }

  /// Stops sound and removes the notification without calling [onStop].
  Future<void> release() async {
    await player.stop();
    videoMode = false;
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> stop() async {
    await player.stop();
    onStop?.call();
    return super.stop();
  }
}

/// One shared handler for the whole app, created on first use.
class AudioBridge {
  static AppAudioHandler? _h;
  static Future<AppAudioHandler>? _starting;

  static AppAudioHandler? get current => _h;

  static Future<AppAudioHandler> handler() {
    return _starting ??= _init();
  }

  static Future<AppAudioHandler> _init() async {
    // Android 13+: no permission = no media notification / lock-screen player.
    await BackgroundPlayback.ensureNotificationPermission();
    return AudioService.init(
      builder: () => AppAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.deeprows.footbolive.audio',
        androidNotificationChannelName: 'Music and video playback',
        androidNotificationIcon: 'drawable/ic_stat_notify',
        // Keep the media notification visible while playback is active and
        // keep the service in the foreground when playback is temporarily paused.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationClickStartsActivity: true,
      ),
    ).then((h) {
      _h = h;
      _keeper ??= _CardKeeper(h);
      return h;
    });
  }

  static _CardKeeper? _keeper;

  /// Video went to the background: keep its sound going from [position].
  static Future<bool> startVideoAudio(
    String path,
    String title,
    Duration position,
    void Function() onStopTapped,
  ) async {
    try {
      final h = await handler();
      h.onNext = null;
      h.onPrevious = null;
      h.onCompleted = null;
      h.onStop = onStopTapped;
      await h.loadFile(
        path,
        MediaItem(id: path, title: title, album: 'Deeprowss'),
        start: position,
        video: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Video is back on screen: stop the background sound and report where it
  /// got to, and whether it was still playing.
  static Future<({Duration position, bool playing})?> endVideoAudio() async {
    final h = _h;
    if (h == null || !h.videoMode) return null;
    final r = (position: h.player.position, playing: h.player.playing);
    h.onStop = null;
    await h.release();
    return r;
  }
}


/// Re-posts the media card whenever the app goes to the background or comes
/// back (e.g. after the person turned notifications on in Settings).
class _CardKeeper with WidgetsBindingObserver {
  final AppAudioHandler handler;
  _CardKeeper(this.handler) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.resumed) {
      handler.refreshCard();
    }
  }
}
