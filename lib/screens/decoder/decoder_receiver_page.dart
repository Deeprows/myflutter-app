import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_channels_page.dart';
import 'decoder_common.dart';

/// Send channel to receiver page: the laptop / TV browser plays the stream
/// itself, with sound, and the phone can be locked.
class DecoderReceiverPage extends StatelessWidget {
  const DecoderReceiverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = DeeprowssMirrorService.instance;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Receiver page', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.web_rounded, size: 30, color: Ui.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(m.running ? m.status : 'No receiver session',
                    style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
              ),
              if (m.connected) const Icon(Icons.circle, color: Colors.green, size: 10),
            ]),
            const SizedBox(height: 10),
            Text(
              'Open the receiver page on a laptop or TV browser, connect with the code below, then send channels to it from your phone.',
              style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (!m.running)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      await m.start(captureScreen: false);
                    } catch (_) {
                      if (context.mounted) decoderToast(context, m.error ?? 'Could not start the receiver session.');
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start receiver session'),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DecoderChannelsPage(only: 'receiver')),
                  ),
                  icon: const Icon(Icons.live_tv_rounded),
                  label: const Text('Choose a channel to send'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await m.stop();
                    if (context.mounted) decoderToast(context, 'Receiver session stopped.');
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop session'),
                ),
              ),
            ],
            if (m.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize: 12)),
              ),
          ])),
          if (m.running && m.pairingUrl != null)
            decoderPanel(Column(children: [
              Text('Connect the receiver', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: m.pairingUrl!,
                  size: 190,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(m.pairingUrl!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('CODE', style: TextStyle(color: Ui.muted, fontSize: 11, letterSpacing: 1.4)),
                const SizedBox(width: 12),
                SelectableText(m.pin ?? '',
                    style: TextStyle(color: Ui.red, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 5)),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '${m.pairingUrl}\nPhone: ${m.url}\nCode: ${m.pin}'));
                  if (context.mounted) decoderToast(context, 'Copied.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy details'),
              ),
            ])),
          decoderPanel(Text(
            'Receiver page plays the stream itself, so sound works and the phone can be locked. Streams that only play with special headers may not play in a browser; use Cast to TV / Kodi for those.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4),
          )),
        ]),
      ),
    );
  }
}
