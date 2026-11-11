import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/bet_slip_pdf.dart';
import '../services/fan_zone_service.dart';
import '../services/remote_config.dart';
import '../theme/app_theme.dart';
import '../utils/safe_error_message.dart';
import '../widgets/bet_slip_card.dart';

/// "My Bet Slip": the selected AI picks drawn as a bookmaker-style slip that
/// can be shared as an image, posted to the community, or printed as a PDF.
class BetSlipScreen extends StatefulWidget {
  const BetSlipScreen({
    super.key,
    required this.entries,
    required this.onRemove,
    required this.onPrint,
    required this.onClear,
  });

  final List<MapEntry<String, BetSlipPick>> entries;
  final ValueChanged<String> onRemove;
  final VoidCallback onPrint;
  final VoidCallback onClear;

  @override
  State<BetSlipScreen> createState() => _BetSlipScreenState();
}

class _BetSlipScreenState extends State<BetSlipScreen> {
  late List<MapEntry<String, BetSlipPick>> _entries;
  final _boundary = GlobalKey();
  bool _capturing = false; // hides the remove buttons while the image is taken
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.entries);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  /// The slip as a PNG, exactly as drawn on screen (without remove buttons).
  Future<Uint8List> _capture() async {
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // The community accepts images up to 4 MB: lower the sharpness only if
      // a very long slip needs it.
      for (final ratio in const [3.0, 2.0, 1.5, 1.0]) {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) continue;
        final bytes = data.buffer.asUint8List();
        if (bytes.length <= 3800 * 1024 || ratio == 1.0) return bytes;
      }
      throw Exception('Could not create the slip image.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/bet-slip-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'My AI bet slip on Deeprowss: ${RemoteConfig.instance.shareLink}',
      );
    } catch (e) {
      _toast(safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _postToCommunity() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (!mounted) return;
      final caption = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _PostSlipSheet(image: bytes),
      );
      if (caption == null || !mounted) return;
      await FanZoneService.publish(kind: 'betslip', text: caption, image: bytes);
      _toast('Bet slip posted to Community Trend.');
    } catch (e) {
      _toast(safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(
          title: const Text('My Bet Slip',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            if (_entries.isNotEmpty)
              IconButton(
                tooltip: 'Print / Save PDF',
                icon: const Icon(Icons.print_rounded),
                onPressed: widget.onPrint,
              ),
            if (_entries.isNotEmpty)
              IconButton(
                tooltip: 'Clear slip',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  widget.onClear();
                  setState(_entries.clear);
                },
              ),
          ],
        ),
        body: _entries.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your bet slip is empty. Add predictions from AI analysis.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RepaintBoundary(
                        key: _boundary,
                        child: BetSlipCard(
                          entries: _entries,
                          onRemove: _capturing
                              ? null
                              : (key) {
                                  widget.onRemove(key);
                                  setState(() =>
                                      _entries.removeWhere((e) => e.key == key));
                                },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: _entries.isEmpty
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: Ui.card,
                    border: Border(top: BorderSide(color: Ui.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _shareImage,
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Share image'),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _postToCommunity,
                          icon: const Icon(Icons.forum_rounded),
                          label: const Text('Post'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
}

/// Preview of the slip image with an optional caption before it is posted.
class _PostSlipSheet extends StatefulWidget {
  const _PostSlipSheet({required this.image});
  final Uint8List image;

  @override
  State<_PostSlipSheet> createState() => _PostSlipSheetState();
}

class _PostSlipSheetState extends State<_PostSlipSheet> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Post bet slip to Community Trend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(widget.image, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _caption,
              maxLines: 3,
              minLines: 1,
              maxLength: 300,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add a caption (optional)…',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _caption.text.trim()),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}
