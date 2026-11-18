import 'dart:io';

import 'package:flutter/material.dart';

import '../services/background_playback.dart';
import '../services/cast_service.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';

/// What a player page wants to send to the TV.
class CastTarget {
  final String title;

  /// Stream link and its kind (hls / dash / video). Embeds and web pages
  /// cannot be sent as a link; the sheet then offers screen mirroring only.
  final String? url;
  final StreamKind? kind;
  final String? referer;
  final String? userAgent;

  /// For videos stored on the phone.
  final Future<File?> Function()? file;

  const CastTarget({
    required this.title,
    this.url,
    this.kind,
    this.referer,
    this.userAgent,
    this.file,
  });

  bool get canCast {
    if (file != null) return true;
    final u = (url ?? '').trim();
    if (u.isEmpty) return false;
    return kind == StreamKind.hls ||
        kind == StreamKind.dash ||
        kind == StreamKind.video;
  }
}

/// The "Cast to screen" icon. Put it on every player page.
///
/// [target] is read when the icon is tapped, so it always sends the stream
/// that is playing right now. [onCastStarted] lets the page pause its own
/// (phone) playback once the TV takes over.
class CastButton extends StatelessWidget {
  final CastTarget Function() target;
  final VoidCallback? onCastStarted;
  final Color? color;
  final double? size;

  const CastButton({
    super.key,
    required this.target,
    this.onCastStarted,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final svc = CastService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final on = svc.casting;
        return IconButton(
          tooltip: on ? 'Casting to ${svc.device?.name ?? 'TV'}' : 'Cast to screen',
          iconSize: size,
          onPressed: () =>
              showCastSheet(context, target(), onCastStarted: onCastStarted),
          icon: Icon(
            on ? Icons.cast_connected_rounded : Icons.cast_rounded,
            color: on ? Ui.red : color,
          ),
        );
      },
    );
  }
}

Future<void> showCastSheet(
  BuildContext context,
  CastTarget target, {
  VoidCallback? onCastStarted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ui.panel,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _CastSheet(target: target, onCastStarted: onCastStarted),
  );
}

class _CastSheet extends StatefulWidget {
  final CastTarget target;
  final VoidCallback? onCastStarted;
  const _CastSheet({required this.target, this.onCastStarted});

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  final svc = CastService.instance;
  double _phoneVol = 0.5;

  @override
  void initState() {
    super.initState();
    BackgroundPlayback.getVolume().then((v) {
      if (mounted) setState(() => _phoneVol = v);
    });
    if (widget.target.canCast && !svc.casting && svc.devices.isEmpty) {
      svc.scan();
    }
    if (svc.casting) svc.refreshTvVolume();
  }

  Future<void> _cast(CastDevice d) async {
    final t = widget.target;
    bool ok;
    if (t.file != null) {
      final f = await t.file!();
      if (f == null) {
        _snack('This file cannot be cast.');
        return;
      }
      ok = await svc.castFile(d, f, title: t.title);
    } else {
      ok = await svc.castUrl(
        d,
        t.url!.trim(),
        title: t.title,
        kind: t.kind,
        referer: t.referer,
        userAgent: t.userAgent,
      );
    }
    if (ok) widget.onCastStarted?.call();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _mirror() async {
    final ok = await CastService.openMirrorSettings();
    if (!ok) {
      _snack('Open "Cast" or "Smart View" from your phone\'s quick settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * .85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ListenableBuilder(
          listenable: svc,
          builder: (context, _) {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                Row(
                  children: [
                    Icon(Icons.cast_rounded, color: Ui.red),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Cast to screen',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                    if (widget.target.canCast && !svc.casting)
                      IconButton(
                        tooltip: 'Search again',
                        onPressed: svc.scanning ? null : svc.scan,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
                if (svc.casting) _nowCasting(),
                _phoneVolume(),
                const SizedBox(height: 6),
                if (!svc.casting) ..._deviceSection(),
                const SizedBox(height: 6),
                _mirrorTile(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(Ui.radius),
          border: Border.all(color: Ui.line),
        ),
        child: child,
      );

  Widget _nowCasting() {
    final d = svc.device;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected_rounded, color: Ui.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Casting to ${d?.name ?? 'TV'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(svc.castTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Ui.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Ui.red),
                onPressed: svc.togglePlay,
                icon: Icon(
                    svc.tvPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 20),
                label: Text(svc.tvPlaying ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: svc.stop,
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('Stop casting'),
              ),
            ],
          ),
          if (svc.tvVolumeSupported) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.tv_rounded, size: 20),
                const SizedBox(width: 8),
                Text('TV volume', style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                Expanded(
                  child: Slider(
                    activeColor: Ui.red,
                    value: (svc.tvVolume < 0 ? 0 : svc.tvVolume).toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 50,
                    label: svc.tvVolume < 0 ? '' : '${svc.tvVolume}',
                    onChanged: (v) => svc.setTvVolume(v.round()),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'You can lock the phone or minimise the app. The TV keeps playing.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _phoneVolume() {
    return _card(
      child: Row(
        children: [
          Icon(
              _phoneVol <= 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              size: 20),
          const SizedBox(width: 8),
          Text('Phone volume', style: TextStyle(color: Ui.muted, fontSize: 12.5)),
          Expanded(
            child: Slider(
              activeColor: Ui.red,
              value: _phoneVol.clamp(0.0, 1.0),
              onChanged: (v) {
                setState(() => _phoneVol = v);
                BackgroundPlayback.setVolume(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _deviceSection() {
    if (!widget.target.canCast) {
      return [
        _card(
          child: Text(
            'This channel is a web page, so it cannot be sent to a TV as a '
            'link. Use screen mirroring below.',
            style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.35),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      Text('TVs on your Wi-Fi',
          style: TextStyle(
              color: Ui.muted, fontSize: 12, fontWeight: FontWeight.w800)),
      if (svc.scanning || svc.connecting)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(color: Ui.red, minHeight: 2),
        ),
      for (final d in svc.devices)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.tv_rounded, color: Ui.red),
          title: Text(d.name,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(d.host, style: TextStyle(color: Ui.muted, fontSize: 12)),
          onTap: svc.connecting ? null : () => _cast(d),
        ),
      if (!svc.scanning && svc.devices.isEmpty && svc.error == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'No TV found yet. Put the phone and the TV on the same Wi-Fi and '
            'switch on the TV\'s "Screen share", "Media" or "DLNA" option.',
            style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.35),
          ),
        ),
      if (svc.error != null && !svc.scanning)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(svc.error!,
              style: TextStyle(color: Ui.red, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
    ];
  }

  Widget _mirrorTile() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.screen_share_rounded),
      title: const Text('Mirror phone screen',
          style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        'For Chromecast, Smart View and web pages. Mirroring may pause when '
        'the phone locks.',
        style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.3),
      ),
      onTap: _mirror,
    );
  }
}
