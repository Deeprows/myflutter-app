import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../models/channel.dart';
import '../../services/cast_service.dart';
import '../../services/feed_service.dart';
import '../../services/stream_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_channel.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';
import 'stream_finder_page.dart';

const _cardHeight = 40.0;
const _rowCardWidth = 140.0;

enum _Filter { all, direct, page, ready }

class _Info {
  final ResolvedStream resolved;
  bool? found; // web pages only: true = a stream was found by the quick scan
  _Info(this.resolved);
  bool get direct => resolved.usesHtmlPlayer;
}

/// TV Channels: every channel, to watch in the app or send to Kodi, a TV or
/// the receiver page. Tap one to choose how to watch it.
class DecoderChannelsPage extends StatefulWidget {
  /// 'receiver' skips the question and sends straight to the receiver page.
  final String? only;
  const DecoderChannelsPage({super.key, this.only});

  @override
  State<DecoderChannelsPage> createState() => _DecoderChannelsPageState();
}

class _DecoderChannelsPageState extends State<DecoderChannelsPage> {
  List<Channel> _all = const [];
  final Map<String, _Info> _info = {};
  bool _loading = true;
  bool _scanning = false;
  int _scanned = 0;
  int _toScan = 0;
  String _query = '';
  _Filter _filter = _Filter.all;
  ChannelCategory? _expandedCategory;
  static const int _previewLimit = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await feed.loadChannels(remote: true);
    for (final c in list) {
      _info[c.url] = _Info(StreamResolver.resolve(c.url));
      final cached = StreamFinderPage.cache[c.url];
      if (cached != null) _info[c.url]!.found = true;
    }
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final pages = _all.where((c) => !(_info[c.url]?.direct ?? true) && _info[c.url]?.found == null).toList();
    if (pages.isEmpty) {
      decoderToast(context, 'Every channel has been checked.');
      return;
    }
    setState(() {
      _scanning = true;
      _scanned = 0;
      _toScan = pages.length;
    });
    final svc = CastService.instance;
    var next = 0;
    Future<void> worker() async {
      while (mounted && next < pages.length) {
        final c = pages[next++];
        final r = await svc.resolveStream(c.url, referer: c.referer, userAgent: c.userAgent);
        _info[c.url]?.found = r != null;
        if (mounted) setState(() => _scanned++);
      }
    }

