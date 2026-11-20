import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
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
  const DecoderHubScreen({super.key, this.target, this.onCastStarted});

  @override
  State<DecoderHubScreen> createState() => _DecoderHubScreenState();
}

class _DecoderHubScreenState extends State<DecoderHubScreen> {
  final CastService svc = CastService.instance;
  final DeeprowssMirrorService mirror = DeeprowssMirrorService.instance;
  bool _premiumChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final allowed = await PremiumGate.allowDecoder(context);
      if (!mounted) return;
      if (!allowed) {
        Navigator.of(context).maybePop();
      } else {
        setState(() => _premiumChecked = true);
      }
    });
  }

  void _open(Widget page) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

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

  @override
  Widget build(BuildContext context) {
    if (!_premiumChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = widget.target;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Deeprowss Decoder', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('Watch on a bigger screen', style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
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
          _tile(Icons.cast_rounded, 'Cast to TV / Kodi', 'Smart TVs and Kodi on your Wi-Fi', () => _open(const DecoderCastPage())),
          _tile(Icons.screen_share_rounded, 'Screen mirroring', 'Show your phone screen', () => _open(const DecoderMirrorPage())),
          _tile(Icons.web_rounded, 'Send to receiver page', 'Play channels in a laptop or TV browser', () => _open(const DecoderReceiverPage())),
          _tile(Icons.gamepad_rounded, 'TV remote', 'Roku, LG, Samsung and playback controls', () => _open(const DecoderRemotePage())),
          _tile(Icons.live_tv_rounded, 'Supported channels', 'See what works, then pick how to watch', () => _open(const DecoderChannelsPage())),
        ]),
      ),
    );
  }
}
