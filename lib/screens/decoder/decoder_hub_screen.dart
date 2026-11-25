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
      // The Smart Decoder itself is Premium-only, not just its sub-pages.
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

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {String? badge}) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Ui.line),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color.alphaBlend(Ui.red.withValues(alpha: .09), Ui.card), Ui.card],
              ),
            ),
            child: ListTile(
              dense: true,
              minVerticalPadding: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Ui.panel,
                  border: Border.all(color: Ui.red.withValues(alpha: .35)),
                ),
                child: Icon(icon, color: Ui.red, size: 20),
              ),
              title: Text(title, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 13)),
              subtitle: Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 10.5)),
              trailing: badge == null
                  ? Icon(Icons.chevron_right, size: 18, color: Ui.redSoft)
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(99)),
                      child: Text(badge,
                          style: TextStyle(color: Ui.palette.onAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)),
                    ),
              onTap: onTap,
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

  /// Header strip under the title: the unique Decoder number (tap to copy).
  Widget _numberPill() {
    final n = _number;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.red.withValues(alpha: .7), width: 1.2),
        ),
        child: InkWell(
          onTap: _copyNumber,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: Ui.red.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.key_rounded, color: Ui.redSoft, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('DECODER NUMBER · TAP TO COPY',
                      style: TextStyle(color: Ui.muted, fontSize: 9.5, letterSpacing: .8, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(n == null ? '···' : DecoderNumber.format(n),
                        style: TextStyle(color: Ui.text, fontSize: 21, letterSpacing: 2.4, fontWeight: FontWeight.w900)),
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'What is this?',
                visualDensity: VisualDensity.compact,
                onPressed: _explainNumber,
                icon: Icon(Icons.info_outline_rounded, color: Ui.muted, size: 20),
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
        backgroundColor: Ui.panel,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Deeprowss Decoder', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('Watch on a bigger screen', style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SizedBox(height: 50, child: _numberPill()),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListenableBuilder(
        listenable: Listenable.merge([svc, mirror]),
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
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
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Ui.red.withValues(alpha: .35)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(Ui.red.withValues(alpha: .20), Ui.card), Ui.card],
              ),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Ui.red.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Ui.red.withValues(alpha: .5)),
                ),
                child: Icon(Icons.settings_input_antenna_rounded, color: Ui.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SMART DECODER CONSOLE', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, letterSpacing: .8, fontSize: 13)),
                const SizedBox(height: 3),
                Text('Choose content, select a screen and enjoy.', style: TextStyle(color: Ui.muted, fontSize: 11)),
              ])),
              Icon(Icons.power_settings_new_rounded, color: Ui.red),
            ]),
          ),
          decoderSectionHeader(
            icon: Icons.live_tv_rounded,
            kicker: '01 · Now showing',
            title: 'Watch on your screen',
            subtitle: 'Cast live football or find a movie.',
            trailing: 'LIVE',
          ),
          _tile(Icons.sports_soccer_rounded, 'Live Fixtures', 'Two cast streams per match · main and backup', () => _open(const DecoderFixturesPage(), 'fixtures'), badge: 'LIVE'),
          _tile(Icons.movie_filter_rounded, 'Pick a Movie & Watch', 'Search the movie library and cast a title', () => _open(const DecoderMoviesPage(), 'movies')),
          decoderSectionHeader(
            icon: Icons.tune_rounded,
            kicker: '02 · Control room',
            title: 'Decoder tools',
            subtitle: 'Connect and control your display.',
            padding: const EdgeInsets.only(top: 12, bottom: 12),
          ),
          _tile(Icons.cast_rounded, 'Cast to TV / Kodi', 'Find compatible screens on your Wi-Fi', () => _open(const DecoderCastPage(), 'cast')),
          _tile(Icons.screen_share_rounded, 'Screen mirroring', 'Mirror your phone screen', () => _open(const DecoderMirrorPage(), 'mirror')),
          _tile(Icons.web_rounded, 'Send to receiver page', 'Use a browser screen as your receiver', _openReceiver),
          _tile(Icons.gamepad_rounded, 'TV remote', 'Roku, LG, Samsung and playback controls', () => _open(const DecoderRemotePage(), 'remote')),
          _tile(Icons.live_tv_rounded, 'Supported channels', 'Browse compatible channel sources', () => _open(const DecoderChannelsPage(), 'channels')),
          _tile(Icons.menu_book_rounded, 'How to use Smart Decoder', 'Setup guide for TVs, Kodi and receiver', () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DecoderGuidePage()),
          )),
        ]),
        ),
      ),
    );
  }
}