    await Future.wait(List.generate(5, (_) => worker()));
    if (!mounted) return;
    setState(() => _scanning = false);
    decoderToast(context, 'Scan finished.');
  }

  CastTarget _target(Channel c) {
    final r = _info[c.url]?.resolved ?? StreamResolver.resolve(c.url);
    return CastTarget(
      title: c.name,
      url: r.url,
      kind: r.kind,
      referer: c.referer,
      userAgent: c.userAgent,
    );
  }

  Future<void> _open(Channel c) async {
    final t = _target(c);
    if (widget.only == 'receiver') {
      await sendToReceiver(context, t);
    } else {
      await chooseConnectivity(context, t, onWatchInApp: () => openChannelPlayer(context, c));
    }
  }

  bool _matches(Channel c) {
    if (_query.isNotEmpty && !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
    final i = _info[c.url];
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.direct:
        return i?.direct ?? false;
      case _Filter.page:
        return !(i?.direct ?? false);
      case _Filter.ready:
        return (i?.direct ?? false) || i?.found == true;
    }
  }

  Widget _badge(_Info? i) {
    String text;
    Color color;
    if (i == null) {
      text = '…';
      color = Ui.muted;
    } else if (i.direct) {
      text = 'Direct';
      color = Colors.green;
    } else if (i.found == true) {
      text = 'Ready';
      color = Colors.green;
    } else if (i.found == false) {
      text = 'Finder';
      color = Colors.amber;
    } else {
      text = 'Web page';
      color = Colors.amber;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  // Same compact card as the TV Channels page: round logo, scrolling name.
  Widget _channelCard(Channel c, {bool compact = false}) => SizedBox(
    height: _cardHeight,
    child: Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.red.withValues(alpha: .8), width: 1.2),
        ),
        child: InkWell(
          onTap: () => _open(c),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
            child: Row(children: [
              _DecoderLogo(channel: c),
              const SizedBox(width: 5),
              Expanded(child: _MarqueeText(c.name)),
            ]),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shown = _all.where(_matches).toList();
    final direct = _all.where((c) => _info[c.url]?.direct ?? false).length;
    final ready = _all.where((c) => !(_info[c.url]?.direct ?? false) && _info[c.url]?.found == true).length;
    const categories = [ChannelCategory.sports,ChannelCategory.news,ChannelCategory.movies,
      ChannelCategory.entertainment,ChannelCategory.music,ChannelCategory.kids,
      ChannelCategory.documentary,ChannelCategory.lifestyle,ChannelCategory.religious,
      ChannelCategory.general,ChannelCategory.other];
    final visibleCategories = categories.where((c) =>
      shown.any((channel) => channel.category == c) &&
      (_expandedCategory == null || _expandedCategory == c)).toList();

    return Scaffold(backgroundColor: Ui.bg,
      appBar: AppBar(backgroundColor: Ui.panel,
        title: Text(_expandedCategory == null ? 'TV Channels' : _expandedCategory!.label,
          style: const TextStyle(fontWeight: FontWeight.w900)),
        leading: _expandedCategory == null ? null : IconButton(icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _expandedCategory = null)),
        actions: [IconButton(tooltip: 'Scan channels',
          onPressed: _scanning || _loading ? null : _scan, icon: const Icon(Icons.radar))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,6),
          child: TextField(onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search),hintText:'Search channels'))),
        if (_expandedCategory == null)
          SizedBox(height:46,child:ListView(scrollDirection:Axis.horizontal,
            padding:const EdgeInsets.symmetric(horizontal:12),children:[
              for(final e in const {_Filter.all:'All',_Filter.direct:'Direct',_Filter.page:'Web page',_Filter.ready:'Ready'}.entries)
                Padding(padding:const EdgeInsets.symmetric(horizontal:4,vertical:6),
                  child:ChoiceChip(label:Text(e.value),selected:_filter==e.key,
                    onSelected:(_) => setState(()=>_filter=e.key))),
            ])),
        Padding(padding:const EdgeInsets.fromLTRB(16,2,16,6),child:Row(children:[
          Expanded(child:Text(_scanning ? 'Scanning web pages… $_scanned / $_toScan' :
            '$direct direct · $ready checked ready · ' + shown.length.toString() + ' shown',
            style:TextStyle(color:Ui.muted,fontSize:12))),
          TextButton.icon(onPressed:_scanning?null:_scan,
            icon:const Icon(Icons.radar,size:18),label:const Text('Scan')),
        ])),
        if(_scanning) LinearProgressIndicator(value:_toScan==0?null:_scanned/_toScan,minHeight:2),
        Expanded(child:shown.isEmpty ? Center(child:Text('No channels here.',style:TextStyle(color:Ui.muted)))
          : ListView(padding:const EdgeInsets.only(bottom:24),children:[
            if(_expandedCategory!=null)
              Padding(padding:const EdgeInsets.fromLTRB(16,10,16,8),
                child:Align(alignment:Alignment.centerLeft,child:TextButton.icon(
                  onPressed:()=>setState(()=>_expandedCategory=null),
                  icon:const Icon(Icons.arrow_back),label:const Text('All channel categories')))),
            for(final category in visibleCategories)...[
              Padding(padding:const EdgeInsets.fromLTRB(16,15,16,10),
                child:InkWell(onTap:()=>setState(()=>
                  _expandedCategory=_expandedCategory==category?null:category),
                  borderRadius:BorderRadius.circular(14),child:Row(children:[
                    Container(width:42,height:42,decoration:BoxDecoration(
                      color:const Color(0xFF30270D),borderRadius:BorderRadius.circular(13)),
                      child:Icon(category.icon,color:const Color(0xFFFFD34C),size:22)),
                    const SizedBox(width:12),
                    Expanded(child:Text(category.label,style:TextStyle(
                      color:Ui.text,fontSize:20,fontWeight:FontWeight.w900))),
                    Text(shown.where((c)=>c.category==category).length.toString(),
                      style:TextStyle(color:Ui.muted,fontSize:15,fontWeight:FontWeight.w800)),
                    const SizedBox(width:7),
                    Icon(_expandedCategory==category?Icons.expand_less:Icons.chevron_right,
                      color:Ui.muted,size:28),
                  ]))),
              Builder(builder:(context){
                final items=shown.where((c)=>c.category==category).toList();
                if(_expandedCategory==category)
                  return Padding(padding:const EdgeInsets.symmetric(horizontal:16),
                    child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
                      itemCount:items.length,
                      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:2,mainAxisSpacing:10,crossAxisSpacing:10,mainAxisExtent:_cardHeight),
                      itemBuilder:(_,index)=>_channelCard(items[index])));
                return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                  SizedBox(height:_cardHeight,child:ListView.separated(scrollDirection:Axis.horizontal,
                    padding:const EdgeInsets.symmetric(horizontal:16),
                    itemCount:items.length>_previewLimit?_previewLimit:items.length,
                    separatorBuilder:(_,__)=>const SizedBox(width:10),
                    itemBuilder:(_,index)=>SizedBox(width:_rowCardWidth,
                      child:_channelCard(items[index],compact:true)))),
                  if(items.length>_previewLimit)
                    Align(alignment:Alignment.centerRight,
                      child:Padding(padding:const EdgeInsets.only(right:16,top:5),
                        child:TextButton(onPressed:()=>setState(()=>_expandedCategory=category),
                          child:Text('View all '+items.length.toString()+' channels  →',
                            style:const TextStyle(color:Color(0xFFFFD34C),fontWeight:FontWeight.w900))))),
                ]);
              }),
            ],
          ])),
      ]));
  }
}


