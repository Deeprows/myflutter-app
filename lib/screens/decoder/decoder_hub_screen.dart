import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/decoder_number.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/premium_gate.dart';
import 'decoder_cast_page.dart';
import 'decoder_channels_page.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';
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
    DecoderNumber.get().then((n) {
      if (mounted) setState(() => _number = n);
    });
    // Everyone can open the Smart Decoder page. Tapping an item asks non-Premium
    // visitors to upgrade (see _open and the Ready-to-watch buttons).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DecoderMemory.save('hub');
      if (!PremiumGate.decoderLocked) {
        final restore = _pageFor(widget.initialPage);
        if (restore != null) _open(restore.$1, restore.$2);
      }
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
    }
    return null;
  }

  Future<void> _open(Widget page, String id) async {
    // Non-Premium visitors see the upgrade sheet instead of the page.
    if (!await PremiumGate.allowDecoder(context) || !mounted) return;
    DecoderMemory.save(id);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    DecoderMemory.save('hub');
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Ui.line),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Ui.red),
          ),
          title: Text(title, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
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
            'This is your personal access code for the Deeprowss Windows app and the receiver page. '
            'Enter it on their home screen to unlock movies and live TV there.',
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
      body: ListenableBuilder(
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
          decoderHeading('Connect', 'Pick how you want to use your TV or laptop.'),
          _tile(Icons.cast_rounded, 'Cast to TV / Kodi', 'Smart TVs and Kodi on your Wi-Fi', () => _open(const DecoderCastPage(), 'cast')),
          _tile(Icons.screen_share_rounded, 'Screen mirroring', 'Show your phone screen', () => _open(const DecoderMirrorPage(), 'mirror')),
          _tile(Icons.web_rounded, 'Send to receiver page', 'Play channels in a laptop or TV browser', () => _open(const DecoderReceiverPage(), 'receiver')),
          _tile(Icons.gamepad_rounded, 'TV remote', 'Roku, LG, Samsung and playback controls', () => _open(const DecoderRemotePage(), 'remote')),
          _tile(Icons.live_tv_rounded, 'Supported channels', 'See what works, then pick how to watch', () => _open(const DecoderChannelsPage(), 'channels')),
        ]),
      ),
    );
  }
}
