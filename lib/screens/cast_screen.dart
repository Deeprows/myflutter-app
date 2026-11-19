import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/cast_target.dart';
import '../services/cast_service.dart';
import '../services/google_cast_service.dart';
import '../services/tv_remote_service.dart';
import '../services/webrtc_mirror_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'plans_screen.dart';
import 'tv_screen.dart';

/// Full-screen decoder dashboard. DLNA playback controls are available on
/// compatible renderers; vendor-specific TV navigation is intentionally not
/// presented as universal because it requires each manufacturer's API.
class CastScreen extends StatefulWidget {
  final CastTarget? target;
  final VoidCallback? onCastStarted;
  const CastScreen({super.key, this.target, this.onCastStarted});

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> with SingleTickerProviderStateMixin {
  final CastService svc = CastService.instance;
  final DeeprowssMirrorService mirrorSvc = DeeprowssMirrorService.instance;
  late final TabController _tabs = TabController(length: 5, vsync: this);
  bool _busy = false;
  String _remoteHost = '';
  String _remoteBrand = 'Auto detect';
  String _remoteModel = '';

  @override
  void initState() {
    super.initState();
    svc.loadDeviceMemory();
    if (svc.devices.isEmpty && !svc.scanning && !svc.casting) svc.scan();
    if (svc.casting) svc.refreshPosition();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan() async => svc.scan();

  Future<void> _manualAdd() async {
    final c = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      title: const Text('Add TV by IP address'),
      content: TextField(
        controller: c,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: '192.168.1.100', labelText: 'TV IP / device URL'),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Find TV'))],
    ));
    c.dispose();
    if (value == null || value.trim().isEmpty) return;
    final d = await svc.addDeviceByIp(value);
    if (d == null) { _toast(svc.error ?? 'Could not add this TV.'); return; }
    await svc.saveDevice(d);
    _toast('${d.name} added');
  }

