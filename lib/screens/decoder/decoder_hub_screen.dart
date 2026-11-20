import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/app_memory.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import '../plans_screen.dart';
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
  /// Optional saved subpage to reopen after the app is restarted.
  final String? initialPage;
  const DecoderHubScreen({super.key, this.target, this.onCastStarted, this.initialPage});

  @override
  State<DecoderHubScreen> createState() => _DecoderHubScreenState();
}

class _DecoderHubScreenState extends State<DecoderHubScreen> {
  final CastService svc = CastService.instance;
  final DeeprowssMirrorService mirror = DeeprowssMirrorService.instance;

  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    final page = widget.initialPage;
    DecoderMemory.save(page ?? 'hub');
    if (page != null && page != 'hub') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restorePage(page));
    }
  }

  Future<void> _restorePage(String page) async {
    if (!mounted || _restoring) return;
    _restoring = true;
    // The saved page is being opened above the hub; popping it should return
    // to the hub rather than reopening the same child again.
    DecoderMemory.save('hub');
    switch (page) {
      case 'cast': await pushDecoderPage<void>(context, const DecoderCastPage(), 'cast'); break;
      case 'mirror': await pushDecoderPage<void>(context, const DecoderMirrorPage(), 'mirror'); break;
      case 'receiver': await pushDecoderPage<void>(context, const DecoderReceiverPage(), 'receiver'); break;
      case 'remote': await pushDecoderPage<void>(context, const DecoderRemotePage(), 'remote'); break;
      case 'channels': await pushDecoderPage<void>(context, const DecoderChannelsPage(), 'channels'); break;
      case 'plans': await pushDecoderPage<void>(context, const PlansScreen(), 'plans'); break;
      default: DecoderMemory.save('hub');
    }
    _restoring = false;
  }

  void _open(Widget page, String pageId) {
    unawaited(pushDecoderPage<void>(context, page, pageId));
  }

  @override
  void dispose() {
    // The hub is the Decoder entry route; leaving it means the user has
    // intentionally exited Decoder, so don't reopen it on the next launch.
    DecoderMemory.clear();
    super.dispose();
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
          _tile(Icons.workspace_premium_rounded, 'Membership', 'Manage your Deeprowss plan', () => _open(const PlansScreen(), 'plans')),
        ]),
      ),
    );
  }
}
