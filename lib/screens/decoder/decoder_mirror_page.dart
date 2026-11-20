import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/cast_service.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';

/// Screen mirroring: shows the phone screen on a laptop / TV browser.
class DecoderMirrorPage extends StatelessWidget {
  const DecoderMirrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = DeeprowssMirrorService.instance;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Screen mirroring', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.screen_share_rounded, size: 32, color: Ui.red),
              const SizedBox(width: 12),
              Expanded(child: Text(m.status, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800))),
              if (m.connected) const Icon(Icons.circle, color: Colors.green, size: 10),
            ]),
            if (m.audioNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(m.audioNote!, style: const TextStyle(color: Colors.amber, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Text(
              'Shows your whole phone screen on a laptop or TV browser over your Wi-Fi. Keep the phone screen on while mirroring.',
              style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (!m.running)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      await m.start();
                      if (context.mounted) decoderToast(context, 'Screen capture started. Connect your TV with the code below.');
                    } catch (e) {
                      if (context.mounted) decoderToast(context, m.error ?? 'Could not start screen mirroring.');
                    }
                  },
                  icon: const Icon(Icons.cast_connected),
                  label: const Text('Start mirroring'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await m.stop();
                    if (context.mounted) decoderToast(context, 'Mirroring stopped.');
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(m.urlMode ? 'Stop receiver session' : 'Stop mirroring'),
                ),
              ),
            if (m.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize: 12)),
              ),
          ])),
          if (m.running && m.pairingUrl != null) _pairing(context, m),
          if (!m.urlMode)
            decoderPanel(Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: m.mutePhone,
                onChanged: m.setMutePhone,
                title: Text('Mute phone while mirroring', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
                subtitle: Text('Only applies when sound reaches the TV.', style: TextStyle(color: Ui.muted, fontSize: 12)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: m.alternateCapture,
                onChanged: m.running ? null : m.setAlternateCapture,
                title: Text('Alternate capture (for sound)', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
                subtitle: Text(
                  'Uses Android display capture with an audio track when the phone supports it. Some Android versions, apps and DRM-protected video block audio capture. Takes effect the next time you start mirroring.',
                  style: TextStyle(color: Ui.muted, fontSize: 12),
                ),
              ),
            ])),
          decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Android Cast / Smart View', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Use the phone’s own mirroring for Miracast-compatible TVs.', style: TextStyle(color: Ui.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await CastService.openMirrorSettings();
                  if (!ok && context.mounted) decoderToast(context, 'Open Cast or Smart View from Quick Settings.');
                },
                icon: const Icon(Icons.settings_input_antenna),
                label: const Text('Open Android Cast'),
              ),
            ),
          ])),
          decoderPanel(Text(
            'Tip: for channels and movies use "Cast to TV / Kodi" or "Send to receiver page". The TV plays them itself, with sound, and your phone can be locked.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4),
          )),
        ]),
      ),
    );
  }

  Widget _pairing(BuildContext context, DeeprowssMirrorService m) => decoderPanel(Column(children: [
        Text('Connect your TV', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
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
        Text('Scan the code, or open the address below on the TV / laptop browser.',
            textAlign: TextAlign.center, style: TextStyle(color: Ui.muted, fontSize: 12)),
        const SizedBox(height: 10),
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
      ]));
}
