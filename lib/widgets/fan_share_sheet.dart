import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Bottom sheet for sharing a post: handle, a small preview of the post and a
/// scrollable row of round share targets (Share via…, Copy link, WhatsApp,
/// Telegram, X).
Future<void> showFanShareSheet(
  BuildContext context, {
  required String author,
  required String text,
  required String url,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final message = '$author on Deeprowss\n$text\n\n$url';
  final encodedMsg = Uri.encodeComponent(message);
  final encodedUrl = Uri.encodeComponent(url);
  final encodedText = Uri.encodeComponent('$author on Deeprowss\n$text');

  Future<void> open(String link) async {
    try {
      final ok = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) await Share.share(message);
    } catch (_) {
      await Share.share(message);
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ui.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheet) {
      void close() => Navigator.of(sheet).pop();
      final targets = <_Target>[
        _Target(
          'Share via…',
          Icons.share_rounded,
          Colors.white,
          const Color(0xFF111418),
          () async {
            close();
            await Share.share(message);
          },
        ),
        _Target(
          'Copy link',
          Icons.link_rounded,
          Colors.white,
          const Color(0xFF111418),
          () async {
            await Clipboard.setData(ClipboardData(text: url));
            close();
            messenger.showSnackBar(
              const SnackBar(content: Text('Link copied')),
            );
          },
        ),
        _Target(
          'WhatsApp',
          Icons.chat_rounded,
          const Color(0xFF25D366),
          Colors.white,
          () async {
            close();
            await open('https://wa.me/?text=$encodedMsg');
          },
        ),
        _Target(
          'Telegram',
          Icons.send_rounded,
          const Color(0xFF229ED9),
          Colors.white,
          () async {
            close();
            await open('https://t.me/share/url?url=$encodedUrl&text=$encodedText');
          },
        ),
        _Target(
          'X',
          Icons.alternate_email_rounded,
          Colors.black,
          Colors.white,
          () async {
            close();
            await open('https://twitter.com/intent/tweet?text=$encodedText&url=$encodedUrl');
          },
        ),
      ];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Ui.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Share post',
                    style: Theme.of(sheet).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Ui.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (text.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Ui.muted, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: Ui.line),
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  itemCount: targets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _TargetView(targets[i]),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Target {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final Future<void> Function() onTap;
  const _Target(this.label, this.icon, this.bg, this.fg, this.onTap);
}

class _TargetView extends StatelessWidget {
  final _Target t;
  const _TargetView(this.t);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: t.onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.bg,
                shape: BoxShape.circle,
                border: t.bg == Colors.black
                    ? Border.all(color: Ui.line)
                    : null,
              ),
              child: Icon(t.icon, color: t.fg, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              t.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
