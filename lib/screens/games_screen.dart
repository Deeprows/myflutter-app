import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const _gold = Color(0xFFFFC857), _red = Color(0xFFFF4566), _green = Color(0xFF35C98A), _blue = Color(0xFF55A8FF), _purple = Color(0xFFB38BFF);

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});
  @override Widget build(BuildContext context) {
    final games = [
      ('LUDO','Race your tokens home. Roll the dice and capture rivals.',Icons.casino_rounded,_red,const _Ludo()),
      ('SNAKES & LADDERS','Climb ladders, dodge snakes and reach 100.',Icons.stairs_rounded,_green,const _Snakes()),
      ('CARROM','Aim, strike and pocket the coins.',Icons.circle_outlined,_gold,const _Carrom()),
      ('CHESS','Classic strategy. Move pieces and outplay your opponent.',Icons.grid_4x4_rounded,_blue,const _Chess()),
      ('CHECKERS','Jump, capture and crown your pieces.',Icons.apps_rounded,_purple,const _Checkers()),
    ];
    return Scaffold(backgroundColor:Ui.bg,appBar:AppBar(title:const Text('Deeprowss Games',style:TextStyle(fontWeight:FontWeight.w900)),backgroundColor:Ui.bg,foregroundColor:Ui.text),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xFF30233F),Color(0xFF151B2A),Color(0xFF10141B)]),border:Border.all(color:_gold.withValues(alpha:.3))),
          child:const Row(children:[Icon(Icons.sports_esports_rounded,color:_gold,size:42),SizedBox(width:15),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('GAME NIGHT',style:TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900,letterSpacing:1)),SizedBox(height:5),Text('Five classics. One place to play. Challenge a friend.',style:TextStyle(color:Color(0xFFBBC3D2),fontSize:12,height:1.4))]))])),
        const SizedBox(height:24),Text('CHOOSE YOUR GAME',style:TextStyle(color:Ui.muted,fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.5)),const SizedBox(height:12),
        for(final g in games) ...[
          Material(color:Ui.card,borderRadius:BorderRadius.circular(20),child:InkWell(borderRadius:BorderRadius.circular(20),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>g.$5)),
            child:Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),border:Border.all(color:Ui.line)),child:Row(children:[
              Container(width:66,height:66,decoration:BoxDecoration(color:g.$4.withValues(alpha:.15),borderRadius:BorderRadius.circular(18)),child:Icon(g.$3,color:g.$4,size:34)),const SizedBox(width:14),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(g.$1,style:TextStyle(color:g.$4,fontSize:14,fontWeight:FontWeight.w900,letterSpacing:.5)),const SizedBox(height:5),Text(g.$2,style:TextStyle(color:Ui.muted,fontSize:11,height:1.35))])),
              Icon(Icons.arrow_forward_ios_rounded,color:Ui.muted,size:16)
            ])))),
          const SizedBox(height:12)
        ]
      ])));
  }
}

class _BoardPage extends StatelessWidget {
  final String title,help; final Color accent; final Widget board,controls;
  const _BoardPage({required this.title,required this.help,required this.accent,required this.board,required this.controls});
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Ui.bg,appBar:AppBar(title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),backgroundColor:Ui.bg,foregroundColor:Ui.text),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(14),children:[
      Row(children:[Container(width:4,height:34,decoration:BoxDecoration(color:accent,borderRadius:BorderRadius.circular(4))),const SizedBox(width:10),Expanded(child:Text(help,style:TextStyle(color:Ui.muted,fontSize:12)))]),
      const SizedBox(height:14),board,const SizedBox(height:14),controls
    ])));
}
Widget _box(Widget child)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Ui.card,borderRadius:BorderRadius.circular(17),border:Border.all(color:Ui.line)),child:child);
Widget _btn(String label,VoidCallback action,Color color)=>SizedBox(width:double.infinity,child:FilledButton(onPressed:action,style:FilledButton.styleFrom(backgroundColor:color,foregroundColor:const Color(0xFF10141B),padding:const EdgeInsets.symmetric(vertical:15),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(13))),child:Text(label,style:const TextStyle(fontWeight:FontWeight.w900,letterSpacing:.6))));

