import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/install_id.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart' show openExternally;

/// Builds the WhatsApp link for people who pay manually. The person's ID is
/// added to the message so the new subscription can be switched on for the
/// right phone. Returns null while no WhatsApp address is set.
Uri? buildWhatsappUri(String baseUrl, String message, String installId) {
  final base = baseUrl.trim();
  if (base.isEmpty) return null;
  final uri = Uri.tryParse(base);
  if (uri == null) return null;
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'text': '$message\n\nMy ID: $installId',
  });
}

/// Free or Premium. Used as the start page ([onContinue] set) and, from the
/// menu or the ad page, as a normal page that closes with the back button.
class PlansScreen extends StatefulWidget {
  final VoidCallback? onContinue;
  const PlansScreen({super.key, this.onContinue});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _sub = SubscriptionService.instance;
  Map<String, dynamic> _paymentConfig = {};
  String _manualMethod = 'opay';

  PlanInfo _plan = PlanInfo.fallback();
  String _installId = '';
  bool _yearly = false;
  bool _busy = false;
  String? _error;

  bool get _startup => widget.onContinue != null;

  @override
  void initState() {
    super.initState();
    AdScheduler.instance.hold(); // no ad pop-up while choosing / paying
    _sub.addListener(_changed);
    unawaited(_loadPaymentAccounts());
    _load();
  }

  @override
  void dispose() {
    _sub.removeListener(_changed);
    AdScheduler.instance.release();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    // The ID shown to the admin (manual payments) is the Gmail account's.
    final id = _sub.accountId ?? await InstallId.get();
    if (!mounted) return;
    setState(() => _installId = id);
    final plan = await _sub.loadPlan();
    unawaited(_sub.refresh(force: true));
    if (mounted) setState(() => _plan = plan);
  }

  void _continue() {
    if (_startup) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------- actions

  Future<void> _loadPaymentAccounts() async {
    try {
      final raw = await rootBundle.loadString('assets/data/payment_accounts.json');
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic> && mounted) setState(() => _paymentConfig = data);
    } catch (_) {}
  }

