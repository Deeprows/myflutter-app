import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final games = [
      ('Snake', 'Eat, grow and beat your high score.', Icons.gesture_rounded, const _SnakeGame(), 'ARCADE'),
      ('Tic Tac Toe', 'Play against the computer or a friend.', Icons.grid_3x3_rounded, const _TicGame(), 'VS CPU / 2 PLAYERS'),
    ];
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(title: const Text('Deeprowss Games'), backgroundColor: Ui.bg, foregroundColor: Ui.text),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: [Ui.red.withValues(alpha: .28), Ui.card, Ui.panel]),
            border: Border.all(color: Ui.red.withValues(alpha: .35))),
          child: Row(children: [
            Icon(Icons.sports_esports_rounded, color: Ui.red, size: 40),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PLAY ANYTIME', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 5),
              Text('Quick games. No downloads. Works offline.', style: TextStyle(color: Ui.muted, fontSize: 12)),
            ])),
          ])),
        const SizedBox(height: 22),
        Text('ALL GAMES', style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        for (final game in games) ...[
          Material(color: Ui.card, borderRadius: BorderRadius.circular(18),
            child: InkWell(borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => game.$4)),
              child: Container(padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)),
                child: Row(children: [
                  Container(width: 62, height: 62,
                    decoration: BoxDecoration(color: Ui.red.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)),
                    child: Icon(game.$3, color: Ui.red, size: 32)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(game.$5, style: TextStyle(color: Ui.red, fontSize: 9, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(game.$1, style: TextStyle(color: Ui.text, fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(game.$2, style: TextStyle(color: Ui.muted, fontSize: 11)),
                  ])),
                  Icon(Icons.chevron_right_rounded, color: Ui.muted),
                ])))),
          const SizedBox(height: 12),
        ],
      ])));
  }
}

class _SnakeGame extends StatefulWidget {
  const _SnakeGame();
  @override
  State<_SnakeGame> createState() => _SnakeGameState();
}
class _SnakeGameState extends State<_SnakeGame> {
  static const n = 18;
  final random = Random();
  Timer? timer;
  List<Point<int>> snake = [];
  Point<int> food = const Point(8, 8), direction = const Point(1, 0), next = const Point(1, 0);
  int score = 0;
  bool started = false, over = false;
  @override
  void initState() { super.initState(); reset(); }
  void reset() {
    timer?.cancel();
    snake = [const Point(8, 9), const Point(7, 9), const Point(6, 9)];
    direction = const Point(1, 0); next = direction; score = 0; started = false; over = false;
    placeFood(); setState(() {});
  }
  void placeFood() {
    do { food = Point(random.nextInt(n), random.nextInt(n)); } while (snake.contains(food));
  }
  void start() {
    if (over) reset();
    if (started) return;
    setState(() => started = true);
    timer = Timer.periodic(const Duration(milliseconds: 155), (_) => tick());
  }
  void tick() {
    final head = snake.first;
    final p = Point(head.x + next.x, head.y + next.y);
    final eating = p == food;
    final body = eating ? snake : snake.take(snake.length - 1).toList();
    if (p.x < 0 || p.x >= n || p.y < 0 || p.y >= n || body.contains(p)) {
      timer?.cancel(); setState(() { over = true; started = false; }); return;
    }
    setState(() {
      direction = next; snake = [p, ...snake];
      if (eating) { score += 10; placeFood(); } else { snake.removeLast(); }
    });
  }
  void turn(Point<int> d) {
    if (d.x == -direction.x && d.y == -direction.y) return;
    next = d;
    if (!started && !over) start();
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Ui.bg,
    appBar: AppBar(title: const Text('Snake'), backgroundColor: Ui.bg, foregroundColor: Ui.text),
    body: SafeArea(child: Column(children: [
      const SizedBox(height: 14),
      _ScorePill(score: score),
      const SizedBox(height: 16),
      Expanded(child: Center(child: AspectRatio(aspectRatio: 1, child: GestureDetector(
        onVerticalDragEnd: (d) { final v = d.primaryVelocity ?? 0; if (v < 0) turn(const Point(0,-1)); if (v > 0) turn(const Point(0,1)); },
        onHorizontalDragEnd: (d) { final v = d.primaryVelocity ?? 0; if (v < 0) turn(const Point(-1,0)); if (v > 0) turn(const Point(1,0)); },
        child: Container(margin: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: const Color(0xFF0D1716), borderRadius: BorderRadius.circular(18), border: Border.all(color: Ui.line)),
          child: ClipRRect(borderRadius: BorderRadius.circular(18), child: CustomPaint(
            painter: _SnakePainter(n, snake, food),
            child: !started ? _Overlay(title: over ? 'GAME OVER' : 'SNAKE', subtitle: over ? 'Score: $score' : 'Swipe to move', button: over ? 'PLAY AGAIN' : 'START', onTap: start) : null,
          ))),
      )))),
      Text('Swipe on the board or use the controls', style: TextStyle(color: Ui.muted, fontSize: 12)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _dirButton(Icons.arrow_left, const Point(-1,0), turn),
        _dirButton(Icons.arrow_downward, const Point(0,1), turn),
        _dirButton(Icons.arrow_upward, const Point(0,-1), turn),
        _dirButton(Icons.arrow_right, const Point(1,0), turn),
      ]),
      const SizedBox(height: 20),
    ])));
}
Widget _dirButton(IconData icon, Point<int> d, ValueChanged<Point<int>> onTap) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 3),
  child: IconButton.filledTonal(onPressed: () => onTap(d), icon: Icon(icon),
    style: IconButton.styleFrom(backgroundColor: Ui.card, foregroundColor: Ui.text)));
