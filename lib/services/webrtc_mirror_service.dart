import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_share_plugin/screen_share_plugin.dart' show ScreenSharePlugin, ScreenShareOptions;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'background_playback.dart';
import 'stream_resolver.dart' show StreamKind;

/// Streams the Android display to a browser / Deeprowss TV Receiver over a
/// local-network WebRTC connection. Signalling stays on the phone; the video
/// itself is peer-to-peer and is not uploaded to a Deeprowss server.
class DeeprowssMirrorService extends ChangeNotifier {
  DeeprowssMirrorService._();
  static final DeeprowssMirrorService instance = DeeprowssMirrorService._();

  HttpServer? _server;
  WebSocket? _socket;
  RTCPeerConnection? _peerConnection;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _creatingPeer = false;
  bool _stopping = false;
  int _failedPairAttempts = 0;
  MediaStream? _screenStream;
  String? _pin;
  String? _url;
  bool _starting = false;
  bool running = false;
  bool connected = false;
  bool audioShared = false;

  /// Why phone sound is not being sent (null when it is, or not yet known).
  String? audioNote;

  /// True when the session only sends a channel link to the receiver page
  /// (no screen capture). The receiver plays the stream itself, so the phone
  /// can be minimised or locked.
  bool urlMode = false;

  /// While mirroring with sound, silence the phone's own speaker so the audio
  /// only plays on the TV / laptop. The previous volume is restored on stop.
  bool mutePhone = true;
  double? _savedVolume;

  /// Experimental: capture through flutter_webrtc itself, which can include
  /// the phone's sound on some phones where the screen-share plugin cannot.
  bool alternateCapture = false;

  void setAlternateCapture(bool value) {
    alternateCapture = value;
    notifyListeners();
  }

  Future<void> setMutePhone(bool value) async {
    mutePhone = value;
    if (running && audioShared) {
      if (value) { await _applyPhoneMute(); } else { await _restorePhoneVolume(); }
    }
    notifyListeners();
  }

  Future<void> _applyPhoneMute() async {
    if (_savedVolume != null) return;
    try {
      _savedVolume = await BackgroundPlayback.getVolume();
      await BackgroundPlayback.setVolume(0);
    } catch (_) {
      _savedVolume = null;
    }
  }

  Future<void> _restorePhoneVolume() async {
    final v = _savedVolume;
    _savedVolume = null;
    if (v == null) return;
    try { await BackgroundPlayback.setVolume(v); } catch (_) {}
  }
  Map<String, dynamic>? _pendingPlay;
  String nowPlayingTitle = '';
  String nowPlayingKind = '';
  int receiverVolume = 100;
  String status = 'Not running';
  String? error;

  String? get url => _url;
  String? get pin => _pin;
  // Serve the receiver page from this same local HTTP origin. A GitHub Pages
  // HTTPS page cannot open an insecure ws:// connection to the phone on modern
  // browsers (mixed-content blocking), so the TV opens this LAN URL directly.
  String? get pairingUrl => _url == null || _pin == null
      ? null
      : Uri.parse(_url!).replace(queryParameters: {'pin': _pin!}).toString();

