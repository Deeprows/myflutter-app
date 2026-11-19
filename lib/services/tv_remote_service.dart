import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TvRemoteInfo {
  final String brand;
  final String host;
  final String model;
  final String name;
  final bool pairingRequired;

  const TvRemoteInfo({
    required this.brand,
    required this.host,
    required this.model,
    required this.name,
    this.pairingRequired = true,
  });
}

/// TV-specific remote adapters. Pairing approval remains controlled by the TV.
/// The service validates device endpoints and waits for registration responses
/// where the manufacturer protocol provides them.
class TvRemoteService {
  static String _hostOnly(String host) {
    var value = host.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    if (value.startsWith('[')) return value.substring(1, value.indexOf(']'));
    return value.split(':').first;
  }

  static Future<TvRemoteInfo?> detect(String host) async {
    final h = _hostOnly(host);
    if (h.isEmpty) return null;

    // Roku ECP exposes a small XML identity endpoint on port 8060.
    try {
      final response = await http.get(Uri.parse('http://$h:8060/query/device-info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 && response.body.toLowerCase().contains('<device-info')) {
        final name = _xmlTag(response.body, 'friendly-device-name') ?? 'Roku TV';
        final model = _xmlTag(response.body, 'model-name') ?? _xmlTag(response.body, 'model-number') ?? 'Roku';
        return TvRemoteInfo(brand: 'Roku', host: h, name: name, model: model);
      }
    } catch (_) {}

    // Samsung Tizen SmartThings remote API usually exposes /api/v2/.
    for (final secure in [true, false]) {
      HttpClient? client;
      try {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        Uri uri;
        if (secure) {
          client.badCertificateCallback = (certificate, certHost, _) => certHost == h;
          uri = Uri.parse('https://$h:8002/api/v2/');
        } else {
          uri = Uri.parse('http://$h:8001/api/v2/');
        }
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(const Duration(seconds: 3));
        final body = await utf8.decodeStream(response).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final device = data['device'] as Map<String, dynamic>? ?? const {};
          final model = device['modelName']?.toString() ?? device['model']?.toString() ?? 'Samsung Smart TV';
          final name = device['name']?.toString() ?? 'Samsung TV';
          return TvRemoteInfo(brand: 'Samsung', host: h, name: name, model: model);
        }
      } catch (_) {
      } finally {
        client?.close(force: true);
      }
    }

    // LG webOS commonly listens on 3000 (plain) or 3001 (TLS). A TCP probe
    // avoids unexpectedly triggering the TV's pairing prompt during discovery.
    for (final port in [3001, 3000]) {
      Socket? socket;
      try {
        socket = await Socket.connect(h, port, timeout: const Duration(seconds: 2));
        return TvRemoteInfo(brand: 'LG webOS', host: h, name: 'LG webOS TV', model: 'webOS', pairingRequired: true);
      } catch (_) {
      } finally {
        socket?.destroy();
      }
    }
    return null;
  }

