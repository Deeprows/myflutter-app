import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
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
  static const int _receiverPort = 42385;
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
  Map<String, String> _mediaHeaders = {};
  String status = 'Not running';
  String? error;

  String? get url => _url;
  String? get pin => _pin;
  static const String _receiverPageBase = String.fromEnvironment(
    'DEEProWSS_MIRROR_RECEIVER_URL',
    defaultValue: 'https://deeprows.github.io/myflutter-app/',
  );
  String? get pairingUrl => _url == null || _pin == null
      ? null
      : Uri.parse(_receiverPageBase).replace(queryParameters: {
          'host': Uri.parse(_url!).authority,
          'pin': _pin!,
        }).toString();

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
      _server = await HttpServer.bind(InternetAddress(ip), _receiverPort, shared: true);
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
              wantAudio = s.getAudioTracks().isNotEmpty;
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
        if (request.uri.path == '/media' && request.method == 'OPTIONS') {
          request.response
            ..statusCode = HttpStatus.noContent
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
            ..headers.set('Access-Control-Allow-Headers', 'Range')
            ..headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
          await request.response.close();
          continue;
        }
        if (request.uri.path == '/media' && (request.method == 'GET' || request.method == 'HEAD')) {
          await _proxyMedia(request);
          continue;
        }
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
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, pairingUrl ?? _receiverPageBase)
            ..headers.set('cache-control', 'no-store');
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

  Future<void> _proxyMedia(HttpRequest request) async {
    final raw = request.uri.queryParameters['url'];
    final uri = Uri.tryParse(raw ?? '');
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final upstream = await client.openUrl(request.method, uri);
      _mediaHeaders.forEach((k, v) => upstream.headers.set(k, v));
      if (!_mediaHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        upstream.headers.set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
      final response = await upstream.close().timeout(const Duration(seconds: 20));
      final contentType = response.headers.contentType?.mimeType.toLowerCase() ?? '';
      final isHls = uri.path.toLowerCase().endsWith('.m3u8') || contentType.contains('mpegurl');
      final out = request.response;
      out.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges')
        ..set('Cache-Control', 'no-store');
      if (isHls && response.statusCode < 400) {
        final body = await response.transform(utf8.decoder).join();
        if (body.trimLeft().startsWith('#EXTM3U')) {
          final origin = 'http://${request.headers.value(HttpHeaders.hostHeader)}';
          String proxied(String value) {
            final absolute = uri.resolve(value.trim()).toString();
            return '$origin/media?url=${Uri.encodeQueryComponent(absolute)}';
          }
          final rewritten = body.split('\n').map((line) {
            final value = line.trimRight();
            if (value.isEmpty) return value;
            if (value.startsWith('#')) {
              return value.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) => 'URI="${proxied(m.group(1)!)}"');
            }
            return proxied(value);
          }).join('\n');
          final bytes = utf8.encode(rewritten);
          out
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl')
            ..contentLength = bytes.length;
          if (request.method != 'HEAD') out.add(bytes);
          await out.close();
          return;
        }
      }
      out.statusCode = response.statusCode;
      if (contentType.isNotEmpty) out.headers.set(HttpHeaders.contentTypeHeader, contentType);
      for (final header in [HttpHeaders.contentRangeHeader, HttpHeaders.acceptRangesHeader]) {
        final value = response.headers.value(header);
        if (value != null) out.headers.set(header, value);
      }
      if (response.contentLength >= 0) out.contentLength = response.contentLength;
      if (request.method != 'HEAD') await out.addStream(response);
      await out.close();
    } catch (e) {
      try {
        request.response
          ..statusCode = HttpStatus.badGateway
          ..write('Upstream stream proxy failed: $e');
        await request.response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
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
        case 'receiver_status':
          if (message['playing'] is bool) {
            status = (message['playing'] as bool)
                ? 'Receiver playing · ${message['title'] ?? 'Video'}'
                : 'Receiver connected · playback paused';
            connected = true;
            notifyListeners();
          }
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
    if (url.trim().isEmpty || kind == StreamKind.embed || kind == StreamKind.invalid) return false;
    if (!running) {
      try { await start(captureScreen: false); } catch (_) { return false; }
    }
    _mediaHeaders = {
      if ((referer ?? '').trim().isNotEmpty) 'Referer': referer!.trim(),
      if ((userAgent ?? '').trim().isNotEmpty) 'User-Agent': userAgent!.trim(),
    };
    // Route receiver playback through the phone so CORS, Referer and
    // User-Agent restrictions can be handled before the TV browser sees it.
    final playUrl = '$_url/media?url=${Uri.encodeQueryComponent(url)}';
    _pendingPlay = {
      'type': 'play',
      'url': playUrl,
      'title': title,
      'kind': kind?.name ?? 'video',
    };
    if (_socket != null) {
      _flushPending();
    } else {
      status = 'Open the receiver page and connect to start the channel';
      notifyListeners();
    }
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
    _mediaHeaders = {};
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
