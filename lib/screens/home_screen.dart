import 'package:flutter/material.dart';

import '../services/login_gate.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'cast_screen.dart';
import 'shell_screen.dart';

/// First in-app page shown after the launch splash and authentication restore.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openSection(BuildContext context, {required bool thread}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShellScreen(
          threadOnly: thread,
          initialTab: thread ? 3 : 0,
          onHome: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openDecoder(BuildContext context) async {
    if (!await ensureSignedIn(context) || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CastScreen()),
    );
  }

  Widget _featureCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool featured = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: featured ? Ui.red.withValues(alpha: .55) : Ui.line,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: featured
                    ? [
                        Color.alphaBlend(Ui.red.withValues(alpha: .23), Ui.card),
                        Ui.panel,
                      ]
                    : [Ui.card, Ui.panel],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Ui.red.withValues(alpha: .25)),
                  ),
                  child: Icon(icon, color: Ui.red, size: 29),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Ui.text,
                          fontSize: 16,
                          letterSpacing: .5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 17, color: Ui.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      drawer: const FootboliveDrawer(),
      appBar: AppBar(
        backgroundColor: Ui.bg,
        titleSpacing: 4,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Ui.red,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: const Text(
                'D',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'DEEPROWSS',
              style: TextStyle(
                color: Ui.text,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          children: [
            Text(
              'Welcome 🤗',
              style: TextStyle(
                color: Ui.text,
                fontSize: 29,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Your entertainment. Your community. One place.',
              style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 28),
            _featureCard(
              context: context,
              icon: Icons.sensors_rounded,
              title: 'LIVE EVENTS',
              subtitle: 'Follow live matches, fixtures and football action.',
              featured: true,
              onTap: () => _openSection(context, thread: false),
            ),
            _featureCard(
              context: context,
              icon: Icons.forum_rounded,
              title: 'DEEPROWSS THREAD',
              subtitle: 'Join the conversation, AI predictions and Match Room.',
              onTap: () => _openSection(context, thread: true),
            ),
            _featureCard(
              context: context,
              icon: Icons.cast_connected_rounded,
              title: 'SMART DECODER',
              subtitle: 'Connect your TV, Kodi or browser receiver.',
              onTap: () => _openDecoder(context),
            ),
          ],
        ),
      ),
    );
  }
}