  static String? _xmlTag(String xml, String name) {
    final match = RegExp('<$name>([\\s\\S]*?)</$name>', caseSensitive: false).firstMatch(xml);
    return match?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  static Future<bool> roku(String host, String key) async {
    final h = _hostOnly(host);
    final safeKey = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (h.isEmpty || safeKey.isEmpty) return false;
    try {
      final r = await http.post(Uri.parse('http://$h:8060/keypress/$safeKey'))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == HttpStatus.ok || r.statusCode == HttpStatus.accepted || r.statusCode == HttpStatus.noContent;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> lgWebOs(String host, String key, {String? clientKey}) async {
    final h = _hostOnly(host);
    if (h.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    clientKey ??= prefs.getString('deeprowss_lg_pair_$h');

    for (final endpoint in ['wss://$h:3001', 'ws://$h:3000']) {
      WebSocket? socket;
      HttpClient? client;
      final registered = Completer<String?>();
      final response = Completer<bool>();
      final requestId = 'deeprowss-key-${DateTime.now().microsecondsSinceEpoch}';
      try {
        if (endpoint.startsWith('wss:')) {
          client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
          // LG TVs commonly use a self-signed local certificate. Trust only
          // this explicitly entered LAN host for this one pairing session.
          client.badCertificateCallback = (certificate, certHost, _) => certHost == h;
        }
        socket = await WebSocket.connect(endpoint, customClient: client)
            .timeout(const Duration(seconds: 5));
        socket.listen((raw) async {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            if (msg['type'] == 'registered' && !registered.isCompleted) {
              final payload = msg['payload'] as Map?;
              final saved = payload?['client-key']?.toString();
              if (saved != null && saved.isNotEmpty) {
                await prefs.setString('deeprowss_lg_pair_$h', saved);
              }
              registered.complete(saved);
            }
            if (msg['id'] == requestId && !response.isCompleted) {
              final payload = msg['payload'] as Map?;
              response.complete(msg['type'] == 'response' && (payload?['returnValue'] != false));
            }
          } catch (_) {}
        }, onError: (_) {
          if (!registered.isCompleted) registered.complete(null);
          if (!response.isCompleted) response.complete(false);
        });

        socket.add(jsonEncode({
          'type': 'register',
          'id': 'deeprowss-remote',
          'payload': {
            'manifest': {
              'manifestVersion': 1,
              'appVersion': '1.1',
              'signed': {
                'created': '20261119',
                'appId': 'com.deeprows.remote',
                'vendorId': 'com.deeprows',
                'localizedAppNames': {'': 'Deeprowss Remote'},
                'localizedVendorNames': {'': 'Deeprowss'},
                'permissions': [
                  'CONTROL_AUDIO', 'CONTROL_INPUT_TEXT', 'CONTROL_MOUSE_AND_KEYBOARD',
                  'CONTROL_POWER', 'READ_INSTALLED_APPS', 'READ_RUNNING_APPS',
                  'READ_TV_CURRENT_CHANNEL', 'READ_TV_CHANNEL_LIST',
                  'WRITE_NOTIFICATION_TOAST',
                ],
              },
              'permissions': ['LAUNCH', 'CONTROL_AUDIO', 'CONTROL_INPUT_TEXT', 'CONTROL_MOUSE_AND_KEYBOARD', 'CONTROL_POWER'],
            },
            if (clientKey != null) 'client-key': clientKey,
          },
        }));

        final newKey = await registered.future.timeout(const Duration(seconds: 18), onTimeout: () => null);
        if (newKey == null && clientKey == null) continue;
        socket.add(jsonEncode({
          'type': 'request',
          'id': requestId,
          'uri': 'ssap://com.webos.service.networkinput/sendEvent',
          'payload': {'keyCode': key},
        }));
        return await response.future.timeout(const Duration(seconds: 4), onTimeout: () => false);
      } catch (_) {
        // Try the other webOS transport.
      } finally {
        try { await socket?.close(); } catch (_) {}
        client?.close(force: true);
      }
    }
    return false;
  }

  static Future<bool> samsung(String host, String key, {String? token}) async {
    final h = _hostOnly(host);
    if (h.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    token ??= prefs.getString('deeprowss_samsung_pair_$h');
    final encodedName = base64Encode(utf8.encode('Deeprowss Remote'));

    // Newer Tizen versions use TLS on 8002; older models expose port 8001.
    for (final secure in [true, false]) {
      WebSocket? socket;
      HttpClient? client;
      try {
        final uri = Uri.parse('${secure ? 'wss' : 'ws'}://$h:${secure ? 8002 : 8001}/api/v2/channels/samsung.remote.control?name=$encodedName${token == null ? '' : '&token=$token'}');
        if (secure) {
          client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
          client.badCertificateCallback = (certificate, certHost, _) => certHost == h;
        }
        socket = await WebSocket.connect(uri.toString(), customClient: client)
            .timeout(const Duration(seconds: 5));
        final connected = Completer<void>();
        socket.listen((raw) async {
          try {
            final message = jsonDecode(raw as String) as Map<String, dynamic>;
            if (message['event'] == 'ms.channel.connect' && !connected.isCompleted) {
              final data = message['data'] as Map?;
              final receivedToken = data?['token']?.toString();
              if (receivedToken != null && receivedToken.isNotEmpty) {
                token = receivedToken;
                await prefs.setString('deeprowss_samsung_pair_$h', receivedToken);
              }
              connected.complete();
            }
          } catch (_) {}
        }, onError: (_) { if (!connected.isCompleted) connected.completeError(StateError('TV remote connection failed')); });

        // First-time pairing may require the user to approve the app on the
        // TV. Wait longer when no saved token exists so that approval can finish.
        try {
          await connected.future.timeout(Duration(seconds: token == null ? 15 : 4));
        } catch (_) {}
        if (socket.readyState != WebSocket.open || (token == null && !connected.isCompleted)) continue;
        socket.add(jsonEncode({
          'method': 'ms.remote.control',
          'params': {'Cmd': 'Click', 'DataOfCmd': key, 'Option': 'false', 'TypeOfRemote': 'SendRemoteKey'},
        }));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return socket.readyState == WebSocket.open;
      } catch (_) {
        // Try legacy non-TLS transport.
      } finally {
        try { await socket?.close(); } catch (_) {}
        client?.close(force: true);
      }
    }
    return false;
  }
}
