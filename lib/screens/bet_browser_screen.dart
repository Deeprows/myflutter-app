import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../theme/app_theme.dart';

/// One betting site shown as a bookmark.
class BetSite {
  final String name;
  final String url;
  final bool custom;
  const BetSite(this.name, this.url, {this.custom = false});

  String get host => Uri.tryParse(url)?.host ?? '';

  Map<String, String> toJson() => {'name': name, 'url': url};
  static BetSite fromJson(Map<String, dynamic> j) =>
      BetSite('${j['name']}', '${j['url']}', custom: true);
}

/// Top betting platforms by region. Opens inside the app; the person logs in
/// on the bookmaker's own page (the app never sees or stores passwords).
const _africa = <BetSite>[
  BetSite('Bet9ja', 'https://www.bet9ja.com'),
  BetSite('SportyBet', 'https://www.sportybet.com'),
  BetSite('BetKing', 'https://www.betking.com'),
  BetSite('1xBet', 'https://1xbet.com'),
  BetSite('Betway', 'https://www.betway.com'),
  BetSite('Betika', 'https://www.betika.com'),
  BetSite('MSport', 'https://www.msport.com'),
  BetSite('Premier Bet', 'https://www.premierbet.com'),
  BetSite('Hollywoodbets', 'https://www.hollywoodbets.net'),
  BetSite('Supabets', 'https://www.supabets.co.za'),
  BetSite('Mozzartbet', 'https://www.mozzartbet.com'),
  BetSite('22Bet', 'https://22bet.com'),
];

const _europe = <BetSite>[
  BetSite('Bet365', 'https://www.bet365.com'),
  BetSite('William Hill', 'https://www.williamhill.com'),
  BetSite('Betfair', 'https://www.betfair.com'),
  BetSite('Paddy Power', 'https://www.paddypower.com'),
  BetSite('Ladbrokes', 'https://www.ladbrokes.com'),
  BetSite('Coral', 'https://www.coral.co.uk'),
  BetSite('Sky Bet', 'https://m.skybet.com'),
  BetSite('Unibet', 'https://www.unibet.com'),
  BetSite('Bwin', 'https://www.bwin.com'),
  BetSite('Betsson', 'https://www.betsson.com'),
  BetSite('Pinnacle', 'https://www.pinnacle.com'),
  BetSite('Betano', 'https://www.betano.com'),
];

const _americas = <BetSite>[
  BetSite('DraftKings', 'https://sportsbook.draftkings.com'),
  BetSite('FanDuel', 'https://sportsbook.fanduel.com'),
  BetSite('BetMGM', 'https://sports.betmgm.com'),
  BetSite('Caesars', 'https://www.caesars.com/sportsbook-and-casino'),
  BetSite('Bovada', 'https://www.bovada.lv'),
  BetSite('Bodog', 'https://www.bodog.eu'),
  BetSite('Betano', 'https://www.betano.com'),
  BetSite('Bet365', 'https://www.bet365.com'),
  BetSite('Betway', 'https://www.betway.com'),
  BetSite('Codere', 'https://www.codere.com'),
  BetSite('Betfair', 'https://www.betfair.com'),
  BetSite('Pinnacle', 'https://www.pinnacle.com'),
];

/// A normal mobile Chrome identity: bookmaker log-in pages often refuse
/// the default "wv" WebView identity.
const _chromeUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

const _prefsKey = 'bet_hub_custom_sites_v1';

/// "Bet Hub": a Chrome-style in-app browser with betting bookmarks.
class BetBrowserScreen extends StatefulWidget {
  const BetBrowserScreen({super.key});

  @override
  State<BetBrowserScreen> createState() => _BetBrowserScreenState();
}

class _BetBrowserScreenState extends State<BetBrowserScreen> {
  final List<WebViewController> _tabs = [];
  final List<String> _tabUrls = [];
  final List<String> _tabTitles = [];
  int _activeTab = 0;
  final List<Map<String, String>> _history = [];
  WebViewController get _wc => _tabs[_activeTab];