class _Ludo extends StatefulWidget { const _Ludo(); @override State<_Ludo> createState()=>_LudoState(); }
class _LudoState extends State<_Ludo>{
 final rng=Random(); final colors=[_red,_green,_gold,_blue]; final labels=['RED','GREEN','YELLOW','BLUE'];
 List<List<int>> pos=List.generate(4,(_)=>List.filled(4,-1)); int turn=0,dice=0,players=4; bool rolled=false; String status='Roll a six to bring a token out.';
 void reset(){pos=List.generate(4,(_)=>List.filled(4,-1));turn=0;dice=0;rolled=false;status='Roll a six to bring a token out.';}
 void roll(){if(rolled)return;setState((){dice=rng.nextInt(6)+1;rolled=true;status=dice==6?'Six! Tap one of your tokens.':'Tap a token to move.';});}
 void move(int t){if(!rolled)return;setState((){if(pos[turn][t]<0&&dice!=6){status='You need a six to leave base.';return;}pos[turn][t]=pos[turn][t]<0?0:min(56,pos[turn][t]+dice);status=pos[turn].every((v)=>v==56)?labels[turn]+' WINS!':'Moved '+dice.toString()+' spaces.';if(!status.contains('WINS')){if(dice!=6)turn=(turn+1)%players;}rolled=false;dice=0;});}
 @override Widget build(BuildContext context)=>_BoardPage(title:'Ludo',help:'A four-colour race • Tap your token after rolling.',accent:_red,
 board:Column(children:[
  Row(children:[Expanded(child:_box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('PLAYERS',style:TextStyle(color:Ui.muted,fontSize:10,fontWeight:FontWeight.w900)),Wrap(spacing:4,children:[2,3,4].map((v)=>ChoiceChip(label:Text(v.toString()),selected:players==v,onSelected:(_)=>setState((){players=v;reset();}),selectedColor:_red,backgroundColor:Ui.panel,labelStyle:TextStyle(color:Ui.text))).toList())])),const SizedBox(width:8),Expanded(child:_box(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('TURN',style:TextStyle(color:Ui.muted,fontSize:10,fontWeight:FontWeight.w900)),const SizedBox(height:7),Text(labels[turn],style:TextStyle(color:colors[turn],fontWeight:FontWeight.w900,fontSize:18))])))]),
  const SizedBox(height:10),
  AspectRatio(aspectRatio:1,child:Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:const Color(0xFFE8E1D2),borderRadius:BorderRadius.circular(16)),child:GridView.builder(physics:const NeverScrollableScrollPhysics(),itemCount:225,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:15),itemBuilder:(c,i){final x=i%15,y=i~/15;Color color=const Color(0xFFF8F2E7);if(x<6&&y<6)color=const Color(0xFFFFDCE2);if(x>8&&y<6)color=const Color(0xFFDDF4E7);if(x<6&&y>8)color=const Color(0xFFFFEBC5);if(x>8&&y>8)color=const Color(0xFFDDEBFF);if(x>=6&&x<=8||y>=6&&y<=8)color=const Color(0xFFF9F5EA);if(x==7&&y==7)color=const Color(0xFF30394A);return Container(margin:const EdgeInsets.all(.5),decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(2)),child:x==7&&y==7?const Icon(Icons.star,color:_gold,size:12):null);}))),
  ]),
 controls:_box(Column(children:[Text(status,style:TextStyle(color:Ui.text,fontWeight:FontWeight.w700)),const SizedBox(height:12),Row(children:[Expanded(child:_btn(dice==0?'🎲  ROLL DICE':'DICE: '+dice.toString(),roll,_red)),const SizedBox(width:8),Expanded(child:_btn('NEW GAME',()=>setState(reset),Ui.panel))]),const SizedBox(height:10),Wrap(spacing:9,runSpacing:9,children:[for(var p=0;p<players;p++)for(var t=0;t<4;t++)GestureDetector(onTap:()=>p==turn?move(t):null,child:Container(width:45,height:45,decoration:BoxDecoration(color:colors[p].withValues(alpha:.17),borderRadius:BorderRadius.circular(12),border:Border.all(color:colors[p])),child:Center(child:Text(pos[p][t]<0?'●':pos[p][t].toString(),style:TextStyle(color:colors[p],fontWeight:FontWeight.w900)))))] )])));
}

