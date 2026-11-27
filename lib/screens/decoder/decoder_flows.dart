import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/stream_resolver.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/premium_gate.dart';
import 'decoder_cast_page.dart';
import 'decoder_mirror_page.dart';
import 'decoder_remote_page.dart';
import 'decoder_common.dart';
import 'decoder_receiver_page.dart';
import 'stream_finder_page.dart';

/// Turns any channel / movie into something a TV can be sent: a direct
/// stream link. Web pages are searched first (quick), and when that fails the
/// in-app stream finder opens the page and captures the real video address.
Future<CastTarget?> prepareTarget(BuildContext context, CastTarget t) async {
  if (t.file != null) return t;
  final url = (t.url ?? '').trim();
  if (url.isEmpty) {
    decoderToast(context, 'There is no video link for "${t.title}".');
    return null;
  }
  final k = t.kind;
  if (k == StreamKind.hls || k == StreamKind.dash || k == StreamKind.video) return t;

  CastTarget fromFound(String u, StreamKind kind, String? ref, String? ua) => CastTarget(
        title: t.title,
        url: u,
        kind: kind,
        referer: ref ?? t.referer,
        userAgent: ua ?? t.userAgent,
        backup: t.backup,
      );

  final cached = StreamFinderPage.cache[url];
  if (cached != null) return fromFound(cached.url, cached.kind, cached.referer, cached.userAgent);

  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Ui.panel,
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(child: Text('Preparing "${t.title}"…')),
        ]),
      ),
    ),
  );
  final quick = await CastService.instance.resolveStream(url, referer: t.referer, userAgent: t.userAgent);
  nav.pop();
  if (quick != null) return fromFound(quick.url, quick.kind, quick.referer, null);
  if (!context.mounted) return null;

  final found = await Navigator.of(context).push<FoundStream>(
    MaterialPageRoute(builder: (_) => StreamFinderPage(url: url, title: t.title, referer: t.referer)),
  );
  if (found == null) {
    if (context.mounted) decoderToast(context, 'Could not find the video on that page. Try another channel.');
    return null;
  }
  return fromFound(found.url, found.kind, found.referer, found.userAgent);
}

/// One row of the choice sheets below.
class _SheetOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final bool highlight;
  const _SheetOption(this.icon, this.title, this.subtitle, this.value, {this.highlight = false});
}

/// Shared bottom sheet: dressed header (poster, label, title, meta) and a
/// list of options. Returns the chosen option's value (null = dismissed).
Future<String?> _showChoiceSheet(
  BuildContext context,
  CastTarget target, {
  required String label,
  required List<_SheetOption> options,
  String? image,
  String? meta,
}) {
  Widget option(BuildContext ctx, _SheetOption o) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: o.highlight ? Ui.red.withValues(alpha: .6) : Ui.line),
              gradient: o.highlight
                  ? LinearGradient(colors: [Color.alphaBlend(Ui.red.withValues(alpha: .18), Ui.card), Ui.card])
                  : null,
              color: o.highlight ? null : Ui.card,
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: o.highlight ? Ui.red : Ui.red.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(o.icon, color: o.highlight ? Ui.palette.onAccent : Ui.red),
              ),
              title: Text(o.title, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
              subtitle: Text(o.subtitle, style: TextStyle(color: Ui.muted, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: Ui.redSoft),
              onTap: () => Navigator.pop(ctx, o.value),
            ),
          ),
        ),
      );
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Ui.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 38, height: 4, decoration: BoxDecoration(color: Ui.line, borderRadius: BorderRadius.circular(9))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(children: [
              if (image != null && image.startsWith('http'))
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 52,
                      height: 76,
                      child: Image.network(image, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Ui.card, child: const Icon(Icons.movie_outlined))),
                    ),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(color: Ui.redSoft, fontSize: 9.5, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(target.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ui.text, fontSize: 17, height: 1.15, fontWeight: FontWeight.w900)),
                  if (meta != null && meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta, style: TextStyle(color: Ui.muted, fontSize: 12)),
                  ],
                ]),
              ),
            ]),
          ),
          for (final o in options) option(ctx, o),
          const SizedBox(height: 6),
        ]),
      ),
    ),
  );
}

