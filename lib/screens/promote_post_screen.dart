import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart' show openExternally;

/// "Promote this post": explains how sponsored posts work and opens a WhatsApp
/// chat with the Deeprowss admin (+234 704 162 9630) so the fan can enquire
/// and pay manually. The admin then pins the post and labels it "Sponsored".
class PromotePostScreen extends StatelessWidget {
  final String postId;
  final String postText;
  const PromotePostScreen({
    super.key,
    required this.postId,
    this.postText = '',
  });

  static const _phoneLabel = '+234 704 162 9630';

  Uri _chatUri() {
    final snippet = postText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final short = snippet.length > 200 ? '${snippet.substring(0, 200)}…' : snippet;
    final message = [
      'Hello Deeprowss Admin, I want to promote my post on the Thread page.',
      'Post ID: $postId',
      if (short.isNotEmpty) 'Post: $short',
      'Please share the available durations, prices and how to pay.',
    ].join('\n');
    final base = Uri.tryParse(AppConfig.adminWhatsappUrl) ??
        Uri.parse('https://wa.me/2347041629630');
    return base.replace(queryParameters: {'text': message});
  }

  Future<void> _chat(BuildContext context) async {
    final ok = await openExternally(_chatUri().toString());
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Message $_phoneLabel instead.'),
        ),
      );
    }
  }

  Widget _step(int n, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: Ui.red.withValues(alpha: .15),
          child: Text(
            '$n',
            style: TextStyle(
              color: Ui.redSoft,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: Ui.muted, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(title: const Text('Promote this post')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Ui.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Ui.line, width: .8),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Ui.red,
                  child: const Icon(Icons.campaign_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deeprowss Admin',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text('@DeeprowssAdmin · $_phoneLabel'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Make an enquiry',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Pay for the number of days you want your post to appear at the '
            'top of the Thread page. Chat the admin on WhatsApp to ask about '
            'durations and prices, then pay manually.',
            style: TextStyle(color: Ui.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          _step(1, 'Chat the admin',
              'Tap the button below. Your post details are filled in for you.'),
          _step(2, 'Choose your days and pay',
              'The admin tells you the price for the days you want and how to pay.'),
          _step(3, 'Your post goes to the top',
              'After your payment is confirmed the admin pins your post and '
              'labels it "Sponsored". Only the admin can pin posts.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _chat(context),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Chat admin on WhatsApp'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _phoneLabel,
              style: TextStyle(color: Ui.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
