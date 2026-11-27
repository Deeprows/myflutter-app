import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key});

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _session;
  String? _error;
  bool _loading = true;
  final List<WebViewController> _pages = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _createSession();
  }

  Future<void> _createSession() async {
    setState(() { _loading = true; _error = null; _session = null; _pages.clear(); });
    try {
      final user = AuthService.instance.user;
      if (user == null || user.email.toLowerCase() != 'deeprows@gmail.com') {
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
      final token = data['token'] as String;
      final base = AppConfig.feedBase;
      final urls = [
        Uri.parse('$base/fan/admin?session=$token'),
        Uri.parse('$base/sub/admin?token=$token'),
        Uri.parse('$base/stats?token=$token'),
      ];
      for (final url in urls) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Ui.bg)
          ..setNavigationDelegate(NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ));
        await controller.loadRequest(url);
        _pages.add(controller);
      }
      if (!mounted) return;
      setState(() { _session = token; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text('Deeprowss Admin'),
        backgroundColor: Ui.panel,
        actions: [
          IconButton(
            tooltip: 'Renew secure session',
            onPressed: _createSession,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'User management', icon: Icon(Icons.people_alt_outlined)),
            Tab(text: 'Subscriptions', icon: Icon(Icons.card_membership_outlined)),
            Tab(text: 'Statistics', icon: Icon(Icons.analytics_outlined)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.admin_panel_settings_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _createSession, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: _pages.map((controller) => WebViewWidget(controller: controller)).toList(),
                ),
    );
  }
}
