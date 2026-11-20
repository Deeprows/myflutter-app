import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_channels_page.dart';
import 'decoder_common.dart';

/// Dashboard for the browser receiver and its remote controls.
class DecoderReceiverPage extends StatelessWidget {
  const DecoderReceiverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = DeeprowssMirrorService.instance;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Receiver dashboard', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.connected_tv_rounded, size: 30, color: Ui.red),
              const SizedBox(width: 12),
              Expanded(child: Text(m.running ? m.status : 'Receiver is offline',
                  style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800))),
              Icon(Icons.circle, color: m.connected ? Colors.green : Ui.muted, size: 10),
            ]),
            const SizedBox(height: 10),
            Text('The TV plays the selected media directly. Send movies from the movie player's Cast button and choose 'Send to receiver page'. Your phone then works as the remote and can be locked.',
                style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.45)),
            const SizedBox(height: 14),
            if (!m.running)
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () async {
                  try { await m.start(captureScreen: false); }
                  catch (_) { if (context.mounted) decoderToast(context, m.error ?? 'Could not start receiver.'); }
                }, icon: const Icon(Icons.power_settings_new), label: const Text('Start receiver'),
              ))
            else ...[
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const DecoderChannelsPage(only: 'receiver'))),
                icon: const Icon(Icons.video_library_outlined), label: const Text('Choose a TV channel'),
              )),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () async { await m.stop(); if (context.mounted) decoderToast(context, 'Receiver stopped.'); },
                icon: const Icon(Icons.stop_circle_outlined), label: const Text('Stop receiver session'),
              )),
            ],
            if (m.error != null) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize: 12))),
          ])),
          if (m.running && m.pairingUrl != null)
            decoderPanel(Column(children: [
              Text('Connect your TV or browser', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(
                data: m.pairingUrl!, size: 190, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M)),
              const SizedBox(height: 12),
              SelectableText(m.pairingUrl!, textAlign: TextAlign.center,
                style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('PIN', style: TextStyle(color: Ui.muted, fontSize: 11, letterSpacing: 1.4)),
                const SizedBox(width: 12),
                SelectableText(m.pin ?? '', style: TextStyle(color: Ui.red, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 5)),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '${m.pairingUrl}\nPIN: ${m.pin}'));
                if (context.mounted) decoderToast(context, 'Receiver details copied.');
              }, icon: const Icon(Icons.copy), label: const Text('Copy connection details')),
            ])),
          if (m.running && m.connected) decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.play_circle_fill, color: Ui.red), const SizedBox(width: 8),
              Text('Now playing', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17))]),
            const SizedBox(height: 6),
            Text(m.nowPlayingTitle.isEmpty ? 'Waiting for media' : m.nowPlayingTitle,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(m.nowPlayingKind == 'embed' ? 'Embedded movie player' : 'Direct media player',
              style: TextStyle(color: Ui.muted, fontSize: 11)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _RemoteButton(icon: Icons.replay_10_rounded, label: '−10 sec', onTap: () => m.sendRemoteCommand('rewind')),
              _RemoteButton(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => m.sendRemoteCommand('play'), primary: true),
              _RemoteButton(icon: Icons.pause_rounded, label: 'Pause', onTap: () => m.sendRemoteCommand('pause')),
              _RemoteButton(icon: Icons.forward_10_rounded, label: '+10 sec', onTap: () => m.sendRemoteCommand('forward')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => m.sendRemoteCommand('mute'),
                icon: const Icon(Icons.volume_off_rounded), label: const Text('Mute'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () => m.sendRemoteCommand('fullscreen'),
                icon: const Icon(Icons.fullscreen_rounded), label: const Text('Fullscreen'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => m.sendRemoteCommand('stop'),
                icon: const Icon(Icons.stop_rounded), label: const Text('Stop'))),
            ]),
            Row(children: [
              const Icon(Icons.volume_down_rounded),
              Expanded(child: Slider(value: m.receiverVolume.toDouble(), min: 0, max: 100,
                onChanged: m.setReceiverVolume)),
              Text('${m.receiverVolume}%', style: TextStyle(color: Ui.muted, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Text('Controls are supported when the movie provider exposes a compatible iframe player API. Some third-party embeds restrict remote control.',
              style: TextStyle(color: Ui.muted, fontSize: 11, height: 1.35)),
          ])),
          decoderPanel(Text('Movie pages are loaded in a dedicated receiver iframe so the provider player can run its own scripts. Kodi cannot play an HTML iframe: Kodi still requires a direct media stream or a Kodi-compatible add-on.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.45))),
        ]),
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _RemoteButton({required this.icon, required this.label, required this.onTap, this.primary = false});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(color: primary ? Ui.red.withValues(alpha: .18) : Ui.card,
      borderRadius: BorderRadius.circular(14), border: Border.all(color: primary ? Ui.red : Ui.line)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: primary ? Ui.red : Ui.text, size: 25),
      const SizedBox(height: 3), Text(label, style: TextStyle(color: Ui.muted, fontSize: 10))]),
  ));
}
