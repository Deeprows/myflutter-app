import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Manufacturer remote adapters. Pairing is TV-controlled: LG/Samsung may
/// display an approval prompt and newer firmware can restrict third-party apps.
class TvRemoteService {
  static String _hostOnly(String host) => host.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').split(':').first;

  static Future<bool> roku(String host, String key) async {
    final uri = Uri.parse('http://${_hostOnly(host)}:8060/keypress/$key');
    try { final r = await http.post(uri).timeout(const Duration(seconds: 3)); return r.statusCode < 400; }
    catch (_) { return false; }
  }

  static Future<bool> lgWebOs(String host, String key, {String? clientKey}) async {
    final prefs = await SharedPreferences.getInstance();
    clientKey ??= prefs.getString('deeprowss_lg_pair_$host');
    WebSocket? socket;
    try {
      socket = await WebSocket.connect('ws://${_hostOnly(host)}:3000',
          headers: {'Origin': 'http://${_hostOnly(host)}:3000'}).timeout(const Duration(seconds: 4));
      final done = Completer<bool>();
      socket.listen((raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (msg['type'] == 'registered') {
            final registeredKey = (msg['payload'] as Map?)?['client-key'] as String?;
            if (registeredKey != null && registeredKey.isNotEmpty) {
              prefs.setString('deeprowss_lg_pair_$host', registeredKey);
            }
            final payload = jsonEncode({'id':'deeprowss-remote','type':'request','uri':'ssap://com.webos.service.tv.systemproperty/getSystemInfo'});
            socket!.add(payload);
            if (!done.isCompleted) done.complete(true);
          }
        } catch (_) {}
      }, onError: (_) { if (!done.isCompleted) done.complete(false); });
      socket.add(jsonEncode({'type':'register','id':'deeprowss-remote','payload':{
        'manifest': {'manifestVersion':1,'appVersion':'1.0','signed':{'created':'20260101','appId':'com.deeprows.remote','vendorId':'com.deeprows','localizedAppNames':{'':'Deeprowss Remote'},'localizedVendorNames':{'':'Deeprowss'},'permissions':['CONTROL_AUDIO','CONTROL_INPUT_TEXT','CONTROL_MOUSE_AND_KEYBOARD','CONTROL_POWER','READ_INSTALLED_APPS','READ_RUNNING_APPS','READ_TV_CURRENT_CHANNEL','READ_TV_CHANNEL_LIST','WRITE_NOTIFICATION_TOAST']},'permissions':['LAUNCH','CONTROL_AUDIO','CONTROL_INPUT_TEXT','CONTROL_MOUSE_AND_KEYBOARD','CONTROL_POWER']}, if (clientKey != null) 'client-key':clientKey}}));
      final registered = await done.future.timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (!registered) return false;
      socket.add(jsonEncode({'type':'request','id':'key-${DateTime.now().microsecondsSinceEpoch}','uri':'ssap://com.webos.service.networkinput/sendEvent','payload':{'keyCode':key}}));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return true;
    } catch (_) { return false; }
    finally { await socket?.close(); }
  }

  static Future<bool> samsung(String host, String key, {String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    token ??= prefs.getString('deeprowss_samsung_pair_$host');
    WebSocket? socket;
    try {
      final auth = base64Encode(utf8.encode('Deeprowss Remote'));
      final uri = Uri.parse('ws://${_hostOnly(host)}:8001/api/v2/channels/samsung.remote.control?name=$auth${token == null ? '' : '&token=$token'}');
      socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 4));
      socket.listen((raw) {
        try {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          final data = message['data'] as Map?;
          final receivedToken = data?['token']?.toString();
          if (receivedToken != null && receivedToken.isNotEmpty) {
            prefs.setString('deeprowss_samsung_pair_$host', receivedToken);
          }
        } catch (_) {}
      });
      socket.add(jsonEncode({'method':'ms.remote.control','params':{'Cmd':'Click','DataOfCmd':key,'Option':'false','TypeOfRemote':'SendRemoteKey'}}));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return true;
    } catch (_) { return false; }
    finally { await socket?.close(); }
  }
}
