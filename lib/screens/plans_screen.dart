import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/install_id.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart' show openExternally;
import 'paystack_checkout_screen.dart';

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
  final _email = TextEditingController();

  PlanInfo _plan = PlanInfo.fallback();
  String _installId = '';
  bool _auto = false;
  bool _busy = false;
  String? _error;

  bool get _startup => widget.onContinue != null;

  @override
  void initState() {
    super.initState();
    AdScheduler.instance.hold(); // no ad pop-up while choosing / paying
    _sub.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _sub.removeListener(_changed);
    AdScheduler.instance.release();
    _email.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final id = await InstallId.get();
    final mail = await _sub.savedEmail();
    if (!mounted) return;
    setState(() {
      _installId = id;
      if (_email.text.isEmpty) _email.text = mail;
    });
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

  Future<void> _subscribe() async {
    if (_busy) return;
    final mail = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(mail)) {
      setState(() => _error = 'Enter a valid e-mail address (for your receipt)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await _sub.startCheckout(
        email: mail,
        recurring: _auto && _plan.recurring,
      );
      if (!mounted) return;
      final doneUrl =
          '${AppConfig.feedBase.trim().replaceAll(RegExp(r'/+$'), '')}/sub/done';
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PaystackCheckoutScreen(
          url: start.url,
          doneUrlPrefix: doneUrl,
        ),
      ));
      if (!mounted) return;
      // Closed or finished: ask the Worker either way.
      final result = await _sub.confirm(start.reference);
      if (!mounted) return;
      switch (result) {
        case PaymentResult.active:
          _toast('Premium is on. Thank you! 💗');
        case PaymentResult.pending:
          _toast('Your payment is still being confirmed. It switches on '
              'by itself in a few minutes.');
        case PaymentResult.failed:
          _toast('No payment was received.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsapp() async {
    final uri = buildWhatsappUri(
        AppConfig.whatsappUrl, AppConfig.whatsappMessage, _installId);
    if (uri == null) {
      _toast('WhatsApp payment will be available soon.');
      return;
    }
    if (!await openExternally(uri.toString()) && mounted) {
      _toast('Could not open WhatsApp');
    }
  }

  Future<void> _restore() async {
    final mail = TextEditingController(text: _email.text);
    final ref = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Restore Premium'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paid on another phone? Enter the e-mail you paid with and the '
              'payment reference from your Paystack receipt.',
              style: TextStyle(color: Ui.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            TextField(
              controller: ref,
              decoration: const InputDecoration(labelText: 'Payment reference'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    final email = mail.text.trim();
    final reference = ref.text.trim();
    mail.dispose();
    ref.dispose();
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    final err = await _sub.restore(email: email, reference: reference);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(err ?? 'Premium restored. Thank you! 💗');
  }

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
                if (!premium) _freeCard() else _continueButton('Continue'),
                const SizedBox(height: 14),
                _manualCard(),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _restore,
                    child: Text('Restore purchase',
                        style: TextStyle(color: Ui.muted)),
                  ),
                ),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_plan.priceDisplay,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900)),
              Text('  / month',
                  style: TextStyle(color: Ui.muted, fontSize: 14)),
            ],
          ),
          if (_plan.localDisplay != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('≈ ${_plan.localDisplay} / month in your currency',
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          feature('No “We Need Your Support” pop-ups'),
          feature('Stream without interruptions'),
          feature('Pay with card, bank transfer or USSD'),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Your e-mail (for the receipt)',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          if (_plan.recurring)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _auto,
              onChanged: _busy ? null : (v) => setState(() => _auto = v),
              title: const Text('Renew automatically every month',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: Text('Card only. Otherwise pay again each month.',
                  style: TextStyle(color: Ui.muted, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: (_busy || !_plan.available) ? null : _subscribe,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              premium
                                  ? 'Add 1 more month'
                                  : 'Subscribe  •  ${_plan.priceDisplay}/month',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_plan.available)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Online payment is not available right now. '
                  'Use WhatsApp below.',
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _freeCard() {
    final m = AppConfig.adIntervalMinutes;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Free',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'Everything is open. A short “Support” page shows every $m '
            'minutes of use.',
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

  Widget _manualCard() => _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Can't pay online?",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Chat with us on WhatsApp and pay manually. We switch Premium '
              'on for you.',
              style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.25),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _whatsapp,
                icon: Icon(Icons.chat_rounded, color: Ui.green),
                label: const Text('Pay manually on WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Ui.green.withValues(alpha: .7)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        ),
      );

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