class _SnakePainter extends CustomPainter {
  final int n; final List<Point<int>> snake; final Point<int> food;
  _SnakePainter(this.n, this.snake, this.food);
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / n;
    final grid = Paint()..color = Colors.white.withValues(alpha: .045)..style = PaintingStyle.stroke;
    for (var i=0; i<=n; i++) {
      canvas.drawLine(Offset(i*cell,0), Offset(i*cell,size.height), grid);
      canvas.drawLine(Offset(0,i*cell), Offset(size.width,i*cell), grid);
    }
    canvas.drawCircle(Offset((food.x+.5)*cell,(food.y+.5)*cell), cell*.34, Paint()..color=const Color(0xFFFFB547));
    for (var i=snake.length-1; i>=0; i--) {
      final p=snake[i];
      final rect=Rect.fromLTWH(p.x*cell+1.5,p.y*cell+1.5,cell-3,cell-3);
      canvas.drawRRect(RRect.fromRectAndRadius(rect,Radius.circular(cell*.24)),
        Paint()..color=i==0?const Color(0xFF8BE0A2):const Color(0xFF28A66A));
    }
  }
  @override
  bool shouldRepaint(covariant _SnakePainter old) => true;
}

class _TicGame extends StatefulWidget {
  const _TicGame();
  @override
  State<_TicGame> createState() => _TicGameState();
}
class _TicGameState extends State<_TicGame> {
  List<String> cells = List.filled(9,'');
  bool xTurn = true, vsCpu = true, draw = false;
  String? winner;
  static const lines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
  String? check(List<String> b) {
    for (final l in lines) { if (b[l[0]].isNotEmpty && b[l[0]]==b[l[1]] && b[l[1]]==b[l[2]]) return b[l[0]]; }
    return null;
  }
  void play(int i) {
    if (cells[i].isNotEmpty || winner!=null || draw) return;
    setState(() { cells[i]=xTurn?'X':'O'; winner=check(cells); draw=winner==null&&cells.every((v)=>v.isNotEmpty); xTurn=!xTurn; });
    if (vsCpu && winner==null && !draw && !xTurn) Future.delayed(const Duration(milliseconds:300), cpu);
  }
  void cpu() {
    if (!mounted || winner!=null || draw) return;
    final free=List.generate(9,(i)=>i).where((i)=>cells[i].isEmpty).toList();
    if (free.isEmpty) return;
    int? move;
    for (final mark in ['O','X']) {
      for (final i in free) { final test=List<String>.from(cells)..[i]=mark; if(check(test)==mark){move=i;break;} }
      if(move!=null) break;
    }
    move ??= cells[4].isEmpty?4:free[Random().nextInt(free.length)];
    setState(() { cells[move!]='O'; winner=check(cells); draw=winner==null&&cells.every((v)=>v.isNotEmpty); xTurn=true; });
  }
  void reset() { setState(() { cells=List.filled(9,''); xTurn=true; winner=null; draw=false; }); }
  @override
  Widget build(BuildContext context) {
    final status = winner != null ? '$winner WINS!' : draw ? 'IT’S A DRAW' : (xTurn ? 'X’S TURN' : 'O’S TURN');
    return Scaffold(backgroundColor: Ui.bg,
      appBar: AppBar(title: const Text('Tic Tac Toe'), backgroundColor: Ui.bg, foregroundColor: Ui.text),
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: Column(children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value:true,label:Text('VS COMPUTER')),ButtonSegment(value:false,label:Text('2 PLAYERS'))],
          selected: {vsCpu}, onSelectionChanged: (v) { setState(() { vsCpu=v.first; cells=List.filled(9,''); xTurn=true; winner=null; draw=false; }); },
          style: SegmentedButton.styleFrom(foregroundColor:Ui.text,selectedForegroundColor:Colors.white,selectedBackgroundColor:Ui.red)),
        const SizedBox(height:26),
        Text(status, style: TextStyle(color:Ui.text,fontSize:20,fontWeight:FontWeight.w900)),
        const SizedBox(height:18),
        AspectRatio(aspectRatio:1,child:GridView.builder(physics:const NeverScrollableScrollPhysics(),itemCount:9,
          gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:9,mainAxisSpacing:9),
          itemBuilder:(_,i)=>Material(color:Ui.card,borderRadius:BorderRadius.circular(17),child:InkWell(
            borderRadius:BorderRadius.circular(17),onTap:()=>play(i),
            child:Center(child:Text(cells[i],style:TextStyle(fontSize:52,fontWeight:FontWeight.w900,color:cells[i]=='X'?Ui.red:const Color(0xFF58C9A5)))))))),
        const SizedBox(height:22),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:reset,icon:const Icon(Icons.refresh),label:const Text('NEW GAME'),
          style:FilledButton.styleFrom(backgroundColor:Ui.red,foregroundColor:Colors.white,padding:const EdgeInsets.all(15)))),
      ])))),
    );
  }
}
class _ScorePill extends StatelessWidget {
  final int score;
  const _ScorePill({required this.score});
  @override
  Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:20,vertical:10),
    decoration:BoxDecoration(color:Ui.card,borderRadius:BorderRadius.circular(12),border:Border.all(color:Ui.line)),
    child:Column(children:[Text('SCORE',style:TextStyle(color:Ui.muted,fontSize:9,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text('$score',style:TextStyle(color:Ui.text,fontSize:17,fontWeight:FontWeight.w900))]));
}
class _Overlay extends StatelessWidget {
  final String title,subtitle,button; final VoidCallback onTap;
  const _Overlay({required this.title,required this.subtitle,required this.button,required this.onTap});
  @override
  Widget build(BuildContext context)=>Container(color:Colors.black.withValues(alpha:.72),
    child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(title,style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w900)),
      const SizedBox(height:7),Text(subtitle,style:const TextStyle(color:Colors.white70,fontSize:13)),
      const SizedBox(height:18),FilledButton(onPressed:onTap,style:FilledButton.styleFrom(backgroundColor:Ui.red),child:Text(button)),
    ])));
}
