import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const _gold = Color(0xFFFFC857);
const _red = Color(0xFFFF4566);
const _green = Color(0xFF35C98A);
const _blue = Color(0xFF55A8FF);
const _purple = Color(0xFFB38BFF);

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = <_GameInfo>[
      _GameInfo('LUDO', 'Race your tokens home.', Icons.casino_rounded, _red, const _Ludo()),
      _GameInfo('SNAKES & LADDERS', 'Climb ladders and avoid snakes.', Icons.stairs_rounded, _green, const _Snakes()),
      _GameInfo('CARROM', 'Aim, strike and pocket the coins.', Icons.circle_outlined, _gold, const _Carrom()),
      _GameInfo('CHESS', 'Classic strategy for two players.', Icons.grid_4x4_rounded, _blue, const _Chess()),
      _GameInfo('CHECKERS', 'Jump, capture and crown your pieces.', Icons.apps_rounded, _purple, const _Checkers()),
    ];
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text('Deeprowss Games', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Ui.bg,
        foregroundColor: Ui.text,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF30233F), Color(0xFF151B2A)]),
                border: Border.all(color: _gold.withOpacity(.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sports_esports_rounded, color: _gold, size: 40),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GAME NIGHT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                        SizedBox(height: 5),
                        Text('Five classics. One place to play.', style: TextStyle(color: Color(0xFFBBC3D2), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('CHOOSE YOUR GAME', style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
            const SizedBox(height: 12),
            for (final game in games) ...[
              Material(
                color: Ui.card,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => game.page)),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(color: game.color.withOpacity(.15), borderRadius: BorderRadius.circular(16)),
                          child: Icon(game.icon, color: game.color, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(game.name, style: TextStyle(color: game.color, fontSize: 13, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              Text(game.description, style: TextStyle(color: Ui.muted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Ui.muted, size: 15),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameInfo {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final Widget page;
  const _GameInfo(this.name, this.description, this.icon, this.color, this.page);
}

class _GamePage extends StatelessWidget {
  final String title;
  final String instruction;
  final Color accent;
  final Widget board;
  final Widget controls;
  const _GamePage({required this.title, required this.instruction, required this.accent, required this.board, required this.controls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), backgroundColor: Ui.bg, foregroundColor: Ui.text),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                Container(width: 4, height: 34, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 10),
                Expanded(child: Text(instruction, style: TextStyle(color: Ui.muted, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 14),
            board,
            const SizedBox(height: 14),
            controls,
          ],
        ),
      ),
    );
  }
}

Widget _panel(Widget child) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(color: Ui.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Ui.line)),
  child: child,
);

Widget _action(String label, VoidCallback onPressed, Color color) => SizedBox(
  width: double.infinity,
  child: FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: const Color(0xFF10141B),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
  ),
);

class _Ludo extends StatefulWidget {
  const _Ludo();
  @override
  State<_Ludo> createState() => _LudoState();
}

class _LudoState extends State<_Ludo> {
  final Random _random = Random();
  final List<Color> _colors = [_red, _green, _gold, _blue];
  final List<String> _names = ['RED', 'GREEN', 'YELLOW', 'BLUE'];
  late List<List<int>> _tokens;
  int _players = 4;
  int _turn = 0;
  int _dice = 0;
  bool _rolled = false;
  String _status = 'Roll a six to bring a token out.';

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _tokens = List.generate(4, (_) => List.filled(4, -1));
    _turn = 0;
    _dice = 0;
    _rolled = false;
    _status = 'Roll a six to bring a token out.';
  }

  void _roll() {
    if (_rolled) return;
    setState(() {
      _dice = _random.nextInt(6) + 1;
      _rolled = true;
      _status = _dice == 6 ? 'Six! Select one of your tokens.' : 'Select a token to move.';
    });
  }

  void _move(int token) {
    if (!_rolled) return;
    setState(() {
      final current = _tokens[_turn][token];
      if (current < 0 && _dice != 6) {
        _status = 'You need a six to leave base.';
        return;
      }
      _tokens[_turn][token] = current < 0 ? 0 : min(56, current + _dice);
      final won = _tokens[_turn].every((value) => value == 56);
      _status = won ? '${_names[_turn]} WINS!' : 'Moved $_dice spaces.';
      if (!won && _dice != 6) _turn = (_turn + 1) % _players;
      _rolled = false;
      _dice = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GamePage(
      title: 'Ludo',
      instruction: 'Take turns rolling the dice and moving your tokens.',
      accent: _red,
      board: Column(
        children: [
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PLAYERS', style: TextStyle(color: Ui.muted, fontSize: 10, fontWeight: FontWeight.w900)),
                Wrap(
                  spacing: 8,
                  children: [2, 3, 4].map((value) => ChoiceChip(
                    label: Text('$value'),
                    selected: _players == value,
                    onSelected: (_) => setState(() { _players = value; _reset(); }),
                  )).toList(),
                ),
                Text('TURN: ${_names[_turn]}', style: TextStyle(color: _colors[_turn], fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: const Color(0xFFE8E1D2), borderRadius: BorderRadius.circular(15)),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 225,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 15),
                itemBuilder: (context, index) {
                  final x = index % 15;
                  final y = index ~/ 15;
                  Color tile = const Color(0xFFF8F2E7);
                  if (x < 6 && y < 6) tile = const Color(0xFFFFDCE2);
                  if (x > 8 && y < 6) tile = const Color(0xFFDDF4E7);
                  if (x < 6 && y > 8) tile = const Color(0xFFFFEBC5);
                  if (x > 8 && y > 8) tile = const Color(0xFFDDEBFF);
                  if ((x >= 6 && x <= 8) || (y >= 6 && y <= 8)) tile = const Color(0xFFF9F5EA);
                  if (x == 7 && y == 7) tile = const Color(0xFF30394A);
                  return Container(
                    margin: const EdgeInsets.all(.5),
                    decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(2)),
                    child: x == 7 && y == 7 ? const Icon(Icons.star, color: _gold, size: 12) : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      controls: _panel(
        Column(
          children: [
            Text(_status, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _action(_rolled ? 'DICE: $_dice' : 'ROLL DICE', _roll, _red)),
                const SizedBox(width: 8),
                Expanded(child: _action('NEW GAME', () => setState(_reset), Ui.panel)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int player = 0; player < _players; player++)
                  for (int token = 0; token < 4; token++)
                    GestureDetector(
                      onTap: player == _turn ? () => _move(token) : null,
                      child: Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(color: _colors[player].withOpacity(.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: _colors[player])),
                        child: Center(child: Text(_tokens[player][token] < 0 ? '●' : '${_tokens[player][token]}', style: TextStyle(color: _colors[player], fontWeight: FontWeight.w900))),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Snakes extends StatefulWidget {
  const _Snakes();
  @override
  State<_Snakes> createState() => _SnakesState();
}

class _SnakesState extends State<_Snakes> {
  final Random _random = Random();
  final List<int> _positions = [0, 0];
  final Map<int, int> _jumps = {4: 25, 13: 46, 33: 49, 42: 63, 50: 69, 62: 81, 74: 92, 99: 41, 95: 75, 89: 53, 66: 45, 54: 31, 40: 3, 27: 5};
  int _turn = 0;
  int _dice = 0;
  String _status = 'Player 1 rolls first.';

  void _reset() {
    _positions[0] = 0;
    _positions[1] = 0;
    _turn = 0;
    _dice = 0;
    _status = 'Player 1 rolls first.';
  }

  void _roll() {
    setState(() {
      _dice = _random.nextInt(6) + 1;
      final landing = _positions[_turn] + _dice;
      if (landing <= 100) {
        _positions[_turn] = _jumps[landing] ?? landing;
        if (_jumps.containsKey(landing)) {
          _status = _jumps[landing]! > landing ? 'Ladder! Climb up.' : 'Snake! Slide down.';
        } else {
          _status = 'Player ${_turn + 1} moved.';
        }
      } else {
        _status = 'You need the exact number to reach 100.';
      }
      if (_positions[_turn] == 100) {
        _status = 'PLAYER ${_turn + 1} WINS!';
      } else {
        _turn = 1 - _turn;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GamePage(
      title: 'Snakes & Ladders',
      instruction: 'Race to 100. Ladders move you up and snakes slide you down.',
      accent: _green,
      board: Column(
        children: [
          Row(
            children: [
              for (int player = 0; player < 2; player++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: player == 0 ? 5 : 0, left: player == 1 ? 5 : 0),
                    child: _panel(Column(children: [
                      Text('PLAYER ${player + 1}', style: TextStyle(color: player == 0 ? _red : _blue, fontWeight: FontWeight.w900)),
                      Text('${_positions[player]} / 100', style: TextStyle(color: Ui.text, fontSize: 23, fontWeight: FontWeight.w900)),
                    ])),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF18332F), borderRadius: BorderRadius.circular(14)),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 100,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 10),
                itemBuilder: (context, index) {
                  final row = index ~/ 10;
                  final col = index % 10;
                  final number = (9 - row) * 10 + (row.isEven ? col + 1 : 10 - col);
                  final destination = _jumps[number];
                  final playerHere = _positions.indexOf(number);
                  return Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: destination != null
                          ? (destination > number ? _green.withOpacity(.3) : _red.withOpacity(.3))
                          : ((row + col).isEven ? const Color(0xFF29443E) : const Color(0xFF203A35)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Stack(
                      children: [
                        Positioned(left: 2, top: 1, child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                        if (destination != null) Center(child: Icon(destination > number ? Icons.stairs : Icons.south, color: destination > number ? _green : _red, size: 15)),
                        if (playerHere >= 0) Align(alignment: Alignment.bottomRight, child: Icon(Icons.circle, color: playerHere == 0 ? _red : _blue, size: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      controls: _panel(Column(children: [
        Text(_status, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _action('PLAYER ${_turn + 1} ROLL  🎲', _roll, _green)),
          const SizedBox(width: 8),
          Expanded(child: _action('RESET', () => setState(_reset), Ui.panel)),
        ]),
        if (_dice > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Dice: $_dice', style: TextStyle(color: Ui.muted, fontWeight: FontWeight.w800))),
      ])),
    );
  }
}

class _Carrom extends StatefulWidget {
  const _Carrom();
  @override
  State<_Carrom> createState() => _CarromState();
}

class _CarromState extends State<_Carrom> {
  final List<Offset> _coins = [];
  Offset _striker = const Offset(.5, .82);
  Offset? _drag;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _rack();
  }

  void _rack() {
    _coins.clear();
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        if (x != 1 || y != 1) _coins.add(Offset(.5 + (x - 1) * .055, .48 + (y - 1) * .055));
      }
    }
    _coins.add(const Offset(.5, .48));
    _striker = const Offset(.5, .82);
    _score = 0;
  }

  void _shoot(Offset point) {
    final pull = _striker - point;
    if (pull.distance < .025) return;
    setState(() {
      final target = _striker + pull * .9;
      int? nearest;
      double distance = .1;
      for (int i = 0; i < _coins.length; i++) {
        final current = (_coins[i] - target).distance;
        if (current < distance) {
          distance = current;
          nearest = i;
        }
      }
      if (nearest != null) {
        _coins.removeAt(nearest);
        _score++;
      }
      _striker = Offset((_striker.dx + pull.dx * .4).clamp(.15, .85), (_striker.dy + pull.dy * .4).clamp(.15, .85));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GamePage(
      title: 'Carrom',
      instruction: 'Drag on the board to aim and release to shoot.',
      accent: _gold,
      board: Column(children: [
        Row(children: [
          Expanded(child: _panel(Column(children: [Text('POCKETED', style: TextStyle(color: Ui.muted, fontSize: 10)), Text('$_score', style: TextStyle(color: Ui.text, fontSize: 24, fontWeight: FontWeight.w900))]))),
          const SizedBox(width: 8),
          Expanded(child: _panel(Column(children: [Text('COINS LEFT', style: TextStyle(color: Ui.muted, fontSize: 10)), Text('${_coins.length}', style: TextStyle(color: Ui.text, fontSize: 24, fontWeight: FontWeight.w900))]))),
        ]),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.maxWidth;
            return GestureDetector(
              onPanUpdate: (details) => _drag = details.localPosition,
              onPanEnd: (_) {
                if (_drag != null) _shoot(Offset(_drag!.dx / size, _drag!.dy / size));
                _drag = null;
              },
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFFC58C55), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE7BB85), width: 6)),
                child: Stack(children: [
                  Positioned.fill(child: Padding(padding: const EdgeInsets.all(22), child: Container(decoration: BoxDecoration(border: Border.all(color: const Color(0xFF75482D), width: 2), borderRadius: BorderRadius.circular(8))))),
                  for (final pocket in [const Offset(.1, .1), const Offset(.9, .1), const Offset(.1, .9), const Offset(.9, .9)])
                    Positioned(left: pocket.dx * size - 13, top: pocket.dy * size - 13, child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: Color(0xFF261914), shape: BoxShape.circle))),
                  for (final coin in _coins)
                    Positioned(left: coin.dx * size - 9, top: coin.dy * size - 9, child: Container(width: 18, height: 18, decoration: BoxDecoration(color: coin == const Offset(.5, .48) ? _red : const Color(0xFFF5E6C8), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF5B3A26), width: 2)))),
                  Positioned(left: _striker.dx * size - 15, top: _striker.dy * size - 15, child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
                ]),
              ),
            );
          }),
        ),
      ]),
      controls: _panel(Column(children: [
        Text(_coins.isEmpty ? 'Board cleared!' : 'Coins remaining: ${_coins.length}', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _action('RESET CARROM BOARD', () => setState(_rack), _gold),
      ])),
    );
  }
}

class _Chess extends StatefulWidget {
  const _Chess();
  @override
  State<_Chess> createState() => _ChessState();
}

class _ChessState extends State<_Chess> {
  late List<String> _board;
  int? _selected;
  bool _whiteTurn = true;
  String _status = 'White to move.';
  final Map<String, String> _pieces = {'K':'♔','Q':'♕','R':'♖','B':'♗','N':'♘','P':'♙','k':'♚','q':'♛','r':'♜','b':'♝','n':'♞','p':'♟'};

  void _reset() {
    _board = 'rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR'.split('');
    _selected = null;
    _whiteTurn = true;
    _status = 'White to move.';
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  bool _own(String piece) => piece != '.' && (piece.toUpperCase() == piece) == _whiteTurn;

  bool _valid(int from, int to) {
    final piece = _board[from];
    final target = _board[to];
    if (piece == '.' || (target != '.' && _own(target))) return false;
    final x = from % 8;
    final y = from ~/ 8;
    final tx = to % 8;
    final ty = to ~/ 8;
    final dx = tx - x;
    final dy = ty - y;
    final kind = piece.toUpperCase();
    if (kind == 'N') return (dx.abs() == 1 && dy.abs() == 2) || (dx.abs() == 2 && dy.abs() == 1);
    if (kind == 'K') return dx.abs() <= 1 && dy.abs() <= 1 && (dx != 0 || dy != 0);
    if (kind == 'P') {
      final direction = piece == 'P' ? -1 : 1;
      return (dx == 0 && target == '.' && dy == direction) ||
          (dx == 0 && target == '.' && dy == 2 * direction && (y == 6 || y == 1) && _board[(y + direction) * 8 + x] == '.') ||
          (dx.abs() == 1 && dy == direction && target != '.');
    }
    final straight = dx == 0 || dy == 0;
    final diagonal = dx.abs() == dy.abs();
    final slides = kind == 'R' ? straight : kind == 'B' ? diagonal : straight || diagonal;
    if (!slides || (dx == 0 && dy == 0)) return false;
    final sx = dx.sign;
    final sy = dy.sign;
    int cx = x + sx;
    int cy = y + sy;
    while (cx != tx || cy != ty) {
      if (_board[cy * 8 + cx] != '.') return false;
      cx += sx;
      cy += sy;
    }
    return true;
  }

  void _tap(int index) {
    setState(() {
      if (_selected == null) {
        if (_own(_board[index])) _selected = index;
        return;
      }
      if (_selected == index) {
        _selected = null;
        return;
      }
      if (_valid(_selected!, index)) {
        final piece = _board[_selected!];
        _board[index] = piece;
        _board[_selected!] = '.';
        if (piece == 'P' && index < 8) _board[index] = 'Q';
        if (piece == 'p' && index >= 56) _board[index] = 'q';
        _whiteTurn = !_whiteTurn;
        _status = _whiteTurn ? 'White to move.' : 'Black to move.';
      }
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GamePage(
      title: 'Chess',
      instruction: 'Tap a piece, then tap its destination square.',
      accent: _blue,
      board: Column(children: [
        _panel(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_whiteTurn ? 'WHITE TO MOVE' : 'BLACK TO MOVE', style: TextStyle(color: _whiteTurn ? _blue : _purple, fontWeight: FontWeight.w900)),
          Text(_status, style: TextStyle(color: Ui.muted, fontSize: 11)),
        ])),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFFB88B60), borderRadius: BorderRadius.circular(14)),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 64,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _tap(index),
                child: Container(
                  decoration: BoxDecoration(color: _selected == index ? _gold : ((index % 8 + index ~/ 8).isEven ? const Color(0xFFF1DDBE) : const Color(0xFF916442))),
                  child: Center(child: Text(_pieces[_board[index]] ?? '', style: TextStyle(fontSize: 30, color: _board[index].toUpperCase() == _board[index] ? Colors.white : const Color(0xFF17202C)))),
                ),
              ),
            ),
          ),
        ),
      ]),
      controls: _action('NEW CHESS GAME', () => setState(_reset), _blue),
    );
  }
}

class _Checkers extends StatefulWidget {
  const _Checkers();
  @override
  State<_Checkers> createState() => _CheckersState();
}

class _CheckersState extends State<_Checkers> {
  late List<int> _board;
  int? _selected;
  bool _redTurn = true;
  String _status = 'Red moves first.';

  void _reset() {
    _board = List.filled(64, 0);
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 8; x++) {
        if ((x + y).isOdd) _board[y * 8 + x] = -1;
      }
    }
    for (int y = 5; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        if ((x + y).isOdd) _board[y * 8 + x] = 1;
      }
    }
    _selected = null;
    _redTurn = true;
    _status = 'Red moves first.';
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  bool _own(int piece) => piece != 0 && (piece > 0) == _redTurn;

  void _tap(int index) {
    setState(() {
      if (_selected == null) {
        if (_own(_board[index])) _selected = index;
        return;
      }
      final from = _selected!;
      final dx = index % 8 - from % 8;
      final dy = index ~/ 8 - from ~/ 8;
      final piece = _board[from];
      if (_board[index] == 0 && dx.abs() == 1 && (piece.abs() == 2 || dy == (_redTurn ? -1 : 1))) {
        _board[index] = piece;
        _board[from] = 0;
        _redTurn = !_redTurn;
        _status = _redTurn ? 'Red to move.' : 'Black to move.';
      } else if (_board[index] == 0 && dx.abs() == 2 && dy.abs() == 2) {
        final middle = ((from % 8 + index % 8) ~/ 2) + (((from ~/ 8 + index ~/ 8) ~/ 2) * 8);
        if (_board[middle] != 0 && !_own(_board[middle])) {
          _board[index] = piece;
          _board[from] = 0;
          _board[middle] = 0;
          _redTurn = !_redTurn;
          _status = 'Piece captured!';
        }
      }
      if ((_redTurn && index ~/ 8 == 0) || (!_redTurn && index ~/ 8 == 7)) {
        _board[index] = _board[index] > 0 ? 2 : -2;
      }
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GamePage(
      title: 'Checkers',
      instruction: 'Move diagonally and jump over your opponent to capture.',
      accent: _purple,
      board: Column(children: [
        _panel(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_redTurn ? 'RED TO MOVE' : 'BLACK TO MOVE', style: TextStyle(color: _redTurn ? _red : Ui.text, fontWeight: FontWeight.w900)),
          Text(_status, style: TextStyle(color: Ui.muted, fontSize: 11)),
        ])),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: const Color(0xFFB58A60), borderRadius: BorderRadius.circular(14)),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 64,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _tap(index),
                child: Container(
                  color: (index % 8 + index ~/ 8).isOdd ? const Color(0xFF68452F) : const Color(0xFFE9D2AD),
                  child: _board[index] == 0 ? null : Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: _board[index] > 0 ? _red : const Color(0xFF252B37), shape: BoxShape.circle, border: Border.all(color: _board[index] > 0 ? const Color(0xFFFFB3BE) : const Color(0xFF8992A3), width: 3)),
                      child: _board[index].abs() == 2 ? const Icon(Icons.star, color: _gold, size: 17) : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
      controls: _action('NEW CHECKERS GAME', () => setState(_reset), _purple),
    );
  }
}
