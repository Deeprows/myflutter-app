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
  late final WebViewController _wc;
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
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(_chromeUa)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final s = Uri.tryParse(r.url)?.scheme.toLowerCase() ?? '';
          const ok = {'http', 'https', 'about', 'data', 'blob'};
          return ok.contains(s)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (u) {
          _fix();
          if (!mounted) return;
          setState(() {
            _error = false;
            _setUrl(u);
          });
        },
        onProgress: (p) => _progress.value = p / 100,
        onUrlChange: (c) {
          if (c.url != null && mounted) setState(() => _setUrl(c.url!));
        },
        onPageFinished: (u) async {
          _fix();
          _progress.value = 1;
          final t = await _wc.getTitle();
          final b = await _wc.canGoBack();
          final f = await _wc.canGoForward();
          if (!mounted) return;
          setState(() {
            _setUrl(u);
            _curTitle = t ?? '';
            _canBack = b;
            _canFwd = f;
          });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = true);
          }
        },
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      // Keeps people logged in and lets log-in pages that use 3rd-party
      // cookies work.
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
      // KYC / document uploads on bookmaker sites.
      p.setOnShowFileSelector((params) async {
        try {
          final r = await FilePicker.platform.pickFiles(
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
          );
          if (r == null) return <String>[];
          return r.paths
              .whereType<String>()
              .map((e) => Uri.file(e).toString())
              .toList();
        } catch (_) {
          return <String>[];
        }
      });
    }
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
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_rounded),
              onPressed: _showHome,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'add') _addSiteDialog();
                if (v == 'clear') _clearData();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Add a site')),
                PopupMenuItem(value: 'clear', child: Text('Clear browsing data')),
              ],
            ),
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
                  _error ? _errorView() : WebViewWidget(controller: _wc),
                ],
              ),
            ),
            if (!_home) _navBar(),
          ],
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

  Widget _navBar() => Container(
        decoration: BoxDecoration(
          color: Ui.panel,
          border: Border(top: BorderSide(color: Ui.line)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _canBack ? () => _wc.goBack() : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _canFwd ? () => _wc.goForward() : null,
              ),
              IconButton(
                icon: const Icon(Icons.grid_view_rounded),
                tooltip: 'Bookmarks',
                onPressed: _showHome,
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

  Widget _homeView() => ListView(
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
      );

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
