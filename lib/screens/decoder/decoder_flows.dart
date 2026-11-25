import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/stream_resolver.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/premium_gate.dart';
import 'decoder_cast_page.dart';
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

/// Bottom sheet that asks how a channel / movie should be watched: the two
/// ways to put it on a bigger screen. [image] / [meta] dress the header.
Future<void> chooseConnectivity(BuildContext context, CastTarget target, {String? image, String? meta}) async {
  final svc = CastService.instance;
  Widget option(BuildContext ctx, IconData icon, String title, String sub, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ui.line),
              color: Ui.card,
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Ui.red.withValues(alpha: .16), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: Ui.red),
              ),
              title: Text(title, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
              subtitle: Text(sub, style: TextStyle(color: Ui.muted, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: Ui.redSoft),
              onTap: () => Navigator.pop(ctx, value),
            ),
          ),
        ),
      );
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Ui.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
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
                Text('CAST THIS TITLE', style: TextStyle(color: Ui.redSoft, fontSize: 9.5, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
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
        option(ctx, Icons.cast_rounded, 'Cast to TV / Kodi',
            svc.casting ? 'Now playing on ${svc.device?.name ?? 'TV'}' : 'Smart TVs and Kodi on your Wi-Fi', 'cast'),
        option(ctx, Icons.web_rounded, 'Send to receiver page', 'Plays in a laptop or TV browser', 'receiver'),
        const SizedBox(height: 6),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'cast') {
    await castToTv(context, target);
  } else {
    await sendToReceiver(context, target);
  }
}

Future<void> castToTv(BuildContext context, CastTarget target, {VoidCallback? onCastStarted}) async {
  // Casting has its own five-use free allowance. Do not open the Premium-only
  // Decoder dashboard just to show the available TV/device options.
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
  final mirror = DeeprowssMirrorService.instance;
  if (mirror.running && mirror.usingQrPairing) {
    final kind = target.kind == StreamKind.invalid ? StreamKind.embed : target.kind;
    final ok = await mirror.sendChannel(url: url, title: target.title, kind: kind,
      referer: target.referer, userAgent: target.userAgent);
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
