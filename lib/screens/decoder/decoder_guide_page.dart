import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'decoder_common.dart';

/// A visual, step-by-step guide to the Smart Decoder connection options.
class DecoderGuidePage extends StatelessWidget {
  const DecoderGuidePage({super.key});

  Widget _step({
    required int number,
    required IconData icon,
    required String title,
    required String description,
    String? note,
  }) {
    return decoderPanel(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Ui.red.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$number', style: TextStyle(color: Ui.red, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: Ui.red, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 7),
          Text(description, style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(10)),
              child: Text(note, style: TextStyle(color: Ui.text, fontSize: 11, height: 1.45)),
            ),
          ],
        ])),
      ],
    ));
  }

  Widget _section(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Row(children: [
      Icon(icon, color: Ui.red, size: 21),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: Ui.text, fontSize: 17, fontWeight: FontWeight.w900)),
        Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 11)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      backgroundColor: Ui.panel,
      title: const Text('How to use Smart Decoder', style: TextStyle(fontWeight: FontWeight.w900)),
    ),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
      Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Ui.red.withValues(alpha: .22), Ui.card]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Ui.red.withValues(alpha: .45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.connected_tv_rounded, size: 34, color: Ui.red),
          const SizedBox(height: 10),
          Text('Your screen. Your choice.', style: TextStyle(color: Ui.text, fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('Use your phone to send Deeprowss videos and channels to a television, Kodi device or laptop — then control playback from your phone.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _tag(Icons.cast, 'Cast to TV'),
            _tag(Icons.web, 'Receiver page'),
            _tag(Icons.gamepad, 'Phone remote'),
          ]),
        ]),
      ),
      _section('1. Cast to an LG or Samsung TV', 'For supported TVs on your home network', Icons.cast_rounded),
      _step(number: 1, icon: Icons.wifi, title: 'Connect to the same Wi-Fi',
        description: 'Connect your phone and TV to the same home Wi-Fi network. Turn the TV on and make sure it is not on a guest network.'),
      _step(number: 2, icon: Icons.cast_connected, title: 'Find your television',
        description: 'Open Smart Decoder → Cast to TV / Kodi. Tap Scan network and wait for nearby supported devices. If your TV is not found, use IP to enter its local IP address.'),
      _step(number: 3, icon: Icons.play_circle_outline, title: 'Start watching',
        description: 'Choose a supported video or channel, open Smart Decoder and select your TV. When connected, use the Now Playing controls to play, pause, seek where supported or disconnect.',
        note: 'Some TV models and apps do not support every casting format. If discovery or playback is unavailable, use the Receiver page method below.'),
      _section('2. Connect to Kodi', 'Enable Kodi network control first', Icons.live_tv_rounded),
      _step(number: 1, icon: Icons.settings, title: 'Allow control in Kodi',
        description: 'On Kodi, open Settings → Services → Control. Enable “Allow remote control via HTTP” and “Allow remote control from applications on other systems”. If the option is available, enable UPnP control too. Set or note the HTTP port, username and password.'),
      _step(number: 2, icon: Icons.router, title: 'Find Kodi on your network',
        description: 'Keep your phone and Kodi device on the same Wi-Fi. In Smart Decoder, choose Cast to TV / Kodi and scan. If it does not appear, tap IP and enter the Kodi device IP address.'),
      _step(number: 3, icon: Icons.lock_open, title: 'Sign in if asked',
        description: 'Enter the Kodi HTTP username and password in the Kodi login prompt, then retry the connection. The default username is often “kodi” if you have not changed it.'),
      _section('3. Use the Receiver page on a TV or laptop', 'Pair the phone with a browser or Deeprowss Windows app', Icons.qr_code_2_rounded),
      _step(number: 1, icon: Icons.open_in_browser, title: 'Open the receiver screen',
        description: 'On the TV browser or laptop, open https://deeprows.github.io/myflutter-app/receiver/ . You can also use the Deeprowss Windows app and choose Cast from Phone. Keep both devices connected to the internet.'),
      _step(number: 2, icon: Icons.qr_code_scanner, title: 'Scan the QR code',
        description: 'On your phone, open Smart Decoder → Send to receiver page → Scan TV QR code. Point the camera at the QR code displayed on the receiver screen and approve camera access if requested.'),
      _step(number: 3, icon: Icons.devices, title: 'Send a video or channel',
        description: 'After pairing, return to Movies or Live TV in Deeprowss and choose the item you want to watch. Send it to the connected receiver. The receiver page or Windows app will play it.'),
      _step(number: 4, icon: Icons.touch_app, title: 'Control it from your phone',
        description: 'Return to the Receiver page screen in Smart Decoder. Use the on-screen remote for navigation, play/pause, stop, mute, volume and fullscreen where supported. Tap Disconnect when finished.'),
      _section('4. Use Deeprowss as your TV remote', 'Control supported LG webOS, Samsung Tizen and Roku TVs', Icons.gamepad_rounded),
      _step(number: 1, icon: Icons.settings_remote, title: 'Open TV remote',
        description: 'In Smart Decoder, choose TV remote and tap Set up. Enter your TV local IP address, or choose Auto detect, then select the TV platform if you prefer.'),
      _step(number: 2, icon: Icons.phonelink, title: 'Approve the connection',
        description: 'Keep your phone and TV on the same Wi-Fi. If the TV displays a pairing or permission prompt, approve the Deeprowss connection.'),
      _step(number: 3, icon: Icons.gamepad, title: 'Control your TV',
        description: 'Use the directional arrows and OK, Home and Back buttons. Supported controls can include volume, mute, power and input. Available buttons depend on the TV brand and model.'),
      decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_outline_rounded, color: Ui.red),
          const SizedBox(width: 8),
          Text('Quick troubleshooting', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        Text('• Make sure both devices are on the same Wi-Fi network.\n• Turn off VPN or guest Wi-Fi isolation if devices cannot find each other.\n• Check the TV/Kodi IP address and allow local network access.\n• Some embedded streams cannot be cast directly; try the Receiver page or another supported stream.\n• Keep Deeprowss open while using the phone as a remote.',
          style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.6)),
      ]),
      const SizedBox(height: 4),
      Text('Deeprowss · Let’s Go Deep', textAlign: TextAlign.center,
        style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _tag(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: Ui.line)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Ui.red),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: Ui.text, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}