/// Bottom sheet that asks how a channel / movie should be watched. When
/// [onWatchInApp] is given (Moviebox) a "Watch in App" option comes first and
/// opens the real in-app player page; the other two put it on a bigger screen.
Future<void> chooseConnectivity(
  BuildContext context,
  CastTarget target, {
  String? image,
  String? meta,
  VoidCallback? onWatchInApp,
}) async {
  final svc = CastService.instance;
  final choice = await _showChoiceSheet(
    context,
    target,
    image: image,
    meta: meta,
    label: onWatchInApp != null ? 'WATCH OR CAST' : 'CAST THIS TITLE',
    options: [
      if (onWatchInApp != null)
        const _SheetOption(Icons.play_circle_fill_rounded, 'Watch in App', 'Open the movie page and play it here', 'watch',
            highlight: true),
      _SheetOption(Icons.cast_rounded, 'Cast to TV / Kodi',
          svc.casting ? 'Now playing on ${svc.device?.name ?? 'TV'}' : 'Smart TVs and Kodi on your Wi-Fi', 'cast'),
      const _SheetOption(Icons.web_rounded, 'Send to receiver page', 'Plays in a laptop or TV browser', 'receiver'),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'watch':
      onWatchInApp?.call();
    case 'cast':
      await castToTv(context, target);
    default:
      await sendToReceiver(context, target);
  }
}

/// What the cast icon on a player / movie page opens: every way of putting
/// the video on a bigger screen, so the person picks the one they prefer.
Future<void> showCastOptions(
  BuildContext context,
  CastTarget target, {
  VoidCallback? onCastStarted,
  String? meta,
  String? image,
}) async {
  final svc = CastService.instance;
  final mirror = DeeprowssMirrorService.instance;
  final url = (target.url ?? '').trim();
  final hasLink = target.file != null || url.isNotEmpty;
  final hasBackup = (target.backup?.url ?? '').trim().isNotEmpty;
  final choice = await _showChoiceSheet(
    context,
    target,
    label: 'CAST TO SCREEN',
    meta: meta,
    image: image,
    options: [
      _SheetOption(Icons.cast_rounded, 'Cast to TV / Kodi',
          svc.casting
              ? 'Now playing on ${svc.device?.name ?? 'TV'}'
              : (hasBackup ? 'Main stream plays, backup takes over if it stops' : 'Smart TVs and Kodi on your Wi-Fi'),
          'cast',
          highlight: true),
      if (url.startsWith(RegExp(r'https?://', caseSensitive: false)))
        _SheetOption(Icons.web_rounded, 'Send to receiver page',
            hasBackup ? 'Laptop or TV browser · backup stream ready' : 'Plays in a laptop or TV browser', 'receiver'),
      _SheetOption(Icons.screen_share_rounded, 'Screen mirroring',
          mirror.running ? 'Mirroring is on · tap to manage' : 'Show your whole phone screen on a TV or laptop', 'mirror'),
      const _SheetOption(Icons.gamepad_rounded, 'TV remote', 'Roku, LG, Samsung and playback controls', 'remote'),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'cast':
      if (!hasLink) {
        decoderToast(context, 'This video cannot be cast as a link. Try Screen mirroring instead.');
        return;
      }
      await castToTv(context, target, onCastStarted: onCastStarted);
    case 'receiver':
      await sendToReceiver(context, target);
    case 'mirror':
      if (!await PremiumGate.allowDecoder(context) || !context.mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DecoderMirrorPage()));
    default:
      if (!await PremiumGate.allowDecoder(context) || !context.mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DecoderRemotePage()));
  }
}

Future<void> castToTv(BuildContext context, CastTarget target, {VoidCallback? onCastStarted}) async {
  // TV / Kodi casting is included in the 72-hour trial and Premium only.
  if (!await PremiumGate.allowCast(context) || !context.mounted) return;
  final ready = await prepareTarget(context, target);
  if (ready == null || !context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => DecoderCastPage(target: ready, onCastStarted: onCastStarted),
  ));
}

Future<void> sendToReceiver(BuildContext context, CastTarget target) async {
  if (!await PremiumGate.allowDecoder(context) || !context.mounted) return;
  final url = (target.url ?? '').trim();
  if (url.isEmpty || !url.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    decoderToast(context, 'This item has no valid web address to send.');
    return;
  }
  if (!await PremiumGate.consumeReceiverAccess(context) || !context.mounted) return;
  final mirror = DeeprowssMirrorService.instance;
  if (mirror.running && mirror.usingQrPairing) {
    final kind = target.kind == StreamKind.invalid ? StreamKind.embed : target.kind;
    final ok = await mirror.sendChannel(url: url, title: target.title, kind: kind,
      referer: target.referer, userAgent: target.userAgent,
      backupUrl: target.backup?.url, backupKind: target.backup?.kind);
    if (!context.mounted) return;
    if (!ok) { decoderToast(context, mirror.error ?? 'Could not send this video.'); return; }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => const DecoderReceiverPage(),
    ));
    return;
  }
  if (mirror.running) await mirror.stop();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => DecoderReceiverPage(target: target),
  ));
}
