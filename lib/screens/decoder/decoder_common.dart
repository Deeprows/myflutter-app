import 'package:flutter/material.dart';

import '../../services/cast_service.dart';
import '../../services/app_memory.dart';
import '../../theme/app_theme.dart';

/// Remembers which Decoder page was open so reopening the app returns there.
/// Page ids: hub, cast, mirror, receiver, remote, channels.
class DecoderMemory {
  static const _key = 'decoder_last_page';

  static String? get lastPage => AppMemory.getString(_key);

  /// Saves the open page; null or an empty id forgets it.
  static void save(String? pageId) => AppMemory.setString(_key, pageId ?? '');
}

/// Short message that disappears by itself (replaces on-screen logs).
void decoderToast(BuildContext context, String message) {
  if (!context.mounted) return;
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 3),
    behavior: SnackBarBehavior.floating,
  ));
}

Widget decoderPanel(Widget child, {double bottom = 14}) => Container(
      margin: EdgeInsets.only(bottom: bottom),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ui.line),
      ),
      child: child,
    );

Widget decoderHeading(String title, String subtitle) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: Ui.text, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Ui.muted, fontSize: 12)),
      ]),
    );

/// Play / pause / stop, seek, volume and sleep timer for the TV that is
/// currently playing.
class DecoderNowPlaying extends StatelessWidget {
  final CastService svc;
  const DecoderNowPlaying({super.key, required this.svc});

  String _clock(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final live = svc.duration <= Duration.zero;
    return decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.cast_connected, color: Ui.red, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Playing on ${svc.device?.name ?? 'TV'}',
              style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        if (live) const Chip(label: Text('LIVE')),
      ]),
      const SizedBox(height: 6),
      Text(svc.castTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Ui.muted)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        IconButton.filledTonal(onPressed: svc.play, icon: const Icon(Icons.play_arrow)),
        IconButton.filledTonal(onPressed: svc.pause, icon: const Icon(Icons.pause)),
        IconButton.filledTonal(onPressed: svc.stop, icon: const Icon(Icons.stop)),
      ]),
      if (!live) ...[
        Slider(
          value: svc.position.inSeconds.clamp(0, svc.duration.inSeconds).toDouble(),
          min: 0,
          max: svc.duration.inSeconds.toDouble(),
          onChanged: (v) => svc.seekTo(Duration(seconds: v.round())),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_clock(svc.position), style: TextStyle(color: Ui.muted, fontSize: 11)),
          Text(_clock(svc.duration), style: TextStyle(color: Ui.muted, fontSize: 11)),
        ]),
      ],
      if (svc.tvVolumeSupported)
        Row(children: [
          const Icon(Icons.volume_down),
          Expanded(
            child: Slider(
              value: svc.tvVolume.clamp(0, 100).toDouble(),
              min: 0,
              max: 100,
              onChanged: (v) => svc.setTvVolume(v.round()),
            ),
          ),
          IconButton(onPressed: () => svc.setTvVolume(0), icon: const Icon(Icons.volume_off)),
        ]),
      Row(children: [
        const Icon(Icons.bedtime_outlined),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            svc.sleepEndsAt == null
                ? 'Sleep timer off'
                : 'Stops at ${TimeOfDay.fromDateTime(svc.sleepEndsAt!).format(context)}',
            style: TextStyle(color: Ui.muted),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: 'Sleep timer',
          onSelected: (v) => svc.setSleepTimer(v == 0 ? null : Duration(minutes: v)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('Off')),
            PopupMenuItem(value: 15, child: Text('15 minutes')),
            PopupMenuItem(value: 30, child: Text('30 minutes')),
            PopupMenuItem(value: 60, child: Text('1 hour')),
            PopupMenuItem(value: 120, child: Text('2 hours')),
          ],
          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.timer_outlined)),
        ),
      ]),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: svc.stop, icon: const Icon(Icons.cast), label: const Text('Disconnect')),
      ),
    ]));
  }
}

/// Asks for the Kodi web-control login. Returns true when it was saved.
Future<bool> decoderKodiLogin(BuildContext context) async {
  final u = TextEditingController(text: 'kodi');
  final p = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      title: const Text('Kodi web login'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Kodi → Settings → Services → Control shows the username and password for "Allow remote control via HTTP". The default username is kodi (password can be empty).',
          style: TextStyle(color: Ui.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextField(controller: u, decoration: const InputDecoration(labelText: 'Username')),
        TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & retry')),
      ],
    ),
  );
  final user = u.text.trim();
  final pass = p.text;
  u.dispose();
  p.dispose();
  if (ok != true) return false;
  await CastService.instance.setKodiLogin(user, pass);
  return true;
}


/// Push a Decoder subpage while remembering both the current page and the
/// destination. When the user returns, restore the page underneath it.
Future<T?> pushDecoderPage<T>(BuildContext context, Widget page, String pageId) async {
  final saved = DecoderMemory.lastPage;
  final previous = (saved == null || saved.isEmpty) ? 'hub' : saved;
  DecoderMemory.save(pageId);
  final result = await Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (_) => page),
  );
  DecoderMemory.save(previous);
  return result;
}
