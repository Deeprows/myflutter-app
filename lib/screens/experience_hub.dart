import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/ad_scheduler.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pitch_painter.dart';
import 'community_shell_screen.dart';
import 'content_shortcut_screen.dart';
import 'highlights_screen.dart';
import 'movies_screen.dart';
import 'shell_screen.dart';
import 'tv_screen.dart';

/// The signed-in entry point: the user chooses football or community.
class ExperienceHub extends StatefulWidget {
  const ExperienceHub({super.key});
  @override
  State<ExperienceHub> createState() => _ExperienceHubState();
}

class _ExperienceHubState extends State<ExperienceHub> {
  String _mode = 'landing';
  bool _adsHeld = false;
  @override
  void initState() {
    super.initState();
    if (PushService.instance.tabRequest.value != null) _mode = 'watch';
    _syncAds();
    if (_mode == 'watch') unawaited(AdScheduler.instance.start());
    PushService.instance.tabRequest.addListener(_notification);
  }

  void _syncAds() {
    if (_mode == 'landing' && !_adsHeld) {
      AdScheduler.instance.hold();
      _adsHeld = true;
    }
    if (_mode != 'landing' && _adsHeld) {
      AdScheduler.instance.release();
      _adsHeld = false;
    }
  }

  void _open(String mode) {
    if (!mounted) return;
    setState(() => _mode = mode);
    _syncAds();
    if (mode != 'landing') unawaited(AdScheduler.instance.start());
  }

  /// Highlights and Movies open as full pages from the front page and come
  /// back here; ads follow the same rules as the other experiences.
  Future<void> _openPage(String title, Widget page) async {
    if (!mounted) return;
    if (_adsHeld) {
      AdScheduler.instance.release();
      _adsHeld = false;
    }
    unawaited(AdScheduler.instance.start());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContentShortcutScreen(title: title, child: page),
      ),
    );
    if (mounted) _syncAds();
  }

  void _notification() {
    if (PushService.instance.tabRequest.value == null || _mode == 'watch')
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || PushService.instance.tabRequest.value == null) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _open('watch');
    });
  }

  @override
  void dispose() {
    PushService.instance.tabRequest.removeListener(_notification);
    if (_adsHeld) AdScheduler.instance.release();
    super.dispose();
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of Deeprowss?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (yes == true) await AuthService.instance.signOut();
  }

  // A slim horizontal button: icon, title + one short line, arrow.
  Widget _choice({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    bool pitch = false,
  }) => Semantics(
    button: true,
    label: title,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: .20), Ui.card],
            ),
            border: Border.all(color: accent.withValues(alpha: .38)),
          ),
          child: Stack(
            children: [
              if (pitch)
                Positioned(
                  right: 30,
                  top: 3,
                  bottom: 3,
                  width: 70,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PitchPainter(
                        color: accent.withValues(alpha: .14),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: accent, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Ui.muted,
                              fontSize: 11.5,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: accent, size: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (_mode == 'watch') return ShellScreen(onHome: () => _open('landing'));
    if (_mode == 'community')
      return CommunityShellScreen(onHome: () => _open('landing'));
    final name = AuthService.instance.user?.name.trim() ?? '';
    final first = name.isEmpty ? 'Fan' : name.split(RegExp(r'\s+')).first;
    return Scaffold(
      backgroundColor: Ui.bg,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/themes/cr7.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Color(0xB3000000), BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Ui.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.sports_soccer_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'DEEPROWSS',
                          style: TextStyle(
                            fontSize: 20,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Welcome, $first',
                    style: TextStyle(
                      color: Ui.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your match. Your people.',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.15,
                      letterSpacing: -.6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The game brings us together. Choose where you want to go.',
                    style: TextStyle(
                      color: Ui.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _choice(
                    title: 'Watch Live Football',
                    subtitle: 'Live events, TV channels and your match.',
                    icon: Icons.stadium_rounded,
                    accent: const Color(0xFF45D99A),
                    pitch: true,
                    onTap: () => _open('watch'),
                  ),
                  const SizedBox(height: 10),
                  _choice(
                    title: 'Football Highlights',
                    subtitle: 'Goals, replays and match highlights.',
                    icon: Icons.play_circle_outline_rounded,
                    accent: const Color(0xFFFFB02E),
                    onTap: () => _openPage(
                      'Football Highlights',
                      const HighlightsScreen(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _choice(
                    title: 'TV Channels',
                    subtitle: 'Live TV channels from around the world.',
                    icon: Icons.live_tv_rounded,
                    accent: const Color(0xFFB16CFF),
                    onTap: () => _openPage('TV Channels', const TvScreen()),
                  ),
                  const SizedBox(height: 10),
                  _choice(
                    title: 'Latest Movies',
                    subtitle: 'New movies and series to watch.',
                    icon: Icons.movie_outlined,
                    accent: const Color(0xFF6C8CFF),
                    onTap: () =>
                        _openPage('Latest Movies', const MoviesScreen()),
                  ),
                  const SizedBox(height: 10),
                  _choice(
                    title: 'Join Community Trend',
                    subtitle: 'Share your take, post photos, follow fans.',
                    icon: Icons.forum_rounded,
                    accent: Ui.redSoft,
                    onTap: () => _open('community'),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      'Let’s Go Deep!',
                      style: TextStyle(
                        color: Ui.dim,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Log out'),
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
}
