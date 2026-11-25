import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/decoder_number.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/premium_gate.dart';
import 'decoder_cast_page.dart';
import 'decoder_fixtures_page.dart';
import 'decoder_movies_page.dart';
import 'decoder_channels_page.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';
import 'decoder_guide_page.dart';
import 'decoder_mirror_page.dart';
import 'decoder_receiver_page.dart';
import 'decoder_remote_page.dart';

/// Deeprowss Decoder: one page per way of getting video to a bigger screen.
class DecoderHubScreen extends StatefulWidget {
  /// The channel / video the user came from (cast button in a player).
  final CastTarget? target;
  final VoidCallback? onCastStarted;

  /// Decoder subpage to reopen straight away (cast, mirror, receiver, remote, channels).
  final String? initialPage;
  const DecoderHubScreen({super.key, this.target, this.onCastStarted, this.initialPage});

  @override
  State<DecoderHubScreen> createState() => _DecoderHubScreenState();
}

class _DecoderHubScreenState extends State<DecoderHubScreen> {
  final CastService svc = CastService.instance;
  final DeeprowssMirrorService mirror = DeeprowssMirrorService.instance;
  String? _number;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      DecoderMemory.save('hub');
      // Smart Decoder requires registration; Premium is not required to enter.
      final allowed = await PremiumGate.allowDecoder(context);
      if (!mounted) return;
      if (!allowed) {
        Navigator.of(context).maybePop();
        return;
      }
      final n = await DecoderNumber.get();
      if (mounted) setState(() => _number = n);
      final restore = _pageFor(widget.initialPage);
      if (restore != null) _open(restore.$1, restore.$2);
    });
  }

  @override
  void dispose() {
    // Leaving the Decoder altogether: nothing to restore next time.
    DecoderMemory.save(null);
    super.dispose();
  }

  (Widget, String)? _pageFor(String? id) {
    switch (id) {
      case 'cast':
        return (const DecoderCastPage(), 'cast');
      case 'mirror':
        return (const DecoderMirrorPage(), 'mirror');
      case 'receiver':
        return (const DecoderReceiverPage(), 'receiver');
      case 'remote':
        return (const DecoderRemotePage(), 'remote');
      case 'channels':
        return (const DecoderChannelsPage(), 'channels');
      case 'fixtures':
        return (const DecoderFixturesPage(), 'fixtures');
      case 'movies':
        return (const DecoderMoviesPage(), 'movies');
    }
    return null;
  }

  Future<void> _open(Widget page, String id) async {
    if (!await PremiumGate.allowDecoder(context) || !mounted) return;
    DecoderMemory.save(id);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    DecoderMemory.save('hub');
  }

  Future<void> _openReceiver() async {
    if (!await PremiumGate.consumeReceiverAccess(context) || !mounted) return;
    await _open(const DecoderReceiverPage(), 'receiver');
  }

  /// Square icon tile used by every card on this page.
  Widget _iconTile(IconData icon, {double size = 46, bool solid = false}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: solid
                ? [Ui.red, Ui.redSoft]
                : [Ui.red.withValues(alpha: .26), Ui.red.withValues(alpha: .09)],
          ),
          border: Border.all(color: Ui.red.withValues(alpha: solid ? 0 : .30)),
        ),
        child: Icon(icon, color: solid ? Ui.palette.onAccent : Ui.red, size: size * .52),
      );

  Widget _arrowDot({bool accent = false}) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent ? Ui.red.withValues(alpha: .20) : Ui.text.withValues(alpha: .07),
        ),
        child: Icon(Icons.arrow_forward_rounded, size: 16, color: accent ? Ui.red : Ui.muted),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: Ui.red,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: TextStyle(color: Ui.palette.onAccent, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .8)),
      );

  /// Wide highlighted card: the main entry of the Watch category.
  Widget _featuredCard(IconData icon, String title, String subtitle, VoidCallback onTap, {String? badge}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Ui.red.withValues(alpha: Ui.isLight ? .14 : .20), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Ui.red.withValues(alpha: .55), width: 1.2),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(Ui.red.withValues(alpha: .28), Ui.card),
                    Color.alphaBlend(Ui.red.withValues(alpha: .05), Ui.panel),
                  ],
                ),
              ),
              child: Row(children: [
                _iconTile(icon, size: 58, solid: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (badge != null) ...[_pill(badge), const SizedBox(height: 7)],
                    Text(title, style: TextStyle(color: Ui.text, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: .3)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.35)),
                  ]),
                ),
                const SizedBox(width: 8),
                _arrowDot(accent: true),
              ]),
            ),
          ),
        ),
      );

  /// Half-width card used in pairs.
  Widget _gridCard(IconData icon, String title, String subtitle, VoidCallback onTap) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ui.line),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(Ui.red.withValues(alpha: .08), Ui.card), Ui.card],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _iconTile(icon, size: 44),
                _arrowDot(),
              ]),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(color: Ui.text, fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Ui.muted, fontSize: 11.5, height: 1.35)),
            ]),
          ),
        ),
      );

  /// One row inside the grouped Decoder tools card.
  Widget _toolRow(IconData icon, String title, String subtitle, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            _iconTile(icon, size: 42),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: Ui.text, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 11.5, height: 1.3)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 22, color: Ui.muted),
          ]),
        ),
      );

  Widget _groupCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Ui.line),
          color: Ui.card,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: Ui.isLight ? .05 : .22), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i != rows.length - 1)
                Divider(height: 1, thickness: 1, indent: 70, endIndent: 14, color: Ui.line),
            ],
          ]),
        ),
      );

  Widget _manualCard() => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const DecoderGuidePage()),
            ),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Ui.red.withValues(alpha: .35)),
                gradient: LinearGradient(
                  colors: [Color.alphaBlend(Ui.red.withValues(alpha: .14), Ui.card), Ui.card],
                ),
              ),
              child: Row(children: [
                _iconTile(Icons.menu_book_rounded, size: 44, solid: true),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Decoder Manual', style: TextStyle(color: Ui.text, fontSize: 14.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('Setup guide for TVs, Kodi and receiver', style: TextStyle(color: Ui.muted, fontSize: 11.5)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, size: 22, color: Ui.redSoft),
              ]),
            ),
          ),
        ),
      );

  void _copyNumber() {
    final n = _number;
    if (n == null) return;
    Clipboard.setData(ClipboardData(text: n));
    HapticFeedback.selectionClick();
    decoderToast(context, 'Decoder number copied.');
  }

  void _explainNumber() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Ui.card,
          title: Text('Your Decoder number', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900)),
          content: Text(
            'This is your Premium access code for the Deeprowss Windows app and receiver page. '
            'Enter it on their home screen to unlock Premium movies and live TV. '
            'The code expires with your subscription; resubscribe to receive a new one.',
            style: TextStyle(color: Ui.muted, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: _copyNumber, child: const Text('Copy')),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );

  /// Decoder number card at the top of the page (tap to copy).
  Widget _numberPill() {
    final n = _number;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Ui.red.withValues(alpha: Ui.isLight ? .10 : .16), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _copyNumber,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Ui.red.withValues(alpha: .55), width: 1.2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(Ui.red.withValues(alpha: .22), Ui.card), Ui.card],
              ),
            ),
            child: Row(children: [
              _iconTile(Icons.key_rounded, size: 46, solid: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DECODER NUMBER',
                      style: TextStyle(color: Ui.muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(n == null ? '···' : DecoderNumber.format(n),
                        style: TextStyle(color: Ui.text, fontSize: 25, letterSpacing: 2.6, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 2),
                  Text('Tap to copy', style: TextStyle(color: Ui.redSoft, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              IconButton(
                tooltip: 'What is this?',
                onPressed: _explainNumber,
                icon: Icon(Icons.info_outline_rounded, color: Ui.muted, size: 21),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Deeprowss Decoder', style: TextStyle(fontWeight: FontWeight.w900, color: Ui.text)),
          Text('Watch on a bigger screen', style: TextStyle(fontSize: 11, color: Ui.muted)),
        ]),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListenableBuilder(
        listenable: Listenable.merge([svc, mirror]),
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
          _numberPill(),
          if (svc.casting)
            decoderPanel(Row(children: [
              Icon(Icons.cast_connected, color: Ui.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Playing on ${svc.device?.name ?? 'TV'} · ${svc.castTitle}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: svc.stop, child: const Text('Stop')),
            ]))
          else if (mirror.running)
            decoderPanel(Row(children: [
              Icon(Icons.screen_share_rounded, color: Ui.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(mirror.status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: mirror.stop, child: const Text('Stop')),
            ])),
          if (t != null && t.canCast)
            decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ready to watch', style: TextStyle(color: Ui.muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await castToTv(context, t);
                      if (svc.casting) widget.onCastStarted?.call();
                    },
                    icon: const Icon(Icons.cast_rounded),
                    label: const Text('TV / Kodi'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => sendToReceiver(context, t),
                    icon: const Icon(Icons.web_rounded),
                    label: const Text('Receiver'),
                  ),
                ),
              ]),
            ])),
          decoderSectionHeader(
            icon: Icons.live_tv_rounded,
            kicker: '01 · Entertainment',
            title: 'Watch on your screen',
            subtitle: 'Live events, movies and TV channels.',
            padding: const EdgeInsets.only(top: 2, bottom: 12),
          ),
          _featuredCard(
            Icons.sports_soccer_rounded,
            'Live Events',
            'Cast live matches with a main and a backup stream.',
            () => _open(const DecoderFixturesPage(), 'fixtures'),
            badge: 'LIVE',
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _gridCard(Icons.movie_filter_rounded, 'Moviebox', 'Search the library and cast a title',
                  () => _open(const DecoderMoviesPage(), 'movies')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _gridCard(Icons.live_tv_rounded, 'TV Channels', 'Browse and play compatible channels',
                  () => _open(const DecoderChannelsPage(), 'channels')),
            ),
          ]),
          decoderSectionHeader(
            icon: Icons.tune_rounded,
            kicker: '02 · Control room',
            title: 'Decoder tools',
            subtitle: 'Connect and control your display.',
            padding: const EdgeInsets.only(top: 26, bottom: 12),
          ),
          _groupCard([
            _toolRow(Icons.cast_rounded, 'Cast to TV / Kodi', 'Find compatible screens on your Wi-Fi',
                () => _open(const DecoderCastPage(), 'cast')),
            _toolRow(Icons.screen_share_rounded, 'Screen mirroring', 'Mirror your phone screen',
                () => _open(const DecoderMirrorPage(), 'mirror')),
            _toolRow(Icons.web_rounded, 'Send to receiver page', 'Use a browser screen as your receiver', _openReceiver),
            _toolRow(Icons.gamepad_rounded, 'TV remote', 'Roku, LG, Samsung and playback controls',
                () => _open(const DecoderRemotePage(), 'remote')),
          ]),
          _manualCard(),
        ]),
        ),
      ),
    );
  }
}
