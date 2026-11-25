import 'package:flutter/material.dart';

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
          liveOnly: !thread,
          initialTab: thread ? 3 : 0,
          restoreLastTab: false,
          onHome: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openDecoder(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CastScreen()),
    );
  }

  /// Fades and slides a child up, one after another (index * 90ms delay).
  Widget _reveal(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: c),
      ),
      child: child,
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool featured = false,
  }) {
    final onAccent = Ui.palette.onAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            if (featured)
              BoxShadow(
                color: Ui.red.withValues(alpha: Ui.isLight ? .18 : .22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: Ui.isLight ? .06 : .25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              padding: EdgeInsets.fromLTRB(18, featured ? 22 : 18, 16, featured ? 22 : 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: featured ? Ui.red.withValues(alpha: .6) : Ui.line,
                  width: featured ? 1.2 : 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: featured
                      ? [
                          Color.alphaBlend(Ui.red.withValues(alpha: .30), Ui.card),
                          Color.alphaBlend(Ui.red.withValues(alpha: .06), Ui.panel),
                        ]
                      : [
                          Ui.card.withValues(alpha: .96),
                          Ui.panel.withValues(alpha: .92),
                        ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: featured ? 64 : 58,
                    height: featured ? 64 : 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: featured
                            ? [Ui.red, Ui.redSoft]
                            : [
                                Ui.red.withValues(alpha: .26),
                                Ui.red.withValues(alpha: .10),
                              ],
                      ),
                      border: Border.all(
                        color: Ui.red.withValues(alpha: featured ? 0 : .30),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: featured ? onAccent : Ui.red,
                      size: featured ? 32 : 29,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (featured) ...[
                          const _LiveBadge(),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            color: Ui.text,
                            fontSize: 15.5,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Ui.muted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: featured
                          ? Ui.red.withValues(alpha: .20)
                          : Ui.text.withValues(alpha: .07),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: featured ? Ui.red : Ui.muted,
                    ),
                  ),
                ],
              ),
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
        backgroundColor: Colors.transparent,
        centerTitle: true,
        toolbarHeight: 68,
        title: Image.asset(
          'assets/icon/logo_header.png',
          height: 52,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Deeprowss',
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Soft brand glow behind the header.
          Positioned(
            top: -140,
            left: -60,
            right: -60,
            child: IgnorePointer(
              child: Container(
                height: 380,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Ui.red.withValues(alpha: Ui.isLight ? .10 : .22),
                      Ui.red.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 84, 20, 30),
              children: [
                _reveal(
                  0,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome 🤗',
                        style: TextStyle(
                          color: Ui.text,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your entertainment. Your community. One place.',
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _reveal(
                  1,
                  _featureCard(
                    icon: Icons.sensors_rounded,
                    title: 'LIVE EVENTS',
                    subtitle: 'Follow live matches, fixtures and football action.',
                    featured: true,
                    onTap: () => _openSection(context, thread: false),
                  ),
                ),
                _reveal(
                  2,
                  _featureCard(
                    icon: Icons.forum_rounded,
                    title: 'DEEPROWSS THREAD',
                    subtitle: 'Join the conversation, AI predictions and Match Room.',
                    onTap: () => _openSection(context, thread: true),
                  ),
                ),
                _reveal(
                  3,
                  _featureCard(
                    icon: Icons.cast_connected_rounded,
                    title: 'SMART DECODER',
                    subtitle: 'Connect your TV, Kodi or browser receiver.',
                    onTap: () => _openDecoder(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "LIVE" pill with a softly pulsing dot.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Ui.red.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ui.red.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: .35, end: 1).animate(_pulse),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: Ui.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE NOW',
            style: TextStyle(
              color: Ui.red,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
