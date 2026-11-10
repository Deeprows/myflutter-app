import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/bet_browser_session.dart';
import '../theme/app_theme.dart';

/// Top betting platforms by region. They open inside the app; the person logs
/// in on the bookmaker's own page (the app never sees or stores passwords).
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

// ------------------------------------------------------------- look & feel

bool get _light => Ui.isLight;

/// Text colours that stay readable on the Bet Hub gradient in both themes.
Color get _ink => _light ? const Color(0xFF1B1530) : Colors.white;
Color get _inkSoft =>
    _light ? const Color(0xFF5B5470) : Colors.white.withValues(alpha: .66);

BoxDecoration _glass({double radius = 16, bool strong = false}) => BoxDecoration(
      color: _light
          ? Colors.white.withValues(alpha: strong ? .85 : .65)
          : Colors.white.withValues(alpha: strong ? .13 : .07),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: _light
            ? const Color(0xFF8E6BFF).withValues(alpha: .18)
            : Colors.white.withValues(alpha: .13),
      ),
    );

/// Night-pitch gradient with soft colour glows and faint pitch markings.
class _HubBackground extends StatelessWidget {
  const _HubBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _light
                  ? const [Color(0xFFF4EFFF), Color(0xFFFFEEF5), Color(0xFFE9F3FF)]
                  : const [Color(0xFF0A0720), Color(0xFF1A0F3C), Color(0xFF3A1040)],
            ),
          ),
        ),
        CustomPaint(painter: _HubPainter(_light)),
      ],
    );
  }
}

class _HubPainter extends CustomPainter {
  final bool light;
  const _HubPainter(this.light);

  @override
  void paint(Canvas canvas, Size s) {
    void glow(Offset c, double r, Color col) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withValues(alpha: light ? .30 : .42), col.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    glow(Offset(s.width * .88, s.height * .06), s.width * .75, const Color(0xFF8E6BFF));
    glow(Offset(s.width * .05, s.height * .48), s.width * .70, const Color(0xFFFF5C8A));
    glow(Offset(s.width * .92, s.height * .92), s.width * .80, const Color(0xFF2EA8FF));

    // Faint football-pitch markings, drawn rotated across the page.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = (light ? const Color(0xFF6A4CD6) : Colors.white)
          .withValues(alpha: light ? .08 : .07);
    canvas.save();
    canvas.translate(s.width / 2, s.height * .62);
    canvas.rotate(-math.pi / 14);
    final w = s.width * 1.15;
    final h = w * .62;
    final pitch = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(pitch, const Radius.circular(18)), line);
    canvas.drawLine(Offset(0, -h / 2), Offset(0, h / 2), line);
    canvas.drawCircle(Offset.zero, h * .17, line);
    canvas.drawCircle(Offset.zero, 3, line..style = PaintingStyle.fill);
    line.style = PaintingStyle.stroke;
    final boxW = w * .15, boxH = h * .5;
    canvas.drawRect(Rect.fromLTWH(-w / 2, -boxH / 2, boxW, boxH), line);
    canvas.drawRect(Rect.fromLTWH(w / 2 - boxW, -boxH / 2, boxW, boxH), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HubPainter old) => old.light != light;
}

// ------------------------------------------------------------------ screen

/// "Bet Hub": a Chrome-style in-app browser with tabs, history and betting
/// bookmarks. The tabs live in [BetBrowserSession], so closing this screen
/// only minimises the browser.
class BetBrowserScreen extends StatefulWidget {
  const BetBrowserScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BetBrowserScreen()),
    );
  }

  @override
  State<BetBrowserScreen> createState() => _BetBrowserScreenState();
}