class _Snakes extends StatefulWidget { const _Snakes(); @override State<_Snakes> createState()=>_SnakesState(); }
class _SnakesState extends State<_Snakes>{
 final rng=Random(); final spots=[0,0]; final jumps={4:25,13:46,33:49,42:63,50:69,62:81,74:92,99:41,95:75,89:53,66:45,54:31,40:3,27:5}; int turn=0,dice=0;String status='Player 1 rolls first.';
 void roll(){final r=rng.nextInt(6)+1;setState((){dice=r;final next=spots[turn]+r;if(next<=100){spots[turn]=jumps[next]??next;status=jumps.containsKey(next)?(jumps[next]!>next?'Ladder! Climb up.':'Snake! Slide down.'):'Player '+(turn+1).toString()+' moved.';if(spots[turn]==100)status='PLAYER '+(turn+1).toString()+' WINS!';}else{status='Exact number needed to reach 100.';}if(spots[turn]!=100)turn=1-turn;});}
 void reset(){spots[0]=0;spots[1]=0;turn=0;dice=0;status='Player 1 rolls first.';}
 @override Widget build(BuildContext context)=>_BoardPage(title:'Snakes & Ladders',help:'Race to square 100. Ladders take you up; snakes slide you down.',accent:_green,
 board:Column(children:[Row(children:[for(var p=0;p<2;p++)Expanded(child:Padding(padding:EdgeInsets.only(right:p==0?6:0,left:p==1?6:0),child:_box(Column(children:[Text('PLAYER '+(p+1).toString(),style:TextStyle(color:p==0?_red:_blue,fontWeight:FontWeight.w900,fontSize:11)),Text(spots[p].toString()+' / 100',style:TextStyle(color:Ui.text,fontWeight:FontWeight.w900,fontSize:24))])))]),const SizedBox(height:10),
 AspectRatio(aspectRatio:1,child:Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:const Color(0xFF18332F),borderRadius:BorderRadius.circular(15)),child:GridView.builder(physics:const NeverScrollableScrollPhysics(),itemCount:100,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:10),itemBuilder:(c,i){final row=i~/10,col=i%10,n=(9-row)*10+(row.isEven?col+1:10-col),jump=jumps[n];return Container(margin:const EdgeInsets.all(1),decoration:BoxDecoration(color:jump!=null?(jump>n?_green.withValues(alpha:.3):_red.withValues(alpha:.3)):((row+col).isEven?const Color(0xFF29443E):const Color(0xFF203A35)),borderRadius:BorderRadius.circular(3)),child:Stack(children:[Positioned(left:2,top:1,child:Text(n.toString(),style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.bold))),if(jump!=null)Center(child:Icon(jump>n?Icons.stairs:Icons.south,color:jump>n?_green:_red,size:16)),if(spots.contains(n))Align(alignment:Alignment.bottomRight,child:Icon(Icons.circle,color:spots[0]==n?_red:_blue,size:12))]));}))) ]),
 controls:_box(Column(children:[Text(status,style:TextStyle(color:Ui.text,fontWeight:FontWeight.w700)),const SizedBox(height:10),Row(children:[Expanded(child:_btn('🎲  PLAYER '+(turn+1).toString()+' ROLL',roll,_green)),const SizedBox(width:8),Expanded(child:_btn('RESET',()=>setState(reset),Ui.panel))]),if(dice>0)Padding(padding:const EdgeInsets.only(top:8),child:Text('Dice: '+dice.toString(),style:TextStyle(color:Ui.muted,fontWeight:FontWeight.w800)))])));
}

