import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cast_target.dart';
import 'background_playback.dart';
import 'stream_resolver.dart';

class _KodiAuth implements Exception {
  const _KodiAuth();
}

enum _KodiResult { ok, unavailable, failed }

/// A TV / speaker on the Wi-Fi that can play a link by itself (DLNA / UPnP
/// "media renderer": Samsung, LG, Sony, Hisense, TCL, Xiaomi, Android TV...).
class CastDevice {
  final String name;
  final String location;
  final String avControl;
  final String avType;
  final String? rcControl;
  final String? rcType;
  final String? manufacturer;
  final String? model;

  const CastDevice({
    required this.name,
    required this.location,
    required this.avControl,
    required this.avType,
    this.rcControl,
    this.rcType,
    this.manufacturer,
    this.model,
  });

  /// Kodi (and XBMC) advertise themselves as DLNA renderers too, but they
  /// play far more reliably when driven through their own JSON-RPC API.
  bool get isKodi {
    final s = '$name ${manufacturer ?? ''} ${model ?? ''}'.toLowerCase();
    return s.contains('kodi') || s.contains('xbmc');
  }

  String get host => Uri.tryParse(location)?.host ?? location;
}

/// Sends a channel / video to a TV so the TV plays it by itself.
///
/// Why this keeps working when the phone is locked or the app is minimised:
///  * The TV pulls the stream directly (or through a tiny relay inside the
///    app when the stream needs a Referer / User-Agent or is https).
///  * While casting, the Android foreground service (see
///    BackgroundPlayback) holds a CPU + Wi-Fi lock, so the relay and the
///    remote control keep running with the screen off.
///
/// Web embeds (pages, iframes) cannot be sent as a link; for those the
/// caller falls back to screen mirroring ([openMirrorSettings]).
class CastService extends ChangeNotifier {
  CastService._();
  static final CastService instance = CastService._();

  final List<CastDevice> devices = [];
  bool scanning = false;
  bool connecting = false;
  bool casting = false;
  bool tvPlaying = false;
  CastDevice? device;
  String castTitle = '';

  /// TV volume 0-100, or -1 when the TV does not report it.
  int tvVolume = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  final List<CastDevice> savedDevices = [];
  final List<Map<String, String>> recentSessions = [];
  Timer? _sleepTimer;
  DateTime? sleepEndsAt;
  String? error;

  /// The last channel / video that could be cast. The Decoder keeps it so
  /// opening the Decoder again (or from another page) still knows what to play.
  CastTarget? lastTarget;

  // ------------------------------------------------------------ cast log
  /// Everything the cast engine does, newest last. Shown on the Devices tab
  /// so a failure ("Playback failed" on the TV) can actually be diagnosed.
  final List<String> log = [];
  int _relayHits = 0;

  void _log(String m) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $m');
    if (log.length > 150) log.removeRange(0, log.length - 150);
    if (kDebugMode) debugPrint('[cast] $m');
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  String get logText => log.join('\n');

