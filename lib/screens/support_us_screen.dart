import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../services/install_id.dart';
import '../services/subscription_service.dart' show SubscriptionService;
import '../theme/app_theme.dart';
import '../utils/currency_map.dart';
import '../utils/l10n.dart';
import 'browser_screen.dart' show openExternally;
import 'plans_screen.dart' show buildWhatsappUri;
import '../widgets/tr_text.dart';

/// "Support Us": a voluntary donation page. Uses the same payment details as
/// the Remove ads page (assets/data/payment_accounts.json, with the
/// AppConfig values as fallback) but is built around helping the team keep
/// improving the AI analysis and the app. Opened from the side menu
/// (Support), the icon on every profile, and the AI Predict headers.
class SupportUsScreen extends StatefulWidget {
  const SupportUsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SupportUsScreen()));

  /// Small heart button for app bars (profile, AI Predict).
  static Widget action(BuildContext context) => IconButton(
        tooltip: 'Support Us'.tr,
        onPressed: () => open(context),
        icon: const Icon(Icons.favorite_rounded, color: Color(0xFFFF5C7A)),
      );

  @override
  State<SupportUsScreen> createState() => _SupportUsScreenState();
}

class _SupportUsScreenState extends State<SupportUsScreen>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFFFC857);
  static const _rose = Color(0xFFFF5C7A);
  /// Support levels, in naira (the account that receives the money is a
  /// naira account). They are shown in the person's own currency.
  static const _amounts = [500, 1000, 2000, 5000, 10000];

  /// Exchange rates (1 naira in other currencies), kept while the app runs.
  static Map<String, double>? _rates;

  late final AnimationController _beat;
  final _custom = TextEditingController();

  Map<String, dynamic> _config = {};
  String _installId = '';
  String _method = 'bank';
  int _amount = 2000; // chosen preset, in naira
  bool _useCustom = false;

  /// 'auto' = this phone's region, otherwise a country code from the picker.
  String _country = 'auto';
  bool _ratesLoading = false;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    unawaited(_loadAccounts());
    unawaited(_loadRates());
    InstallId.get().then((v) {
      if (mounted) setState(() => _installId = v);
    });
  }

  @override
  void dispose() {
    _beat.dispose();
    _custom.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- payment data

  Future<void> _loadAccounts() async {
    try {
      final raw = await rootBundle.loadString('assets/data/payment_accounts.json');
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic> && mounted) setState(() => _config = d);
    } catch (_) {}
    // Newest details from the repo (so you can change them without a new
    // APK). Ignored if offline or if the file looks wrong.
    if (AppConfig.paymentAccountsUrl.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse(AppConfig.paymentAccountsUrl))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body);
      if (d is! Map<String, dynamic>) return;
      final accs = d['accounts'];
      if (accs is! List) return;
      for (final a in accs.whereType<Map>()) {
        if (a['id'] == 'opay' &&
            !RegExp(r'^\d{6,20}$').hasMatch('${a['account_number']}')) {
          return;
        }
        if (a['id'] == 'wallet' &&
            !RegExp(r'^[A-Za-z0-9]+$').hasMatch('${a['wallet_address']}')) {
          return;
        }
      }
      if (mounted) setState(() => _config = d);
    } catch (_) {}
  }

  Map<String, dynamic>? _account(String id) {
    final raw = _config['accounts'];
    if (raw is List) {
      for (final a in raw.whereType<Map>()) {
        if (a['id'] == id && a['enabled'] != false) {
          return Map<String, dynamic>.from(a);
        }
      }
    }
    return null;
  }

  Map<String, dynamic> get _bank =>
      _account('opay') ??
      const {
        'provider': AppConfig.payBankProvider,
        'account_name': AppConfig.payBankAccountName,
        'account_number': AppConfig.payBankAccountNumber,
      };

  Map<String, dynamic> get _wallet =>
      _account('wallet') ??
      const {
        'provider': AppConfig.payCryptoProvider,
        'network': AppConfig.payCryptoNetwork,
        'wallet_name': AppConfig.payCryptoAccountName,
        'wallet_address': AppConfig.payCryptoAddress,
      };

  String get _receiptUrl =>
      (_config['receipt_whatsapp'] as String?) ?? AppConfig.receiptWhatsappUrl;

  // ------------------------------------------------------------- currency

  Future<void> _loadRates() async {
    if (_rates != null) return;
    if (mounted) setState(() => _ratesLoading = true);
    try {
      final r = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/NGN'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final raw = d is Map ? d['rates'] : null;
        if (raw is Map) {
          final out = <String, double>{};
          raw.forEach((k, v) {
            if (k is String && v is num && v > 0) out[k] = v.toDouble();
          });
          if (out.isNotEmpty) _rates = out;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _ratesLoading = false);
  }

  String get _effectiveCountry => _country == 'auto'
      ? (SubscriptionService.instance.deviceCountry ?? '')
      : _country;

  String get _currency => currencyForCountry(_effectiveCountry);

  /// How much of [_currency] one naira is worth (null = not known, so
  /// naira is shown).
  double? get _rate {
    if (_currency == 'NGN') return 1.0;
    final r = _rates?[_currency];
    return (r != null && r > 0) ? r : null;
  }

  bool get _local => _currency != 'NGN' && _rate != null;

  /// Rounds up to 2 significant digits so chips read like 50 or 1.5.
  double _nice(double v) {
    if (v <= 0) return 0;
    var mag = 1.0;
    while (v / mag >= 100) {
      mag *= 10;
    }
    while (v / mag < 10) {
      mag /= 10;
    }
    return (v / mag).ceil() * mag;
  }

  /// Amount shown on a preset chip, in the person's currency.
  double _localFor(int ngn) => _local ? _nice(ngn * _rate!) : ngn.toDouble();

  /// Naira that has to be sent for [localAmount] of the person's currency.
  int _ngnFor(double localAmount) {
    if (localAmount <= 0) return 0;
    return _local ? (localAmount / _rate!).ceil() : localAmount.ceil();
  }

  double get _customLocal => double.tryParse(_custom.text.trim()) ?? 0;

  /// What the person chose, in their currency.
  double get _chosenLocal => _useCustom ? _customLocal : _localFor(_amount);

  /// What is actually transferred, in naira.
  int get _chosenNgn =>
      _useCustom ? _ngnFor(_customLocal) : _ngnFor(_localFor(_amount));

  static const _symbols = {
    'NGN': '\u20A6',
    'USD': 'US\$',
    'GBP': '\u00A3',
    'EUR': '\u20AC',
    'EGP': 'E\u00A3',
    'GHS': 'GH\u20B5',
    'KES': 'KSh ',
    'ZAR': 'R ',
    'INR': '\u20B9',
    'JPY': '\u00A5',
    'CNY': 'CN\u00A5',
    'CAD': 'CA\$',
    'AUD': 'A\$',
  };

  String _fmt(double v) {
    final whole = v >= 100 || v == v.roundToDouble();
    final t = whole ? v.round().toString() : v.toStringAsFixed(2);
    final dot = t.indexOf('.');
    final intPart = dot < 0 ? t : t.substring(0, dot);
    final frac = dot < 0 ? '' : t.substring(dot);
    final b = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) b.write(',');
      b.write(intPart[i]);
    }
    return '$b$frac';
  }

  String _money(String code, double v) {
    final sym = _symbols[code] ?? '$code ';
    return '$sym${_fmt(v)}';
  }

  /// The chosen amount in the person's currency ("E\u00A350").
  String get _chosenLocalText =>
      _money(_local ? _currency : 'NGN', _chosenLocal);

  /// USDT worth of the chosen naira amount (null if no rate).
  String? get _usdtText {
    final usd = _rates?['USD'];
    if (usd == null || _chosenNgn <= 0) return null;
    final v = _chosenNgn * usd;
    return v >= 100 ? v.round().toString() : v.toStringAsFixed(2);
  }

  // --------------------------------------------------------------- actions

  String _naira(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\u20A6$b';
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _copy(String v, String what) async {
    await Clipboard.setData(ClipboardData(text: v));
    HapticFeedback.selectionClick();
    if (mounted) _toast('{what} copied'.trArgs({'what': what}));
  }

  Future<void> _sendReceipt() async {
    final bank = _method == 'bank';
    final how = bank
        ? '${_bank['provider'] ?? 'Bank'} bank transfer'
        : '${_wallet['provider'] ?? 'Crypto'} (${_wallet['network'] ?? ''})';
    final ngn = _chosenNgn;
    final amt = ngn > 0
        ? '\nAmount: ${_naira(ngn)}${_local ? ' (about $_chosenLocalText)' : ''}'
        : '';
    final uri = buildWhatsappUri(
      _receiptUrl,
      'Hello, I just supported the Deeprowss app. Thank you!\n'
      'Payment: $how$amt\nMy receipt is attached.',
      _installId,
    );
    if (uri == null || !await openExternally(uri.toString())) {
      if (mounted) _toast('Could not open WhatsApp'.tr);
    }
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: Text('Support Us'.tr,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 30),
          children: [
            _hero(),
            const SizedBox(height: 18),
            _heading('Where your support goes'.tr),
            _impactGrid(),
            const SizedBox(height: 20),
            _heading('Choose your support'.tr),
            _amountPicker(),
            const SizedBox(height: 20),
            _heading('Send it your way'.tr),
            _payCard(),
            const SizedBox(height: 14),
            _receiptCard(),
            const SizedBox(height: 22),
            _thanks(),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1230), Color(0xFF1B1030), Color(0xFF0E1A33)],
        ),
        border: Border.all(color: _rose.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: _rose.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _beat,
            builder: (_, _) {
              final t = Curves.easeInOut.transform(_beat.value);
              return Container(
                width: 92 + 10 * t,
                height: 92 + 10 * t,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    _rose.withValues(alpha: .32),
                    _rose.withValues(alpha: .0),
                  ]),
                ),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF8FA3), Color(0xFFE11D48)],
                    ),
                  ),
                  child: Transform.scale(
                    scale: 1 + .08 * t,
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 34),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Support Us'.tr,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your support can make us upgrade better for more better AI analysis and generality of this app.'
                .tr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Color(0xFFE9E4F5),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _gold.withValues(alpha: .45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.trending_up_rounded, color: _gold, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Support us to keep us going forward and upward.'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          t,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      );

  Widget _impactGrid() {
    final items = <(IconData, Color, String, String)>[
      (Icons.psychology_alt_rounded, const Color(0xFF8E6BFF),
          'Smarter AI analysis', 'Better match insight and predictions.'),
      (Icons.public_rounded, const Color(0xFF29B6F6),
          'More coverage', 'More leagues, teams and national sides.'),
      (Icons.bolt_rounded, _gold, 'Faster and stable',
          'Quicker servers and fewer errors.'),
      (Icons.auto_awesome_rounded, const Color(0xFF26D07C), 'New features',
          'Fresh tools shipped all year round.'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final it in items)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Ui.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Ui.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: it.$2.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(it.$1, color: it.$2, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(it.$3.tr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(it.$4.tr,
                        style: TextStyle(
                            color: Ui.muted, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _currencyPicker() {
    return DropdownButtonFormField<String>(
      key: ValueKey('country-$_country'),
      initialValue: _country,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Pricing country / currency'.tr,
        prefixIcon: const Icon(Icons.public_rounded),
      ),
      items: [
        DropdownMenuItem(
          value: 'auto',
          child: Text('Automatic (device region)'.tr),
        ),
        for (final c in kPricingCountries)
          DropdownMenuItem(
            value: c[0],
            child: Text('${c[1]} (${currencyForCountry(c[0])})'),
          ),
      ],
      onChanged: (v) {
        if (v == null || v == _country) return;
        setState(() => _country = v);
        _loadRates();
      },
    );
  }

  Widget _amountPicker() {
    final code = _local ? _currency : 'NGN';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _currencyPicker(),
          const SizedBox(height: 14),
          Text(
            'Any amount helps. Pick one or enter your own.'.tr,
            style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _amounts)
                _chip(
                  _money(code, _localFor(a)),
                  !_useCustom && _amount == a,
                  () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _useCustom = false;
                      _amount = a;
                    });
                  },
                  sub: _local ? '\u2248 ${_naira(_ngnFor(_localFor(a)))}' : null,
                ),
              _chip('Other'.tr, _useCustom,
                  () => setState(() => _useCustom = true)),
            ],
          ),
          if (_useCustom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _custom,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              decoration: InputDecoration(
                prefixText: '${_symbols[code] ?? '$code '} ',
                hintText: 'Enter amount'.tr,
                filled: true,
                fillColor: Ui.cardDeep,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Ui.line),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_ratesLoading && _currency != 'NGN')
            Row(children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Getting today\u2019s exchange rate...'.tr,
                    style: TextStyle(color: Ui.muted, fontSize: 12.5)),
              ),
            ])
          else if (_currency != 'NGN' && !_local)
            Text(
              'Could not get the exchange rate, so amounts are shown in naira (\u20A6).'
                  .tr,
              style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.3),
            )
          else if (_local)
            Text(
              'Bank transfers are received in naira (\u20A6). Your amount is converted at today\u2019s rate, so it is an estimate in your currency.'
                  .tr,
              style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.3),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap, {String? sub}) =>
      InkWell(
        borderRadius: BorderRadius.circular(sub == null ? 30 : 18),
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: sub == null ? 10 : 8),
          decoration: BoxDecoration(
            color: on ? _rose.withValues(alpha: .18) : Ui.cardDeep,
            borderRadius: BorderRadius.circular(sub == null ? 30 : 18),
            border: Border.all(color: on ? _rose : Ui.line, width: on ? 1.6 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                  color: on ? Ui.text : Ui.muted,
                ),
              ),
              if (sub != null)
                Text(sub, style: TextStyle(fontSize: 11, color: Ui.dim)),
            ],
          ),
        ),
      );

  Widget _payCard() {
    final bank = _method == 'bank';
    final ngn = _chosenNgn;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: _method_('bank', Icons.account_balance_rounded,
                  'Bank transfer'.tr),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _method_('crypto', Icons.currency_bitcoin_rounded,
                  'Crypto (USDT)'.tr),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Ui.cardDeep,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Ui.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bank) ...[
                  _kv('Provider'.tr, '${_bank['provider'] ?? 'Bank'}'),
                  _kv('Account name'.tr, '${_bank['account_name'] ?? ''}'),
                  const SizedBox(height: 6),
                  _copyValue('Account number'.tr,
                      '${_bank['account_number'] ?? ''}', 'Account number'.tr),
                  const SizedBox(height: 10),
                  Text(
                    ngn > 0
                        ? (_local
                            ? 'Transfer {amt} (about {local}) to this account.'
                                .trArgs({
                                'amt': _naira(ngn),
                                'local': _chosenLocalText,
                              })
                            : 'Transfer {amt} to this account.'
                                .trArgs({'amt': _naira(ngn)}))
                        : 'Transfer any amount to this account.'.tr,
                    style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
                  ),
                ] else ...[
                  _kv('Provider'.tr, '${_wallet['provider'] ?? 'Crypto'}'),
                  _kv('Network'.tr, '${_wallet['network'] ?? ''}'),
                  _kv('Account name'.tr,
                      '${_wallet['wallet_name'] ?? _wallet['account_name'] ?? ''}'),
                  const SizedBox(height: 6),
                  _copyValue(
                    'Wallet address'.tr,
                    '${_wallet['wallet_address'] ?? _wallet['address'] ?? ''}',
                    'Wallet address'.tr,
                    small: true,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (_usdtText != null
                            ? 'Send about {usdt} USDT ({amt}). Only use the {net} network, or the funds are lost.'
                                .trArgs({
                                'usdt': _usdtText,
                                'amt': _naira(ngn),
                                'net': '${_wallet['network'] ?? ''}',
                              })
                            : 'Send any USDT amount. Only use the {net} network, or the funds are lost.'
                                .trArgs({'net': '${_wallet['network'] ?? ''}'})),
                    style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _method_(String id, IconData icon, String label) {
    final on = _method == id;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _method = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: on ? _rose.withValues(alpha: .16) : Ui.cardDeep,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? _rose : Ui.line, width: on ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: on ? _rose : Ui.muted),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: on ? Ui.text : Ui.muted,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: 112,
            child: Text(k, style: TextStyle(color: Ui.muted, fontSize: 14)),
          ),
          Expanded(
            child: Text(v,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
      );

  Widget _copyValue(String label, String value, String what,
          {bool small = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Ui.muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(
                  fontSize: small ? 14 : 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: small ? 0 : .5,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Copy'.tr,
              onPressed: () => _copy(value, what),
              icon: const Icon(Icons.copy_rounded, size: 20, color: _rose),
            ),
          ]),
        ],
      );

  Widget _receiptCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long_rounded, color: _gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Done? Let us say thank you'.tr,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15.5),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Optional: send your receipt on WhatsApp so we can thank you personally.'
                  .tr,
              style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1FAF5A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _sendReceipt,
                icon: const Icon(Icons.chat_rounded),
                label: Text('Send receipt on WhatsApp'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      );

  Widget _thanks() => Column(children: [
        const Icon(Icons.favorite_rounded, color: _rose, size: 22),
        const SizedBox(height: 8),
        Text(
          'Thank you for being part of Deeprowss.'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Support is always optional and never required to use the app.'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(color: Ui.muted, fontSize: 12.5),
        ),
      ]);

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Ui.line),
      );
}
