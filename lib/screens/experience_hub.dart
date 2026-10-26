import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/ad_scheduler.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pitch_painter.dart';
import 'community_shell_screen.dart';
import 'shell_screen.dart';

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

  Widget _choice({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    bool pitch = false,
  }) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: .23), Ui.card],
            ),
            border: Border.all(color: accent.withValues(alpha: .4)),
          ),
          child: Stack(
            children: [
              if (pitch)
                Positioned(
                  right: -10,
                  top: 4,
                  bottom: 4,
                  width: 160,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PitchPainter(
                        color: accent.withValues(alpha: .14),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(icon, color: accent, size: 29),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_rounded, color: accent),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Ui.muted,
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),
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
      body: SafeArea(
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
                    IconButton(
                      tooltip: 'Log out',
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(
                  'Welcome, $first',
                  style: TextStyle(
                    color: Ui.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your match.\nYour people.',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'The game brings us together.\nChoose where you want to go.',
                  style: TextStyle(color: Ui.muted, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 28),
                _choice(
                  title: 'Watch Live Football',
                  subtitle:
                      'Open live events, find your match and enjoy the action.',
                  icon: Icons.stadium_rounded,
                  accent: const Color(0xFF45D99A),
                  pitch: true,
                  onTap: () => _open('watch'),
                ),
                const SizedBox(height: 16),
                _choice(
                  title: 'Join Community Trend',
                  subtitle:
                      'Share your take. Post photos. Follow fans and join the conversation.',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
