import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../services/cast_service.dart';
import '../../services/stream_resolver.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../theme/app_theme.dart';
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

/// Bottom sheet that asks how a channel / movie should be watched.
Future<void> chooseConnectivity(BuildContext context, CastTarget target) async {
  final svc = CastService.instance;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Ui.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(target.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Ui.text, fontSize: 17, fontWeight: FontWeight.w900)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('How do you want to watch it?', style: TextStyle(color: Ui.muted, fontSize: 12)),
          ),
        ),
        ListTile(
          leading: Icon(Icons.cast_rounded, color: Ui.red),
          title: const Text('Cast to TV / Kodi'),
          subtitle: Text(svc.casting ? 'Now playing on ${svc.device?.name ?? 'TV'}' : 'Smart TVs and Kodi on your Wi-Fi'),
          onTap: () => Navigator.pop(ctx, 'cast'),
        ),
        ListTile(
          leading: Icon(Icons.web_rounded, color: Ui.red),
          title: const Text('Send to receiver page'),
          subtitle: const Text('Plays in a laptop or TV browser'),
          onTap: () => Navigator.pop(ctx, 'receiver'),
        ),
        const SizedBox(height: 8),
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

Future<void> castToTv(BuildContext context, CastTarget target) async {
  final ready = await prepareTarget(context, target);
  if (ready == null || !context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DecoderCastPage(target: ready)));
}

Future<void> sendToReceiver(BuildContext context, CastTarget target) async {
  final ready = await prepareTarget(context, target);
  if (ready == null || !context.mounted) return;
  final url = ready.url;
  if (url == null || url.isEmpty) {
    decoderToast(context, 'There is no video link to send.');
    return;
  }
  final mirror = DeeprowssMirrorService.instance;
  final ok = await mirror.sendChannel(url: url, title: ready.title, kind: ready.kind);
  if (!context.mounted) return;
  if (!ok) {
    decoderToast(context, mirror.error ?? 'Could not start the receiver session.');
    return;
  }
  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DecoderReceiverPage()));
}