/// Round channel logo with an accent ring (same as the TV Channels page), or
/// the category icon when there is no logo or it fails to load.
class _DecoderLogo extends StatelessWidget {
  final Channel channel;
  const _DecoderLogo({required this.channel});

  static const _size = 27.0;

  @override
  Widget build(BuildContext context) {
    final url = channel.logo ?? '';
    final icon = Icon(channel.category.icon, color: Ui.redSoft, size: 15);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: url.isEmpty ? Ui.red.withValues(alpha: .16) : Colors.white,
        border: Border.all(color: Ui.red, width: 1.3),
      ),
      child: url.isEmpty
          ? Center(child: icon)
          : ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(2.5),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  cacheWidth: 120,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Center(child: icon),
                ),
              ),
            ),
    );
  }
}

/// Channel name, centred; a long name slowly scrolls sideways so it can be
/// read in full (same behaviour as the TV Channels page).
class _MarqueeText extends StatefulWidget {
  final String text;
  const _MarqueeText(this.text);

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  static const _style =
      TextStyle(fontSize: 12.5, height: 1.1, fontWeight: FontWeight.w800);

  final _scroll = ScrollController();
  bool _alive = true;
  bool _running = false;

  @override
  void dispose() {
    _alive = false;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loop() async {
    if (_running) return;
    _running = true;
    while (_alive) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!_alive || !_scroll.hasClients) break;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) break;
      await _scroll.animateTo(
        max,
        duration: Duration(milliseconds: (max * 28).round().clamp(900, 9000)),
        curve: Curves.linear,
      );
      if (!_alive || !_scroll.hasClients) break;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!_alive || !_scroll.hasClients) break;
      _scroll.jumpTo(0);
    }
    _running = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final overflows = painter.width > box.maxWidth;
        if (!overflows) {
          return Center(
            child: Text(widget.text, maxLines: 1, softWrap: false, style: _style),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loop());
        });
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [
              Color(0x00FFFFFF),
              Colors.white,
              Colors.white,
              Color(0x00FFFFFF),
            ],
            stops: [0, .08, .92, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                heightFactor: 1,
                child: Text(widget.text, maxLines: 1, softWrap: false, style: _style),
              ),
            ),
          ),
        );
      },
    );
  }
}