  Future<void> _cast(CastDevice d) async {
    final t = widget.target;
    if (t == null || !t.canCast) {
      _toast('Open a supported video or channel first, then tap Cast.');
      return;
    }
    setState(() => _busy = true);
    bool ok = false;
    try {
      if (t.file != null) {
        final File? f = await t.file!();
        if (f != null) ok = await svc.castFile(d, f, title: t.title);
      } else {
        ok = await svc.castUrl(d, t.url!, title: t.title, kind: t.kind,
          referer: t.referer, userAgent: t.userAgent);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (ok) {
      widget.onCastStarted?.call();
      _tabs.animateTo(0);
      _toast('Playing on ${d.name}');
    } else {
      _toast(svc.error ?? 'Could not start casting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Deeprowss Decoder', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('Cast • Mirror • Remote', style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
        actions: [IconButton(tooltip: 'Scan for TVs', onPressed: svc.scanning ? null : _scan,
          icon: const Icon(Icons.refresh_rounded))],
        bottom: TabBar(
          controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: Ui.red, labelColor: Ui.text, unselectedLabelColor: Ui.muted,
          tabs: const [Tab(icon: Icon(Icons.home_rounded), text: 'Home'),
            Tab(icon: Icon(Icons.tv_rounded), text: 'Devices'),
            Tab(icon: Icon(Icons.gamepad_rounded), text: 'Remote'),
            Tab(icon: Icon(Icons.screen_share_rounded), text: 'Mirror'),
            Tab(icon: Icon(Icons.workspace_premium_rounded), text: 'Plan')],
        ),
      ),
      body: ListenableBuilder(listenable: Listenable.merge([svc, SubscriptionService.instance]), builder: (context, _) => TabBarView(
        controller: _tabs,
        children: [_home(), _devices(), _remote(), _mirror(), _subscription()],
      )),
    );
  }

  Widget _page(List<Widget> children) => ListView(padding: const EdgeInsets.all(16), children: children);
  Widget _panel(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)),
    child: child,
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: Ui.text, fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 12)),
    ]));

  Widget _home() => _page([
    _heading('Your decoder', 'Connect once. Control your TV from your phone.'),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(svc.casting ? Icons.cast_connected : Icons.cast, color: Ui.red, size: 28), const SizedBox(width: 10),
        Expanded(child: Text(svc.casting ? 'Connected to ${svc.device?.name ?? 'TV'}' : 'No TV connected', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 16))) ,
        if (svc.casting) const Chip(label: Text('LIVE'))]),
      const SizedBox(height: 8), Text(svc.casting ? svc.castTitle : 'Scan your Wi-Fi network to find a compatible Smart TV.', style: TextStyle(color: Ui.muted)),
      const SizedBox(height: 14),
      if (svc.casting) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton.filledTonal(onPressed: svc.play, icon: const Icon(Icons.play_arrow)),
          IconButton.filledTonal(onPressed: svc.pause, icon: const Icon(Icons.pause)),
          IconButton.filledTonal(onPressed: svc.stop, icon: const Icon(Icons.stop)),
        ]),
        if (svc.duration > Duration.zero) _seekControl(),
        if (svc.tvVolumeSupported) _volumeControl(),
        _sleepControl(),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: svc.stop, icon: const Icon(Icons.cast), label: const Text('Disconnect'))),
      ] else Row(children: [Expanded(child: FilledButton.icon(onPressed: svc.scanning ? null : _scan,
        icon: svc.scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
        label: Text(svc.scanning ? 'Scanning…' : 'Scan for TVs'))), const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: _manualAdd, icon: const Icon(Icons.add_link), tooltip: 'Add by IP')]),
    ])),
    if (widget.target != null) _panel(Row(children: [const Icon(Icons.play_circle_outline), const SizedBox(width: 10), Expanded(child: Text('Ready to cast: ${widget.target!.title}', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700))),
      TextButton(onPressed: () => _tabs.animateTo(1), child: const Text('Choose TV'))])),
    _panel(ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.live_tv_rounded, color: Ui.red),
      title: Text('Browse live channels', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
      subtitle: Text('Choose a channel, then cast it to your TV.', style: TextStyle(color: Ui.muted)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TvScreen())))),
    _heading('Recently cast', 'Your recent decoder sessions'),
    if (svc.recentSessions.isEmpty) _panel(Text('Your recent sessions will appear here.', style: TextStyle(color: Ui.muted)))
    else ...svc.recentSessions.take(6).map((r) => _panel(ListTile(contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history), title: Text(r['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(r['device'] ?? ''), dense: true))),
  ]);

  Widget _devices() => _page([
    _heading('TV devices', 'Find compatible TVs on the same Wi-Fi network.'),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.cast_connected, color: Ui.red), const SizedBox(width: 10), Expanded(child: Text('Google Cast / Chromecast', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 6), Text('Use Google’s native Cast discovery and receiver session, separately from DLNA devices.', style: TextStyle(color: Ui.muted, fontSize: 12)),
      const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () async {
        try { await GoogleCastService.showPicker(); } catch (_) { _toast('Google Cast is not available on this device.'); }
      }, icon: const Icon(Icons.cast), label: const Text('Find Chromecast / Google TV'))),
      if (widget.target?.url != null) TextButton.icon(onPressed: () async {
        final t = widget.target!;
        final kind = t.kind;
        final mime = kind == null ? 'video/mp4' : kind.name == 'hls' ? 'application/x-mpegURL' : kind.name == 'dash' ? 'application/dash+xml' : 'video/mp4';
        final ok = await GoogleCastService.load(url: t.url!, title: t.title, contentType: mime, live: kind?.name == 'hls');
        if (ok) { widget.onCastStarted?.call(); _toast('Sent to Google Cast receiver.'); }
        else _toast('Choose a Google Cast device first, then try again.');
      }, icon: const Icon(Icons.play_arrow), label: const Text('Send current video to selected Cast device')),
    ])),
    Row(children: [Expanded(child: FilledButton.icon(onPressed: svc.scanning ? null : _scan,
      icon: const Icon(Icons.radar), label: Text(svc.scanning ? 'Scanning…' : 'Scan network'))),
      const SizedBox(width: 8), OutlinedButton.icon(onPressed: _manualAdd, icon: const Icon(Icons.add), label: const Text('IP'))]),
    if (svc.error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(svc.error!, style: TextStyle(color: Ui.red))),
    const SizedBox(height: 12),
    if (svc.devices.isEmpty && !svc.scanning) _panel(Text('No discovered TVs yet. Ensure your phone and TV are on the same Wi-Fi. Some routers isolate wireless devices.', style: TextStyle(color: Ui.muted))),
    ...svc.devices.map((d) => _deviceTile(d, saved: svc.savedDevices.any((x) => x.host == d.host))),
    if (svc.savedDevices.isNotEmpty) ...[_heading('Saved TVs', 'Reconnect to devices you use often.'),
      ...svc.savedDevices.where((d) => !svc.devices.any((x) => x.host == d.host)).map((d) => _deviceTile(d, saved: true))],
    _panel(Text('DLNA / UPnP devices appear below. Chromecast and Google TV use the native Google Cast picker above. TV-specific remote functions depend on the model and pairing permissions.', style: TextStyle(color: Ui.muted, fontSize: 12))),
  ]);

  Widget _deviceTile(CastDevice d, {required bool saved}) => _panel(Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.tv, color: Colors.white70)),
    const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d.name, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)), Text(d.host, style: TextStyle(color: Ui.muted, fontSize: 11))])),
    IconButton(onPressed: () => saved ? svc.removeSavedDevice(d) : svc.saveDevice(d), icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: Ui.red)),
    FilledButton(onPressed: _busy ? null : () => _cast(d), child: const Text('Connect')),
  ]));

  Future<void> _pairVendorRemote() async {
    final ip = TextEditingController(text: _remoteHost);
    String dialogBrand = _remoteBrand;
    final choice = await showDialog<({String ip, String brand})>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      backgroundColor: Ui.panel,
      title: const Text('Connect TV remote'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ip, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'TV IP address', hintText: '192.168.1.50')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: dialogBrand, decoration: const InputDecoration(labelText: 'TV platform'),
          items: const [DropdownMenuItem(value: 'Auto detect', child: Text('Auto detect TV brand')), DropdownMenuItem(value: 'Roku', child: Text('Roku')), DropdownMenuItem(value: 'LG webOS', child: Text('LG webOS')), DropdownMenuItem(value: 'Samsung', child: Text('Samsung Tizen'))],
          onChanged: (v) { if (v != null) setDialog(() => dialogBrand = v); }),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, (ip: ip.text.trim(), brand: dialogBrand)), child: const Text('Connect'))],
    )));
    ip.dispose();
    if (choice == null || choice.ip.isEmpty) return;
    var brand = choice.brand;
    var model = '';
    if (brand == 'Auto detect') {
      final info = await TvRemoteService.detect(choice.ip);
      if (info == null) {
        _toast('Could not identify a supported Roku, LG webOS or Samsung TV at that IP.');
        return;
      }
      brand = info.brand;
      model = info.model;
    }
    setState(() { _remoteHost = choice.ip; _remoteBrand = brand; _remoteModel = model; });
    final ok = await _sendVendorKey('KEY_HOME');
    _toast(ok ? '$brand remote command sent. Approve Deeprowss on the TV if prompted.' : '$brand was detected, but pairing or command delivery did not complete. Check the TV prompt and try again.');
  }

  Future<bool> _sendVendorKey(String key) async {
    if (_remoteHost.isEmpty) return false;
    switch (_remoteBrand) {
      case 'Roku':
        final rokuKey = {'KEY_UP':'Up','KEY_DOWN':'Down','KEY_LEFT':'Left','KEY_RIGHT':'Right','KEY_ENTER':'Select','KEY_HOME':'Home','KEY_BACK':'Back','KEY_VOLUMEUP':'VolumeUp','KEY_VOLUMEDOWN':'VolumeDown','KEY_MUTE':'VolumeMute','KEY_MENU':'Info','KEY_POWER':'Power','KEY_SOURCE':'InputTuner'}[key] ?? key;
        return TvRemoteService.roku(_remoteHost, rokuKey);
      case 'LG webOS':
        final lgKey = {'KEY_UP':'UP','KEY_DOWN':'DOWN','KEY_LEFT':'LEFT','KEY_RIGHT':'RIGHT','KEY_ENTER':'ENTER','KEY_HOME':'HOME','KEY_BACK':'BACK','KEY_VOLUMEUP':'VOLUMEUP','KEY_VOLUMEDOWN':'VOLUMEDOWN','KEY_MUTE':'MUTE','KEY_MENU':'MENU','KEY_POWER':'POWER','KEY_SOURCE':'INPUT'}[key] ?? key;
        return TvRemoteService.lgWebOs(_remoteHost, lgKey);
      case 'Samsung':
        final samsungKey = {'KEY_VOLUMEUP':'KEY_VOLUP','KEY_VOLUMEDOWN':'KEY_VOLDOWN','KEY_BACK':'KEY_RETURN'}[key] ?? key;
        return TvRemoteService.samsung(_remoteHost, samsungKey);
      default: return false;
    }
  }

  Widget _vendorRemotePanel() => _panel(Column(children: [
    Row(children: [Expanded(child: Text(_remoteHost.isEmpty ? 'Manufacturer remote' : '$_remoteBrand · $_remoteHost${_remoteModel.isEmpty ? '' : ' · $_remoteModel'}', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800))), TextButton(onPressed: _pairVendorRemote, child: Text(_remoteHost.isEmpty ? 'Set up' : 'Change'))]),
    if (_remoteHost.isNotEmpty) ...[
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_remoteKey(Icons.arrow_upward, 'Up', 'KEY_UP')]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_remoteKey(Icons.arrow_back, 'Left', 'KEY_LEFT'), _remoteKey(Icons.circle_outlined, 'OK', 'KEY_ENTER'), _remoteKey(Icons.arrow_forward, 'Right', 'KEY_RIGHT')]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_remoteKey(Icons.arrow_downward, 'Down', 'KEY_DOWN')]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_remoteKey(Icons.home, 'Home', 'KEY_HOME'), _remoteKey(Icons.undo, 'Back', 'KEY_BACK'), _remoteKey(Icons.volume_up, 'Vol +', 'KEY_VOLUMEUP'), _remoteKey(Icons.volume_down, 'Vol −', 'KEY_VOLUMEDOWN')]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_remoteKey(Icons.volume_off, 'Mute', 'KEY_MUTE'), _remoteKey(Icons.menu, 'Menu', 'KEY_MENU'), _remoteKey(Icons.power_settings_new, 'Power', 'KEY_POWER'), _remoteKey(Icons.input, 'Input', 'KEY_SOURCE')]),
    ],
  ]));

  Widget _remoteKey(IconData icon, String label, String key) => Column(mainAxisSize: MainAxisSize.min, children: [
    IconButton.filledTonal(onPressed: () async { final ok = await _sendVendorKey(key); if (!ok) _toast('TV did not accept this remote command.'); }, icon: Icon(icon)),
    Text(label, style: TextStyle(color: Ui.muted, fontSize: 10)),
  ]);

  Widget _remote() => _page([
    _heading('TV remote', 'Control media playback and supported TV navigation.'),
    _vendorRemotePanel(),
    _panel(Row(children: [Expanded(child: Text('Google Cast remote', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800))), IconButton(onPressed: GoogleCastService.play, icon: const Icon(Icons.play_arrow)), IconButton(onPressed: GoogleCastService.pause, icon: const Icon(Icons.pause)), IconButton(onPressed: GoogleCastService.stop, icon: const Icon(Icons.stop))])),
    if (!svc.casting) _panel(Text('DLNA playback controls appear after connecting to a DLNA TV. Google Cast controls work for an active Google Cast session.', style: TextStyle(color: Ui.muted)))
    else ...[
      _panel(Column(children: [Text(svc.device?.name ?? 'Connected TV', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 8), Text(svc.castTitle, style: TextStyle(color: Ui.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _remoteButton(Icons.replay_10, 'Back 10s', () => svc.seekTo(svc.position - const Duration(seconds: 10))),
          _remoteButton(svc.tvPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, svc.tvPlaying ? 'Pause' : 'Play', svc.togglePlay, large: true),
          _remoteButton(Icons.forward_10, 'Forward 10s', () => svc.seekTo(svc.position + const Duration(seconds: 10))),
        ]), if (svc.duration > Duration.zero) _seekControl(), if (svc.tvVolumeSupported) _volumeControl(), _sleepControl(),
        FilledButton.tonalIcon(onPressed: svc.stop, icon: const Icon(Icons.stop), label: const Text('Stop casting')),
      ])),
      _panel(Text('Roku ECP, LG webOS and Samsung Tizen remotes support automatic endpoint detection, saved pairing keys/tokens where supplied by the TV, and navigation, playback, volume and additional keys where the model exposes them. Some TVs require an on-screen approval prompt. A command can still be rejected by firmware or parental/network settings.', style: TextStyle(color: Ui.muted, fontSize: 12))),
    ],
  ]);

  Widget _remoteButton(IconData icon, String label, VoidCallback action, {bool large = false}) => Column(children: [
    IconButton.filledTonal(onPressed: action, icon: Icon(icon, size: large ? 38 : 27), iconSize: large ? 68 : 54),
    Text(label, style: TextStyle(color: Ui.muted, fontSize: 11)),
  ]);

  Widget _seekControl() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Slider(value: svc.position.inSeconds.clamp(0, svc.duration.inSeconds).toDouble(), min: 0, max: svc.duration.inSeconds.toDouble(), onChanged: (v) => svc.seekTo(Duration(seconds: v.round()))),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_clock(svc.position), style: TextStyle(color: Ui.muted, fontSize: 11)), Text(_clock(svc.duration), style: TextStyle(color: Ui.muted, fontSize: 11))]),
  ]);
  String _clock(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Widget _volumeControl() => Row(children: [const Icon(Icons.volume_down), Expanded(child: Slider(value: svc.tvVolume.clamp(0, 100).toDouble(), min: 0, max: 100, onChanged: (v) => svc.setTvVolume(v.round()))),
    IconButton(onPressed: () => svc.setTvVolume(0), icon: const Icon(Icons.volume_off))]);

  Widget _sleepControl() => Row(children: [const Icon(Icons.bedtime_outlined), const SizedBox(width: 8), Expanded(child: Text(svc.sleepEndsAt == null ? 'Sleep timer off' : 'Stops at ${TimeOfDay.fromDateTime(svc.sleepEndsAt!).format(context)}', style: TextStyle(color: Ui.muted))),
    PopupMenuButton<int>(tooltip: 'Sleep timer', onSelected: (v) => svc.setSleepTimer(v == 0 ? null : Duration(minutes: v)), itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('Off')), PopupMenuItem(value: 15, child: Text('15 minutes')), PopupMenuItem(value: 30, child: Text('30 minutes')), PopupMenuItem(value: 60, child: Text('1 hour')), PopupMenuItem(value: 120, child: Text('2 hours'))], child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.timer_outlined)))]);

  Widget _mirror() => ListenableBuilder(
    listenable: mirrorSvc,
    builder: (context, _) => _page([
      _heading('Screen mirroring', 'Stream your entire Android display to a TV over your local Wi-Fi.'),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.screen_share_rounded, size: 32, color: Ui.red),
          const SizedBox(width: 12),
          Expanded(child: Text(mirrorSvc.status, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800))),
          if (mirrorSvc.connected) const Icon(Icons.circle, color: Colors.green, size: 10),
        ]),
        const SizedBox(height: 10),
        Text('Deeprowss captures the Android screen with the system permission dialog and sends the video directly to a receiver on the same Wi-Fi network using WebRTC. The secure receiver page is hosted on GitHub Pages, while the actual screen video travels directly over your local network.', style: TextStyle(color: Ui.muted, fontSize: 12)),
        const SizedBox(height: 16),
        if (!mirrorSvc.running) SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: () async {
            try {
              await mirrorSvc.start();
              if (mounted) _toast('Screen capture started. Connect your TV using the address and code below.');
            } catch (e) {
              if (mounted) _toast(mirrorSvc.error ?? 'Could not start screen mirroring: $e');
            }
          },
          icon: const Icon(Icons.cast_connected),
          label: const Text('Start Deeprowss screen mirroring'),
        )) else SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
          onPressed: () async { await mirrorSvc.stop(); if (mounted) _toast('Screen mirroring stopped.'); },
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop mirroring'),
        )),
        if (mirrorSvc.error != null) ...[
          const SizedBox(height: 10),
          Text(mirrorSvc.error!, style: TextStyle(color: Ui.red, fontSize: 12)),
        ],
      ])),
      if (mirrorSvc.running && mirrorSvc.pairingUrl != null) _panel(Column(children: [
        Text('Connect your TV', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 12),
        Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(
          data: mirrorSvc.pairingUrl!, size: 190, backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        )),
        const SizedBox(height: 12),
        Text('1. Open the Deeprowss TV Receiver app or a compatible TV browser.\n2. Open the secure receiver page below (or scan the QR code).\n3. Enter the phone address and six-digit code if they are not filled automatically.', textAlign: TextAlign.center, style: TextStyle(color: Ui.muted, height: 1.5, fontSize: 12)),
        const SizedBox(height: 14),
        SelectableText(mirrorSvc.pairingUrl!, textAlign: TextAlign.center, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 10),
        Text('Phone address', style: TextStyle(color: Ui.muted, fontSize: 11)),
        SelectableText(mirrorSvc.url!, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('PAIRING CODE', style: TextStyle(color: Ui.muted, fontSize: 11, letterSpacing: 1.4)),
          const SizedBox(width: 12),
          SelectableText(mirrorSvc.pin!, style: TextStyle(color: Ui.red, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 5)),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: '${mirrorSvc.pairingUrl}\nPhone: ${mirrorSvc.url}\nCode: ${mirrorSvc.pin}'));
          if (mounted) _toast('Receiver address and code copied.');
        }, icon: const Icon(Icons.copy), label: const Text('Copy receiver details')),
      ])),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Other TV connection options', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('• Google Cast: use the Chromecast / Google TV picker in Devices.\n• DLNA: send supported video streams directly to compatible TVs.\n• Android Cast / Smart View: use the phone’s system mirroring picker for Miracast-compatible TVs.', style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () async {
          final ok = await CastService.openMirrorSettings();
          if (!ok) _toast('Open Cast or Smart View from Android Quick Settings.');
        }, icon: const Icon(Icons.settings_input_antenna), label: const Text('Open Android Cast / Smart View'))),
      ])),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('AirPlay compatibility', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Android has no general-purpose Apple AirPlay sender SDK. Deeprowss uses Google Cast, DLNA or Android’s system mirroring when the TV supports them. Apple TV / AirPlay-only devices need a separately licensed and compatible sender implementation; Deeprowss does not claim native AirPlay support.', style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
      ])),
      _panel(Text('Mirroring requires the phone and TV to be on the same local network. Android displays a screen-capture consent prompt and a persistent sharing notification. Some apps protect their video with DRM and may show a black screen. Locking the phone, stopping the system projection, or battery-management restrictions can end mirroring.', style: TextStyle(color: Ui.muted, fontSize: 12))),
    ]),
  );

  Widget _subscription() {
    final sub = SubscriptionService.instance;
    return _page([
      _heading('Decoder membership', 'Manage your existing Deeprowss subscription.'),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.workspace_premium, size: 32), const SizedBox(width: 10), Expanded(child: Text(sub.isPremium ? 'Premium active' : 'Free account', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 18)))]),
        const SizedBox(height: 8), Text(sub.isPremium ? 'Your existing premium access is recognised by Deeprowss.' : 'Explore available plans and manage your Deeprowss membership.', style: TextStyle(color: Ui.muted)),
        const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlansScreen())), icon: const Icon(Icons.manage_accounts), label: const Text('Manage subscription'))),
      ])),
      _panel(Text('Casting availability and TV compatibility depend on the device and stream format. This page uses the app’s existing subscription account; it does not create a separate decoder payment system.', style: TextStyle(color: Ui.muted, fontSize: 12))),
    ]);
  }
}
