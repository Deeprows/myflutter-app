import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/install_id.dart';
import '../services/subscription_service.dart'
    show PlanInfo, SubscriptionService, TokenState;
import '../theme/app_theme.dart';
import 'browser_screen.dart' show openExternally;
import 'plans_screen.dart' show buildWhatsappUri;

/// "Remove ads": ask for a token, or type one you were given. A valid token
/// switches every ad off on this phone for the days it carries. The Worker
/// (see cloudflare/worker.js, TOKENS.md) hands tokens out and counts them.
class RemoveAdsScreen extends StatefulWidget {
  const RemoveAdsScreen({super.key});

  @override
  State<RemoveAdsScreen> createState() => _RemoveAdsScreenState();
}

class _RemoveAdsScreenState extends State<RemoveAdsScreen> {
  final _sub = SubscriptionService.instance;
  final _contact = TextEditingController();
  final _token = TextEditingController();

  TokenState _state = const TokenState('unknown');
  PlanInfo _plan = PlanInfo.fallback(); // ₦2,000 until the Worker answers
  String _installId = '';
  String _method = 'bank'; // 'bank' | 'crypto'
  bool _busy = false;
  bool _checking = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    AdScheduler.instance.hold(); // no ad pop-up while sorting this out
    _sub.addListener(_changed);
    _load();
    // While waiting for an answer, look again every 20 seconds so the token
    // shows up by itself as soon as it is made.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_state.state == 'pending' && !_busy) _check();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub.removeListener(_changed);
    AdScheduler.instance.release();
    _contact.dispose();
    _token.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    final id = await InstallId.get();
    if (!mounted) return;
    setState(() => _installId = id);
    // Price (naira + the person's own currency) from the Worker.
    unawaited(_sub.loadPlan().then((p) {
      if (mounted) setState(() => _plan = p);
    }));
    await _check();
  }

  Future<void> _check() async {
    final st = await _sub.tokenStatus();
    if (!mounted) return;
    setState(() {
      _state = st;
      _checking = false;
    });
  }

  // ------------------------------------------------------------- actions

  Future<void> _request() async {
    if (_busy) return;
    // The WhatsApp number is the one required field: it is how you reach the
    // person to confirm payment.
    final number = _contact.text.trim();
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      setState(() => _error =
          'Enter your WhatsApp number with country code, e.g. +234 801 234 5678');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await _sub.requestToken(contact: number);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    await _check();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_sub.isPremium) _toast('Request sent ✅');
  }

  Future<void> _redeem(String token) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await _sub.redeemToken(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) _toast('Ads removed. Thank you! 💗');
  }

  Future<void> _chat() async {
    final uri = buildWhatsappUri(
        AppConfig.whatsappUrl, AppConfig.tokenRequestMessage, _installId);
    final link = uri?.toString() ?? AppConfig.joinUrl;
    if (link.isEmpty) {
      _toast('The chat link is not set up yet');
      return;
    }
    if (!await openExternally(link) && mounted) {
      _toast('Could not open the chat');
    }
  }

  /// Opens WhatsApp with the receipt message ready; the person attaches the
  /// payment screenshot there.
  Future<void> _sendReceipt() async {
    final how = _method == 'bank'
        ? '${AppConfig.payBankProvider} bank transfer'
        : '${AppConfig.payCryptoProvider} (${AppConfig.payCryptoNetwork})';
    final message = 'Hello, I have paid to remove ads on the Deeprowss app.\n'
        'Payment: $how\n'
        'Amount: ${_plan.priceDisplay}\n'
        'My receipt is attached.';
    final uri = buildWhatsappUri(
        AppConfig.receiptWhatsappUrl, message, _installId);
    if (uri == null || !await openExternally(uri.toString())) {
      if (mounted) _toast('Could not open WhatsApp');
    }
  }

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _toast('$what copied');
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final premium = _sub.isPremium;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: const Text('Remove ads',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
              children: [
                if (premium)
                  _activeCard()
                else ...[
                  _hero(),
                  const SizedBox(height: 14),
                  _stepCard(
                    number: 1,
                    title: 'Make your payment',
                    child: _payBlock(),
                  ),
                  const SizedBox(height: 12),
                  _stepCard(
                    number: 2,
                    title: 'Send your receipt',
                    child: _receiptBlock(),
                  ),
                  const SizedBox(height: 12),
                  _stepCard(
                    number: 3,
                    title: 'Get your token',
                    child: _tokenBlock(),
                  ),
                  const SizedBox(height: 12),
                  _haveTokenCard(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ui.redSoft, fontSize: 13.5)),
                ],
                const SizedBox(height: 10),
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
    final date = _sub.expiresLabel;
    final left = _sub.daysLeft;
    final detail = [
      if (date != null) 'No ads until $date',
      if (left != null && left <= 400) '$left day${left == 1 ? '' : 's'} left',
    ].join(' · ');
    return _box(
      highlight: true,
      child: Row(children: [
        Icon(Icons.verified_rounded, color: Ui.green, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Subscription: Active',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(detail.isEmpty ? 'All ads are removed' : detail,
                  style: TextStyle(color: Ui.muted, fontSize: 13.5)),
            ],
          ),
        ),
      ]),
    );
  }

  /// Title + price at the top of the page.
  Widget _hero() {
    final local = _plan.localDisplay;
    return _box(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Ui.red.withValues(alpha: .18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.block_rounded, color: Ui.redSoft),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Go ad-free',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_plan.priceDisplay,
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Text('/ month', style: TextStyle(color: Ui.muted, fontSize: 14)),
              if (local != null) ...[
                const SizedBox(width: 10),
                Text('≈ $local',
                    style: TextStyle(
                        color: Ui.green,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            local != null
                ? 'No ads for 30 days on this phone. Charged in naira; $local '
                    'is an estimate in your currency.'
                : 'No ads for 30 days on this phone.',
            style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required int number,
    required String title,
    required Widget child,
  }) =>
      _box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: Ui.red,
                child: Text('$number',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  // ---- step 1: payment details

  Widget _payBlock() {
    final bank = _method == 'bank';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: _methodChip(
              id: 'bank',
              icon: Icons.account_balance_rounded,
              label: 'Bank transfer',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _methodChip(
              id: 'crypto',
              icon: Icons.currency_bitcoin_rounded,
              label: 'Crypto (USDT)',
            ),
          ),
        ]),
        const SizedBox(height: 12),
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
                _kv('Provider', AppConfig.payBankProvider),
                _kv('Account name', AppConfig.payBankAccountName),
                const SizedBox(height: 6),
                _copyValue(
                  label: 'Account number',
                  value: AppConfig.payBankAccountNumber,
                  what: 'Account number',
                ),
                const SizedBox(height: 10),
                Text(
                  'Transfer ${_plan.priceDisplay} to this account.',
                  style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
                ),
              ] else ...[
                _kv('Provider', AppConfig.payCryptoProvider),
                _kv('Network', AppConfig.payCryptoNetwork),
                _kv('Account name', AppConfig.payCryptoAccountName),
                const SizedBox(height: 6),
                _copyValue(
                  label: 'Wallet address',
                  value: AppConfig.payCryptoAddress,
                  what: 'Wallet address',
                ),
                const SizedBox(height: 10),
                Text(
                  'Send the USDT equivalent of ${_plan.priceDisplay}. Only '
                  'send on the ${AppConfig.payCryptoNetwork} network, or the '
                  'funds are lost.',
                  style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _methodChip({
    required String id,
    required IconData icon,
    required String label,
  }) {
    final on = _method == id;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _method = id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: on ? Ui.red.withValues(alpha: .16) : Ui.cardDeep,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: on ? Ui.red : Ui.line, width: on ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: on ? Ui.redSoft : Ui.muted),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? Colors.white : Ui.muted)),
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
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
      );

  Widget _copyValue({
    required String label,
    required String value,
    required String what,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Ui.muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: SelectableText(value,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4)),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: () => _copy(value, what),
              icon: Icon(Icons.copy_rounded, color: Ui.redSoft),
            ),
          ]),
        ],
      );

  // ---- step 2: receipt on WhatsApp

  Widget _receiptBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'After paying, send your receipt or a screenshot of the payment '
            'on WhatsApp. We confirm it and make your token.',
            style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sendReceipt,
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Send receipt on WhatsApp',
                  style:
                      TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: in WhatsApp, tap the attach (📎) button and choose your '
            'payment screenshot. Your ID is added to the message for you.',
            style: TextStyle(color: Ui.dim, fontSize: 12, height: 1.3),
          ),
        ],
      );

  // ---- step 3: token request / pending / ready

  Widget _tokenBlock() {
    final st = _state.state;
    if (_checking) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    if (st == 'ready' && _state.token != null) return _readyBlock();
    if (st == 'pending') return _pendingBlock();
    return _askBlock();
  }

  Widget _askBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Request your token. When it is ready it shows up here and one '
            'tap switches every ad off on this phone.',
            style: TextStyle(color: Ui.muted, fontSize: 13.5, height: 1.3),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            maxLength: 20,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ()]')),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: const InputDecoration(
              labelText: 'Your WhatsApp number',
              hintText: '+234 801 234 5678',
              helperText: 'Required. We message you here to confirm payment.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          _primary(
            label: 'Request token',
            icon: Icons.vpn_key_rounded,
            onTap: _request,
          ),
        ],
      );

  Widget _pendingBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.hourglass_top_rounded, color: Ui.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Request sent. Your token will appear here by itself once '
                'your payment is confirmed.',
                style: TextStyle(color: Ui.muted, fontSize: 13.5),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _primary(label: 'Check now', icon: Icons.refresh_rounded, onTap: () async {
            setState(() => _busy = true);
            await _check();
            if (mounted) setState(() => _busy = false);
          }),
          TextButton(
            onPressed: _chat,
            child: const Text('Need help? Chat on WhatsApp'),
          ),
        ],
      );

  Widget _readyBlock() {
    final t = _state.token!;
    final days = _state.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          days > 0 ? 'Your token is ready ($days days)' : 'Your token is ready',
          style: TextStyle(color: Ui.green, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Ui.cardDeep,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Ui.line),
          ),
          child: SelectableText(
            t,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ),
        const SizedBox(height: 12),
        _primary(
          label: 'Remove ads now',
          icon: Icons.check_circle_rounded,
          onTap: () => _redeem(t),
        ),
      ],
    );
  }

  Widget _haveTokenCard() => _box(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Already have a token?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            children: [
              TextField(
                controller: _token,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 16,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                  _UpperCaseFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Token (XXXX-XXXX-XXXX)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              _primary(
                label: 'Remove ads',
                icon: Icons.block_rounded,
                onTap: () => _redeem(_token.text),
              ),
            ],
          ),
        ),
      );

  Widget _primary({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : onTap,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white))
              : Icon(icon),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: Ui.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
          ),
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

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
