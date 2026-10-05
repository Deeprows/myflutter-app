import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/player_screen.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';

/// Bottom sheet to paste any m3u8 / mp4 / embed link and play it.
Future<void> showLinkSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LinkSheet(),
  );
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _c.text = data!.text!.trim();
        _error = null;
      });
    }
  }

  void _play() {
    final s = StreamResolver.resolve(_c.text);
    if (s.kind == StreamKind.invalid) {
      setState(() => _error = 'Enter a valid http(s) link');
      return;
    }
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: 'Custom stream',
        subtitle: s.url,
        url: s.url,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Keyboard height when typing, otherwise the phone's navigation bar, so
    // the Play button is never hidden underneath it.
    final bottomGap = mq.viewInsets.bottom > mq.viewPadding.bottom
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Play a link',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('m3u8, mp4, mpd, embed pages or any direct stream link.',
              style: TextStyle(color: Ui.muted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLines: 2,
            minLines: 1,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: 'https://…/stream.m3u8',
              errorText: _error,
              filled: true,
              fillColor: Ui.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _play,
              style: FilledButton.styleFrom(
                backgroundColor: Ui.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
