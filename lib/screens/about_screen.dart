import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import 'legal_screen.dart';

/// "About Deeprowss", opened from Settings and support.
Future<void> showAboutDeeprowss(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const AboutScreen()));

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _sections = <(String, String)>[
    ('Who we are',
        '${AppConfig.appName} is a digital media and communication platform built for people who love live sport, great entertainment and lively conversation. We bring everyday viewing, discovery and community together in one simple, modern app.'),
    ('What we do',
        'We make it easier to find and enjoy what is available online. From live football events and match highlights to TV channels and movies, ${AppConfig.appName} organises the experience into one clean place, so you spend less time searching and more time watching, sharing and talking about it.'),
    ('Our role as a bridge',
        '${AppConfig.appName} serves as a bridge to sources that are already available on the internet. We connect you to them; we do not host, upload or store the videos, streams or channels listed in the app.'),
    ('Content and ownership',
        'All content belongs to its rightful owners, and we respect their ownership and the work behind it. Names, logos and trademarks shown in the app remain the property of their respective owners and are used for identification only.'),
    ('Working with rights holders',
        'We value good relationships with content owners. If you represent a rights holder and would like to share feedback about how something is listed, please reach out through the button below and our team will gladly review it.'),
    ('Community',
        'Thread, Match Room, predictions and ranks give fans a friendly space to share opinions, react to matches together and celebrate the game. We encourage respectful, positive conversation for everyone.'),
    ('Our promise',
        'We are committed to a clean, reliable experience: continuous improvements, thoughtful design, privacy that is explained clearly, and support that is easy to reach.'),
  ];

  static const _features = <(IconData, String)>[
    (Icons.sports_soccer_rounded, 'Live football'),
    (Icons.video_library_rounded, 'Highlights'),
    (Icons.live_tv_rounded, 'TV channels'),
    (Icons.movie_creation_outlined, 'Movies'),
    (Icons.auto_awesome_rounded, 'AI Predict'),
    (Icons.forum_rounded, 'Fan community'),
    (Icons.play_circle_outline_rounded, 'Media player'),
    (Icons.cast_connected_rounded, 'Cast to screen'),
  ];

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('About ${AppConfig.appName}', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            // ── header ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Ui.card,
                border: Border.all(color: Ui.line),
              ),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(20)),
                  child: Icon(Icons.hub_rounded, size: 34, color: Ui.palette.onAccent),
                ),
                const SizedBox(height: 12),
                Text(AppConfig.appName,
                    style: TextStyle(color: Ui.text, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Digital media and communication',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ui.redSoft, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text('Your bridge to the sport, shows and conversations you love.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 18),

            // ── what is inside ──
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in _features)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: Ui.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Ui.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(f.$1, size: 16, color: Ui.red),
                    const SizedBox(width: 6),
                    Text(f.$2, style: TextStyle(color: Ui.text, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
            const SizedBox(height: 20),

            // ── write-up ──
            for (final s in _sections) ...[
              Text(s.$1, style: TextStyle(color: Ui.redSoft, fontSize: 14.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(s.$2, style: TextStyle(color: Ui.text, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 16),
            ],

            // ── actions ──
            FilledButton.icon(
              onPressed: () => _open(AppConfig.whatsappUrl),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Contact us on WhatsApp'),
              style: FilledButton.styleFrom(
                backgroundColor: Ui.red,
                foregroundColor: Ui.palette.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showTermsOfUse(context),
                  icon: const Icon(Icons.gavel_rounded, size: 18),
                  label: const Text('Terms'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Ui.text,
                    side: BorderSide(color: Ui.line),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showPrivacyPolicy(context),
                  icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                  label: const Text('Privacy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Ui.text,
                    side: BorderSide(color: Ui.line),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Center(
              child: Text('${AppConfig.appName} · Version ${AppConfig.appVersion}',
                  style: TextStyle(color: Ui.dim, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
