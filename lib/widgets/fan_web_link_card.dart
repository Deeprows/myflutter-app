import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/post_links.dart';

/// Link card shown in a post for a web page link. Tapping opens the page
/// inside the app (WhatsApp / Telegram links open in their own apps).
class FanWebLinkCard extends StatelessWidget {
  final String url;
  const FanWebLinkCard({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
    final chat = isChatAppLink(url);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Ui.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Ui.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openPostLink(context, url),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    chat ? Icons.chat_rounded : Icons.language_rounded,
                    color: Ui.redSoft,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chat ? 'Opens in its app' : 'Opens inside Deeprowss',
                        style: TextStyle(color: Ui.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  chat ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
                  color: Ui.dim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