class _BetBrowserScreenState extends State<BetBrowserScreen> {
  final _s = BetBrowserSession.instance;
  final _addr = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _s.init();
    _syncAddr();
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    _addr.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _syncAddr();
    setState(() {});
  }

  void _syncAddr() {
    if (_focus.hasFocus) return;
    final t = _s.tab;
    _addr.text = t.home ? '' : t.url;
  }

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
    _s.load(_s.tab, url);
  }

  Future<void> _onBack() async {
    if (_focus.hasFocus) {
      _focus.unfocus();
      return;
    }
    final t = _s.tab;
    if (!t.home && t.wc != null) {
      if (await t.wc!.canGoBack()) {
        await t.wc!.goBack();
        return;
      }
      _s.showHome(t);
      return;
    }
    // On the bookmarks page: leave. The tabs stay, so this minimises.
    if (mounted) Navigator.of(context).pop();
  }

  void _minimise() {
    _focus.unfocus();
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------ bookmarks

  Future<void> _toggleBookmark() async {
    final t = _s.tab;
    if (t.home || t.url.isEmpty) return;
    if (_s.isCustom(t.url)) {
      await _s.removeCustomUrl(t.url);
      _toast('Removed from My sites');
      return;
    }
    final name = t.title.trim().isNotEmpty
        ? t.title.trim()
        : t.host;
    await _s.addCustom(BetSite(name, t.url, custom: true));
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
    await _s.addCustom(BetSite(
      n.isEmpty ? uri.host.replaceFirst('www.', '') : n,
      link,
      custom: true,
    ));
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
    if (del == true) await _s.removeCustomUrl(s.url);
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
    await _s.clearBrowsingData();
    _toast('Browsing data cleared');
  }

  Future<void> _closeHub() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: const Text('Close all tabs?'),
        content: const Text('Every open tab will be closed. You stay logged in on the sites.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close all')),
        ],
      ),
    );
    if (ok != true) return;
    _s.closeAll();
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------- tabs & history

  Future<void> _openTabs() async {
    _focus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Ui.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: .88,
        child: _TabsSheet(session: _s),
      ),
    );
  }

  Future<void> _openHistory() async {
    _focus.unfocus();
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => _HistoryScreen(session: _s)),
    );
    if (url != null && url.isNotEmpty) _s.load(_s.tab, url);
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
    final t = _s.tab;
    final top = MediaQuery.of(context).padding.top + kToolbarHeight;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: _ink),
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Minimise',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: _minimise,
          ),
          title: Text('Bet Hub',
              style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
          actions: [
            IconButton(
              tooltip: 'Minimise',
              icon: const Icon(Icons.close_fullscreen_rounded, size: 20),
              onPressed: _minimise,
            ),
            PopupMenuButton<String>(
              iconColor: _ink,
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    _s.newTab();
                    break;
                  case 'tabs':
                    _openTabs();
                    break;
                  case 'history':
                    _openHistory();
                    break;
                  case 'add':
                    _addSiteDialog();
                    break;
                  case 'clear':
                    _clearData();
                    break;
                  case 'close':
                    _closeHub();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('New tab')),
                PopupMenuItem(value: 'tabs', child: Text('All tabs')),
                PopupMenuItem(value: 'history', child: Text('History')),
                PopupMenuItem(value: 'add', child: Text('Add a site')),
                PopupMenuItem(value: 'clear', child: Text('Clear browsing data')),
                PopupMenuItem(value: 'close', child: Text('Close all tabs')),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _HubBackground()),
            Padding(
              padding: EdgeInsets.only(top: top),
              child: Column(
                children: [
                  _addressBar(t),
                  ValueListenableBuilder<double>(
                    valueListenable: t.progress,
                    builder: (_, v, _) => SizedBox(
                      height: 2,
                      child: (!t.home && v > 0 && v < 1)
                          ? LinearProgressIndicator(
                              value: v,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                            )
                          : null,
                    ),
                  ),
                  Expanded(child: _content(t)),
                  _navBar(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BetTab t) {
    if (t.home || t.wc == null) return _homeView();
    if (t.error) return _errorView(t);
    return WebViewWidget(key: ValueKey(t.id), controller: t.wc!);
  }

  Widget _addressBar(BetTab t) {
    final page = !t.home && t.wc != null;
    final starred = page && _s.isCustom(t.url);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Container(
        height: 46,
        decoration: _glass(radius: 26, strong: true),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              !page
                  ? Icons.search_rounded
                  : (t.url.startsWith('https')
                      ? Icons.lock_outline_rounded
                      : Icons.info_outline_rounded),
              size: 18,
              color: _inkSoft,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _addr,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                style: TextStyle(fontSize: 14, color: _ink),
                cursorColor: const Color(0xFF8E6BFF),
                decoration: InputDecoration(
                  hintText: 'Search or type a website',
                  hintStyle: TextStyle(color: _inkSoft),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
                onTap: () => _addr.selection =
                    TextSelection(baseOffset: 0, extentOffset: _addr.text.length),
                onSubmitted: _go,
              ),
            ),
            if (page)
              IconButton(
                tooltip: starred ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(
                  starred ? Icons.star_rounded : Icons.star_border_rounded,
                  color: starred ? Colors.amber : _inkSoft,
                ),
                onPressed: _toggleBookmark,
              ),
            if (page)
              IconButton(
                tooltip: 'Reload',
                icon: Icon(Icons.refresh_rounded, color: _inkSoft),
                onPressed: () => _s.reload(t),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navBar(BetTab t) {
    final page = !t.home && t.wc != null;
    return Container(
      decoration: BoxDecoration(
        color: _light
            ? Colors.white.withValues(alpha: .8)
            : const Color(0xFF0A0720).withValues(alpha: .9),
        border: Border(
          top: BorderSide(color: _ink.withValues(alpha: .10)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              tooltip: 'Back',
              color: _ink,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: page && t.canBack ? () => _s.goBack(t) : null,
            ),
            IconButton(
              tooltip: 'Forward',
              color: _ink,
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: page && t.canFwd ? () => _s.goForward(t) : null,
            ),
            IconButton(
              tooltip: 'Bookmarks',
              color: _ink,
              icon: const Icon(Icons.home_rounded),
              onPressed: () {
                _focus.unfocus();
                _s.showHome(t);
              },
            ),
            IconButton(
              tooltip: 'Tabs',
              icon: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: _ink, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_s.tabs.length}',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w900, color: _ink),
                ),
              ),
              onPressed: _openTabs,
            ),
            IconButton(
              tooltip: 'History',
              color: _ink,
              icon: const Icon(Icons.history_rounded),
              onPressed: _openHistory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(BetTab t) => Container(
        color: _light ? Colors.white : const Color(0xFF120B2B),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: _inkSoft),
                const SizedBox(height: 12),
                Text('This page could not be loaded',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 4),
                Text(
                  'Check your connection or try again. Some sites are not available in every country.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _inkSoft, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _s.reload(t),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _homeView() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF8E6BFF), Color(0xFFFF5C8A)],
                  ),
                ),
                child: const Icon(Icons.local_fire_department_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your betting sites, one tap away',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _ink)),
                    Text('Open as many tabs as you like. Minimise to keep them running.',
                        style: TextStyle(fontSize: 11, color: _inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          _section('MY SITES', _s.custom, showAdd: true),
          _section('AFRICA', _africa),
          _section('EUROPE', _europe),
          _section('AMERICAS', _americas),
          const SizedBox(height: 14),
          Text(
            '18+ only. Betting can be addictive, so play responsibly. '
            'Availability depends on your country. You log in on each '
            'bookmaker\'s own page; Deeprowss never sees or stores your passwords.',
            style: TextStyle(fontSize: 11, color: _inkSoft, height: 1.4),
          ),
        ],
      );

  Widget _section(String title, List<BetSite> sites, {bool showAdd = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w900,
              color: _light ? const Color(0xFF6A4CD6) : const Color(0xFFC9B8FF),
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
              width: 56,
              height: 56,
              decoration: _glass(radius: 18, strong: true),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CachedNetworkImage(
                  imageUrl:
                      'https://www.google.com/s2/favicons?domain=${s.host}&sz=64',
                  width: 56,
                  height: 56,
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
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _ink),
            ),
          ],
        ),
      );

  Widget _letter(BetSite s) => Center(
        child: Text(
          s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: _inkSoft),
        ),
      );

  Widget _addTile() => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _addSiteDialog,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _inkSoft),
              ),
              child: Icon(Icons.add_rounded, color: _inkSoft),
            ),
            const SizedBox(height: 6),
            Text('Add site',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- tab list

class _TabsSheet extends StatelessWidget {
  final BetBrowserSession session;
  const _TabsSheet({required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final tabs = session.tabs;
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Ui.muted.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tabs.length} ${tabs.length == 1 ? 'tab' : 'tabs'}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: session.closeAll,
                    child: const Text('Close all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: tabs.length,
                itemBuilder: (_, i) => _card(context, tabs[i], i),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      session.newTab();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New tab'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, BetTab t, int i) {
    final here = i == session.current;
    final hasPage = t.wc != null;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        session.select(i);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: here ? const Color(0xFF8E6BFF) : Ui.line,
            width: here ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (hasPage && t.host.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl:
                        'https://www.google.com/s2/favicons?domain=${t.host}&sz=32',
                    width: 16,
                    height: 16,
                    errorWidget: (_, _, _) => const Icon(Icons.public, size: 16),
                  )
                else
                  const Icon(Icons.add_box_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: 'Close tab',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => session.closeTab(i),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasPage ? Icons.language_rounded : Icons.grid_view_rounded,
                      size: 34,
                      color: Ui.muted,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasPage ? t.host : 'Bookmarks',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Ui.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (here)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'YOU ARE HERE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF8E6BFF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- history

class _HistoryScreen extends StatefulWidget {
  final BetBrowserSession session;
  const _HistoryScreen({required this.session});

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final q = _q.text.trim().toLowerCase();
        final all = widget.session.history
            .where((e) =>
                q.isEmpty ||
                e.title.toLowerCase().contains(q) ||
                e.url.toLowerCase().contains(q))
            .toList();
        final rows = <Object>[];
        String? last;
        for (final e in all) {
          final label = _day(DateTime.fromMillisecondsSinceEpoch(e.at));
          if (label != last) {
            rows.add(label);
            last = label;
          }
          rows.add(e);
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('History',
                style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              TextButton(
                onPressed: widget.session.history.isEmpty
                    ? null
                    : () => widget.session.clearHistory(),
                child: const Text('Clear all'),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search history',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          widget.session.history.isEmpty
                              ? 'No history yet'
                              : 'Nothing matches',
                          style: TextStyle(color: Ui.muted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          if (r is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                              child: Text(
                                r.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF8E6BFF),
                                ),
                              ),
                            );
                          }
                          final e = r as BetHistoryEntry;
                          final host = Uri.tryParse(e.url)?.host ?? '';
                          return Dismissible(
                            key: ValueKey('${e.url}_${e.at}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red.withValues(alpha: .8),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) => widget.session.removeHistory(e),
                            child: ListTile(
                              leading: CachedNetworkImage(
                                imageUrl:
                                    'https://www.google.com/s2/favicons?domain=$host&sz=32',
                                width: 22,
                                height: 22,
                                errorWidget: (_, _, _) =>
                                    const Icon(Icons.public, size: 22),
                              ),
                              title: Text(
                                e.title.isEmpty ? host : e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                e.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Ui.muted),
                              ),
                              trailing: Text(
                                _time(DateTime.fromMillisecondsSinceEpoch(e.at)),
                                style: TextStyle(fontSize: 11, color: Ui.muted),
                              ),
                              onTap: () => Navigator.pop(context, e.url),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- mini bar

/// Shown on the AI Predict page while Bet Hub is minimised, like a mini
/// player: tap it to come back to your tabs exactly where you left them.
class BetMiniBar extends StatelessWidget {
  const BetMiniBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = BetBrowserSession.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!s.hasPages) return const SizedBox.shrink();
        final t = s.tab;
        final n = s.pageCount;
        final sub = t.wc != null && t.host.isNotEmpty ? t.host : 'Bookmarks';
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => BetBrowserScreen.open(context),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A1A5E), Color(0xFF5A1B55)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: .15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bet Hub · $n ${n == 1 ? 'tab' : 'tabs'} open',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: .7)),
                          ),
                        ],
                      ),
                    ),
                    const Text('OPEN',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    IconButton(
                      tooltip: 'Close Bet Hub',
                      iconSize: 18,
                      color: Colors.white,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: s.closeAll,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
