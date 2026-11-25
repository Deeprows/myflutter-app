import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cast_target.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../services/stream_resolver.dart' show StreamKind;
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_qr_scan_page.dart';

class DecoderReceiverPage extends StatefulWidget {
  final CastTarget? target;
  const DecoderReceiverPage({super.key, this.target});
  @override
  State<DecoderReceiverPage> createState() => _DecoderReceiverPageState();
}

class _DecoderReceiverPageState extends State<DecoderReceiverPage> {
  final m = DeeprowssMirrorService.instance;
  bool _busy = false;

  Future<void> _scanAndConnect() async {
    final pair = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const DecoderQrScanPage()),
    );
    if (!mounted || pair == null) return;
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false, relayRoom: pair['room'], relayToken: pair['token']);
      final target = widget.target;
      if (target != null && (target.url ?? '').trim().isNotEmpty) {
        await m.sendChannel(url: target.url!, title: target.title,
          kind: target.kind == StreamKind.invalid ? StreamKind.embed : target.kind,
          referer: target.referer, userAgent: target.userAgent,
          backupUrl: target.backup?.url, backupKind: target.backup?.kind);
      }
      if (mounted) decoderToast(context, target == null ? 'Paired with receiver. Choose a video or channel to send.' : 'Sending ' + target.title + ' to your receiver.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not connect to receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLegacy() async {
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false);
      if (mounted) decoderToast(context, 'Manual receiver session started.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not start receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _key(String command) {
    HapticFeedback.selectionClick();
    if (!m.sendRemoteKey(command) && mounted) decoderToast(context, 'Receiver is not connected yet.');
  }

  String get _screenLabel {
    if (m.receiverPlayerOpen) {
      return m.nowPlayingTitle.isEmpty ? 'Playing on receiver' : m.nowPlayingTitle;
    }
    final pc = m.receiverIsDesktop;
    switch (m.receiverView) {
      case 'movies':
        return pc ? 'Browsing movies on the PC' : 'Browsing movies on the TV';
      case 'connect':
        return 'Receiver is waiting for a video';
      default:
        return pc ? 'Windows app home screen' : 'TV home screen';
    }
  }

  Widget _remotePanel() {
    final playing = m.receiverPlayerOpen;
    final mirror = m.receiverMode == 'mirror';
    final canPlay = playing && !mirror;
    final pc = m.receiverIsDesktop;
    return decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(playing ? Icons.play_circle_fill : Icons.settings_remote_rounded, color: Ui.red),
        const SizedBox(width: 8),
        Expanded(child: Text(_screenLabel, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 15))),
      ]),
      const SizedBox(height: 14),
      // Navigation pad: moves around the TV screens and acts as seek / volume while a video plays.
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _RemoteButton(icon: Icons.keyboard_arrow_up_rounded, label: 'Up', onTap: () => _key('up'), width: 84),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _RemoteButton(icon: Icons.keyboard_arrow_left_rounded, label: 'Left', onTap: () => _key('left'), width: 84),
          const SizedBox(width: 8),
          _RemoteButton(icon: Icons.radio_button_checked_rounded, label: 'OK', onTap: () => _key('enter'), primary: true, width: 84),
          const SizedBox(width: 8),
          _RemoteButton(icon: Icons.keyboard_arrow_right_rounded, label: 'Right', onTap: () => _key('right'), width: 84),
        ]),
        const SizedBox(height: 8),
        _RemoteButton(icon: Icons.keyboard_arrow_down_rounded, label: 'Down', onTap: () => _key('down'), width: 84),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _RemoteButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => _key('back'))),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(icon: Icons.home_rounded, label: 'Home', onTap: () => _key('home'))),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(
          icon: m.receiverFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: m.receiverFullscreen ? 'Exit full' : 'Full screen',
          onTap: (canPlay || mirror || pc) && !m.receiverIsTv ? () => _key('fullscreen') : null)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _RemoteButton(icon: Icons.replay_10_rounded, label: '−10 sec',
          onTap: canPlay ? () => _key('rewind') : null)),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(
          icon: m.receiverPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: m.receiverPlaying ? 'Pause' : 'Play',
          primary: true,
          onTap: canPlay ? () { HapticFeedback.selectionClick(); m.toggleReceiverPlay(); } : null)),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(icon: Icons.forward_10_rounded, label: '+10 sec',
          onTap: canPlay ? () => _key('forward') : null)),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(icon: Icons.stop_rounded, label: 'Stop',
          onTap: playing ? () => m.stopPlayback() : null)),
      ]),
      const SizedBox(height: 8),
      if (m.receiverHasBackup) ...[
        Row(children: [
          Expanded(child: _RemoteButton(icon: Icons.swap_horiz_rounded, label: 'Switch to backup stream',
            onTap: () { HapticFeedback.selectionClick(); if (!m.switchToBackup()) decoderToast(context, 'Receiver is not connected yet.'); })),
        ]),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Expanded(child: _RemoteButton(
          icon: m.receiverMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: m.receiverMuted ? 'Unmute' : 'Mute',
          onTap: playing ? () { HapticFeedback.selectionClick(); m.toggleReceiverMute(); } : null)),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(icon: Icons.volume_down_rounded, label: 'Vol −',
          onTap: playing ? () => m.nudgeReceiverVolume(-10) : null)),
        const SizedBox(width: 8),
        Expanded(child: _RemoteButton(icon: Icons.volume_up_rounded, label: 'Vol +',
          onTap: playing ? () => m.nudgeReceiverVolume(10) : null)),
      ]),
      Row(children: [
        Icon(m.receiverMuted ? Icons.volume_off_rounded : Icons.volume_down_rounded, color: Ui.muted),
        Expanded(child: Slider(
          value: (m.receiverMuted ? 0 : m.receiverVolume).toDouble().clamp(0.0, 100.0).toDouble(),
          min: 0, max: 100,
          onChanged: playing ? m.setReceiverVolume : null)),
        Text((m.receiverMuted ? 0 : m.receiverVolume).toString() + '%', style: TextStyle(color: Ui.muted, fontSize: 11)),
      ]),
      Text(pc
          ? (playing
              ? 'Windows app: OK / Play taps the player. If an ad eats the first tap, press it again. Full screen fills the PC screen (F11 or Esc leaves it).'
              : 'Windows app: arrows and OK move around the app. Full screen, Back and Home work too.')
        : playing
          ? (m.receiverMode == 'iframe'
              ? (m.receiverIsTv
                  ? 'OK / Play taps the player. If an ad eats the first tap, press it again. Embedded providers may ignore seek and volume.'
                  : 'Embedded providers may ignore some buttons (seek, volume). Back and Home always work.')
              : 'Arrows seek ±10 s and change volume while a video is open. OK toggles play / pause.')
          : 'Use the arrows and OK to browse movies on the TV. Back and Home work like the TV remote.',
        style: TextStyle(color: Ui.muted, fontSize: 11, height: 1.35)),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(backgroundColor: Ui.panel,
      title: const Text('Connect to receiver', style: TextStyle(fontWeight: FontWeight.w900))),
    body: ListenableBuilder(listenable: m, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16), children: [
        decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.connected_tv_rounded, size: 29, color: Ui.red),
            const SizedBox(width: 11),
            Expanded(child: Text(m.running ? m.status : 'No receiver connected',
              style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900))),
            Icon(Icons.circle, size: 10, color: m.connected ? Colors.green : Ui.muted),
          ]),
          const SizedBox(height: 10),
          Text('On your TV or laptop, open the Deeprowss Receiver page, or open the Deeprowss Cinema Windows app and choose Cast from Phone. Scan the QR code shown there with your phone to connect.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy || m.running ? null : _scanAndConnect,
            icon: _busy ? const SizedBox(width: 17,height: 17,child:CircularProgressIndicator(strokeWidth:2))
              : const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_busy ? 'Connecting…' : 'Scan TV QR code'))),
          if (!m.running) ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _busy ? null : _startLegacy,
              icon: const Icon(Icons.pin_outlined), label: const Text('Use legacy PIN connection'))),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () async { await m.stop(); },
              icon: const Icon(Icons.stop_circle_outlined), label: const Text('Disconnect receiver'))),
          ],
          if (m.error != null) Padding(padding: const EdgeInsets.only(top:10),
            child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize:12))),
        ])),
        if (m.running) _remotePanel(),
        decoderPanel(Text('The QR code pairs your phone with the TV. Video and audio travel directly between devices using WebRTC; the pairing service only relays connection messages.',
          style:TextStyle(color:Ui.muted,fontSize:12,height:1.5))),
      ])),
  );
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double? width;
  const _RemoteButton({required this.icon, required this.label, required this.onTap, this.primary = false, this.width});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : .38,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: primary ? Ui.red.withValues(alpha: .18) : Ui.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: primary ? Ui.red : Ui.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: primary ? Ui.red : Ui.text, size: 24),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(color: Ui.muted, fontSize: 10))),
          ]),
        ),
      ),
    );
  }
}
