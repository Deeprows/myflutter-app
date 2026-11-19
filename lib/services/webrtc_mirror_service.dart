import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:screen_share_plugin/screen_share_plugin.dart' show ScreenSharePlugin, ScreenShareOptions;

import 'background_playback.dart';

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

  Future<void> start() async {
    if (running || _starting) return;
    _starting = true;
    error = null;
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

      _screenStream = await ScreenSharePlugin.startScreenShare(
        options: const ScreenShareOptions(
          audio: false,
          frameRate: 20,
          androidNotificationTitle: 'Deeprowss screen mirroring',
          androidNotificationText: 'Your screen is being shared with a TV',
          androidFullScreenOnly: true,
        ),
        onStopped: () => unawaited(stop()),
      );
      running = true;
      status = 'Waiting for your TV to connect…';
      notifyListeners();
      if (_socket != null) await _createPeerConnection();
    } catch (e) {
      error = _friendlyError(e);
      status = 'Could not start mirroring';
      _stopping = true;
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
          incoming.listen(_onSignal,
            onError: (_) => _receiverDisconnected(),
            onDone: _receiverDisconnected,
            cancelOnError: true,
          );
          status = 'TV connected · establishing video…';
          notifyListeners();
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

  Future<void> _onSignal(dynamic raw) async {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (message['type']) {
        case 'ready':
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
          status = 'Mirroring to your TV';
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
      status = 'TV disconnected · receiver can reconnect using the same code';
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
    await _releaseResources(stopCapture: true);
    connected = false;
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
