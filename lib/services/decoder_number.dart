import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The phone's unique Decoder number: 6 random digits + 4 check digits.
/// It is the access code for the Windows app and the receiver page
/// (assets/receiver/gate.js checks the same check digits, so no server is needed).
class DecoderNumber {
  DecoderNumber._();

  static const _prefKey = 'decoder_number_v1';
  static const _salt = 'dpdec1'; // must match SALT in assets/receiver/gate.js
  static String? _cached;

  static int _check(String prefix) {
    var h = 0x811C9DC5;
    for (final u in '$_salt:$prefix'.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h % 10000;
  }

  static bool isValid(String n) =>
      RegExp(r'^\d{10}$').hasMatch(n) &&
      n.substring(6) == _check(n.substring(0, 6)).toString().padLeft(4, '0');

  /// 3-3-4 grouping, e.g. 482 173 9051.
  static String format(String n) =>
      n.length == 10 ? '${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}' : n;

  static String _generate() {
    final r = Random.secure();
    final prefix = (1 + r.nextInt(9)).toString() +
        List.generate(5, (_) => r.nextInt(10)).join();
    return prefix + _check(prefix).toString().padLeft(4, '0');
  }

  /// The saved number; created once on first use and kept on this phone.
  static Future<String> get() async {
    final c = _cached;
    if (c != null) return c;
    String? n;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      n = prefs.getString(_prefKey);
    } catch (_) {}
    if (n == null || !isValid(n)) {
      n = _generate();
      try {
        await prefs?.setString(_prefKey, n);
      } catch (_) {}
    }
    return _cached = n;
  }
}