  final _addr = TextEditingController();
  final _focus = FocusNode();
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  List<BetSite> _custom = [];
  bool _home = true;
  bool _canBack = false;
  bool _canFwd = false;
  bool _error = false;
  String _curUrl = '';
  String _curTitle = '';

  /// Links that open a new tab/window would do nothing inside the app, so
  /// they are opened in the same page instead.
  static const _clickFix = '''
(function(){
  if (window.__bhFix) return; window.__bhFix = true;
  window.open = function(u){ if (u) { location.href = u; } return window; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
    if (a && a.target !== '_self') { a.target = '_self'; }
  }, true);
})();
''';

  @override
  void initState() {
    super.initState();
    _loadCustom();
    _addTab(initial: true);
    _focus.addListener(() { if (mounted) setState(() {}); });

  }

  WebViewController _buildController() {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF10131D))
      ..setUserAgent(_chromeUa)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final scheme = Uri.tryParse(r.url)?.scheme.toLowerCase() ?? '';
          const ok = {'http', 'https', 'about', 'data', 'blob'};
          return ok.contains(scheme) ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onPageStarted: (u) {
          try { controller.runJavaScript(_clickFix); } catch (_) {}
          if (!mounted || !_tabs.contains(controller) || _wc != controller) return;
          setState(() { _error = false; _home = false; _setUrl(u); });
        },
        onProgress: (p) { if (_tabs.contains(controller) && _wc == controller) _progress.value = p / 100; },
        onUrlChange: (c) {
          if (c.url != null && mounted && _tabs.contains(controller) && _wc == controller) setState(() => _setUrl(c.url!));
        },
        onPageFinished: (u) async {
          try { controller.runJavaScript(_clickFix); } catch (_) {}
          final title = await controller.getTitle();
          final back = await controller.canGoBack();
          final forward = await controller.canGoForward();
          if (!mounted || !_tabs.contains(controller) || _wc != controller) return;
          setState(() {
            _setUrl(u); _curTitle = title ?? ''; _canBack = back; _canFwd = forward;
            _tabUrls[_activeTab] = u; _tabTitles[_activeTab] = _curTitle;
            if (u.startsWith('http')) {
              _history.removeWhere((e) => e['url'] == u);
              _history.insert(0, {'url': u, 'title': _curTitle});
              if (_history.length > 60) _history.removeLast();
            }
          });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted && _wc == controller) setState(() => _error = true);
        },
      ));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) cookies.setAcceptThirdPartyCookies(platform, true);
      platform.setOnShowFileSelector((params) async {
        try {
          final result = await FilePicker.platform.pickFiles(allowMultiple: params.mode == FileSelectorMode.openMultiple);
          if (result == null) return <String>[];
          return result.paths.whereType<String>().map((e) => Uri.file(e).toString()).toList();
        } catch (_) { return <String>[]; }
      });
    }
    return controller;
  }

  void _addTab({bool initial = false, String? url}) {
    final controller = _buildController();
    setState(() {
      _tabs.add(controller); _tabUrls.add(url ?? ''); _tabTitles.add('New tab');
      _activeTab = _tabs.length - 1; _home = url == null; _error = false;
      _curUrl = url ?? ''; _curTitle = 'New tab'; _canBack = false; _canFwd = false; _addr.text = url ?? '';
    });
    if (url != null) controller.loadRequest(Uri.parse(url));
  }

  Future<void> _switchTab(int index) async {
    if (index < 0 || index >= _tabs.length || index == _activeTab) return;
    setState(() {
      _activeTab = index; _curUrl = _tabUrls[index]; _curTitle = _tabTitles[index];
      _home = _curUrl.isEmpty; _error = false; _addr.text = _curUrl; _canBack = false; _canFwd = false;
    });
    final back = await _wc.canGoBack(); final forward = await _wc.canGoForward();
    if (mounted) setState(() { _canBack = back; _canFwd = forward; });
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      _tabs[index].loadRequest(Uri.parse('about:blank'));
      setState(() { _tabUrls[index] = ''; _tabTitles[index] = 'New tab'; _activeTab = index; _home = true; _curUrl = ''; _curTitle = ''; });
      return;
    }
    setState(() {
      _tabs.removeAt(index); _tabUrls.removeAt(index); _tabTitles.removeAt(index);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      else if (index < _activeTab) _activeTab--;
      _curUrl = _tabUrls[_activeTab]; _curTitle = _tabTitles[_activeTab]; _home = _curUrl.isEmpty; _addr.text = _curUrl;
    });
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context, backgroundColor: Ui.panel, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .65,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(18), child: Row(children: [
            const Icon(Icons.history_rounded), const SizedBox(width: 10),
            const Expanded(child: Text('Browsing history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            TextButton(onPressed: () { setState(() => _history.clear()); Navigator.pop(ctx); }, child: const Text('Clear')),
          ])),
          Expanded(child: _history.isEmpty
            ? Center(child: Text('No browsing history yet', style: TextStyle(color: Ui.muted)))
            : ListView.builder(itemCount: _history.length, itemBuilder: (_, i) {
                final item = _history[i];
                return ListTile(leading: const Icon(Icons.public_rounded),
                  title: Text(item['title']?.isNotEmpty == true ? item['title']! : item['url']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(item['url']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () { Navigator.pop(ctx); _go(item['url']!); });
              })),
        ]),
      )),
    );
  }

  @override
  void dispose() {
    _addr.dispose();
    _focus.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _fix() {
    try {
      _wc.runJavaScript(_clickFix);
    } catch (_) {}
  }

  void _setUrl(String u) {
    _curUrl = u;
    if (!_focus.hasFocus) _addr.text = u;
  }

  // ---------------------------------------------------------------- storage

  Future<void> _loadCustom() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => BetSite.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (mounted) setState(() => _custom = list);
    } catch (_) {}
  }

  Future<void> _saveCustom() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _prefsKey, jsonEncode(_custom.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }

  bool get _curIsBookmarked => _custom.any((s) => _sameUrl(s.url, _curUrl));

  bool _sameUrl(String a, String b) =>
      a.replaceAll(RegExp(r'/+$'), '') == b.replaceAll(RegExp(r'/+$'), '');

  // ------------------------------------------------------------- navigation

  /// Turns what was typed into a page address, or a Google search.
  String _toUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return '';
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (!t.contains(' ') && t.contains('.') && !t.startsWith('.')) {
      return 'https://$t';
    }
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(t)}';
  }

  void _go(String input) {
    final url = _toUrl(input);
    if (url.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _home = false;
      _error = false;
      _curUrl = url;
      _tabUrls[_activeTab] = url;
      _tabTitles[_activeTab] = Uri.tryParse(url)?.host ?? 'Loading…';
      _curTitle = _tabTitles[_activeTab];
      _addr.text = url;
    });
    _progress.value = 0.05;
    _wc.loadRequest(Uri.parse(url));
  }

  Future<void> _onBack() async {
    if (_focus.hasFocus) {
      _focus.unfocus();
      return;
    }
    if (!_home) {
      if (await _wc.canGoBack()) {
        await _wc.goBack();
        return;
      }
      if (mounted) setState(() => _home = true);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showHome() {
    _focus.unfocus();
    setState(() => _home = true);
  }

  // -------------------------------------------------------------- bookmarks

  Future<void> _toggleBookmark() async {
    if (_home || _curUrl.isEmpty) return;
    if (_curIsBookmarked) {
      setState(() => _custom.removeWhere((s) => _sameUrl(s.url, _curUrl)));
      await _saveCustom();
      _toast('Removed from My sites');
      return;
    }
    final host = Uri.tryParse(_curUrl)?.host ?? '';
    final name = _curTitle.trim().isNotEmpty
        ? _curTitle.trim()
        : host.replaceFirst('www.', '');
    setState(() => _custom.add(BetSite(name, _curUrl, custom: true)));
    await _saveCustom();
    _toast('Saved to My sites');
  }

  Future<void> _addSiteDialog() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Add your betting site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Website',
                hintText: 'example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    final n = name.text.trim();
    final u = url.text.trim();
    name.dispose();
    url.dispose();
    if (ok != true || u.isEmpty) return;
    var link = u;
    if (!link.toLowerCase().startsWith('http')) link = 'https://$link';
    final uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      _toast('That does not look like a website address');
      return;
    }
    setState(() => _custom.add(BetSite(
        n.isEmpty ? uri.host.replaceFirst('www.', '') : n, link,
        custom: true)));
    await _saveCustom();
  }

  Future<void> _siteMenu(BetSite s) async {
    if (!s.custom) return;
    final del = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Ui.panel,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text('Remove ${s.name}'),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (del == true) {
      setState(() => _custom.remove(s));
      await _saveCustom();
    }
  }

  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Clear browsing data?'),
        content: const Text(
            'You will be logged out of every betting site opened here. Your saved sites stay.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await WebViewCookieManager().clearCookies();
    await _wc.clearCache();
    await _wc.clearLocalStorage();
    _toast('Browsing data cleared');
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Bet Hub',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(tooltip: 'Minimise browser', icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: () => Navigator.of(context).maybePop()),
          ],
        ),
        body: Column(
          children: [
            _addressBar(),
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, v, _) => SizedBox(
                height: 2,
                child: (!_home && v > 0 && v < 1)
                    ? LinearProgressIndicator(value: v, minHeight: 2)
                    : null,
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _home ? 0 : 1,
                children: [
                  _homeView(),
                  _error ? _errorView() : WebViewWidget(key: ValueKey(_activeTab), controller: _wc),
                ],
              ),
            ),
            if (!_focus.hasFocus) _bottomBar(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------ tabs & bottom bar

  void _showTabs() {
    _focus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Ui.panel,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 6),
                child: Row(children: [
                  Expanded(child: Text('${_tabs.length} ${_tabs.length == 1 ? 'tab' : 'tabs'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7257E8)),
                    onPressed: () { Navigator.pop(ctx); _addTab(); },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New tab'),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final active = i == _activeTab;
                    final title = _tabTitles[i].isEmpty ? 'New tab' : _tabTitles[i];
                    final url = _tabUrls[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () { Navigator.pop(ctx); _switchTab(i); },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        decoration: BoxDecoration(
                          color: Ui.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: active ? const Color(0xFF8B70FF) : Ui.line, width: active ? 1.6 : 1),
                        ),
                        child: Row(children: [
                          Icon(Icons.public_rounded, size: 20, color: Ui.muted),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (url.isNotEmpty) Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Ui.muted)),
                          ])),
                          IconButton(
                            tooltip: 'Close tab',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              _closeTab(i);
                              setSheet(() {});
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showMenu() {
    _focus.unfocus();
    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () { Navigator.pop(context); onTap(); },
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: Ui.panel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          item(Icons.home_rounded, 'Home', _showHome),
          if (!_home) item(_curIsBookmarked ? Icons.star_rounded : Icons.star_border_rounded, _curIsBookmarked ? 'Remove bookmark' : 'Bookmark this page', _toggleBookmark),
          if (!_home) item(Icons.refresh_rounded, 'Reload', () => _wc.reload()),
          item(Icons.history_rounded, 'History', _showHistory),
          item(Icons.add_link_rounded, 'Add a site', _addSiteDialog),
          item(Icons.delete_sweep_outlined, 'Clear browsing data', _clearData),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Chrome-style bottom bar: back, forward, new tab, tab switcher, menu.
  /// Sits above the phone's navigation (gesture bar or buttons).
  Widget _bottomBar() {
    // From a page, Back always works (it falls back to Home when there is no history).
    final canBack = !_home;
    return Container(
      decoration: BoxDecoration(
        color: Ui.panel,
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: canBack ? _onBack : null,
              ),
              IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: (!_home && _canFwd) ? () => _wc.goForward() : null,
              ),
              InkWell(
                onTap: () => _addTab(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 38, height: 38,
                  decoration: const BoxDecoration(color: Color(0xFF7257E8), shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                ),
              ),
              IconButton(
                tooltip: 'Tabs',
                onPressed: _showTabs,
                icon: Container(
                  width: 24, height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Theme.of(context).iconTheme.color ?? Colors.white, width: 2),
                  ),
                  child: Text('${_tabs.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                ),
              ),
              IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: _showMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Ui.line),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                _home
                    ? Icons.search_rounded
                    : (_curUrl.startsWith('https')
                        ? Icons.lock_outline_rounded
                        : Icons.info_outline_rounded),
                size: 18,
                color: Ui.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _addr,
                  focusNode: _focus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search or type a website',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onTap: () => _addr.selection = TextSelection(
                      baseOffset: 0, extentOffset: _addr.text.length),
                  onSubmitted: _go,
                ),
              ),
              if (!_home)
                IconButton(
                  tooltip: _curIsBookmarked ? 'Remove bookmark' : 'Bookmark',
                  icon: Icon(
                    _curIsBookmarked
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _curIsBookmarked ? Colors.amber : Ui.muted,
                  ),
                  onPressed: _toggleBookmark,
                ),
              if (!_home)
                IconButton(
                  tooltip: 'Reload',
                  icon: Icon(Icons.refresh_rounded, color: Ui.muted),
                  onPressed: () => _wc.reload(),
                ),
            ],
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: Ui.muted),
              const SizedBox(height: 12),
              const Text('This page could not be loaded',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Check your connection or try again. Some sites are not available in every country.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() => _error = false);
                  _wc.reload();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _homeView() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF20183B), Color(0xFF111B2B), Color(0xFF080D16)],
          ),
        ),
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _section('MY SITES', _custom, showAdd: true),
          _section('AFRICA', _africa),
          _section('EUROPE', _europe),
          _section('AMERICAS', _americas),
          const SizedBox(height: 8),
          Text(
            '18+ only. Betting can be addictive, so play responsibly. '
            'Availability depends on your country. You log in on each '
            'bookmaker\'s own page; Deeprowss never sees or stores your passwords.',
            style: TextStyle(fontSize: 11, color: Ui.muted, height: 1.4),
          ),
        ],
      ));

  Widget _section(String title, List<BetSite> sites, {bool showAdd = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
              color: Ui.isLight
                  ? const Color(0xFF6A4CD6)
                  : const Color(0xFFB39DFF),
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            childAspectRatio: .82,
            children: [
              for (final s in sites) _tile(s),
              if (showAdd) _addTile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BetSite s) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _go(s.url),
        onLongPress: () => _siteMenu(s),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Ui.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Ui.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl:
                      'https://www.google.com/s2/favicons?domain=${s.host}&sz=64',
                  width: 54,
                  height: 54,
                  fit: BoxFit.scaleDown,
                  errorWidget: (_, _, _) => _letter(s),
                  placeholder: (_, _) => _letter(s),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _letter(BetSite s) => Center(
        child: Text(
          s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: Ui.muted),
        ),
      );

  Widget _addTile() => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _addSiteDialog,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Ui.muted.withValues(alpha: .6)),
              ),
              child: Icon(Icons.add_rounded, color: Ui.muted),
            ),
            const SizedBox(height: 6),
            const Text('Add site',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