class _Carrom extends StatefulWidget { const _Carrom(); @override State<_Carrom> createState()=>_CarromState(); }
class _CarromState extends State<_Carrom>{
 final coins=<Offset>[];Offset striker=const Offset(.5,.82);Offset? drag;int score=0;String status='Drag the striker back and release to shoot.';
 void rack(){coins.clear();for(var y=0;y<3;y++)for(var x=0;x<3;x++)if(x!=1||y!=1)coins.add(Offset(.5+(x-1)*.055,.48+(y-1)*.055));coins.add(const Offset(.5,.48));striker=const Offset(.5,.82);score=0;}
 @override void initState(){super.initState();rack();}
 void shoot(Offset p){setState((){final pull=striker-p; if(pull.distance>.025){final target=striker+pull*.9;var best=-1;var dist=.1;for(var i=0;i<coins.length;i++){final d=(coins[i]-target).distance;if(d<dist){dist=d;best=i;}}if(best>=0){coins.removeAt(best);score++;status='Coin pocketed! Keep playing.';}else{status='Missed. Adjust your aim and try again.';}striker=Offset((striker.dx+pull.dx*.4).clamp(.15,.85),(striker.dy+pull.dy*.4).clamp(.15,.85));}});}
 @override Widget build(BuildContext context)=>_BoardPage(title:'Carrom',help:'Drag from the striker towards the coins to take your shot.',accent:_gold,
 board:Column(children:[Row(children:[Expanded(child:_box(Column(children:[Text('POCKETED',style:TextStyle(color:Ui.muted,fontSize:10)),Text(score.toString(),style:TextStyle(color:Ui.text,fontSize:25,fontWeight:FontWeight.w900))]))),const SizedBox(width:8),Expanded(child:_box(Column(children:[Text('COINS LEFT',style:TextStyle(color:Ui.muted,fontSize:10)),Text(coins.length.toString(),style:TextStyle(color:Ui.text,fontSize:25,fontWeight:FontWeight.w900))]))) ]),const SizedBox(height:10),
 AspectRatio(aspectRatio:1,child:LayoutBuilder(builder:(c,box){final size=Size(box.maxWidth,box.maxWidth);return GestureDetector(onPanUpdate:(d)=>drag=d.localPosition,onPanEnd:(d){if(drag!=null)shoot(Offset(drag!.dx/size.width,drag!.dy/size.height));drag=null;},child:Container(decoration:BoxDecoration(color:const Color(0xFFC58C55),borderRadius:BorderRadius.circular(17),border:Border.all(color:const Color(0xFFE7BB85),width:6)),child:Stack(children:[
 Positioned.fill(child:Padding(padding:const EdgeInsets.all(22),child:Container(decoration:BoxDecoration(border:Border.all(color:const Color(0xFF75482D),width:2),borderRadius:BorderRadius.circular(8))))),
 for(final p in [const Offset(.1,.1),const Offset(.9,.1),const Offset(.1,.9),const Offset(.9,.9)])Positioned(left:p.dx*size.width-13,top:p.dy*size.height-13,child:Container(width:26,height:26,decoration:const BoxDecoration(color:Color(0xFF261914),shape:BoxShape.circle))),
 for(final p in coins)Positioned(left:p.dx*size.width-9,top:p.dy*size.height-9,child:Container(width:18,height:18,decoration:BoxDecoration(color:p==const Offset(.5,.48)?_red:const Color(0xFFF5E6C8),shape:BoxShape.circle,border:Border.all(color:const Color(0xFF5B3A26),width:2)))),
 Positioned(left:striker.dx*size.width-15,top:striker.dy*size.height-15,child:Container(width:30,height:30,decoration:BoxDecoration(color:_blue,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3))))
 ])));})),]),
 controls:_box(Column(children:[Text(status,style:TextStyle(color:Ui.text,fontWeight:FontWeight.w700)),const SizedBox(height:10),_btn('RESET CARROM BOARD',()=>setState(rack),_gold)])));
}

class _Chess extends StatefulWidget { const _Chess(); @override State<_Chess> createState()=>_ChessState(); }
class _ChessState extends State<_Chess>{
 late List<String> b;int? selected;bool white=true;String status='White to move.';
 void reset(){b='rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR'.split('');selected=null;white=true;status='White to move.';}
 @override void initState(){super.initState();reset();}
 bool own(String p)=>p!='.'&&(p.toUpperCase()==p)==white;
 bool valid(int a,int z){final p=b[a],q=b[z];if(p=='.'||(q!='.'&&own(q)))return false;final x=a%8,y=a~/8,tx=z%8,ty=z~/8,dx=tx-x,dy=ty-y,k=p.toUpperCase();if(k=='N')return(dx.abs()==1&&dy.abs()==2)||(dx.abs()==2&&dy.abs()==1);if(k=='K')return dx.abs()<=1&&dy.abs()<=1;if(k=='P'){final d=p==p.toUpperCase()?-1:1;return(dx==0&&q=='.'&&dy==d)||(dx==0&&q=='.'&&dy==2*d&&(y==6||y==1)&&b[(y+d)*8+x]=='.')||(dx.abs()==1&&dy==d&&q!='.');}final line=k=='R'?(dx==0||dy==0):k=='B'?dx.abs()==dy.abs():(dx==0||dy==0||dx.abs()==dy.abs());if(!line||(dx==0&&dy==0))return false;final sx=dx.sign,sy=dy.sign;var cx=x+sx,cy=y+sy;while(cx!=tx||cy!=ty){if(b[cy*8+cx]!='.')return false;cx+=sx;cy+=sy;}return true;}
 void tap(int i){setState((){if(selected==null){if(own(b[i]))selected=i;return;}if(selected==i){selected=null;return;}if(valid(selected!,i)){var p=b[selected!];b[i]=p;b[selected!]='.';if(p=='P'&&i<8)b[i]='Q';if(p=='p'&&i>=56)b[i]='q';white=!white;status=white?'White to move.':'Black to move.';}selected=null;});}
 final glyph={'K':'♔','Q':'♕','R':'♖','B':'♗','N':'♘','P':'♙','k':'♚','q':'♛','r':'♜','b':'♝','n':'♞','p':'♟'};
 @override Widget build(BuildContext context)=>_BoardPage(title:'Chess',help:'Tap one of your pieces, then tap a legal destination.',accent:_blue,
 board:Column(children:[_box(Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(white?'WHITE TO MOVE':'BLACK TO MOVE',style:TextStyle(color:white?_blue:_purple,fontWeight:FontWeight.w900)),Text(status,style:TextStyle(color:Ui.muted,fontSize:11))])),const SizedBox(height:10),
 AspectRatio(aspectRatio:1,child:Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:const Color(0xFFB88B60),borderRadius:BorderRadius.circular(14)),child:GridView.builder(physics:const NeverScrollableScrollPhysics(),itemCount:64,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:8),itemBuilder:(c,i)=>GestureDetector(onTap:()=>tap(i),child:Container(decoration:BoxDecoration(color:selected==i?_gold:((i%8+i~/8).isEven?const Color(0xFFF1DDBE):const Color(0xFF916442)),border:Border.all(color:selected==i?Colors.white:Colors.transparent,width:2)),child:Center(child:Text(glyph[b[i]]??'',style:TextStyle(fontSize:32,color:b[i].toUpperCase()==b[i]?Colors.white:const Color(0xFF17202C),shadows:[const Shadow(color:Colors.black54,blurRadius:2)])))))))]),
 controls:_btn('NEW CHESS GAME',()=>setState(reset),_blue)));
}

