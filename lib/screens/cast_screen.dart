import 'package:flutter/material.dart';

import '../services/cast_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cast_button.dart';
import 'plans_screen.dart';

/// Dedicated decoder-style hub for TV discovery, casting, mirroring and remote control.
class CastScreen extends StatefulWidget {
  final CastTarget? target;
  final VoidCallback? onCastStarted;
  const CastScreen({super.key, this.target, this.onCastStarted});

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  final CastService svc = CastService.instance;
  final TextEditingController _ip = TextEditingController();
  bool _openingMirror = false;

  @override
  void initState() {
    super.initState();
    svc.loadSavedDevices();
    if (svc.devices.isEmpty && !svc.scanning) svc.scan();
    if (svc.casting) svc.refreshTvVolume();
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _cast(CastDevice d) async {
    final t = widget.target;
    if (t == null || !t.canCast) {
      _snack('Open a channel or video first, then choose Cast to send it to your TV.');
      return;
    }
    bool ok;
    if (t.file != null) {
      final f = await t.file!();
      if (f == null) return;
      ok = await svc.castFile(d, f, title: t.title);
    } else {
      ok = await svc.castUrl(d, t.url!, title: t.title, kind: t.kind,
          referer: t.referer, userAgent: t.userAgent);
    }
    if (ok) {
      widget.onCastStarted?.call();
      if (mounted) _snack('Playing on ${d.name}');
    } else if (mounted) {
      _snack(svc.error ?? 'Could not connect to this TV.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _clock(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final sub = SubscriptionService.instance;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: const Text('Cast & TV Remote', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Scan for TVs', onPressed: svc.scanning ? null : () => svc.scan(), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _hero(),
            const SizedBox(height: 16),
            if (svc.casting) _remote() else _setupCard(),
            const SizedBox(height: 16),
            _sectionTitle('YOUR DEVICES', trailing: svc.scanning ? 'SCANNING…' : '${svc.devices.length} FOUND'),
            const SizedBox(height: 9),
            if (svc.scanning && svc.devices.isEmpty)
              const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator()))
            else if (svc.devices.isEmpty)
              _emptyDevices()
            else
              ...svc.devices.map(_deviceTile),
            if (svc.recentDevices.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionTitle('RECENT CONNECTIONS'),
              const SizedBox(height: 7),
              ...svc.recentDevices.take(3).map((item) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Row(children: [const Icon(Icons.history_rounded, size: 16, color: Colors.white38), const SizedBox(width: 8), Expanded(child: Text(item.split('|').first, style: const TextStyle(color: Colors.white60, fontSize: 12))), Text(item.split('|').last, style: const TextStyle(color: Colors.white38, fontSize: 11))]))),
            ],
            const SizedBox(height: 16),
            _manualIp(),
            const SizedBox(height: 16),
            _mirrorCard(),
            const SizedBox(height: 16),
            _subscriptionCard(sub),
            if (svc.error != null) ...[
              const SizedBox(height: 12),
              Text(svc.error!, style: const TextStyle(color: Colors.orangeAccent)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF28202A), Color(0xFF111820), Color(0xFF101318)]),
      border: Border.all(color: Colors.white.withOpacity(.08)),
    ),
    child: Row(children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: Ui.red.withOpacity(.16), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.cast_connected_rounded, color: Ui.red, size: 30)),
      const SizedBox(width: 14),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your personal TV decoder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        SizedBox(height: 5), Text('Connect, control and manage your big-screen experience.', style: TextStyle(color: Colors.white70, height: 1.35)),
      ])),
    ]),
  );

  Widget _sectionTitle(String title, {String? trailing}) => Row(children: [
    Text(title, style: const TextStyle(fontSize: 11, letterSpacing: 1.3, color: Colors.white60, fontWeight: FontWeight.w800)),
    const Spacer(), if (trailing != null) Text(trailing, style: TextStyle(fontSize: 10, color: svc.scanning ? Ui.red : Colors.white54, fontWeight: FontWeight.w800)),
  ]);

  Widget _setupCard() => _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Ready to connect?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), const Text('Connect your phone and TV to the same Wi-Fi, then scan to find compatible Smart TVs and media players.', style: TextStyle(color: Colors.white60, height: 1.4)),
    const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: svc.scanning ? null : () => svc.scan(), icon: const Icon(Icons.radar_rounded), label: Text(svc.scanning ? 'Scanning for TVs…' : 'Scan for TVs'))),
  ]));

  Widget _deviceTile(CastDevice d) {
    final active = svc.device?.host == d.host && svc.casting;
    return Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(15), border: Border.all(color: active ? Ui.red.withOpacity(.6) : Colors.white.withOpacity(.06))), child: ListTile(
      leading: CircleAvatar(backgroundColor: Ui.red.withOpacity(.13), child: Icon(Icons.tv_rounded, color: Ui.red)),
      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(d.host, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: svc.isSaved(d) ? 'Remove saved TV' : 'Save TV', onPressed: () => svc.toggleSaved(d), icon: Icon(svc.isSaved(d) ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber)),
        if (active) const Icon(Icons.check_circle_rounded, color: Colors.greenAccent) else IconButton(onPressed: svc.connecting ? null : () => _cast(d), icon: Icon(Icons.cast_rounded, color: Ui.red)),
      ]),
      onTap: active ? null : () => _cast(d),
    ));
  }

  Widget _emptyDevices() => _panel(child: Column(children: [
    const Icon(Icons.tv_off_rounded, size: 34, color: Colors.white38),
    const SizedBox(height: 8), const Text('No TVs found yet', style: TextStyle(fontWeight: FontWeight.w700)),
    const SizedBox(height: 4), const Text('Check the Wi-Fi connection or add a TV by IP address.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
  ]));

  Widget _manualIp() => _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('ADD TV MANUALLY', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1)),
    const SizedBox(height: 10),
    Row(children: [Expanded(child: TextField(controller: _ip, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'TV IP address (e.g. 192.168.1.20)', isDense: true))), const SizedBox(width: 8), IconButton.filled(onPressed: () async { final d = await svc.addManualDevice(_ip.text); if (d != null) { _ip.clear(); _snack('${d.name} added'); } }, icon: const Icon(Icons.add_rounded))]),
  ]));

  Widget _remote() => _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Icon(Icons.cast_connected_rounded, color: Colors.greenAccent), const SizedBox(width: 8), Expanded(child: Text('Connected to ${svc.device?.name ?? 'TV'}', style: const TextStyle(fontWeight: FontWeight.w800))), TextButton(onPressed: svc.stop, child: const Text('DISCONNECT', style: TextStyle(color: Colors.redAccent, fontSize: 10)))]),
    const Divider(color: Colors.white12),
    Text(svc.castTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
    const SizedBox(height: 15),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: () => svc.seekBy(const Duration(seconds: -10)), icon: const Icon(Icons.replay_10_rounded), iconSize: 30),
      const SizedBox(width: 15), IconButton.filled(onPressed: svc.togglePlay, icon: Icon(svc.tvPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), iconSize: 32),
      const SizedBox(width: 15), IconButton(onPressed: () => svc.seekBy(const Duration(seconds: 10)), icon: const Icon(Icons.forward_10_rounded), iconSize: 30),
    ]),
    if (svc.duration > Duration.zero) ...[
      Slider(value: svc.position.inSeconds.clamp(0, svc.duration.inSeconds).toDouble(), max: svc.duration.inSeconds.toDouble().clamp(1, double.infinity).toDouble(), onChanged: (v) => svc.seekTo(Duration(seconds: v.round()))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_clock(svc.position), style: const TextStyle(color: Colors.white54, fontSize: 11)), Text(_clock(svc.duration), style: const TextStyle(color: Colors.white54, fontSize: 11))]),
    ],
    const SizedBox(height: 8),
    Row(children: [IconButton(onPressed: () => svc.setMuted(!svc.tvMuted), icon: Icon(svc.tvMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded)), const Text('TV volume', style: TextStyle(color: Colors.white70)), const Spacer(), if (svc.tvVolumeSupported) SizedBox(width: 145, child: Slider(value: (svc.tvVolume < 0 ? 0 : svc.tvVolume).toDouble(), min: 0, max: 100, onChanged: (v) => svc.setTvVolume(v.round()))) else const Text('Not supported', style: TextStyle(color: Colors.white38, fontSize: 11))]),
    const SizedBox(height: 6),
    Row(children: [const Icon(Icons.timer_outlined, size: 18, color: Colors.white60), const SizedBox(width: 8), const Text('Sleep timer', style: TextStyle(color: Colors.white70)), const Spacer(), DropdownButton<int?>(value: svc.sleepMinutes, dropdownColor: Ui.panel, hint: const Text('Off'), items: const [DropdownMenuItem(value: 15, child: Text('15 min')), DropdownMenuItem(value: 30, child: Text('30 min')), DropdownMenuItem(value: 60, child: Text('1 hour')), DropdownMenuItem(value: 120, child: Text('2 hours')), DropdownMenuItem<int?>(value: null, child: Text('Off'))], onChanged: (v) => svc.setSleepTimer(v == null ? null : Duration(minutes: v))) ]),
  ]));

  Widget _mirrorCard() => _panel(child: Row(children: [const Icon(Icons.screen_share_rounded, color: Colors.white70, size: 25), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mirror your phone screen', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('Open Android Cast / Smart View for full-screen mirroring.', style: TextStyle(color: Colors.white54, fontSize: 12))])), TextButton(onPressed: _openingMirror ? null : () async { setState(() => _openingMirror = true); final ok = await CastService.openMirrorSettings(); if (mounted) { setState(() => _openingMirror = false); if (!ok) _snack('Screen mirroring settings are unavailable on this device.'); } }, child: Text(_openingMirror ? 'OPENING' : 'OPEN'))]));

  Widget _subscriptionCard(SubscriptionService sub) => _panel(child: Row(children: [Icon(Icons.workspace_premium_rounded, color: sub.isPremium ? Colors.amber : Colors.white60, size: 27), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(sub.isPremium ? 'Premium active' : 'Manage subscription', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(sub.isPremium ? 'Your existing subscription is active.' : 'View plans, renew or manage your existing plan.', style: const TextStyle(color: Colors.white54, fontSize: 12))])), TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlansScreen())), child: const Text('MANAGE'))]));

  Widget _panel({required Widget child}) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white.withOpacity(.06))), child: child);
}
