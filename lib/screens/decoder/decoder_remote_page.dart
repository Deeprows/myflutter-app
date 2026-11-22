import 'package:flutter/material.dart';

import '../../services/cast_service.dart';
import '../../services/tv_remote_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';

/// TV remote: manufacturer remote (Roku, LG webOS, Samsung) and playback
/// controls for the TV that is playing.
class DecoderRemotePage extends StatefulWidget {
  const DecoderRemotePage({super.key});

  @override
  State<DecoderRemotePage> createState() => _DecoderRemotePageState();
}

class _DecoderRemotePageState extends State<DecoderRemotePage> {
  final CastService svc = CastService.instance;
  String _host = '';
  String _brand = 'Auto detect';
  String _model = '';

  Future<void> _pair() async {
    final ip = TextEditingController(text: _host);
    String dialogBrand = _brand;
    final choice = await showDialog<({String ip, String brand})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Ui.panel,
          title: const Text('Connect TV remote'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ip,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'TV IP address', hintText: '192.168.1.50'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: dialogBrand,
              decoration: const InputDecoration(labelText: 'TV platform'),
              items: const [
                DropdownMenuItem(value: 'Auto detect', child: Text('Auto detect TV brand')),
                DropdownMenuItem(value: 'Roku', child: Text('Roku')),
                DropdownMenuItem(value: 'LG webOS', child: Text('LG webOS')),
                DropdownMenuItem(value: 'Samsung', child: Text('Samsung Tizen')),
              ],
              onChanged: (v) {
                if (v != null) setDialog(() => dialogBrand = v);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (ip: ip.text.trim(), brand: dialogBrand)),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
    ip.dispose();
    if (choice == null || choice.ip.isEmpty) return;
    var brand = choice.brand;
    var model = '';
    if (brand == 'Auto detect') {
      final info = await TvRemoteService.detect(choice.ip);
      if (info == null) {
        if (mounted) decoderToast(context, 'No supported Roku, LG webOS or Samsung TV found at that IP.');
        return;
      }
      brand = info.brand;
      model = info.model;
    }
    setState(() {
      _host = choice.ip;
      _brand = brand;
      _model = model;
    });
    final ok = await _send('KEY_HOME');
    if (mounted) {
      decoderToast(context, ok ? '$brand remote ready. Approve Deeprowss on the TV if asked.' : 'Pairing did not complete. Check the TV prompt and try again.');
    }
  }

  Future<bool> _send(String key) async {
    if (_host.isEmpty) return false;
    switch (_brand) {
      case 'Roku':
        final k = {
              'KEY_UP': 'Up', 'KEY_DOWN': 'Down', 'KEY_LEFT': 'Left', 'KEY_RIGHT': 'Right',
              'KEY_ENTER': 'Select', 'KEY_HOME': 'Home', 'KEY_BACK': 'Back', 'KEY_VOLUMEUP': 'VolumeUp',
              'KEY_VOLUMEDOWN': 'VolumeDown', 'KEY_MUTE': 'VolumeMute', 'KEY_MENU': 'Info', 'KEY_1': 'Lit_1', 'KEY_2': 'Lit_2',
              'KEY_POWER': 'Power', 'KEY_SOURCE': 'InputTuner',
            }[key] ??
            key;
        return TvRemoteService.roku(_host, k);
      case 'LG webOS':
        final k = {
              'KEY_UP': 'UP', 'KEY_DOWN': 'DOWN', 'KEY_LEFT': 'LEFT', 'KEY_RIGHT': 'RIGHT',
              'KEY_ENTER': 'ENTER', 'KEY_HOME': 'HOME', 'KEY_BACK': 'BACK', 'KEY_VOLUMEUP': 'VOLUMEUP',
              'KEY_VOLUMEDOWN': 'VOLUMEDOWN', 'KEY_MUTE': 'MUTE', 'KEY_MENU': 'MENU', 'KEY_1': '1', 'KEY_2': '2',
              'KEY_POWER': 'POWER', 'KEY_SOURCE': 'INPUT',
            }[key] ??
            key;
        return TvRemoteService.lgWebOs(_host, k);
      case 'Samsung':
        final k = {'KEY_VOLUMEUP': 'KEY_VOLUP', 'KEY_VOLUMEDOWN': 'KEY_VOLDOWN', 'KEY_BACK': 'KEY_RETURN', 'KEY_1': 'KEY_1', 'KEY_2': 'KEY_2'}[key] ?? key;
        return TvRemoteService.samsung(_host, k);
      default:
        return false;
    }
  }

  Widget _key(IconData icon, String label, String key) => Column(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(
          onPressed: () async {
            final ok = await _send(key);
            if (!ok && mounted) decoderToast(context, 'The TV did not accept that button.');
          },
          icon: Icon(icon),
        ),
        Text(label, style: TextStyle(color: Ui.muted, fontSize: 10)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('TV remote', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          if (svc.casting) DecoderNowPlaying(svc: svc),
          decoderPanel(Column(children: [
            Row(children: [
              Expanded(
                child: Text(
                  _host.isEmpty ? 'Manufacturer remote' : '$_brand · $_host${_model.isEmpty ? '' : ' · $_model'}',
                  style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: _pair, child: Text(_host.isEmpty ? 'Set up' : 'Change')),
            ]),
            if (_host.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Works with Roku, LG webOS and Samsung Tizen TVs.', style: TextStyle(color: Ui.muted, fontSize: 12)),
              ),
            if (_host.isNotEmpty) ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [_key(Icons.arrow_upward, 'Up', 'KEY_UP')]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _key(Icons.arrow_back, 'Left', 'KEY_LEFT'),
                _key(Icons.circle_outlined, 'OK', 'KEY_ENTER'),
                _key(Icons.arrow_forward, 'Right', 'KEY_RIGHT'),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [_key(Icons.arrow_downward, 'Down', 'KEY_DOWN')]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _key(Icons.home, 'Home', 'KEY_HOME'),
                _key(Icons.undo, 'Back', 'KEY_BACK'),
                _key(Icons.volume_up, 'Vol +', 'KEY_VOLUMEUP'),
                _key(Icons.volume_down, 'Vol −', 'KEY_VOLUMEDOWN'),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _key(Icons.looks_one, 'Main stream', 'KEY_1'),
                _key(Icons.looks_two, 'Backup stream', 'KEY_2'),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _key(Icons.volume_off, 'Mute', 'KEY_MUTE'),
                _key(Icons.menu, 'Menu', 'KEY_MENU'),
                _key(Icons.power_settings_new, 'Power', 'KEY_POWER'),
                _key(Icons.input, 'Input', 'KEY_SOURCE'),
              ]),
            ],
          ])),
          if (!svc.casting)
            decoderPanel(Text('Playback controls appear here while a TV or Kodi is playing.', style: TextStyle(color: Ui.muted))),
        ]),
      ),
    );
  }
}