class _Checkers extends StatefulWidget { const _Checkers(); @override State<_Checkers> createState()=>_CheckersState(); }
class _CheckersState extends State<_Checkers>{
 late List<int> b;int? selected;bool red=true;String status='Red moves first.';
 void reset(){b=List.filled(64,0);for(var y=0;y<3;y++)for(var x=0;x<8;x++)if((x+y).isOdd)b[y*8+x]=-1;for(var y=5;y<8;y++)for(var x=0;x<8;x++)if((x+y).isOdd)b[y*8+x]=1;selected=null;red=true;status='Red moves first.';}
 @override void initState(){super.initState();reset();}
 bool own(int p)=>p!=0&&(p>0)==red;
 void tap(int i){setState((){if(selected==null){if(own(b[i]))selected=i;return;}final from=selected!,dx=i%8-from%8,dy=i~/8-from~/8,p=b[from];if(b[i]==0&&dx.abs()==1&&(p.abs()==2||dy==(red?-1:1))){b[i]=p;b[from]=0;red=!red;status=red?'Red to move.':'Black to move.';}else if(b[i]==0&&dx.abs()==2&&dy.abs()==2){final mid=((from%8+i%8)~/2)+(((from~/8+i~/8)~/2)*8);if(b[mid]!=0&&!own(b[mid])){b[i]=p;b[from]=0;b[mid]=0;red=!red;status='Piece captured!';}}if((red&&i~/8==0)||(!red&&i~/8==7))b[i]=b[i]>0?2:-2;selected=null;});}
 @override Widget build(BuildContext context)=>_BoardPage(title:'Checkers',help:'Move diagonally. Jump over enemy pieces to capture them.',accent:_purple,
 board:Column(children:[_box(Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(red?'RED TO MOVE':'BLACK TO MOVE',style:TextStyle(color:red?_red:Ui.text,fontWeight:FontWeight.w900)),Text(status,style:TextStyle(color:Ui.muted,fontSize:11))])),const SizedBox(height:10),
 AspectRatio(aspectRatio:1,child:Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:const Color(0xFFB58A60),borderRadius:BorderRadius.circular(14)),child:GridView.builder(physics:const NeverScrollableScrollPhysics(),itemCount:64,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:8),itemBuilder:(c,i)=>GestureDetector(onTap:()=>tap(i),child:Container(color:(i%8+i~/8).isOdd?const Color(0xFF68452F):const Color(0xFFE9D2AD),child:b[i]==0?null:Center(child:Container(width:30,height:30,decoration:BoxDecoration(color:b[i]>0?_red:const Color(0xFF252B37),shape:BoxShape.circle,border:Border.all(color:b[i]>0?const Color(0xFFFFB3BE):const Color(0xFF8992A3),width:3)),child:b[i].abs()==2?const Icon(Icons.star,color:_gold,size:17):null))))))]),
 controls:_btn('NEW CHECKERS GAME',()=>setState(reset),_purple)));
}
