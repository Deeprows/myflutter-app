import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme/app_theme.dart';

/// Terms of Use and Privacy Policy, opened from Settings.
enum LegalDoc { terms, privacy }

Future<void> showTermsOfUse(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const LegalScreen(doc: LegalDoc.terms)));

Future<void> showPrivacyPolicy(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const LegalScreen(doc: LegalDoc.privacy)));

class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  static const _updated = '25 November 2026';

  static const _terms = <(String, String)>[
    ('1. Acceptance',
        'By installing or using ${AppConfig.appName} you agree to these Terms of Use. If you do not agree, please do not use the app. You must be 18 or older to use match chat and to post in the community.'),
    ('2. What the app does',
        '${AppConfig.appName} brings together live football events, highlights, TV channels, movies, an AI match analysis tool (AI Predict), a fan community (Thread, Match Room, predictions and ranks), a media player, and tools to cast to a TV or another screen.'),
    ('3. Content we do not own',
        '${AppConfig.appName} does not host, upload or own the channels, matches, movies or videos shown in the app. Streams and links come from third-party sources and are the copyright of their respective owners. You are responsible for making sure you have the right to watch what you play. Content may be unavailable, blocked in your country or removed at any time.'),
    ('4. Your account',
        'You sign in with a Gmail account. Keep your account secure; you are responsible for activity under it. Your community name must be unique, may be limited in how often it can change, and must not impersonate another person or the ${AppConfig.appName} team.'),
    ('5. Community rules',
        'Be respectful. Do not post hate speech, threats, harassment, adult, violent or illegal content, spam, scams or unwanted promotions. Do not post private details such as phone numbers, bank or account details or passwords, and do not post content you have no right to share. Posts that break these rules may be removed and repeat offenders may be restricted or removed.'),
    ('6. Predictions and AI analysis',
        'Predictions, AI analysis and suggested picks are opinions for entertainment and information only. They are not guarantees, financial advice or betting advice. Never risk money you cannot afford to lose. Betting may be restricted or illegal where you live; you are responsible for following your local laws.'),
    ('7. Premium, tokens and payments',
        'Some features need Premium. Plans, prices and durations are shown in the app and are paid by card, bank transfer, USSD, crypto or manually through WhatsApp. Premium belongs to the Gmail account you used. Payments are handled by the payment provider or confirmed by the admin; fees already paid are generally not refundable unless the law requires it. We may change prices and features, and we may switch off a token or Premium that was obtained by mistake or abuse.'),
    ('8. Ads and sponsored posts',
        'Free users may see support pages, ads and sponsored posts. Links inside ads or third-party streams lead to sites we do not control.'),
    ('9. Acceptable use',
        'Do not copy, resell, reverse engineer or attack the app or its servers, bypass Premium or limits, create fake accounts, cheat in predictions or ranks, or use the app to break the law. We may suspend or end access for anyone who does.'),
    ('10. App Lock',
        'App Lock is a convenience for families. If you forget your PIN you can use your recovery answer; we cannot recover it for you.'),
    ('11. No warranty',
        'The app is provided "as is" and "as available". We do not promise that it, or any stream, will always work, be accurate or be free of errors.'),
    ('12. Limit of liability',
        'To the fullest extent the law allows, ${AppConfig.appName} is not liable for indirect or consequential loss, for the content of third-party streams, links or ads, or for decisions you make from predictions or analysis.'),
    ('13. Changes',
        'We may update these Terms. The date at the top shows the latest version; continuing to use the app after a change means you accept it.'),
    ('14. Contact',
        'Questions about these Terms? Contact us through the button below.'),
  ];

  static const _privacy = <(String, String)>[
    ('1. Who we are',
        '${AppConfig.appName} ("we", "us") provides this app. This policy explains what information the app uses and why.'),
    ('2. Information we collect',
        'Account: when you sign in with Google we receive your Gmail address, name and profile photo.\n\nProfile and community: your chosen name, @username, bio, club, photos, posts, comments, polls, reposts, follows, predictions, points and rank. These are public inside the community; your Gmail address is not.\n\nMatch chat and messages you send to the admin.\n\nPremium and payments: your plan, expiry, token and payment reference. We do not see or store your full card details; card payments are handled by the payment provider.\n\nDevice and usage: a random install ID, app version and platform used to count app opens, and a push notification token so we can send alerts.\n\nOn your phone only: your saved bookmarks, playlists, watch history, downloads, settings, language, theme and App Lock PIN are stored on your device.'),
    ('3. Permissions',
        'The app may ask for: notifications (match, highlight, movie and community alerts); access to photos, videos and music (to use the media player, attach images and save downloads); camera (to scan a receiver QR code); network and Wi-Fi access (to find and cast to a TV or laptop); and screen capture if you choose Screen mirroring. You can turn these off in your phone settings; some features will then stop working.'),
    ('4. How we use information',
        'To run your account and community profile; show posts, ranks and results; verify and settle predictions; provide Premium and ad-free access; send notifications you chose; cast and play media; keep the app secure, prevent abuse and fix problems; count how many people use the app; and improve features such as AI analysis.'),
    ('5. AI analysis',
        'When you ask for an analysis, the match names you chose are sent to our servers and an AI provider to create it. Do not enter personal information in matchup fields.'),
    ('6. Services we rely on',
        'Google Sign-In and Firebase (sign-in and push notifications), our Cloudflare servers (community, analytics and configuration), our payment provider, sports and movie data providers, and third-party stream and embed websites. When you open a third-party stream, web page, ad or betting site, that site collects information under its own policy.'),
    ('7. Sharing',
        'We do not sell your personal information. We share it only with the services above to operate the app, when you post publicly, when the law requires it, or to protect the app and its users.'),
    ('8. Cast and screen mirroring',
        'Casting sends a link to your TV, Kodi device or receiver page. Screen mirroring shows your phone screen on the screen you choose over your network; keep it away from private content while mirroring.'),
    ('9. Retention and deletion',
        'We keep account and community data while your account exists and as needed for Premium, ranks and security. Anyone can delete their own posts. To ask us to delete your account or data, contact us using the button below. Data stored only on your phone is removed when you clear the app data or uninstall.'),
    ('10. Security',
        'We use reasonable measures to protect information, but no system is completely secure. Please keep your Gmail account secure.'),
    ('11. Children',
        'The app is not meant for children under 13, and match chat and community names require you to be 18 or older. Parents can use App Lock to stop children opening the app. If you believe a child has given us information, contact us and we will remove it.'),
    ('12. Your choices',
        'You can switch notification types off in Alerts, clear browsing data and history in the app, log out, change your profile, and ask us to access, correct or delete your information.'),
    ('13. Changes',
        'We may update this policy. The date at the top shows the latest version.'),
    ('14. Contact',
        'For privacy questions or requests, contact us through the button below.'),
  ];

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isTerms = doc == LegalDoc.terms;
    final sections = isTerms ? _terms : _privacy;
    final title = isTerms ? 'Terms of Use' : 'Privacy Policy';
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(13)),
                child: Icon(isTerms ? Icons.gavel_rounded : Icons.privacy_tip_rounded, color: Ui.palette.onAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${AppConfig.appName} $title',
                      style: TextStyle(color: Ui.text, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('Last updated: $_updated', style: TextStyle(color: Ui.muted, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            for (final s in sections) ...[
              Text(s.$1, style: TextStyle(color: Ui.redSoft, fontSize: 14.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(s.$2, style: TextStyle(color: Ui.text, fontSize: 13.5, height: 1.45)),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () => _open(AppConfig.whatsappUrl),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Contact us on WhatsApp'),
              style: FilledButton.styleFrom(
                backgroundColor: Ui.red, foregroundColor: Ui.palette.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                builder: (_) => LegalScreen(doc: isTerms ? LegalDoc.privacy : LegalDoc.terms),
              )),
              icon: Icon(isTerms ? Icons.privacy_tip_outlined : Icons.gavel_rounded),
              label: Text(isTerms ? 'Read the Privacy Policy' : 'Read the Terms of Use'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Ui.text, side: BorderSide(color: Ui.line),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
