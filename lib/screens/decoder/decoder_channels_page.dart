import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../models/channel.dart';
import '../../services/cast_service.dart';
import '../../services/feed_service.dart';
import '../../services/stream_resolver.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';
import 'stream_finder_page.dart';

enum _Filter { all, direct, page, ready }

class _Info {
  final ResolvedStream resolved;
  bool? found; // web pages only: true = a stream was found by the quick scan
  _Info(this.resolved);
  bool get direct => resolved.usesHtmlPlayer;
}

/// Supported channels: every channel with how it can be sent to Kodi, a TV or
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
      await chooseConnectivity(context, t);
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

  @override
  Widget build(BuildContext context) {
    final shown = _all.where(_matches).toList();
    final direct = _all.where((c) => _info[c.url]?.direct ?? false).length;
    final ready = _all.where((c) => !(_info[c.url]?.direct ?? false) && _info[c.url]?.found == true).length;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Supported channels', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Scan channels',
            onPressed: _scanning || _loading ? null : _scan,
            icon: const Icon(Icons.radar),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search channels'),
                ),
              ),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final e in const {
                      _Filter.all: 'All',
                      _Filter.direct: 'Direct',
                      _Filter.page: 'Web page',
                      _Filter.ready: 'Ready',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _scanning
                          ? 'Scanning web pages… $_scanned / $_toScan'
                          : '$direct direct · $ready checked ready · ${_all.length} total',
                      style: TextStyle(color: Ui.muted, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.radar, size: 18),
                    label: const Text('Scan'),
                  ),
                ]),
              ),
              if (_scanning) LinearProgressIndicator(value: _toScan == 0 ? null : _scanned / _toScan, minHeight: 2),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text('No channels here.', style: TextStyle(color: Ui.muted)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final c = shown[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Ui.panel,
                              backgroundImage: (c.logo ?? '').isEmpty ? null : NetworkImage(c.logo!),
                              onBackgroundImageError: (c.logo ?? '').isEmpty ? null : (_, _) {},
                              child: (c.logo ?? '').isEmpty ? Icon(c.category.icon, size: 18, color: Ui.muted) : null,
                            ),
                            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(c.category.label, style: TextStyle(color: Ui.muted, fontSize: 11)),
                            trailing: _badge(_info[c.url]),
                            onTap: () => _open(c),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
