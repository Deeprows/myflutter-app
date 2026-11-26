import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

class _Game {
  final String title;
  final String category;
  final String description;
  final String slug;
  final String gameId;
  final IconData icon;
  final bool landscape;

  const _Game({
    required this.title,
    required this.category,
    required this.description,
    required this.slug,
    required this.gameId,
    required this.icon,
    this.landscape = false,
  });

  String get embedUrl =>
      'https://html5.gamedistribution.com/$gameId/?gd_sdk_referrer_url=https://deeprowss.com/games/$slug';
}

/// Dedicated Games area. Each title opens in its own in-app game player.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  static const _categories = ['All', 'Football', 'Racing', 'Arcade'];
  static const _games = <_Game>[
    _Game(
      title: 'Football Superstars 2026',
      category: 'Football',
      description: 'Choose a national team and compete in tournaments.',
      slug: 'football-superstars-2026',
      gameId: 'dba31dd236944415a71960309ff0d1c3',
      icon: Icons.sports_soccer_rounded,
    ),
    _Game(
      title: 'Real Football',
      category: 'Football',
      description: 'Build your dream team and chase the championship.',
      slug: 'real-football',
      gameId: '0e790569b4c74967923678652de3dbc4',
      icon: Icons.stadium_rounded,
      landscape: true,
    ),
    _Game(
      title: 'Soccer Orbit',
      category: 'Arcade',
      description: 'Kick the ball across the galaxy and beat your distance.',
      slug: 'soccer-orbit',
      gameId: 'a442e2eb310a4c64aa9e475a4fdd045d',
      icon: Icons.public_rounded,
    ),
    _Game(
      title: 'Road Race 3D',
      category: 'Racing',
      description: 'Race through challenging tracks and obstacles.',
      slug: 'road-race-3d',
      gameId: '361861cb4a054a2eb13f0087013b4f83',
      icon: Icons.directions_car_rounded,
      landscape: true,
    ),
    _Game(
      title: '3D Super Rolling Ball Race',
      category: 'Racing',
      description: 'Navigate fast 3D tracks and avoid falling.',
      slug: '3d-super-rolling-ball-race',
      gameId: 'c77c8b1ffef242609915d126535b0ca9',
      icon: Icons.sports_esports_rounded,
      landscape: true,
    ),
    _Game(
      title: 'Football Kickoff',
      category: 'Football',
      description: 'Aim, set your power and kick for the goal.',
      slug: 'football-kickoff',
      gameId: '4a13848d5f2d4051a34deda6e5d84d10',
      icon: Icons.sports_score_rounded,
    ),
  ];

  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final visibleGames = _selectedCategory == 'All'
        ? _games
        : _games.where((game) => game.category == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text('Deeprowss Games'),
        backgroundColor: Ui.bg,
        foregroundColor: Ui.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Ui.red.withValues(alpha: .24),
                      Ui.card,
                      Ui.panel,
                    ],
                  ),
                  border: Border.all(color: Ui.red.withValues(alpha: .32)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Ui.red.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.sports_esports_rounded,
                          color: Ui.red, size: 29),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PLAY MORE. HAVE FUN.',
                            style: TextStyle(
                              color: Ui.text,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pick a game and start playing.',
                            style: TextStyle(color: Ui.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = category == _selectedCategory;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = category),
                    selectedColor: Ui.red.withValues(alpha: .22),
                    backgroundColor: Ui.card,
                    side: BorderSide(
                      color: selected ? Ui.red : Ui.line,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? Ui.red : Ui.text,
                      fontWeight: FontWeight.w800,
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                itemCount: visibleGames.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .88,
                ),
                itemBuilder: (context, index) {
                  final game = visibleGames[index];
                  return _GameCard(
                    game: game,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => _GamePlayerScreen(game: game),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final _Game game;
  final VoidCallback onTap;

  const _GameCard({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ui.card,
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: Ui.line),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Ui.red.withValues(alpha: .28),
                        Ui.panel,
                      ],
                    ),
                  ),
                  child: Icon(game.icon, size: 48, color: Ui.red),
                ),
              ),
              const SizedBox(height: 11),
              Text(
                game.category.toUpperCase(),
                style: TextStyle(
                  color: Ui.red,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Ui.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.play_circle_fill_rounded,
                      color: Ui.red, size: 17),
                  const SizedBox(width: 5),
                  Text(
                    'PLAY NOW',
                    style: TextStyle(
                      color: Ui.text,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePlayerScreen extends StatefulWidget {
  final _Game game;

  const _GamePlayerScreen({required this.game});

  @override
  State<_GamePlayerScreen> createState() => _GamePlayerScreenState();
}

class _GamePlayerScreenState extends State<_GamePlayerScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (!mounted || !error.isForMainFrame) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to load this game.')),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.game.embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.game.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Reload game',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
