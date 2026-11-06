import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../screens/browser_screen.dart' show openExternally;
import '../theme/app_theme.dart';
import 'download_manager.dart';
import 'subscription_service.dart';

class ManualAd {
  final bool enabled;
  final String id;
  final String imageUrl;
  final String downloadUrl;
  final String pageUrl;

  const ManualAd({this.enabled = false, this.id = '', this.imageUrl = '', this.downloadUrl = '', this.pageUrl = ''});

  /// Identity of this popup. A new image, download link, page link or id
  /// makes it a "different" popup that can be shown again.
  String get key => [id, imageUrl, downloadUrl, pageUrl].join('|');

  bool get visible => enabled && imageUrl.startsWith('http') &&
      (downloadUrl.startsWith('http') || pageUrl.startsWith('http'));

  factory ManualAd.fromJson(dynamic raw) {
    if (raw is! Map) return const ManualAd();
    String value(String key) => (raw[key] ?? '').toString().trim();
    return ManualAd(
      enabled: raw['enabled'] != false,
      id: value('id'),
      imageUrl: value('image_url'),
      downloadUrl: value('download_url'),
      pageUrl: value('url').isNotEmpty ? value('url') : value('link'),
    );
  }
}

class ManualAdService {
  ManualAdService._();
  static final instance = ManualAdService._();
  static const _cacheKey = 'manual_ad_json_cache';
  static const _clickedKey = 'manual_ad_clicked_keys';

  Future<bool> _wasClicked(ManualAd ad) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_clickedKey) ?? const <String>[]).contains(ad.key);
  }

  Future<void> _markClicked(ManualAd ad) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...(prefs.getStringList(_clickedKey) ?? const <String>[])];
    if (!list.contains(ad.key)) list.add(ad.key);
    // Keep the list short; only recent popups matter.
    final trimmed = list.length > 40 ? list.sublist(list.length - 40) : list;
    await prefs.setStringList(_clickedKey, trimmed);
  }

  Future<ManualAd> _load(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final remote = AppConfig.manualAdUrl.trim();
    if (remote.isNotEmpty) {
      try {
        final original = Uri.parse(remote);
        final uri = original.replace(queryParameters: {
          ...original.queryParameters,
          '_refresh': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        final response = await http.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes);
          await prefs.setString(_cacheKey, body);
          return ManualAd.fromJson(jsonDecode(body));
        }
      } catch (_) {}
    }
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try { return ManualAd.fromJson(jsonDecode(cached)); } catch (_) {}
    }
    try {
      final body = await DefaultAssetBundle.of(context).loadString('assets/data/manual_ad.json');
      return ManualAd.fromJson(jsonDecode(body));
    } catch (_) {
      return const ManualAd();
    }
  }

  Future<void> show(BuildContext context) async {
    if (!context.mounted || SubscriptionService.instance.isPremium) return;
    final ad = await _load(context);
    if (!context.mounted || !ad.visible || SubscriptionService.instance.isPremium) return;
    // Someone who already tapped this popup's button never sees it again;
    // only a popup with a different image / download link / page link shows.
    if (await _wasClicked(ad)) return;
    if (!context.mounted || SubscriptionService.instance.isPremium) return;
    final screenH = MediaQuery.of(context).size.height;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF101722),
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 540, maxHeight: screenH * .9),
          child: Stack(children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              // Edge-to-edge image: no padding around it.
              Flexible(
                child: CachedNetworkImage(
                  imageUrl: ad.imageUrl,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(
                    height: 360,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => const SizedBox(
                    height: 240,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: ad.downloadUrl.startsWith('http')
                    ? SizedBox(width: double.infinity, child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Ui.red, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          final error = await DownloadManager.instance.enqueue(ad.downloadUrl);
                          if (!dialogContext.mounted) return;
                          if (error != null) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            await _markClicked(ad);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          }
                        },
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download now', style: TextStyle(fontWeight: FontWeight.w900)),
                      ))
                    : SizedBox(width: double.infinity, child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Ui.red, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          await _markClicked(ad);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                          openExternally(ad.pageUrl);
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Visit page', style: TextStyle(fontWeight: FontWeight.w900)),
                      )),
              ),
            ]),
            Positioned(top: 6, right: 6, child: Material(
              color: Colors.black.withValues(alpha: .72), shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Close advertisement', visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            )),
          ]),
        ),
      ),
    );
  }
}
