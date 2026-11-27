import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

const String _adminEmail = 'deeprows@gmail.com';

/// Everything the admin can open. Each entry is its OWN full page (not a tab).
class _AdminSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final String Function(String base, String token) url;
  const _AdminSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.url,
  });
}

final List<_AdminSection> _sections = [
  _AdminSection(
    title: 'User management',
    subtitle: 'Find fans, ban or unban, review reports and publish weekly winners.',
    icon: Icons.people_alt_rounded,
    tint: const Color(0xFF4DA3FF),
    url: (b, t) => '$b/fan/admin?session=$t',
  ),
  _AdminSection(
    title: 'Subscriptions',
    subtitle: 'Premium and ad-free tokens: look up, grant, stop or extend.',
    icon: Icons.workspace_premium_rounded,
    tint: const Color(0xFFF3C76B),
    url: (b, t) => '$b/sub/admin?token=$t',
  ),
  _AdminSection(
    title: 'Statistics',
    subtitle: 'Phones, app versions, feed requests and opens in the last 24 hours.',
    icon: Icons.insights_rounded,
    tint: const Color(0xFF22E07A),
    url: (b, t) => '$b/stats?token=$t',
  ),
];

/// Asks the worker for a short-lived admin session token.
Future<String> _createAdminSession() async {
  final user = AuthService.instance.user;
  if (user == null || user.email.toLowerCase() != _adminEmail) {
    throw Exception('Admin access is restricted to DeeprowssAdmin.');
  }
  final idToken = await AuthService.instance.idToken(refresh: true);
  final response = await http.post(
    Uri.parse('${AppConfig.feedBase}/fan/admin/session'),
    headers: {'authorization': 'Bearer $idToken'},
  ).timeout(const Duration(seconds: 20));
  final data = jsonDecode(response.body);
  if (response.statusCode != 200 || data is! Map || data['token'] is! String) {
    throw Exception(data is Map ? '${data['error'] ?? 'Admin verification failed.'}' : 'Admin verification failed.');
  }
  return data['token'] as String;
}

// ───────────────────────────── hub (landing) ─────────────────────────────

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.user;
    final allowed = user != null && user.email.toLowerCase() == _adminEmail;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text('Deeprowss Admin'),
        backgroundColor: Ui.panel,
      ),
      body: !allowed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.admin_panel_settings_outlined, size: 44, color: Ui.muted),
                  const SizedBox(height: 12),
                  Text('Admin access is restricted to DeeprowssAdmin.',
                      textAlign: TextAlign.center, style: TextStyle(color: Ui.text)),
                ]),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                _HeaderCard(email: user!.email),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text('MANAGE',
                      style: TextStyle(color: Ui.muted, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                ),
                for (final s in _sections) ...[
                  _SectionCard(
                    section: s,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AdminPageScreen(section: s)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String email;
  const _HeaderCard({required this.email});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.red.withValues(alpha: .22), Ui.card],
          ),
          border: Border.all(color: Ui.line),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Ui.red.withValues(alpha: .2)),
            child: Icon(Icons.admin_panel_settings_rounded, color: Ui.red, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Control centre',
                  style: TextStyle(color: Ui.text, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
            ]),
          ),
          Icon(Icons.verified_user_rounded, color: Ui.green, size: 22),
        ]),
      );
}

class _SectionCard extends StatelessWidget {
  final _AdminSection section;
  final VoidCallback onTap;
  const _SectionCard({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Ui.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ui.line),
            ),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: section.tint.withValues(alpha: .16),
                ),
                child: Icon(section.icon, color: section.tint, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(section.title,
                      style: TextStyle(color: Ui.text, fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(section.subtitle,
                      style: TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: Ui.muted),
            ]),
          ),
        ),
      );
}

// ───────────────────────── one page per section ─────────────────────────

class AdminPageScreen extends StatefulWidget {
  final _AdminSection section;
  const AdminPageScreen({super.key, required this.section});

  @override
  State<AdminPageScreen> createState() => _AdminPageScreenState();
}

class _AdminPageScreenState extends State<AdminPageScreen> {
  WebViewController? _web;
  String? _error;
  bool _loading = true;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  /// Creates a fresh secure session and (re)loads this page with it.
  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final token = await _createAdminSession();
      final url = Uri.parse(widget.section.url(AppConfig.feedBase, token));
      final controller = _web ??
          (WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(Ui.bg)
            ..setNavigationDelegate(NavigationDelegate(
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
              onNavigationRequest: (request) {
                final uri = Uri.tryParse(request.url);
                if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            )));
      _web = controller;
      await controller.loadRequest(url);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        titleSpacing: 0,
        title: Row(children: [
          Icon(s.icon, size: 22, color: s.tint),
          const SizedBox(width: 10),
          Flexible(child: Text(s.title, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Reload with a new secure session',
            onPressed: _open,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: (_progress > 0 && _progress < 100)
              ? LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: s.tint, backgroundColor: Colors.transparent)
              : const SizedBox(height: 2),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.admin_panel_settings_outlined, size: 42, color: Ui.muted),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Ui.text)),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _open, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                ]),
              ),
            )
          : (_web == null || (_loading && _progress == 0))
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(top: false, child: WebViewWidget(controller: _web!)),
    );
  }
}
