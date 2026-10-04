import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';

/// Paste any stream link (m3u8, mpd, mp4 or an embed page) and play it.
class NetworkStreamScreen extends StatefulWidget {
  const NetworkStreamScreen({super.key});

  @override
  State<NetworkStreamScreen> createState() => _NetworkStreamScreenState();
}

class _NetworkStreamScreenState extends State<NetworkStreamScreen> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    if (d?.text != null) setState(() => _ctrl.text = d!.text!.trim());
  }

  void _play() {
    final s = StreamResolver.resolve(_ctrl.text);
    if (s.kind == StreamKind.invalid) {
      setState(() => _error = 'Enter a valid http(s) link');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: 'Network Stream',
        subtitle: s.label,
        url: s.url,
        isLive: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network Stream')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Stream link',
                style: TextStyle(color: Ui.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _play(),
              decoration: InputDecoration(
                hintText: 'https://example.com/live.m3u8',
                errorText: _error,
                filled: true,
                fillColor: Ui.card,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Ui.line)),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _play,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 16),
            const Text('Supports m3u8 (HLS), mpd (DASH), mp4 and embed pages.',
                style: TextStyle(color: Ui.dim, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
