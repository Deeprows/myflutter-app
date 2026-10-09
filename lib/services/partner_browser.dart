import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../screens/browser_screen.dart' show openExternally;
import '../theme/app_theme.dart';

enum _Offer { getBrowser, continueBrowser, phoneBrowser }

/// Promotes the Deeprows Browser when someone taps Download on a movie.
///
///  * Browser already installed -> the movie download page opens in it.
///  * Not installed -> a pop-up offers "Get Deeprows Browser" (downloads the
///    APK inside the app, starts the installer, and when the person is back
///    the movie download page opens in the new browser) or "Use my phone's
///    browser" (opens the movie download page in the phone's own browser).
///
/// Needs [AppConfig.partnerBrowserApkUrl] and [AppConfig.partnerBrowserPackage].
/// While either is empty, Download simply opens the phone's browser as before.
class PartnerBrowser with WidgetsBindingObserver {
  PartnerBrowser._();
  static final PartnerBrowser instance = PartnerBrowser._();

  String? _pendingUrl;
  DateTime? _pendingAt;
  bool _observing = false;
  bool _busy = false;

  bool get configured =>
      AppConfig.partnerBrowserApkUrl.trim().startsWith('http') &&
      AppConfig.partnerBrowserPackage.trim().isNotEmpty;

  AndroidIntent _viewIntent(String url) => AndroidIntent(
        action: 'action_view',
        data: url,
        package: AppConfig.partnerBrowserPackage.trim(),
      );

  Future<bool> isInstalled() async {
    if (!Platform.isAndroid || !configured) return false;
    try {
      return await _viewIntent('https://deeprowss.com').canResolveActivity() ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openInBrowser(String url) async {
    try {
      await _viewIntent(url).launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ entry point

  /// Call from the Download button with the movie's download link.
  Future<void> download(BuildContext context, String movieUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context, rootNavigator: true);

    Future<void> phoneBrowser() async {
      if (!await openExternally(movieUrl)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the download link')),
        );
      }
    }

    if (_busy) return;
    if (!configured || !Platform.isAndroid) {
      await phoneBrowser();
      return;
    }

    // Re-check on every Download tap. Once the partner browser is installed,
    // show the matching Continue action instead of the install offer.
    final installed = await isInstalled();
    final choice = await showDialog<_Offer>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => _OfferDialog(installed: installed),
    );
    if (choice == _Offer.continueBrowser && installed) {
      if (!await _openInBrowser(movieUrl)) await phoneBrowser();
    } else if (choice == _Offer.getBrowser && !installed) {
      await _installThenOpen(nav, messenger, movieUrl, phoneBrowser);
    } else {
      await phoneBrowser();
    }
  }

  // ---------------------------------------------------------- install flow

  Future<void> _installThenOpen(
    NavigatorState nav,
    ScaffoldMessengerState messenger,
    String movieUrl,
    Future<void> Function() fallback,
  ) async {
    _busy = true;
    final name = AppConfig.partnerBrowserName;
    void say(String m) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    try {
      // Android asks once for "install apps from this source".
      if (!await Permission.requestInstallPackages.isGranted) {
        final st = await Permission.requestInstallPackages.request();
        if (!st.isGranted) {
          say('Allow installs to get $name. Opening your phone browser instead.');
          await fallback();
          return;
        }
      }

      final file = await _downloadApk(nav);
      if (file == null) {
        // Cancelled by the person.
        await fallback();
        return;
      }

      _pendingUrl = movieUrl;
      _pendingAt = DateTime.now();
      _watch();
      say('Install $name. Your movie download opens right after.');
      final r = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (r.type != ResultType.done) {
        _clearPending();
        say('Could not start the install. Opening your phone browser instead.');
        await fallback();
      }
    } on _NotAnApk {
      say('The $name file is not available right now. Using your phone browser.');
      await fallback();
    } catch (_) {
      _clearPending();
      say('Could not get $name. Using your phone browser instead.');
      await fallback();
    } finally {
      _busy = false;
    }
  }

  /// Downloads the APK with a progress pop-up. Null = the person cancelled.
  Future<File?> _downloadApk(NavigatorState nav) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    var dialogOpen = true;

    unawaited(showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Ui.panel,
          title: Text('Getting ${AppConfig.partnerBrowserName}…',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    color: Ui.red,
                    backgroundColor: Ui.line,
                  ),
                ),
                const SizedBox(height: 8),
                Text(v == null ? 'Starting…' : '${(v * 100).round()}%',
                    style: TextStyle(color: Ui.muted, fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(AppConfig.partnerBrowserApkUrl))
        ..headers['user-agent'] = AppConfig.userAgent;
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      final type = (resp.headers['content-type'] ?? '').toLowerCase();
      if (resp.statusCode != 200 || type.contains('text/html')) {
        throw _NotAnApk();
      }
      final total = resp.contentLength ?? 0;
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/deeprows-browser.apk');
      sink = file.openWrite();
      var got = 0;
      await for (final chunk in resp.stream) {
        if (cancelled) break;
        sink.add(chunk);
        got += chunk.length;
        progress.value = total > 0 ? got / total : null;
      }
      await sink.close();
      sink = null;
      if (cancelled) {
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }
      return file;
    } finally {
      client.close();
      try {
        await sink?.close();
      } catch (_) {}
      if (dialogOpen && nav.mounted) nav.pop();
      progress.dispose();
    }
  }

  // ----------------------------------------- after the install: open movie

  void _watch() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _clearPending() {
    _pendingUrl = null;
    _pendingAt = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final url = _pendingUrl;
    final at = _pendingAt;
    if (url == null || at == null) return;
    if (DateTime.now().difference(at) > const Duration(minutes: 20)) {
      _clearPending(); // the person went away: don't surprise them later
      return;
    }
    unawaited(() async {
      if (!await isInstalled()) return; // still installing / cancelled
      _clearPending();
      await _openInBrowser(url);
    }());
  }
}

class _NotAnApk implements Exception {}

class _OfferDialog extends StatelessWidget {
  final bool installed;
  const _OfferDialog({required this.installed});

  @override
  Widget build(BuildContext context) {
    final name = AppConfig.partnerBrowserName;
    return AlertDialog(
      backgroundColor: Ui.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: Ui.red.withValues(alpha: .4)),
      ),
      title: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Download faster',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        ),
      ]),
      content: Text(
        installed
            ? '$name is already installed. Continue to open this movie in '
                "$name, or use your phone's own browser."
            : 'Download $name for fast downloads, or use your phone\'s own '
                'browser.\n\n$name installs in seconds, then your movie download '
                'opens in it automatically.',
        style: TextStyle(color: Ui.muted, fontSize: 14, height: 1.35),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Ui.red,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: () => Navigator.pop(
              context,
              installed ? _Offer.continueBrowser : _Offer.getBrowser,
            ),
            icon: Icon(installed ? Icons.open_in_browser_rounded : Icons.download_rounded),
            label: Text(
              installed ? 'Continue in $name' : 'Get $name',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context, _Offer.phoneBrowser),
            child: Text('Use my phone\'s browser',
                style: TextStyle(
                    color: Ui.muted, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