  Map<String, dynamic>? _paymentAccount(String id) {
    final rows = _paymentConfig['accounts'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is Map && row['id'] == id && row['enabled'] != false) {
        return Map<String, dynamic>.from(row);
      }
    }
    return null;
  }

  Future<void> _copyPayment(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _toast('$label copied');
  }

  Future<void> _sendManualReceipt() async {
    if (_sub.accountId == null) {
      _toast('Please sign in with Google in the Deeprowss App before making a Premium payment.');
      return;
    }
    final account = _manualMethod == 'opay' ? _paymentAccount('opay') : _paymentAccount('wallet');
    final network = (account?['network'] ?? 'TRC20').toString();
    final method = _manualMethod == 'opay' ? 'OPay transfer' : 'USDT ' + network + ' wallet';
    final days = _yearly ? 366 : 31;
    final local = _shownLocal == null ? '' : ' (local estimate: $_shownLocal)';
    final periodName = _yearly ? 'Yearly' : 'Monthly';
    final message = 'Hello Deeprowss, I have made a manual Premium payment.\n'
        'Plan: ' + periodName + ' (' + days.toString() + ' days)\n'
        'Payment method: ' + method + '\n'
        'Amount: $_shownPrice$local\n'
        'Please confirm my payment and activate Premium. I will attach my receipt.';
    final uri = buildWhatsappUri(AppConfig.receiptWhatsappUrl, message, _installId);
    if (uri == null || !await openExternally(uri.toString())) {
      if (mounted) _toast('Could not open WhatsApp');
    }
  }

  Future<void> _checkManualActivation() async {
    if (_sub.accountId == null) {
      _toast('Please sign in with Google to check your Premium account.');
      return;
    }
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    await _sub.refresh(force: true);
    final active = _sub.isPremium;
    final decoder = active ? await _sub.issueDecoderNumber() : null;
    if (!mounted) return;
    setState(() => _busy = false);
    if (!active) {
      _toast('Payment is not confirmed yet. Please send your receipt on WhatsApp first.');
      return;
    }
    final display = decoder == null ? '' : decoder.substring(0,3) + ' ' + decoder.substring(3,6) + ' ' + decoder.substring(6);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Premium activated 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Premium is active. Use this Decoder number on the EXE and Android TV:'),
            const SizedBox(height: 10),
            if (display.isNotEmpty) SelectableText(display, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2))
            else const Text('Open Smart Decoder to retrieve your Decoder number.'),
          ],
        ),
        actions: [
          if (decoder != null) TextButton(
            onPressed: () async { await Clipboard.setData(ClipboardData(text: decoder)); if (ctx.mounted) Navigator.pop(ctx); if (mounted) _toast('Decoder number copied'); },
            child: const Text('Copy Decoder number'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  String get _shownPrice => _yearly ? _plan.yearPriceDisplay : _plan.priceDisplay;
  String? get _shownLocal => _yearly ? _plan.yearLocalDisplay : _plan.localDisplay;
  String get _perLabel => _yearly ? 'year' : 'month';

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final premium = _sub.isPremium;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: _startup
          ? null
          : AppBar(
              backgroundColor: Ui.bg,
              title: const Text('Plans',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                if (_startup) ...[
                  Image.asset('assets/splash/splash.png',
                      height: 84, fit: BoxFit.contain),
                  const SizedBox(height: 6),
                ],
                Text(
                  premium ? 'You are Premium' : 'Choose your plan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                if (premium) _activeCard(),
                _premiumCard(premium),
                const SizedBox(height: 12),
                if (!premium) ...[
                  _freeCard(),
                  const SizedBox(height: 14),
                  _manualCard(),
                ] else _continueButton('Continue'),
                _idLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _box({required Widget child, bool highlight = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ui.panel,
          gradient: highlight
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Ui.red.withValues(alpha: .16), Ui.panel, Ui.panel],
                  stops: const [0, .55, 1],
                )
              : null,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: highlight ? Ui.red.withValues(alpha: .5) : Ui.line,
              width: highlight ? 1.3 : 1),
        ),
        child: child,
      );

  Widget _activeCard() {
    final d = _sub.expiresAt;
    final date = d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _box(
        child: Row(children: [
          Icon(Icons.verified_rounded, color: Ui.green, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Premium is active',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('No ads until $date',
                    style: TextStyle(color: Ui.muted, fontSize: 13)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _premiumCard(bool premium) {
    Widget feature(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 18, color: Ui.green),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600))),
          ]),
        );

    return _box(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Premium',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ui.red.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('NO ADS',
                  style: TextStyle(
                      color: Ui.redSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 12),
          _periodToggle(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_shownPrice,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900)),
              Text('  / $_perLabel',
                  style: TextStyle(color: Ui.muted, fontSize: 14)),
            ],
          ),
          if (_shownLocal != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('≈ $_shownLocal / $_perLabel in your currency',
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          feature('No pop-ups'),
          feature('Stream without interruptions'),
          feature('Unlimited movies, series and downloads'),
          feature('Premium Smart Decoder access'),
          feature('Manual payment with OPay or USDT (TRC20)'),
          feature('Monthly or yearly (save with yearly)'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Ui.bg.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ui.line),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Paystack online payment', style: TextStyle(fontWeight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Ui.red.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
                  child: Text('COMING SOON', style: TextStyle(color: Ui.redSoft, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('For now, pay manually using OPay or USDT below. Your Premium is activated after we confirm your receipt on WhatsApp.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35)),
        ],
      ),
    );
  }

  Widget _periodToggle() {
    Widget tab(String label, bool yearly, {String? badge}) {
      final on = _yearly == yearly;
      return Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => setState(() => _yearly = yearly),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? Ui.red.withValues(alpha: .22) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: on ? Ui.red : Colors.transparent, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                        color: on ? null : Ui.muted)),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Ui.green.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            color: Ui.green,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final save = _plan.yearSavingPercent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Ui.bg.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Ui.line),
      ),
      child: Row(children: [
        tab('Monthly', false),
        tab('Yearly', true, badge: save > 0 ? 'SAVE $save%' : null),
      ]),
    );
  }

  Widget _freeCard() {
    final m = RemoteConfig.instance.adIntervalMinutes;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Free',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'Browse the full catalogue and watch 3 distinct movie or series '
            'titles free. After that, Play, Alternate player and Download '
            'require Premium. Smart Decoder is Premium-only. A short “Support” '
            'page shows every $m minutes of use.',
            style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.25),
          ),
          const SizedBox(height: 12),
          _continueButton(_startup ? 'Continue with ads' : 'Maybe later'),
        ],
      ),
    );
  }

  Widget _continueButton(String label) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _continue,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: BorderSide(color: Ui.line),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _manualCard() {
    final bank = _paymentAccount('opay') ?? {
      'provider': AppConfig.payBankProvider,
      'account_name': AppConfig.payBankAccountName,
      'account_number': AppConfig.payBankAccountNumber,
    };
    final wallet = _paymentAccount('wallet') ?? {
      'provider': AppConfig.payCryptoProvider,
      'network': AppConfig.payCryptoNetwork,
      'wallet_name': AppConfig.payCryptoAccountName,
      'wallet_address': AppConfig.payCryptoAddress,
    };
    final local = _shownLocal == null ? '' : ' · approximately $_shownLocal in your currency';
    Widget detail(String label, String value, {bool copy = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 105, child: Text(label, style: TextStyle(color: Ui.muted, fontSize: 12))),
        Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        if (copy) IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _copyPayment(value, label),
          icon: Icon(Icons.copy_rounded, size: 18, color: Ui.redSoft),
        ),
      ]),
    );
    Widget choice(String id, String label, IconData icon) {
      final on = _manualMethod == id;
      return Expanded(child: OutlinedButton.icon(
        onPressed: () => setState(() => _manualMethod = id),
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: on ? Ui.text : Ui.muted,
          backgroundColor: on ? Ui.red.withValues(alpha: .16) : Ui.bg,
          side: BorderSide(color: on ? Ui.red : Ui.line),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 7),
        ),
      ));
    }
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Manual Premium payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text('Choose OPay or USDT, transfer the amount, then send your receipt on WhatsApp. We confirm your payment and activate Premium.',
          style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 12),
        Row(children: [
          choice('opay', 'OPay', Icons.account_balance_rounded),
          const SizedBox(width: 8),
          choice('crypto', 'USDT · TRC20', Icons.currency_bitcoin_rounded),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: Ui.bg.withValues(alpha: .55), borderRadius: BorderRadius.circular(15), border: Border.all(color: Ui.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_manualMethod == 'opay') ...[
              detail('Provider', (bank['provider'] ?? bank['name'] ?? 'OPay').toString()),
              detail('Account name', (bank['account_name'] ?? 'Taiwo').toString()),
              detail('Account number', (bank['account_number'] ?? '').toString(), copy: true),
              Text('Transfer $_shownPrice for the ' + (_yearly ? 'yearly' : 'monthly') + ' plan$local.',
                style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35)),
            ] else ...[
              detail('Wallet', (wallet['provider'] ?? wallet['name'] ?? 'USDT').toString()),
              detail('Network', (wallet['network'] ?? 'TRC20').toString()),
              detail('Wallet name', (wallet['wallet_name'] ?? wallet['account_name'] ?? 'Taiwo').toString()),
              detail('Address', (wallet['wallet_address'] ?? wallet['address'] ?? '').toString(), copy: true),
              Text('Send the USDT equivalent of $_shownPrice for the ' + (_yearly ? 'yearly' : 'monthly') + ' plan$local. Use TRC20 only.',
                style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy ? null : _sendManualReceipt,
          icon: const Icon(Icons.chat_rounded),
          label: const Text('Send payment receipt on WhatsApp'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
        )),
        const SizedBox(height: 6),
        Text(_sub.accountId == null
            ? 'Sign in with Google before paying so your Premium can be linked to your account.'
            : 'Attach your payment screenshot in WhatsApp. Your account ID is included automatically: $_installId',
          style: TextStyle(color: Ui.dim, fontSize: 11.5, height: 1.3)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _busy ? null : _checkManualActivation,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
          label: const Text("I've paid — check Premium activation"),
        )),
        const SizedBox(height: 6),
        Center(child: Text('WhatsApp helpline: +234 704 162 9630', style: TextStyle(color: Ui.muted, fontSize: 12))),
      ]),
    );
  }

  Widget _idLine() {
    if (_installId.isEmpty) return const SizedBox.shrink();
    return Center(
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: _installId));
          if (mounted) _toast('ID copied');
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
              'Your ID: ${_installId.length > 8 ? _installId.substring(0, 8) : _installId}…  (tap to copy)',
              style: TextStyle(color: Ui.dim, fontSize: 11.5)),
        ),
      ),
    );
  }
}
