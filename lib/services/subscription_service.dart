import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../utils/currency_map.dart';
import 'install_id.dart';

/// What the plans page shows. The Worker answers with the naira price and,
/// for people outside Nigeria, the same price in their own currency.
class PlanInfo {
  final bool available;
  final bool recurring;
  final bool recurringYear;
  final String priceDisplay; // "₦2,000"
  final String? localDisplay; // "$1.30" (null for naira users / no rate)
  final String yearPriceDisplay; // "₦20,000"
  final String? yearLocalDisplay;
  final int priceNgn;
  final int yearPriceNgn;

  const PlanInfo({
    required this.available,
    required this.recurring,
    required this.priceDisplay,
    this.localDisplay,
    this.recurringYear = false,
    this.yearPriceDisplay = '₦20,000',
    this.yearLocalDisplay,
    this.priceNgn = 2000,
    this.yearPriceNgn = 20000,
  });

  /// Whole months of the monthly price that the yearly price saves.
  int get yearSavingPercent {
    final full = priceNgn * 12;
    if (full <= 0 || yearPriceNgn >= full) return 0;
    return (((full - yearPriceNgn) / full) * 100).round();
  }

  /// Used until the Worker answers (or when it cannot be reached).
  factory PlanInfo.fallback() => PlanInfo(
        available: true,
        recurring: false,
        priceDisplay: '₦${_withCommas(AppConfig.premiumPriceFallbackNgn)}',
        yearPriceDisplay:
            '₦${_withCommas(AppConfig.premiumYearPriceFallbackNgn)}',
        priceNgn: AppConfig.premiumPriceFallbackNgn,
        yearPriceNgn: AppConfig.premiumYearPriceFallbackNgn,
      );

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
        available: j['available'] == true,
        recurring: j['recurring'] == true,
        recurringYear: j['recurring_year'] == true,
        priceNgn: (j['price_ngn'] as num?)?.toInt() ??
            AppConfig.premiumPriceFallbackNgn,
        yearPriceNgn: (j['year_price_ngn'] as num?)?.toInt() ??
            AppConfig.premiumYearPriceFallbackNgn,
        yearPriceDisplay: (j['year_price_display'] ?? '').toString().isEmpty
            ? '₦${_withCommas(AppConfig.premiumYearPriceFallbackNgn)}'
            : j['year_price_display'].toString(),
        yearLocalDisplay: (j['year_local_display'] ?? '').toString().isEmpty
            ? null
            : j['year_local_display'].toString(),
        priceDisplay: (j['price_display'] ?? '').toString().isEmpty
            ? '₦${_withCommas(AppConfig.premiumPriceFallbackNgn)}'
            : j['price_display'].toString(),
        localDisplay: (j['local_display'] ?? '').toString().isEmpty
            ? null
            : j['local_display'].toString(),
      );

  static String _withCommas(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

class CheckoutStart {
  final String url;
  final String reference;
  const CheckoutStart(this.url, this.reference);
}

enum PaymentResult { active, pending, failed }

/// Where this phone is in the ad-free token flow.
///   none    - nothing requested yet
///   pending - requested, waiting for an answer
///   ready   - a token was made for this phone ([token] is filled in)
///   active  - ads are already removed
///   unknown - the Worker could not be reached
class TokenState {
  final String state;
  final String? token;
  final int days;
  const TokenState(this.state, {this.token, this.days = 0});
}

/// Free or Premium. The phone only keeps a copy of "premium until <date>";
/// the truth lives in the Cloudflare Worker (D1), filled in by Paystack.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const _kExpires = 'sub_expires_ms';
  static const _kEmail = 'sub_email';
  static const _kVerified = 'sub_verified_ms'; // last time the Worker confirmed
  static const _kHigh = 'sub_clock_high_ms'; // latest time ever seen

  /// How long the saved copy is trusted without hearing from the Worker. After
  /// this, ad-free switches off until the phone is online again, so a phone
  /// that blocks the network cannot keep a stopped / expired token forever.
  static const _offlineGrace = Duration(days: 3);

  DateTime? _expires;
  DateTime? _lastRefresh;
  DateTime? _verified; // last successful answer from the Worker
  DateTime? _high; // clock high-water mark: stops "set the date back" tricks
  Timer? _watch;
  bool _wasPremium = false;
  int _ticks = 0;
  bool _loaded = false;

  /// Plans + ads need the Worker address.
  bool get enabled =>
      AppConfig.plansEnabled && AppConfig.feedBase.trim().isNotEmpty;

  /// Whether Premium is shown to people (AppConfig.showSubscriptions).
  bool get visible => enabled && AppConfig.showSubscriptions;

  /// Whether the "Remove ads" (token) feature is shown to people.
  bool get tokensVisible => enabled && AppConfig.showRemoveAds;

  /// The phone's clock, but never earlier than the latest time we have already
  /// seen (or the Worker told us). Setting the date back does not help.
  DateTime _now() {
    final n = DateTime.now();
    final h = _high;
    return (h != null && h.isAfter(n)) ? h : n;
  }

  bool get isPremium {
    final e = _expires;
    if (e == null) return false;
    final now = _now();
    if (!e.isAfter(now)) return false; // the days have run out
    final v = _verified;
    if (v == null || now.difference(v) > _offlineGrace) return false;
    return true;
  }

  DateTime? get expiresAt => _expires;

  /// "09/11/2026" while ad-free is active, else null.
  String? get expiresLabel {
    final d = _expires;
    if (d == null || !isPremium) return null;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Whole days of ad-free time left (rounded up), or null when not active.
  int? get daysLeft {
    final d = _expires;
    if (d == null || !isPremium) return null;
    final hours = d.difference(DateTime.now()).inHours;
    return hours <= 0 ? 1 : (hours / 24).ceil();
  }

  /// Reads the saved copy (fast, offline-safe) and asks the Worker in the
  /// background.
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kExpires);
      if (ms != null && ms > 0) {
        _expires = DateTime.fromMillisecondsSinceEpoch(ms);
      }
      final v = prefs.getInt(_kVerified);
      if (v != null && v > 0) _verified = DateTime.fromMillisecondsSinceEpoch(v);
      final h = prefs.getInt(_kHigh);
      if (h != null && h > 0) _high = DateTime.fromMillisecondsSinceEpoch(h);
      // Phones updated from an older version have no "verified" stamp yet:
      // give them one grace period, the Worker check below renews it.
      if (_expires != null && _verified == null) {
        _verified = DateTime.now();
        await prefs.setInt(_kVerified, _verified!.millisecondsSinceEpoch);
      }
    } catch (_) {}
    _wasPremium = isPremium;
    _startWatch();
    unawaited(refresh(force: true));
  }

  /// Every minute while ad-free is on: remember the latest time seen, switch
  /// ads back on the moment the days run out (even with the app open), and ask
  /// the Worker every 10 minutes so a stopped subscription ends quickly.
  void _startWatch() {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    final n = DateTime.now();
    if (_high == null || n.isAfter(_high!)) {
      _high = n;
      unawaited(_saveInt(_kHigh, n.millisecondsSinceEpoch));
    }
    final now = isPremium;
    if (now != _wasPremium) {
      _wasPremium = now;
      notifyListeners();
    }
    if (_expires != null && ++_ticks % 10 == 0) unawaited(refresh(force: true));
  }

  Future<void> _saveInt(String key, int v) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(key, v);
    } catch (_) {}
  }

  /// Marks a good answer from the Worker: restarts the offline grace and
  /// trusts the Worker's clock over the phone's.
  Future<void> _markVerified(Map<String, dynamic> j) async {
    final server = (j['now'] as num?)?.toInt();
    final trusted = server != null && server > 0
        ? DateTime.fromMillisecondsSinceEpoch(server)
        : DateTime.now();
    _verified = trusted;
    _high = trusted;
    await _saveInt(_kVerified, trusted.millisecondsSinceEpoch);
    await _saveInt(_kHigh, trusted.millisecondsSinceEpoch);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.feedBase.trim());
    return base.replace(path: path, queryParameters: query);
  }

  /// Asks the Worker whether this install is premium. Failing (offline) keeps
  /// whatever the phone already knows.
  Future<void> refresh({bool force = false}) async {
    if (!enabled) return;
    final now = DateTime.now();
    if (!force &&
        _lastRefresh != null &&
        now.difference(_lastRefresh!) < const Duration(minutes: 10)) {
      return;
    }
    _lastRefresh = now;
    try {
      final id = await InstallId.get();
      final r = await http
          .get(_uri('/sub/status', {'install': id}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      await _markVerified(j);
      // The Worker is the truth: 0 / a past date (expired or stopped by you)
      // switches ad-free off on this phone straight away.
      await _setExpiresMs((j['expires_at'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  Future<void> _setExpiresMs(int ms) async {
    final next = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    final changed = next?.millisecondsSinceEpoch != _expires?.millisecondsSinceEpoch;
    _expires = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove(_kExpires);
      } else {
        await prefs.setInt(_kExpires, ms);
      }
    } catch (_) {}
    final now = isPremium;
    if (changed || now != _wasPremium) {
      _wasPremium = now;
      notifyListeners();
    }
  }

  /// The person's own currency, from the phone's region setting.
  String get currencyCode =>
      currencyForCountry(PlatformDispatcher.instance.locale.countryCode);

  Future<PlanInfo> loadPlan() async {
    try {
      final r = await http
          .get(_uri('/sub/config', {'cur': currencyCode}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        return PlanInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return PlanInfo.fallback();
  }

  Future<String> savedEmail() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_kEmail) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Creates the Paystack checkout. Throws an [Exception] whose message can
  /// be shown to the person.
  Future<CheckoutStart> startCheckout({
    required String email,
    required bool recurring,
    String period = 'month',
    List<String> channels = const [],
  }) async {
    final id = await InstallId.get();
    final http.Response r;
    try {
      r = await http
          .post(
            _uri('/sub/start'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'install_id': id,
              'email': email,
              'recurring': recurring,
              'period': period,
              if (channels.isNotEmpty) 'channels': channels,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw Exception('No connection. Check your internet and try again.');
    }
    Map<String, dynamic> j = {};
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    final url = (j['authorization_url'] ?? '').toString();
    if (r.statusCode != 200 || url.isEmpty) {
      throw Exception((j['error'] ?? 'Could not start the payment').toString());
    }
    try {
      (await SharedPreferences.getInstance()).setString(_kEmail, email);
    } catch (_) {}
    return CheckoutStart(url, (j['reference'] ?? '').toString());
  }

  /// Confirms a payment with the Worker (which asks Paystack). Retries a few
  /// times because a transfer can take a moment to land.
  Future<PaymentResult> confirm(String reference, {int tries = 4}) async {
    if (reference.isEmpty) return PaymentResult.failed;
    for (var i = 0; i < tries; i++) {
      try {
        final r = await http
            .get(_uri('/sub/verify', {'reference': reference}))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final status = (j['status'] ?? '').toString();
          if (status == 'success') {
            await _markVerified(j);
            await _setExpiresMs((j['expires_at'] as num?)?.toInt() ?? 0);
            return isPremium ? PaymentResult.active : PaymentResult.failed;
          }
          if (status == 'failed') return PaymentResult.failed;
        }
      } catch (_) {}
      if (i < tries - 1) await Future<void>.delayed(const Duration(seconds: 3));
    }
    return PaymentResult.pending;
  }

  /// New phone: e-mail + Paystack reference (from the receipt e-mail).
  /// Returns null on success or the message to show.
  Future<String?> restore({
    required String email,
    required String reference,
  }) async {
    try {
      final id = await InstallId.get();
      final r = await http
          .post(
            _uri('/sub/restore'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'install_id': id,
              'email': email,
              'reference': reference,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && j['active'] == true) {
        await _markVerified(j);
        await _setExpiresMs((j['expires_at'] as num?)?.toInt() ?? 0);
        return null;
      }
      return (j['error'] ?? 'Could not restore').toString();
    } catch (_) {
      return 'No connection. Check your internet and try again.';
    }
  }

  // ------------------------------------------------------------ ad-free tokens

  String _errorOf(http.Response r, String fallback) {
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final e = (j['error'] ?? '').toString();
      if (e.isNotEmpty) return e;
    } catch (_) {}
    return fallback;
  }

  /// Asks the Worker whether the request was answered. A token made for this
  /// phone comes back in [TokenState.token].
  Future<TokenState> tokenStatus() async {
    if (!enabled) return const TokenState('unknown');
    try {
      final id = await InstallId.get();
      final r = await http
          .get(_uri('/sub/token/mine', {'install': id}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return const TokenState('unknown');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final state = (j['state'] ?? 'none').toString();
      await _markVerified(j);
      // Anything but "active" means the Worker has no time for this phone
      // (expired or stopped): drop the saved copy too.
      await _setExpiresMs(
          state == 'active' ? (j['expires_at'] as num?)?.toInt() ?? 0 : 0);
      final t = (j['token'] ?? '').toString();
      return TokenState(
        state,
        token: t.isEmpty ? null : t,
        days: (j['days'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const TokenState('unknown');
    }
  }

  /// Sends a token request. [contact] (name / WhatsApp number) is optional and
  /// only shown to you on the admin page. Returns null on success or the
  /// message to show.
  Future<String?> requestToken({String contact = ''}) async {
    try {
      final id = await InstallId.get();
      final r = await http
          .post(
            _uri('/sub/token/request'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'install_id': id, 'contact': contact.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        // Already ad-free on the server (e.g. reinstall): pick that up.
        unawaited(refresh(force: true));
        return null;
      }
      return _errorOf(r, 'Could not send the request. Try again.');
    } catch (_) {
      return 'No connection. Check your internet and try again.';
    }
  }

  /// Turns a token into ad-free days for this phone. Returns null on success
  /// (ads are gone straight away) or the message to show.
  Future<String?> redeemToken(String token) async {
    final t = token.trim();
    if (t.isEmpty) return 'Enter your token';
    try {
      final id = await InstallId.get();
      final r = await http
          .post(
            _uri('/sub/token/redeem'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'install_id': id, 'token': t}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await _markVerified(j);
        await _setExpiresMs((j['expires_at'] as num?)?.toInt() ?? 0);
        return isPremium ? null : 'That token has expired. Request a new one.';
      }
      return _errorOf(r, 'Could not use that token');
    } catch (_) {
      return 'No connection. Check your internet and try again.';
    }
  }
}