  /// URL without its query string (tokens) for logging.
  static String _short(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}${u.path}';
  }

  // ------------------------------------------------------------ Kodi state
  int? _kodiPort;
  bool _kodiMode = false;
  int? _kodiPlayerId;
  bool kodiNeedsLogin = false;
  String? kodiHint;
  String _kodiUser = 'kodi';
  String _kodiPass = '';

  Future<void> _loadKodiLogin() async {
    final prefs = await SharedPreferences.getInstance();
    _kodiUser = prefs.getString('kodi_user') ?? 'kodi';
    _kodiPass = prefs.getString('kodi_pass') ?? '';
  }

  Future<void> setKodiLogin(String user, String pass) async {
    _kodiUser = user;
    _kodiPass = pass;
    _kodiPort = null;
    kodiNeedsLogin = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kodi_user', user);
    await prefs.setString('kodi_pass', pass);
    _log('Kodi login saved (user "$user").');
    notifyListeners();
  }

  Future<void> loadDeviceMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('decoder_saved_tvs') ?? const <String>[];
    final recent = prefs.getStringList('decoder_cast_recents') ?? const <String>[];
    savedDevices.clear();
    for (final raw in saved) {
      try {
        final d = await _describe(raw);
        if (d != null) savedDevices.add(d);
      } catch (_) {}
    }
    recentSessions
      ..clear()
      ..addAll(recent.map((v) {
        final bits = v.split('|');
        return <String, String>{'title': bits.first, 'device': bits.length > 1 ? bits[1] : ''};
      }));
    notifyListeners();
  }

  Future<void> saveDevice(CastDevice d) async {
    if (!savedDevices.any((x) => x.host == d.host)) savedDevices.add(d);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('decoder_saved_tvs', savedDevices.map((x) => x.location).toList());
    notifyListeners();
  }

  Future<void> removeSavedDevice(CastDevice d) async {
    savedDevices.removeWhere((x) => x.host == d.host);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('decoder_saved_tvs', savedDevices.map((x) => x.location).toList());
    notifyListeners();
  }

  Future<CastDevice?> addDeviceByIp(String value) async {
    var input = value.trim();
    if (input.isEmpty) return null;
    if (!input.contains('://')) input = 'http://$input';
    final base = Uri.tryParse(input);
    if (base == null || base.host.isEmpty) return null;
    final candidates = <String>{base.toString()};
    if (base.path == '/' || base.path.isEmpty) {
      for (final path in ['/description.xml', '/rootDesc.xml', '/device.xml', '/upnp/description.xml']) {
        candidates.add(base.replace(path: path).toString());
      }
    }
    for (final url in candidates) {
      final d = await _describe(url);
      if (d != null) {
        if (!devices.any((x) => x.host == d.host)) devices.add(d);
        notifyListeners();
        return d;
      }
    }
    error = 'No compatible DLNA media renderer was found at that address.';
    notifyListeners();
    return null;
  }

  Future<void> setSleepTimer(Duration? value) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt = null;
    if (value != null && value > Duration.zero) {
      sleepEndsAt = DateTime.now().add(value);
      _sleepTimer = Timer(value, () { stop(); });
    }
    notifyListeners();
  }

  Timer? _poll;
  int _fails = 0;
  int _stoppedPolls = 0;
  bool _everPlayed = false;

  HttpServer? _server;
  HttpClient? _client;
  Map<String, String> _upHeaders = {};
  File? _localFile;

  // ------------------------------------------------------------- discovery

  static const _ssdpAddr = '239.255.255.250';

  /// What the last scan saw, shown on the Devices tab to help troubleshooting.
  String? scanReport;

  /// One SSDP search round. Binding to the phone's Wi-Fi address makes the
  /// multicast search leave through Wi-Fi even when mobile data is on.
  Future<Set<String>> _ssdpRound(InternetAddress bindTo, Duration duration) async {
    final locations = <String>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(bindTo, 0);
      final s = sock;
      final re = RegExp(r'^location:\s*(\S+)', caseSensitive: false, multiLine: true);
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        Datagram? d = s.receive();
        while (d != null) {
          final m = re.firstMatch(utf8.decode(d.data, allowMalformed: true));
          if (m != null) locations.add(m.group(1)!.trim());
          d = s.receive();
        }
      });
      const targets = [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'upnp:rootdevice',
        'ssdp:all',
      ];
      void ping() {
        for (final st in targets) {
          final msg = 'M-SEARCH * HTTP/1.1\r\n'
              'HOST: $_ssdpAddr:1900\r\n'
              'MAN: "ssdp:discover"\r\n'
              'MX: 2\r\n'
              'ST: $st\r\n\r\n';
          try {
            s.send(utf8.encode(msg), InternetAddress(_ssdpAddr), 1900);
          } catch (_) {}
        }
      }

      final step = Duration(milliseconds: duration.inMilliseconds ~/ 3);
      ping();
      await Future<void>.delayed(step);
      ping();
      await Future<void>.delayed(step);
      ping();
      await Future<void>.delayed(step);
    } finally {
      sock?.close();
    }
    return locations;
  }

  /// Looks for TVs on the Wi-Fi (about 6 seconds).
  Future<void> scan({Duration duration = const Duration(seconds: 6)}) async {
    if (scanning) return;
    scanning = true;
    error = null;
    scanReport = null;
    notifyListeners();
    await BackgroundPlayback.requestLocalNetwork();
    await BackgroundPlayback.setMulticast(true);
    var locations = <String>{};
    String? ip;
    try {
      ip = await _lanIp();
      if (ip != null) {
        locations = await _ssdpRound(InternetAddress(ip), duration);
      }
      if (locations.isEmpty) {
        // Second try on every interface, in case the Wi-Fi address guess was wrong.
        locations = await _ssdpRound(InternetAddress.anyIPv4, duration);
      }
    } catch (_) {
      error = 'Could not search for TVs. Check your Wi-Fi connection.';
    } finally {
      await BackgroundPlayback.setMulticast(false);
    }

    final found = await Future.wait(locations.map(_describe));
    final seen = <String>{};
    devices
      ..clear()
      ..addAll(found.whereType<CastDevice>().where((d) => seen.add('${d.name}|${d.host}')));
    devices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final hosts = locations.map((l) => Uri.tryParse(l)?.host ?? l).toSet().take(8).join(', ');
    scanReport = 'Phone Wi-Fi address: ${ip ?? 'not found'}\n'
        'Devices that answered the search: ${locations.length}'
        '${hosts.isEmpty ? '' : ' ($hosts)'}\n'
        'Playable DLNA TVs among them: ${devices.length}';
    scanning = false;
    _log('Scan: ${locations.length} answered, ${devices.length} playable'
        '${devices.isEmpty ? '' : ' (${devices.map((d) => d.isKodi ? '${d.name} [Kodi]' : d.name).join(', ')})'}');
    if (devices.isEmpty && error == null) {
      error = locations.isEmpty
          ? 'No device answered. The TV / laptop may be on another network, the router may block device-to-device traffic, or a firewall on the TV / laptop is blocking the search.'
          : 'Some devices answered, but none is a DLNA player that Deeprowss can use.';
    }
    notifyListeners();
  }

  Future<CastDevice?> _describe(String location) async {
    try {
      final r = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) return null;
      final xml = utf8.decode(r.bodyBytes, allowMalformed: true);
      final baseRaw = _tag(xml, 'URLBase');
      final base = Uri.parse(
          (baseRaw == null || baseRaw.isEmpty) ? location : baseRaw);
      String? avUrl, avType, rcUrl, rcType;
      for (final m in RegExp(r'<service>([\s\S]*?)</service>', caseSensitive: false)
          .allMatches(xml)) {
        final block = m.group(1)!;
        final type = _tag(block, 'serviceType') ?? '';
        final ctl = _tag(block, 'controlURL');
        if (ctl == null) continue;
        final abs = base.resolve(ctl.trim()).toString();
        if (type.contains('AVTransport') && avUrl == null) {
          avUrl = abs;
          avType = type.trim();
        } else if (type.contains('RenderingControl') && rcUrl == null) {
          rcUrl = abs;
          rcType = type.trim();
        }
      }
      if (avUrl == null || avType == null) return null;
      final name = _unesc(_tag(xml, 'friendlyName') ?? Uri.parse(location).host);
      return CastDevice(
        name: name,
        location: location,
        avControl: avUrl,
        avType: avType,
        rcControl: rcUrl,
        rcType: rcType,
        manufacturer: _unesc(_tag(xml, 'manufacturer') ?? ''),
        model: _unesc(_tag(xml, 'modelName') ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- casting

  /// Sends a stream link to [d]. Returns true when the TV accepted it.
  Future<bool> castUrl(
    CastDevice d,
    String url, {
    required String title,
    StreamKind? kind,
    String? referer,
    String? userAgent,
  }) async {
    // 0. Work out what the link really is. Links without a file extension and
    //    web pages that hide the real stream cannot be sent as they are:
    //    find the actual video address first.
    if (kind == null || kind == StreamKind.embed || kind == StreamKind.invalid) {
      try {
        final found = await _resolveLink(url, referer: referer, userAgent: userAgent);
        if (found == null) {
          error = 'This link is a web page that hides its video, so it cannot be sent to Kodi / the TV as a stream. Use the Mirror tab to show it on the screen instead.';
          _log('Could not find a stream inside ${_short(url)}');
          notifyListeners();
          return false;
        }
        _log('Real stream: ${_short(found.url)} (${found.kind.name})');
        url = found.url;
        kind = found.kind;
        referer = found.referer;
      } catch (e) {
        _log('Link check failed: $e');
      }
    }
    final headers = <String, String>{
      if ((userAgent ?? '').trim().isNotEmpty) 'User-Agent': userAgent!.trim(),
      if ((referer ?? '').trim().isNotEmpty) 'Referer': referer!.trim(),
    };
    _log('Cast "$title" to ${d.name} (${d.host}) <- ${_short(url)}'
        '${headers.isEmpty ? '' : ' [headers: ${headers.keys.join(', ')}]'}');

    // 1. Make sure the channel itself answers. A dead / blocked stream is the
    //    most common reason a TV or Kodi reports "Playback failed".
    try {
      await _probeStream(url, headers);
    } catch (e) {
      error = e is String ? e : 'Could not check the stream.';
      _log('Stream check failed: $error');
      notifyListeners();
      return false;
    }

    // 2. Kodi: drive it through its own API (no relay, headers are native).
    if (d.isKodi) {
      final r = await _castKodi(d, url, title, headers);
      if (r != _KodiResult.unavailable) return r == _KodiResult.ok;
      _log('Kodi web control not usable, falling back to DLNA.');
    }

    // 3. Everything else (and Kodi without web control): DLNA / UPnP.
    final ok = await _begin(d, title, () async {
      _upHeaders = headers;
      final lower = url.toLowerCase();
      final needsRelay = headers.isNotEmpty || lower.startsWith('https');
      final mime = _mimeFor(kind, lower);
      if (!needsRelay) return (url: url, mime: mime);
      final origin = await _ensureServer();
      final name = kind == StreamKind.hls
          ? 'index.m3u8'
          : kind == StreamKind.dash
              ? 'index.mpd'
              : _nameOf(url);
      return (url: '$origin/p/${_b64(url)}/$name', mime: mime);
    });
    if (d.isKodi) {
      // Show why Kodi did / did not play, straight from Kodi's own log.
      unawaited(Future<void>.delayed(Duration(seconds: ok ? 8 : 1), () => fetchKodiLog(d)));
    }
    return ok;
  }

  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Finds the real media address behind [page]: the link itself when it is
  /// already a stream (even without a file extension), otherwise the first
  /// .m3u8 / .mpd / .mp4 address written in the page or in its iframes.
  Future<({String url, StreamKind kind, String? referer})?> _resolveLink(
    String page, {
    String? referer,
    String? userAgent,
    int depth = 0,
  }) async {
    final direct = StreamResolver.resolve(page);
    if (direct.usesHtmlPlayer) {
      return (url: direct.url, kind: direct.kind, referer: referer);
    }
    final sniffed = await StreamResolver.sniff(page, referer: referer, userAgent: userAgent);
    if (sniffed != null) return (url: page, kind: sniffed, referer: referer);
    if (depth > 2) return null;

    final res = await http.get(Uri.parse(page), headers: {
      'User-Agent': (userAgent ?? '').trim().isEmpty ? _browserUa : userAgent!.trim(),
      if ((referer ?? '').trim().isNotEmpty) 'Referer': referer!.trim(),
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode >= 400) return null;
    var text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (text.length > 1500000) text = text.substring(0, 1500000);
    text = text
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u002F', '/');
    final base = Uri.parse(page);

    for (final entry in const [
      (r'\.m3u8', StreamKind.hls),
      (r'\.mpd', StreamKind.dash),
      (r'\.(?:mp4|webm|mkv)', StreamKind.video),
    ]) {
      final m = RegExp('https?://[^\\s"\'<>\\\\)]+?${entry.$1}(?:\\?[^\\s"\'<>\\\\)]*)?',
              caseSensitive: false)
          .firstMatch(text);
      if (m != null) {
        return (url: m.group(0)!, kind: entry.$2, referer: page);
      }
    }
    for (final m in RegExp(r'''<iframe[^>]+(?:data-)?src\s*=\s*["']([^"']+)["']''', caseSensitive: false)
        .allMatches(text)) {
      var src = m.group(1)!.trim();
      if (src.startsWith('about:') || src.startsWith('javascript:')) continue;
      final abs = base.resolve(src.startsWith('//') ? 'https:$src' : src).toString();
      final inner = await _resolveLink(abs, referer: page, userAgent: userAgent, depth: depth + 1);
      if (inner != null) return inner;
    }
    return null;
  }

  /// Quick search for the real stream inside a link or web page (no web
  /// view). Returns null when the page hides it; the app then opens its
  /// in-app stream finder.
  Future<({String url, StreamKind kind, String? referer})?> resolveStream(
    String page, {
    String? referer,
    String? userAgent,
  }) async {
    try {
      return await _resolveLink(page, referer: referer, userAgent: userAgent)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _log('Quick search failed: $e');
      return null;
    }
  }

  /// Opens the stream from the phone once, with the same headers the TV will
  /// use, so a dead / geo-blocked / HTML-error stream is reported here with a
  /// clear message instead of as a vague "Playback failed" on the TV.
  Future<void> _probeStream(String url, Map<String, String> headers) async {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = null;
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      req.followRedirects = true;
      req.maxRedirects = 6;
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close().timeout(const Duration(seconds: 10));
      final ct = res.headers.contentType?.mimeType.toLowerCase() ?? '';
      List<int> head = const [];
      try {
        head = await res.first.timeout(const Duration(seconds: 8));
      } catch (_) {}
      _log('Stream check: HTTP ${res.statusCode}, type ${ct.isEmpty ? 'unknown' : ct}, '
          '${head.length} bytes read');
      if (res.statusCode >= 400) {
        throw 'This channel is not responding right now (HTTP ${res.statusCode}), '
            'so Kodi / the TV shows "Playback failed". Try another channel.';
      }
      final sniff = utf8
          .decode(head.take(300).toList(), allowMalformed: true)
          .trimLeft()
          .toLowerCase();
      if (ct.contains('html') ||
          sniff.startsWith('<!doctype') ||
          sniff.startsWith('<html')) {
        throw 'The channel returned a web page instead of video (it may need a login, '
            'be blocked in your country or be offline). Try another channel.';
      }
    } on String {
      rethrow;
    } catch (e) {
      // Network hiccup on the phone side: do not block casting, just note it.
      _log('Stream check skipped: $e');
    } finally {
      c.close(force: true);
    }
  }

  /// Sends a video file stored on the phone (served over Wi-Fi).
  Future<bool> castFile(CastDevice d, File file, {required String title}) async {
    return _begin(d, title, () async {
      _localFile = file;
      final origin = await _ensureServer();
      final name = _nameOf(file.path);
      return (url: '$origin/f/$name', mime: _mimeOfPath(file.path));
    });
  }

  Future<bool> _begin(
    CastDevice d,
    String title,
    Future<({String url, String mime})> Function() prepare,
  ) async {
    if (connecting) return false;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      if (casting) await stop();
      final p = await prepare();
      await _soapQuiet(d.avControl, d.avType, 'Stop', '<InstanceID>0</InstanceID>');
      final didl = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
          '<item id="0" parentID="-1" restricted="1">'
          '<dc:title>${_esc(title)}</dc:title>'
          '<upnp:class>object.item.videoItem</upnp:class>'
          '<res protocolInfo="http-get:*:${p.mime}:*">${_esc(p.url)}</res>'
          '</item></DIDL-Lite>';
      await _soap(
        d.avControl,
        d.avType,
        'SetAVTransportURI',
        '<InstanceID>0</InstanceID>'
            '<CurrentURI>${_esc(p.url)}</CurrentURI>'
            '<CurrentURIMetaData>${_esc(didl)}</CurrentURIMetaData>',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _soap(d.avControl, d.avType, 'Play',
          '<InstanceID>0</InstanceID><Speed>1</Speed>');

      _kodiMode = false;
      await _startSession(d, title);
      return true;
    } catch (e) {
      _log('DLNA cast failed: $e');
      _cleanup();
      error = e is TimeoutException
          ? 'The TV did not answer. Try again.'
          : (e is String ? e : 'The TV could not play this stream.');
      connecting = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _startSession(CastDevice d, String title) async {
    device = d;
    casting = true;
    tvPlaying = true;
    castTitle = title;
    _everPlayed = false;
    _stoppedPolls = 0;
    _fails = 0;
    _relayHits = 0;
    BackgroundPlayback.castActive = true;
    BackgroundPlayback.castHook = _onNotificationAction;
    await BackgroundPlayback.startCasting(title, 'Casting to ${d.name}');
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) { _check(); refreshPosition(); });
    // First health check early, so a failure shows up in seconds.
    Timer(const Duration(seconds: 4), _check);
    unawaited(_rememberRecent(title, d.name));
    connecting = false;
    notifyListeners();
    unawaited(refreshTvVolume());
  }

  // ------------------------------------------------------ Kodi (JSON-RPC)

  Future<dynamic> _rpc(String host, int port, String method, [Map<String, dynamic>? params]) async {
    final r = await http
        .post(
          Uri.parse('http://$host:$port/jsonrpc'),
          headers: {
            'Content-Type': 'application/json',
            if (_kodiUser.isNotEmpty || _kodiPass.isNotEmpty)
              'Authorization': 'Basic ${base64Encode(utf8.encode('$_kodiUser:$_kodiPass'))}',
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            if (params != null) 'params': params,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (r.statusCode == 401) {
      kodiNeedsLogin = true;
      throw const _KodiAuth();
    }
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (j is Map && j['error'] != null) {
      final e = j['error'];
      throw 'Kodi: ${e is Map ? e['message'] : e}';
    }
    return j is Map ? j['result'] : null;
  }

  Future<int?> _findKodi(String host) async {
    for (final port in const [8080, 80]) {
      try {
        await _rpc(host, port, 'JSONRPC.Ping');
        _log('Kodi web control found on port $port.');
        return port;
      } on _KodiAuth {
        _log('Kodi on port $port asked for a username / password.');
      } catch (e) {
        _log('Kodi web control not on port $port ($e).');
      }
    }
    return null;
  }

  Map<String, String> get _kodiAuthHeader => {
        if (_kodiUser.isNotEmpty || _kodiPass.isNotEmpty)
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_kodiUser:$_kodiPass'))}',
      };

  /// Reads Kodi's own log (kodi.log) from the laptop through Kodi's web
  /// server and copies the important lines (errors / warnings / playback)
  /// into the Cast log. Needs "Allow remote control via HTTP" in Kodi.
  Future<bool> fetchKodiLog(CastDevice d) async {
    _log('--- Reading Kodi log from ${d.name} ---');
    notifyListeners();
    try {
      await _loadKodiLogin();
      final port = _kodiPort ?? await _findKodi(d.host);
      if (port == null) {
        _log(kodiNeedsLogin
            ? 'Kodi log: Kodi needs its web login (Devices tab → Kodi login).'
            : 'Kodi log: cannot read it. On the laptop open Kodi → Settings → Services → Control and turn ON "Allow remote control via HTTP".');
        notifyListeners();
        return false;
      }
      _kodiPort = port;
      final r = await _rpc(d.host, port, 'Files.PrepareDownload', {'path': 'special://logpath/kodi.log'});
      final details = r is Map ? r['details'] : null;
      final path = details is Map ? details['path'] : null;
      if (path is! String) throw 'Kodi did not return the log file';
      final res = await http
          .get(Uri.parse('http://${d.host}:$port/$path'), headers: {..._kodiAuthHeader, 'Range': 'bytes=-300000'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 206) throw 'HTTP ${res.statusCode}';
      final lines = const LineSplitter().convert(utf8.decode(res.bodyBytes, allowMalformed: true));
      final re = RegExp(r'ERROR|WARNING|OpenFile|Open failed|failed|PLT|UPnP|Platinum|Playback|CVideoPlayer|ffmpeg|inputstream', caseSensitive: false);
      final hits = lines.where(re.hasMatch).toList();
      if (hits.isEmpty) {
        _log('Kodi log: no errors in the latest lines.');
      } else {
        for (final l in hits.skip(hits.length > 40 ? hits.length - 40 : 0)) {
          _log('KODI  ${l.length > 220 ? l.substring(0, 220) : l}');
        }
      }
      notifyListeners();
      return true;
    } catch (e) {
      _log('Kodi log: could not read it ($e).');
      notifyListeners();
      return false;
    }
  }

  Future<void> _kodiPrepare(CastDevice d, int port, String title) async {
    try {
      // More detailed Kodi log, so a failure has a real reason in it.
      await _rpc(d.host, port, 'Settings.SetSettingValue', {'setting': 'debug.showloginfo', 'value': true});
    } catch (_) {}
    try {
      await _rpc(d.host, port, 'GUI.ShowNotification',
          {'title': 'Deeprowss', 'message': 'Loading $title', 'displaytime': 4000});
    } catch (_) {}
  }

  Future<_KodiResult> _castKodi(
      CastDevice d, String url, String title, Map<String, String> headers) async {
    if (connecting) return _KodiResult.failed;
    connecting = true;
    error = null;
    kodiNeedsLogin = false;
    kodiHint = null;
    notifyListeners();
    try {
      await _loadKodiLogin();
      final port = await _findKodi(d.host);
      if (port == null) {
        kodiHint = kodiNeedsLogin
            ? 'Kodi is asking for its web login. Enter the username and password from Kodi → Settings → Services → Control.'
            : 'Kodi is not accepting remote control yet. On the laptop open Kodi → Settings → Services → Control and turn ON "Allow remote control via HTTP" (port 8080). Then try again.';
        connecting = false;
        notifyListeners();
        return kodiNeedsLogin ? _KodiResult.failed : _KodiResult.unavailable;
      }
      _kodiPort = port;
      await _kodiPrepare(d, port, title);
      if (casting) await stop();
      // Kodi understands "url|Header=value&Header2=value" natively.
      final pipe = headers.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final file = pipe.isEmpty ? url : '$url|$pipe';
      await _rpc(d.host, port, 'Player.Open', {'item': {'file': file}});
      _log('Kodi accepted Player.Open.');
      _kodiMode = true;
      await _startSession(d, title);
      return _KodiResult.ok;
    } on _KodiAuth {
      kodiHint = 'Kodi rejected the web login. Check the username / password in Kodi → Settings → Services → Control.';
      error = kodiHint;
      _log('Kodi login rejected.');
      connecting = false;
      notifyListeners();
      return _KodiResult.failed;
    } catch (e) {
      _log('Kodi cast failed: $e');
      _cleanup();
      error = e is TimeoutException ? 'Kodi did not answer. Is Kodi open on the laptop?' : (e is String ? e : 'Kodi could not start this stream.');
      connecting = false;
      notifyListeners();
      return _KodiResult.failed;
    }
  }

  Future<int?> _kodiActivePlayer() async {
    final d = device;
    final port = _kodiPort;
    if (d == null || port == null) return null;
    final r = await _rpc(d.host, port, 'Player.GetActivePlayers');
    if (r is List && r.isNotEmpty && r.first is Map) {
      final id = (r.first as Map)['playerid'];
      if (id is int) {
        _kodiPlayerId = id;
        return id;
      }
    }
    return null;
  }

  Future<void> _kodiPlayPause(bool wantPlaying) async {
    final d = device;
    final port = _kodiPort;
    if (d == null || port == null) return;
    try {
      final id = await _kodiActivePlayer();
      if (id == null) return;
      await _rpc(d.host, port, 'Player.PlayPause', {'playerid': id, 'play': wantPlaying});
      tvPlaying = wantPlaying;
      BackgroundPlayback.setPlaying(wantPlaying, fromCast: true);
    } catch (e) {
      _log('Kodi play/pause failed: $e');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- TV remote

  Future<void> play() async {
    final d = device;
    if (d == null) return;
    if (_kodiMode) return _kodiPlayPause(true);
    try {
      await _soap(d.avControl, d.avType, 'Play',
          '<InstanceID>0</InstanceID><Speed>1</Speed>');
      tvPlaying = true;
      BackgroundPlayback.setPlaying(true, fromCast: true);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> pause() async {
    final d = device;
    if (d == null) return;
    if (_kodiMode) return _kodiPlayPause(false);
    try {
      await _soap(d.avControl, d.avType, 'Pause', '<InstanceID>0</InstanceID>');
      tvPlaying = false;
      BackgroundPlayback.setPlaying(false, fromCast: true);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> togglePlay() => tvPlaying ? pause() : play();

  /// Stops the TV and ends casting.
  Future<void> stop() async {
    final d = device;
    if (d != null && _kodiMode && _kodiPort != null) {
      try {
        final id = _kodiPlayerId ?? await _kodiActivePlayer();
        if (id != null) await _rpc(d.host, _kodiPort!, 'Player.Stop', {'playerid': id});
      } catch (e) {
        _log('Kodi stop failed: $e');
      }
    } else if (d != null) {
      await _soapQuiet(d.avControl, d.avType, 'Stop', '<InstanceID>0</InstanceID>');
    }
    _cleanup();
    notifyListeners();
  }

  Future<void> refreshPosition() async {
    final d = device;
    if (d == null || !casting || _kodiMode) return;
    try {
      final x = await _soap(d.avControl, d.avType, 'GetPositionInfo', '<InstanceID>0</InstanceID>');
      position = _parseClock(_tag(x, 'RelTime') ?? '00:00:00');
      duration = _parseClock(_tag(x, 'TrackDuration') ?? '00:00:00');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> seekTo(Duration value) async {
    final d = device;
    if (d == null || duration <= Duration.zero) return;
    final target = value < Duration.zero ? Duration.zero : (value > duration ? duration : value);
    final h = target.inHours.toString().padLeft(2, '0');
    final m = (target.inMinutes % 60).toString().padLeft(2, '0');
    final sec = (target.inSeconds % 60).toString().padLeft(2, '0');
    try {
      await _soap(d.avControl, d.avType, 'Seek', '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>$h:$m:$sec</Target>');
      position = target;
      notifyListeners();
    } catch (_) { error = 'Seeking is not supported by this TV or stream.'; notifyListeners(); }
  }

  static Duration _parseClock(String raw) {
    final p = raw.split(':');
    if (p.length != 3) return Duration.zero;
    return Duration(hours: int.tryParse(p[0]) ?? 0, minutes: int.tryParse(p[1]) ?? 0, seconds: int.tryParse(p[2].split('.').first) ?? 0);
  }

  Future<void> _rememberRecent(String title, String tv) async {
    recentSessions.insert(0, {'title': title, 'device': tv});
    if (recentSessions.length > 12) recentSessions.removeRange(12, recentSessions.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('decoder_cast_recents', recentSessions.map((x) => '${x['title']}|${x['device']}').toList());
  }

  Future<void> refreshTvVolume() async {
    final d = device;
    if (d != null && _kodiMode && _kodiPort != null) {
      try {
        final r = await _rpc(d.host, _kodiPort!, 'Application.GetProperties', {'properties': ['volume']});
        final v = r is Map ? r['volume'] : null;
        if (v is num) {
          tvVolume = v.round().clamp(0, 100);
          notifyListeners();
        }
      } catch (_) {}
      return;
    }
    if (d == null || d.rcControl == null) return;
    try {
      final x = await _soap(d.rcControl!, d.rcType!, 'GetVolume',
          '<InstanceID>0</InstanceID><Channel>Master</Channel>');
      final v = int.tryParse(_tag(x, 'CurrentVolume') ?? '');
      if (v != null) {
        tvVolume = v.clamp(0, 100);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setTvVolume(int value) async {
    final d = device;
    final v = value.clamp(0, 100);
    if (d != null && _kodiMode && _kodiPort != null) {
      tvVolume = v;
      notifyListeners();
      try {
        await _rpc(d.host, _kodiPort!, 'Application.SetVolume', {'volume': v});
      } catch (_) {}
      return;
    }
    if (d == null || d.rcControl == null) return;
    tvVolume = v;
    notifyListeners();
    try {
      await _soap(d.rcControl!, d.rcType!, 'SetVolume',
          '<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>$v</DesiredVolume>');
    } catch (_) {}
  }

  bool get tvVolumeSupported => _kodiMode || device?.rcControl != null;

  /// Opens Android's "Cast screen / Smart View" panel (mirrors the phone
  /// screen to a TV or Chromecast). Used for web embeds, which cannot be sent
  /// as a link. Mirroring needs the phone screen on.
  static Future<bool> openMirrorSettings() async {
    const actions = [
      'android.settings.CAST_SETTINGS',
      'android.settings.WIFI_DISPLAY_SETTINGS',
    ];
    for (final a in actions) {
      try {
        await AndroidIntent(action: a).launch();
        return true;
      } catch (_) {}
    }
    return false;
  }

  // ---------------------------------------------------------- housekeeping

  bool _onNotificationAction(String action) {
    switch (action) {
      case 'play':
        play();
      case 'pause':
        pause();
      case 'stop':
        stop();
    }
    return true; // seek buttons do nothing while casting live TV
  }

  Future<void> _check() async {
    final d = device;
    if (d == null || !casting) return;
    if (_kodiMode) {
      try {
        final id = await _kodiActivePlayer();
        _fails = 0;
        if (id != null) {
          _everPlayed = true;
          _stoppedPolls = 0;
        } else if (_everPlayed) {
          if (++_stoppedPolls >= 2) _finish('Kodi stopped playing.');
        } else if (++_stoppedPolls >= 3) {
          _log('Kodi never started a player for this stream.');
          unawaited(fetchKodiLog(d));
          _finish('Kodi could not play this channel ("Playback failed"). The stream may be offline or blocked. See the Cast log on the Devices tab.');
        }
      } catch (e) {
        _log('Kodi check failed: $e');
        if (++_fails >= 4) _finish('Lost connection to Kodi.');
      }
      return;
    }
    try {
      final x = await _soap(
          d.avControl, d.avType, 'GetTransportInfo', '<InstanceID>0</InstanceID>');
      _fails = 0;
      final st = (_tag(x, 'CurrentTransportState') ?? '').toUpperCase();
      final playing = st == 'PLAYING' || st == 'TRANSITIONING';
      if (playing) _everPlayed = true;
      if (playing != tvPlaying) {
        tvPlaying = playing;
        BackgroundPlayback.setPlaying(playing, fromCast: true);
        notifyListeners();
      }
      final stopped = st == 'STOPPED' || st == 'NO_MEDIA_PRESENT';
      if (!playing && stopped) {
        if (_everPlayed) {
          if (++_stoppedPolls >= 2) _finish('The TV stopped playing.');
        } else if (++_stoppedPolls >= 3) {
          if (d.isKodi) unawaited(fetchKodiLog(d));
          _finish('The TV accepted the stream but never started playing it ("Playback failed"). See the Cast log for the reason.');
        }
      } else {
        _stoppedPolls = 0;
      }
    } catch (_) {
      if (++_fails >= 4) _finish('Lost connection to the TV.');
    }
  }

  void _finish(String message) {
    _log(message);
    _cleanup();
    error = message;
    notifyListeners();
  }

  void _cleanup() {
    _poll?.cancel();
    _poll = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt = null;
    final wasCasting = casting;
    casting = false;
    connecting = false;
    tvPlaying = false;
    tvVolume = -1;
    device = null;
    castTitle = '';
    position = Duration.zero;
    duration = Duration.zero;
    _localFile = null;
    _upHeaders = {};
    _kodiMode = false;
    _kodiPlayerId = null;
    _server?.close(force: true);
    _server = null;
    _client?.close(force: true);
    _client = null;
    BackgroundPlayback.castHook = null;
    BackgroundPlayback.castActive = false;
    if (wasCasting) BackgroundPlayback.stopCasting();
  }

  // ----------------------------------------------------------------- SOAP

  Future<String> _soap(String url, String service, String action, String args) async {
    final body = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$service">$args</u:$action></s:Body></s:Envelope>';
    final r = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction': '"$service#$action"',
          },
          body: utf8.encode(body),
        )
        .timeout(const Duration(seconds: 8));
    if (r.statusCode >= 300) {
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final desc = _tag(body, 'errorDescription');
      final code = _tag(body, 'errorCode');
      _log('$action refused: HTTP ${r.statusCode}'
          '${code == null ? '' : ' UPnP $code'}${desc == null ? '' : ' ($desc)'}');
      throw 'The TV refused this stream (${r.statusCode}${desc == null ? '' : ': $desc'}).';
    }
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  Future<void> _soapQuiet(String url, String service, String action, String args) async {
    try {
      await _soap(url, service, action, args);
    } catch (_) {}
  }

  // ---------------------------------------------- relay (phone -> TV)

  /// Small web server on the phone. The TV asks it for the stream; it adds
  /// the headers the channel needs (Referer / User-Agent), rewrites m3u8
  /// playlists so every segment also goes through it, and turns https into
  /// plain http, which every TV accepts.
  Future<String> _ensureServer() async {
    final ip = await _lanIp();
    if (ip == null) {
      throw 'Connect the phone to the same Wi-Fi as the TV.';
    }
    if (_server == null) {
      final s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = s;
      s.listen(_handle, onError: (_) {});
    }
    return 'http://$ip:${_server!.port}';
  }

  Future<String?> _lanIp() async {
    try {
      final ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      String? fallback;
      for (final i in ifs) {
        for (final a in i.addresses) {
          final ip = a.address;
          final lan = ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (!lan) continue;
          final n = i.name.toLowerCase();
          if (n.contains('wlan') || n.contains('wifi') || n.startsWith('en')) {
            return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segs = req.uri.pathSegments;
      if (segs.length >= 2 && segs[0] == 'p') {
        final upstream = utf8.decode(base64Url.decode(base64Url.normalize(segs[1])));
        await _proxy(req, upstream);
      } else if (segs.isNotEmpty && segs[0] == 'f' && _localFile != null) {
        await _serveFile(req, _localFile!);
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = 502;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _proxy(HttpRequest req, String upstream) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = null;
    final up = await client.getUrl(Uri.parse(upstream));
    up.followRedirects = true;
    up.maxRedirects = 6;
    _upHeaders.forEach((k, v) => up.headers.set(k, v));
    // Kodi asks for "Range: bytes=0-" even on playlists. A playlist must come
    // back whole (and rewritten), so only forward Range for media files.
    final range = req.headers.value('range');
    final looksPlaylist = upstream.toLowerCase().contains('.m3u8');
    if (range != null && !looksPlaylist) up.headers.set('range', range);
    final r = await up.close();
    final res = req.response;
    if (r.statusCode >= 400 || _relayHits++ < 4) {
      _log('Relay: ${req.method} ${_short(upstream)} -> ${r.statusCode}');
    }

    var base = Uri.parse(upstream);
    for (final red in r.redirects) {
      base = base.resolveUri(red.location);
    }
    final ct = r.headers.contentType?.mimeType.toLowerCase() ?? '';
    final isPlaylist = base.path.toLowerCase().endsWith('.m3u8') ||
        upstream.toLowerCase().contains('.m3u8') ||
        ct.contains('mpegurl');

    if (isPlaylist && (r.statusCode == 200 || r.statusCode == 206)) {
      final bytes = await r.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.trimLeft().startsWith('#EXTM3U')) {
        final origin = 'http://${req.headers.value('host')}';
        final out = utf8.encode(_rewritePlaylist(text, base, origin));
        res.statusCode = 200;
        res.headers.set('content-type', 'application/vnd.apple.mpegurl');
        res.headers.set('cache-control', 'no-cache');
        res.headers.set('accept-ranges', 'none');
        res.contentLength = out.length;
        res.add(out);
        await res.close();
        return;
      }
      res.statusCode = 200;
      if (ct.isNotEmpty) res.headers.set('content-type', ct);
      res.contentLength = bytes.length;
      res.add(bytes);
      await res.close();
      return;
    }

    res.statusCode = r.statusCode;
    if (ct.isNotEmpty) {
      res.headers.set('content-type', r.headers.contentType.toString());
    } else if (base.path.toLowerCase().endsWith('.ts')) {
      res.headers.set('content-type', 'video/mp2t');
    }
    for (final h in const ['content-range', 'accept-ranges']) {
      final v = r.headers.value(h);
      if (v != null) res.headers.set(h, v);
    }
    if (r.contentLength >= 0) res.contentLength = r.contentLength;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(r);
    await res.close();
  }

  String _rewritePlaylist(String text, Uri base, String origin) {
    String prox(String ref) {
      final abs = base.resolve(ref.trim()).toString();
      return '$origin/p/${_b64(abs)}/${_nameOf(abs)}';
    }

    final uriAttr = RegExp(r'URI="([^"]+)"');
    final out = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.add(line);
      } else if (line.startsWith('#')) {
        out.add(line.replaceAllMapped(
            uriAttr, (m) => 'URI="${prox(m.group(1)!)}"'));
      } else {
        out.add(prox(line));
      }
    }
    return out.join('\n');
  }

  Future<void> _serveFile(HttpRequest req, File f) async {
    final len = await f.length();
    final res = req.response;
    res.headers.set('accept-ranges', 'bytes');
    res.headers.set('content-type', _mimeOfPath(f.path));
    var start = 0;
    var end = len - 1;
    final rng = req.headers.value('range');
    if (rng != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rng);
      if (m != null) {
        final a = m.group(1)!;
        final b = m.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = len - int.parse(b);
        } else {
          if (a.isNotEmpty) start = int.parse(a);
          if (b.isNotEmpty) end = int.parse(b);
        }
        if (start < 0) start = 0;
        if (end >= len) end = len - 1;
        if (start > end) {
          res.statusCode = 416;
          await res.close();
          return;
        }
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $start-$end/$len');
      }
    }
    res.contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(f.openRead(start, end + 1));
    await res.close();
  }

  // -------------------------------------------------------------- helpers

  static String _b64(String s) => base64Url.encode(utf8.encode(s));

  static String _nameOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    var n = path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).lastOrNull ?? 'stream';
    n = n.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (n.length > 40) n = n.substring(n.length - 40);
    return n.isEmpty ? 'stream' : n;
  }

  static String _mimeFor(StreamKind? kind, String lowerUrl) {
    if (kind == StreamKind.hls || lowerUrl.contains('.m3u8')) {
      return 'application/vnd.apple.mpegurl';
    }
    if (kind == StreamKind.dash || lowerUrl.contains('.mpd')) {
      return 'application/dash+xml';
    }
    return _mimeOfPath(lowerUrl.split('?').first);
  }

  static String _mimeOfPath(String p) {
    final l = p.toLowerCase();
    if (l.endsWith('.mkv')) return 'video/x-matroska';
    if (l.endsWith('.webm')) return 'video/webm';
    if (l.endsWith('.mov')) return 'video/quicktime';
    if (l.endsWith('.ts')) return 'video/mpeg';
    if (l.endsWith('.mp3')) return 'audio/mpeg';
    if (l.endsWith('.aac')) return 'audio/aac';
    if (l.endsWith('.m4a')) return 'audio/mp4';
    return 'video/mp4';
  }

  static String? _tag(String xml, String tag) {
    final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false)
        .firstMatch(xml);
    return m?.group(1)?.trim();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _unesc(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