  Future<void> start({bool captureScreen = true}) async {
    if (running || _starting) return;
    _starting = true;
    error = null;
    urlMode = !captureScreen;
    status = 'Preparing local mirroring session…';
    notifyListeners();
    try {
      _pin = (Random.secure().nextInt(900000) + 100000).toString();
      _failedPairAttempts = 0;
      final localNetworkAllowed = await BackgroundPlayback.requestLocalNetwork();
      if (!localNetworkAllowed) {
        throw StateError('Allow Deeprowss to access devices on your local network, then try again.');
      }
      final ip = await _findLanAddress();
      if (ip == null) throw StateError('Could not find your Wi-Fi IP address. Connect to the same Wi-Fi as your TV.');
      // Bind only to the selected LAN interface rather than every phone network.
      _server = await HttpServer.bind(InternetAddress(ip), 0, shared: true);
      unawaited(_serve(_server!));
      _url = 'http://$ip:${_server!.port}';

      if (captureScreen) {
        // Phone audio (games, videos, music) is captured with Android's
        // AudioPlaybackCapture (Android 10+), which needs the microphone
        // (RECORD_AUDIO) permission. If it is refused or unsupported we still
        // mirror the video, just without sound.
        audioNote = null;
        var wantAudio = false;
        try {
          wantAudio = (await Permission.microphone.request()).isGranted;
        } catch (_) {}
        if (!wantAudio) audioNote = 'Audio permission was not granted, so no phone sound is sent.';
        Future<MediaStream?> capture(bool audio) => ScreenSharePlugin.startScreenShare(
              options: ScreenShareOptions(
                audio: audio,
                frameRate: 20,
                androidNotificationTitle: 'Deeprowss screen mirroring',
                androidNotificationText: 'Your screen is being shared with a TV',
                androidFullScreenOnly: true,
              ),
              onStopped: () => unawaited(stop()),
            );
        if (alternateCapture) {
          try {
            final s = await navigator.mediaDevices.getDisplayMedia({
              'video': {'frameRate': 20},
              'audio': true,
            });
            if (s.getVideoTracks().isNotEmpty) {
              _screenStream = s;
              for (final track in s.getVideoTracks()) {
                track.onEnded = () => unawaited(stop());
              }
            }
          } catch (e) {
            _screenStream = null;
            audioNote = 'Alternate capture is not available on this phone, using the standard capture.';
          }
        }
        try {
          _screenStream ??= await capture(wantAudio);
        } catch (e) {
          final m = e.toString().toLowerCase();
          final refused = m.contains('permission') || m.contains('denied') || m.contains('cancel');
          if (!wantAudio || refused) rethrow;
          wantAudio = false;
          audioNote = 'Phone audio capture failed: $e';
          _screenStream = await capture(false);
        }
        audioShared = wantAudio && (_screenStream?.getAudioTracks().isNotEmpty ?? false);
        if (wantAudio && !audioShared) {
          audioNote = 'The screen-share plugin sent no audio track, so phone sound cannot be mirrored with it. The phone stays unmuted.';
        }
        // Keep the phone awake: Android ends a full-screen capture when the
        // phone is locked, so the screen must not time out while mirroring.
        try { await WakelockPlus.enable(); } catch (_) {}
        if (audioShared && mutePhone) await _applyPhoneMute();
      }
      running = true;
      status = captureScreen
          ? 'Waiting for your TV to connect…'
          : 'Open the receiver page and connect to start the channel';
      notifyListeners();
      if (_socket != null) await _createPeerConnection();
    } catch (e) {
      error = _friendlyError(e);
      status = 'Could not start mirroring';
      urlMode = false;
      _pendingPlay = null;
      _stopping = true;
      try { await WakelockPlus.disable(); } catch (_) {}
      await _restorePhoneVolume();
      await _releaseResources(stopCapture: true);
      _stopping = false;
      notifyListeners();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        if (request.uri.path == '/ws') {
          if (_failedPairAttempts >= 10) {
            request.response
              ..statusCode = HttpStatus.tooManyRequests
              ..write('Too many pairing attempts. Restart mirroring in Deeprowss.');
            await request.response.close();
            continue;
          }
          if (request.uri.queryParameters['pin'] != _pin || _pin == null) {
            _failedPairAttempts++;
            request.response
              ..statusCode = HttpStatus.forbidden
              ..write('Invalid Deeprowss pairing code');
            await request.response.close();
            continue;
          }
          if (!WebSocketTransformer.isUpgradeRequest(request)) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('WebSocket upgrade required');
            await request.response.close();
            continue;
          }
          final incoming = await WebSocketTransformer.upgrade(request);
          if (_socket != null) {
            await incoming.close(WebSocketStatus.policyViolation, 'A receiver is already connected');
            continue;
          }
          _socket = incoming;
          connected = true;
          incoming.listen(_onSignal,
            onError: (_) => _receiverDisconnected(),
            onDone: _receiverDisconnected,
            cancelOnError: true,
          );
          status = 'TV connected · establishing video…';
          notifyListeners();
          _flushPending();
          if (_screenStream != null) await _createPeerConnection();
          continue;
        }

        if (request.method == 'GET' && (request.uri.path == '/' || request.uri.path == '/index.html')) {
          try {
            final html = await rootBundle.loadString('assets/receiver/index.html');
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
              ..headers.set('x-content-type-options', 'nosniff')
              ..write(html);
          } catch (e) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write('Deeprowss receiver page could not be loaded: $e');
          }
          await request.response.close();
          continue;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
      }
    } catch (e) {
      if (running) {
        error = 'Receiver server stopped: $e';
        status = 'Receiver connection ended';
        notifyListeners();
      }
    }
  }

  Future<void> _onSignal(dynamic raw) async {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (message['type']) {
        case 'ready':
          _flushPending();
          if (_screenStream != null) await _createPeerConnection();
          break;
        case 'answer':
          final pc = _peerConnection;
          if (pc == null) return;
          await pc.setRemoteDescription(
            RTCSessionDescription(message['sdp'] as String?, message['sdpType'] as String? ?? 'answer'),
          );
          for (final candidate in List<RTCIceCandidate>.from(_pendingRemoteCandidates)) {
            await pc.addCandidate(candidate);
          }
          _pendingRemoteCandidates.clear();
          break;
        case 'candidate':
          final pc = _peerConnection;
          if (pc == null) return;
          final candidate = message['candidate'] as Map<String, dynamic>?;
          if (candidate != null) {
            final parsed = RTCIceCandidate(
              candidate['candidate'] as String?,
              candidate['sdpMid'] as String?,
              (candidate['sdpMLineIndex'] as num?)?.toInt(),
            );
            if (await pc.getRemoteDescription() == null) {
              _pendingRemoteCandidates.add(parsed);
            } else {
              await pc.addCandidate(parsed);
            }
          }
          break;
        case 'receiver-status':
          final detail = message['message'];
          if (detail is String && detail.isNotEmpty) status = detail;
          notifyListeners();
          break;
        case 'stop':
          await stop();
          break;
      }
    } catch (e) {
      error = 'The TV receiver sent an invalid connection message.';
      notifyListeners();
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null || _creatingPeer || _socket == null || _screenStream == null) return;
    _creatingPeer = true;
    try {
      final pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      });
      _peerConnection = pc;
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null || _socket == null) return;
        _send({
          'type': 'candidate',
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      };
      pc.onConnectionState = (state) {
        final value = state.toString().toLowerCase();
        if (value.contains('connected')) {
          connected = true;
          status = audioShared ? 'Mirroring to your TV (with sound)' : 'Mirroring to your TV (no sound)';
        } else if (value.contains('failed')) {
          connected = false;
          status = 'Connection failed · keep both devices on the same Wi-Fi';
        } else if (value.contains('disconnected')) {
          connected = false;
          status = 'TV disconnected';
        } else if (value.contains('connecting')) {
          status = 'Connecting to TV…';
        }
        notifyListeners();
      };
      for (final track in _screenStream!.getTracks()) {
        await pc.addTrack(track, _screenStream!);
      }
      final offer = await pc.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(offer);
      _send({'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type});
      status = 'Connecting to Deeprowss TV Receiver…';
      notifyListeners();
    } catch (e) {
      error = 'Could not create the video connection: $e';
      status = 'Connection failed';
      notifyListeners();
      await _closePeer();
    } finally {
      _creatingPeer = false;
    }
  }

  /// Sends a channel/video link to the receiver page, which plays it itself.
  /// Starts a receiver session (no screen capture) when none is running.
  Future<bool> sendChannel({
    required String url,
    required String title,
    StreamKind? kind,
    String? referer,
    String? userAgent,
  }) async {
    if (url.trim().isEmpty || kind == StreamKind.invalid) return false;
    if (!running) {
      try { await start(captureScreen: false); } catch (_) { return false; }
    }
    _pendingPlay = {
      'type': 'play',
      'url': url,
      'title': title,
      'kind': kind?.name ?? 'video',
      if ((referer ?? '').trim().isNotEmpty) 'referer': referer!.trim(),
      if ((userAgent ?? '').trim().isNotEmpty) 'userAgent': userAgent!.trim(),
      'mode': kind == StreamKind.embed ? 'iframe' : 'media',
    };
    nowPlayingTitle = title;
    nowPlayingKind = kind?.name ?? 'video';
    // Keep a foreground media notification alive while the remote receiver
    // plays. Notification actions are forwarded over the same receiver socket.
    BackgroundPlayback.castActive = true;
    BackgroundPlayback.castHook = (action) {
      switch (action) {
        case 'play': case 'pause': case 'rewind': case 'forward':
          sendRemoteCommand(action);
          return true;
        case 'stop':
          sendRemoteCommand('stop');
          BackgroundPlayback.castActive = false;
          BackgroundPlayback.castHook = null;
          unawaited(BackgroundPlayback.stopCasting());
          return true;
        default:
          return false;
      }
    };
    unawaited(BackgroundPlayback.startCasting(title, 'Playing on Deeprowss receiver'));
    if (_socket != null) {
      _flushPending();
    } else {
      status = 'Open the receiver page and connect to start the channel';
      notifyListeners();
    }
    return true;
  }

  /// Sends a remote command to the connected browser receiver. Embed providers
  /// may expose different control APIs; the receiver reports unsupported commands.
  void setReceiverVolume(double value) {
    receiverVolume = value.round().clamp(0, 100).toInt();
    sendRemoteCommand('volume', value: receiverVolume.toDouble());
    notifyListeners();
  }

  bool sendRemoteCommand(String command, {double? value}) {
    if (_socket == null || _socket!.readyState != WebSocket.open) return false;
    _send({'type': 'remote', 'command': command, if (value != null) 'value': value});
    return true;
  }

  void _flushPending() {
    final play = _pendingPlay;
    if (play == null || _socket == null) return;
    _send(play);
    connected = true;
    status = 'Playing "${play['title']}" on the receiver page';
    notifyListeners();
  }

  void _send(Map<String, dynamic> value) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(value));
  }

  void _receiverDisconnected() {
    _socket = null;
    connected = false;
    unawaited(_closePeer());
    if (running) {
      status = urlMode
          ? 'Receiver disconnected · the channel keeps playing there'
          : 'TV disconnected · receiver can reconnect using the same code';
      notifyListeners();
    }
  }

  Future<void> _closePeer() async {
    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      try { await pc.close(); } catch (_) {}
      try { await pc.dispose(); } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (_stopping || (!running && _server == null && _screenStream == null)) return;
    _stopping = true;
    status = 'Stopping mirroring…';
    notifyListeners();
    running = false;
    try { await WakelockPlus.disable(); } catch (_) {}
    await _restorePhoneVolume();
    await _releaseResources(stopCapture: true);
    connected = false;
    audioShared = false;
    audioNote = null;
    urlMode = false;
    _pendingPlay = null;
    BackgroundPlayback.castHook = null;
    BackgroundPlayback.castActive = false;
    unawaited(BackgroundPlayback.stopCasting());
    nowPlayingTitle = '';
    nowPlayingKind = '';
    status = 'Mirroring stopped';
    _stopping = false;
    notifyListeners();
  }

  Future<void> _releaseResources({required bool stopCapture}) async {
    final socket = _socket;
    _socket = null;
    try { await socket?.close(WebSocketStatus.normalClosure, 'Deeprowss stopped'); } catch (_) {}
    await _closePeer();
    if (stopCapture) {
      try { await ScreenSharePlugin.stopScreenShare(); } catch (_) {}
    }
    final stream = _screenStream;
    _screenStream = null;
    try { await stream?.dispose(); } catch (_) {}
    final server = _server;
    _server = null;
    try { await server?.close(force: true); } catch (_) {}
    _pin = null;
    _url = null;
    _failedPairAttempts = 0;
    _pendingRemoteCandidates.clear();
  }

  Future<String?> _findLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = interfaces.expand((i) => i.addresses).where((a) => !a.isLoopback).toList();
    for (final address in addresses) {
      final value = address.address;
      if (value.startsWith('192.168.') || value.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(value)) return value;
    }
    return addresses.isEmpty ? null : addresses.first.address;
  }

  String _friendlyError(Object e) {
    final value = e.toString().toLowerCase();
    if (value.contains('permission') || value.contains('denied')) {
      return 'Screen-capture permission was not granted. Allow screen sharing and try again.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
