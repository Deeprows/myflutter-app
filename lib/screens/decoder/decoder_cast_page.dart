import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/premium_gate.dart';
import 'decoder_common.dart';

/// Cast to TV / Kodi: find TVs on the Wi-Fi and play on them.
class DecoderCastPage extends StatefulWidget {
  final CastTarget? target;
  const DecoderCastPage({super.key, this.target});

  @override
  State<DecoderCastPage> createState() => _DecoderCastPageState();
}

class _DecoderCastPageState extends State<DecoderCastPage> {
  final CastService svc = CastService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    svc.loadDeviceMemory();
    if (svc.devices.isEmpty && !svc.scanning && !svc.casting) svc.scan();
    if (svc.casting) svc.refreshPosition();
  }

  Future<void> _manualAdd() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Add TV by IP address'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.1.100', labelText: 'TV or laptop IP'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Find')),
        ],
      ),
    );
    c.dispose();
    if (value == null || value.trim().isEmpty) return;
    final d = await svc.addDeviceByIp(value);
    if (!mounted) return;
    if (d == null) {
      decoderToast(context, svc.error ?? 'Could not add this device.');
      return;
    }
    await svc.saveDevice(d);
    if (mounted) decoderToast(context, '${d.name} added');
  }

  Future<void> _cast(CastDevice d, {bool alreadyAllowed = false}) async {
    final t = widget.target;
    if (t == null || !t.canCast) {
      await svc.saveDevice(d);
      if (mounted) decoderToast(context, '${d.name} saved. Pick a channel from Supported channels to play on it.');
      return;
    }
    if (!alreadyAllowed && !await PremiumGate.allowCast(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      if (t.file != null) {
        final File? f = await t.file!();
        if (f != null) ok = await svc.castFile(d, f, title: t.title);
      } else {
        ok = await svc.castUrl(d, t.url!,
            title: t.title, kind: t.kind, referer: t.referer, userAgent: t.userAgent);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (ok) {
      decoderToast(context, 'Playing on ${d.name}');
    } else {
      decoderToast(context, svc.error ?? svc.kodiHint ?? 'Could not start casting.');
      if (svc.kodiNeedsLogin && await decoderKodiLogin(context) && mounted) {
        await _cast(d, alreadyAllowed: true);
      }
    }
  }

  Widget _deviceTile(CastDevice d, bool saved) => decoderPanel(Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(12)),
          child: Icon(d.isKodi ? Icons.laptop_mac_rounded : Icons.tv, color: Colors.white70),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
            Text(d.isKodi ? '${d.host} · Kodi' : d.host, style: TextStyle(color: Ui.muted, fontSize: 11)),
          ]),
        ),
        IconButton(
          onPressed: () => saved ? svc.removeSavedDevice(d) : svc.saveDevice(d),
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: Ui.red),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _cast(d),
          child: Text(widget.target?.canCast == true ? 'Play' : 'Save'),
        ),
      ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Cast to TV / Kodi', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Scan for TVs',
            onPressed: svc.scanning ? null : () => svc.scan(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          final saved = svc.savedDevices;
          final others = saved.where((d) => !svc.devices.any((x) => x.host == d.host));
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (widget.target != null)
              decoderPanel(Row(children: [
                Icon(Icons.play_circle_outline, color: Ui.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.target!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
                ),
              ])),
            if (svc.casting) DecoderNowPlaying(svc: svc),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: svc.scanning ? null : () => svc.scan(),
                  icon: svc.scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar),
                  label: Text(svc.scanning ? 'Scanning…' : 'Scan network'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _manualAdd, icon: const Icon(Icons.add), label: const Text('IP')),
            ]),
            const SizedBox(height: 14),
            if (svc.kodiHint != null)
              decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kodi setup', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(svc.kodiHint!, style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => decoderKodiLogin(context), child: const Text('Kodi login')),
                ),
              ])),
            if (svc.devices.isEmpty && !svc.scanning && others.isEmpty)
              decoderPanel(Text(
                'No TVs found yet. Keep your phone and TV on the same Wi-Fi (some routers isolate devices). For Kodi, turn on Settings → Services → Control → "Allow remote control via HTTP" and "via UPnP".',
                style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4),
              )),
            ...svc.devices.map((d) => _deviceTile(d, saved.any((x) => x.host == d.host))),
            if (others.isNotEmpty) ...[
              decoderHeading('Saved TVs', 'Reconnect to devices you use often.'),
              ...others.map((d) => _deviceTile(d, true)),
            ],
          ]);
        },
      ),
    );
  }
}
