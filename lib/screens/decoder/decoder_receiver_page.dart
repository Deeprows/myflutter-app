import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cast_target.dart';
import '../../services/webrtc_mirror_service.dart';
import '../../services/stream_resolver.dart' show StreamKind;
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_qr_scan_page.dart';

class DecoderReceiverPage extends StatefulWidget {
  final CastTarget? target;
  const DecoderReceiverPage({super.key, this.target});
  @override
  State<DecoderReceiverPage> createState() => _DecoderReceiverPageState();
}

class _DecoderReceiverPageState extends State<DecoderReceiverPage> {
  final m = DeeprowssMirrorService.instance;
  bool _busy = false;

  /// Counts fingers that are on a remote button. While > 0 the page does not
  /// scroll, so pressing and holding a button can never scroll the page.
  final ValueNotifier<int> _touching = ValueNotifier<int>(0);
  DateTime _lastToast = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _touching.dispose();
    super.dispose();
  }

  // ───────────────────────── connection ─────────────────────────

  Future<void> _scanAndConnect() async {
    final pair = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => const DecoderQrScanPage()),
    );
    if (!mounted || pair == null) return;
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false, relayRoom: pair['room'], relayToken: pair['token']);
      final target = widget.target;
      if (target != null && (target.url ?? '').trim().isNotEmpty) {
        await m.sendChannel(url: target.url!, title: target.title,
          kind: target.kind == StreamKind.invalid ? StreamKind.embed : target.kind,
          referer: target.referer, userAgent: target.userAgent,
          backupUrl: target.backup?.url, backupKind: target.backup?.kind);
      }
      if (mounted) decoderToast(context, target == null ? 'Paired with receiver. Choose a video or channel to send.' : 'Sending ' + target.title + ' to your receiver.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not connect to receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLegacy() async {
    setState(() => _busy = true);
    try {
      await m.start(captureScreen: false);
      if (mounted) decoderToast(context, 'Manual receiver session started.');
    } catch (_) {
      if (mounted) decoderToast(context, m.error ?? 'Could not start receiver.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── remote keys ─────────────────────────

  /// Sends one remote key. Returns false when the receiver is not connected
  /// (the toast is rate-limited so a held button does not spam the screen).
  bool _key(String command) {
    final ok = m.sendRemoteKey(command);
    if (!ok && mounted) {
      final now = DateTime.now();
      if (now.difference(_lastToast).inMilliseconds > 2500) {
        _lastToast = now;
        decoderToast(context, 'Receiver is not connected yet.');
      }
    }
    return ok;
  }

  Future<void> _confirmOff() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ui.panel,
        title: Text('Turn off receiver?', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900)),
        content: Text('This closes the Deeprowss app on the TV or PC.', style: TextStyle(color: Ui.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (go == true) {
      HapticFeedback.mediumImpact();
      _key('off');
    }
  }

  Future<void> _openKeyboard() async {
    final ctrl = TextEditingController();
    Timer? debounce;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ui.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.keyboard_alt_outlined, color: Ui.red),
            const SizedBox(width: 10),
            Expanded(child: Text('Phone keyboard', style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900, fontSize: 16))),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close_rounded, color: Ui.muted)),
          ]),
          Text('Select a search box on the TV first, then type here. Text appears on the TV as you type.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: Ui.text),
            decoration: InputDecoration(
              hintText: 'Type to search…',
              hintStyle: TextStyle(color: Ui.muted),
              filled: true,
              fillColor: Ui.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Ui.line)),
              suffixIcon: IconButton(
                icon: Icon(Icons.backspace_outlined, color: Ui.muted),
                onPressed: () {
                  ctrl.clear();
                  m.sendRemoteCommand('clear');
                },
              ),
            ),
            onChanged: (v) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 350), () => m.sendRemoteText(v));
            },
            onSubmitted: (v) {
              debounce?.cancel();
              m.sendRemoteText(v, submit: true);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () {
              debounce?.cancel();
              m.sendRemoteText(ctrl.text, submit: true);
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search on TV'),
          )),
        ]),
      ),
    );
    debounce?.cancel();
    ctrl.dispose();
  }

  // ───────────────────────── labels ─────────────────────────

  String get _screenLabel {
    if (m.receiverPlayerOpen) {
      return m.nowPlayingTitle.isEmpty ? 'Playing on receiver' : m.nowPlayingTitle;
    }
    if (m.receiverOverlay) return 'Dialog open on receiver';
    final pc = m.receiverIsDesktop;
    switch (m.receiverView) {
      case 'movies':
        return pc ? 'Browsing movies on the PC' : 'Browsing movies on the TV';
      case 'tv':
        return 'TV channels';
      case 'fixtures':
        return 'Live football';
      case 'downloads':
        return 'Download apps';
      case 'learn':
        return 'Learn';
      case 'connect':
        return 'Receiver is waiting for a video';
      default:
        return pc ? 'Windows app home screen' : 'TV home screen';
    }
  }

  String get _hint {
    final playing = m.receiverPlayerOpen;
    if (m.receiverIsDesktop) {
      return playing
          ? 'Windows app: OK / Play taps the player. If an ad eats the first tap, press it again. Full screen fills the PC screen (F11 or Esc leaves it).'
          : 'Windows app: arrows and OK move around the app. Hold an arrow to keep moving. Back closes dialogs; Home always returns to the start screen.';
    }
    if (playing) {
      if (m.receiverMode == 'iframe') {
        return m.receiverIsTv
            ? 'OK / Play taps the player. If an ad eats the first tap, press it again. Embedded providers may ignore seek and volume.'
            : 'Embedded providers may ignore some buttons (seek, volume). Back and Home always work.';
      }
      return 'Left / Right seek ±10 s and Up / Down change the volume while a video is open. OK toggles play / pause.';
    }
    return 'Use the wheel to browse. Hold an arrow to keep moving. Back closes dialogs; Home always returns to the start screen.';
  }

  // ───────────────────────── remote body ─────────────────────────

  Widget _remote() {
    final playing = m.receiverPlayerOpen;
    final mirror = m.receiverMode == 'mirror';
    final canPlay = playing && !mirror;
    final pc = m.receiverIsDesktop;
    final canFull = (canPlay || mirror || pc) && !m.receiverIsTv;
    final vol = m.receiverMuted ? 0 : m.receiverVolume;

    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 296), child: Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ui.cardDeep, Ui.card],
        ),
        border: Border.all(color: Ui.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        // ── top row: power · screen status · menu ──
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _Round(icon: Icons.power_settings_new_rounded, size: 38, tone: _Tone.danger, onPress: _confirmOff, lock: _touching, semantics: 'Power off'),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => decoderToast(context, '$_hint Tip: drag on OK to move a cursor, tap OK to click, double-tap OK to double-click.'),
            child: _statusChip(playing),
          )),
          const SizedBox(width: 8),
          _Round(icon: Icons.settings_rounded, size: 38, onPress: () => _key('menu'), lock: _touching, semantics: 'Settings menu'),
        ]),
        const SizedBox(height: 8),

        // ── navigation wheel ──
        _DPad(
          onKey: _key,
          onCursor: (dx, dy) => m.sendRemoteCommand('cursor', text: '${dx.toStringAsFixed(1)},${dy.toStringAsFixed(1)}'),
          lock: _touching,
        ),
        const SizedBox(height: 8),

        // ── back · home · full screen ──
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _LabeledRound(icon: Icons.arrow_back_rounded, label: 'Back', onPress: () => _key('back'), lock: _touching),
          _LabeledRound(icon: Icons.home_rounded, label: 'Home', onPress: () => _key('home'), lock: _touching, tone: _Tone.accent),
          _LabeledRound(
            icon: m.receiverFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            label: m.receiverFullscreen ? 'Exit full' : 'Full screen',
            onPress: canFull ? () => _key('fullscreen') : null,
            lock: _touching,
          ),
        ]),
        const SizedBox(height: 8),

        // ── volume · mute / keyboard · page ──
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
          _Rocker(
            label: 'VOL',
            sub: playing ? (m.receiverMuted ? 'MUTE' : '$vol%') : '',
            upIcon: Icons.add_rounded,
            downIcon: Icons.remove_rounded,
            enabled: playing,
            onUp: () => m.nudgeReceiverVolume(10),
            onDown: () => m.nudgeReceiverVolume(-10),
            lock: _touching,
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            _LabeledRound(
              icon: m.receiverMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              label: m.receiverMuted ? 'Unmute' : 'Mute',
              onPress: playing ? () => m.toggleReceiverMute() : null,
              lock: _touching,
              size: 38,
            ),
            const SizedBox(height: 8),
            _LabeledRound(icon: Icons.keyboard_alt_outlined, label: 'Keyboard', onPress: _openKeyboard, lock: _touching, size: 38),
          ]),
          _Rocker(
            label: 'PAGE',
            sub: '',
            upIcon: Icons.keyboard_arrow_up_rounded,
            downIcon: Icons.keyboard_arrow_down_rounded,
            enabled: true,
            onUp: () => _key('chup'),
            onDown: () => _key('chdown'),
            lock: _touching,
          ),
        ]),
        const SizedBox(height: 8),

        // ── transport ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Ui.bg.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Ui.line),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Round(icon: Icons.replay_10_rounded, size: 38, onPress: canPlay ? () => _key('rewind') : null, lock: _touching, semantics: 'Back 10 seconds'),
            _Round(
              icon: m.receiverPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 52,
              tone: _Tone.accent,
              iconSize: 28,
              onPress: canPlay ? () => m.toggleReceiverPlay() : null,
              lock: _touching,
              semantics: m.receiverPlaying ? 'Pause' : 'Play',
            ),
            _Round(icon: Icons.forward_10_rounded, size: 38, onPress: canPlay ? () => _key('forward') : null, lock: _touching, semantics: 'Forward 10 seconds'),
            _Round(icon: Icons.stop_rounded, size: 38, onPress: playing ? () => m.stopPlayback() : null, lock: _touching, semantics: 'Stop'),
          ]),
        ),
        if (m.receiverHasBackup) ...[
          const SizedBox(height: 8),
          _Pill(
            icon: Icons.swap_horiz_rounded,
            label: 'Switch to backup stream',
            lock: _touching,
            onPress: () {
              if (!m.switchToBackup()) decoderToast(context, 'Receiver is not connected yet.');
            },
          ),
        ],
        const SizedBox(height: 8),

        // ── app shortcuts ──
        Align(alignment: Alignment.centerLeft, child: Text('QUICK ACCESS',
          style: TextStyle(color: Ui.muted, fontSize: 9, letterSpacing: 1.3, fontWeight: FontWeight.w900))),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          childAspectRatio: 2.1,
          children: [
            _AppTile(icon: Icons.movie_creation_outlined, label: 'Movies', color: const Color(0xFFE5484D), onPress: () => _key('movies'), lock: _touching),
            _AppTile(icon: Icons.live_tv_rounded, label: 'TV channels', color: const Color(0xFF3E8BFF), onPress: () => _key('tv'), lock: _touching),
            _AppTile(icon: Icons.sports_soccer_rounded, label: 'Live football', color: const Color(0xFF2FB36B), onPress: () => _key('football'), lock: _touching),
            _AppTile(icon: Icons.download_rounded, label: 'Download apps', color: const Color(0xFFF59E0B), onPress: () => _key('downloads'), lock: _touching),
            _AppTile(icon: Icons.qr_code_2_rounded, label: 'Connect app', color: const Color(0xFF8B5CF6), onPress: () => _key('connect'), lock: _touching),
            _AppTile(icon: Icons.workspace_premium_rounded, label: 'Subscribe', color: const Color(0xFFEC4899), onPress: () => _key('subscribe'), lock: _touching),
          ],
        ),
        const SizedBox(height: 8),
        Text('$_hint\nTip: drag on OK to move a cursor · tap OK to click · double-tap OK to double-click.', textAlign: TextAlign.center, style: TextStyle(color: Ui.muted, fontSize: 10, height: 1.3)),
      ]),
    )));
  }

  Widget _statusChip(bool playing) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Ui.bg.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Ui.line),
    ),
    child: Row(children: [
      Icon(playing ? Icons.play_circle_fill_rounded : Icons.settings_remote_rounded, size: 18, color: Ui.red),
      const SizedBox(width: 6),
      Expanded(child: Text(_screenLabel, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 11, height: 1.15))),
    ]),
  );

  // ───────────────────────── page ─────────────────────────

  Widget _connectionCard() => decoderPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(Icons.connected_tv_rounded, size: 29, color: Ui.red),
      const SizedBox(width: 11),
      Expanded(child: Text(m.running ? m.status : 'No receiver connected',
        style: TextStyle(color: Ui.text, fontWeight: FontWeight.w900))),
      Icon(Icons.circle, size: 10, color: m.connected ? Colors.green : Ui.muted),
    ]),
    if (!m.running) ...[
      const SizedBox(height: 10),
      Text('On your TV or laptop, open the Deeprowss Receiver page, or open the Deeprowss Cinema Windows app and choose Cast from Phone. Scan the QR code shown there with your phone to connect.',
        style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5)),
    ],
    const SizedBox(height: 14),
    if (!m.running) ...[
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _busy ? null : _scanAndConnect,
        icon: _busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.qr_code_scanner_rounded),
        label: Text(_busy ? 'Connecting…' : 'Scan TV QR code'))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _busy ? null : _startLegacy,
        icon: const Icon(Icons.pin_outlined), label: const Text('Use legacy PIN connection'))),
    ] else
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () async { await m.stop(); },
        icon: const Icon(Icons.stop_circle_outlined), label: const Text('Disconnect receiver'))),
    if (m.error != null) Padding(padding: const EdgeInsets.only(top: 10),
      child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize: 12))),
  ]));

  /// One-line version of the connection card, used while the remote is shown
  /// so the whole remote fits on screen without scrolling.
  Widget _compactConnectionCard() => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    decoration: BoxDecoration(
      color: Ui.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Ui.line),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.connected_tv_rounded, size: 22, color: Ui.red),
        const SizedBox(width: 8),
        Expanded(child: Text(m.status, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 13))),
        Icon(Icons.circle, size: 9, color: m.connected ? Colors.green : Ui.muted),
        const SizedBox(width: 4),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: () async { await m.stop(); },
          child: const Text('Disconnect', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
      ]),
      if (m.error != null) Padding(padding: const EdgeInsets.only(bottom: 4),
        child: Text(m.error!, style: TextStyle(color: Ui.red, fontSize: 11))),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(backgroundColor: Ui.panel,
      title: const Text('Connect to receiver', style: TextStyle(fontWeight: FontWeight.w900))),
    body: ListenableBuilder(listenable: m, builder: (context, _) => m.running
      // Connected: no scrolling. The remote is scaled down to fit the free height.
      ? SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(children: [
            _compactConnectionCard(),
            const SizedBox(height: 10),
            Expanded(child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(width: 296, child: _remote()),
            )),
          ]),
        ))
      : ValueListenableBuilder<int>(
      valueListenable: _touching,
      builder: (context, touching, _) => ListView(
        physics: touching > 0 ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewPadding.bottom + 28),
        children: [
          _connectionCard(),
          decoderPanel(Text('The QR code pairs your phone with the TV. Video and audio travel directly between devices using WebRTC; the pairing service only relays connection messages.',
            style: TextStyle(color: Ui.muted, fontSize: 12, height: 1.5))),
        ],
      ),
    )),
  );
}

// ═══════════════════════════ remote widgets ═══════════════════════════

enum _Tone { normal, accent, danger }

/// A button that reacts the moment a finger touches it (like a real remote),
/// shrinks while pressed, and optionally repeats while it is held down.
class _Press extends StatefulWidget {
  final VoidCallback? onPress;
  final ValueNotifier<int>? lock;
  final int repeatMs; // 0 = no repeat
  final Widget Function(bool pressed) builder;
  const _Press({required this.onPress, required this.builder, this.lock, this.repeatMs = 0});
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  Timer? _hold;
  Timer? _rep;

  void _stopTimers() {
    _hold?.cancel();
    _rep?.cancel();
    _hold = null;
    _rep = null;
  }

  void _start() {
    final cb = widget.onPress;
    if (cb == null || _down) return;
    setState(() => _down = true);
    widget.lock?.value++;
    HapticFeedback.selectionClick();
    cb();
    if (widget.repeatMs > 0) {
      _hold = Timer(const Duration(milliseconds: 380), () {
        _rep = Timer.periodic(Duration(milliseconds: widget.repeatMs), (_) {
          final c = widget.onPress;
          if (c == null) {
            _stopTimers();
            return;
          }
          c();
        });
      });
    }
  }

  void _end() {
    if (!_down) return;
    _stopTimers();
    final l = widget.lock;
    if (l != null && l.value > 0) l.value--;
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _stopTimers();
    if (_down) {
      final l = widget.lock;
      if (l != null && l.value > 0) l.value--;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPress != null;
    return Opacity(
      opacity: enabled ? 1 : .38,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: const Duration(milliseconds: 70),
          child: widget.builder(_down),
        ),
      ),
    );
  }
}

Color _toneFill(_Tone t, bool pressed) {
  switch (t) {
    case _Tone.accent:
      return Ui.red.withValues(alpha: pressed ? .45 : .22);
    case _Tone.danger:
      return const Color(0xFFF0445E).withValues(alpha: pressed ? .4 : .18);
    case _Tone.normal:
      return pressed ? Ui.line : Ui.card;
  }
}

Color _toneBorder(_Tone t) {
  switch (t) {
    case _Tone.accent:
      return Ui.red;
    case _Tone.danger:
      return const Color(0x99F0445E);
    case _Tone.normal:
      return Ui.line;
  }
}

Color _toneIcon(_Tone t) {
  switch (t) {
    case _Tone.accent:
      return Ui.red;
    case _Tone.danger:
      return const Color(0xFFFF7185);
    case _Tone.normal:
      return Ui.text;
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final double size;
  final double? iconSize;
  final _Tone tone;
  final VoidCallback? onPress;
  final ValueNotifier<int>? lock;
  final int repeatMs;
  final String? semantics;
  const _Round({
    required this.icon,
    required this.onPress,
    this.size = 56,
    this.iconSize,
    this.tone = _Tone.normal,
    this.lock,
    this.repeatMs = 0,
    this.semantics,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    child: _Press(
      onPress: onPress,
      lock: lock,
      repeatMs: repeatMs,
      builder: (pressed) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _toneFill(tone, pressed),
          border: Border.all(color: _toneBorder(tone), width: tone == _Tone.normal ? 1 : 1.6),
          boxShadow: pressed ? null : [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Icon(icon, size: iconSize ?? size * .46, color: _toneIcon(tone)),
      ),
    ),
  );
}

class _LabeledRound extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPress;
  final ValueNotifier<int>? lock;
  final _Tone tone;
  final double size;
  const _LabeledRound({
    required this.icon,
    required this.label,
    required this.onPress,
    this.lock,
    this.tone = _Tone.normal,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _Round(icon: icon, onPress: onPress, lock: lock, tone: tone, size: size, semantics: label),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1,
        style: TextStyle(color: Ui.muted, fontSize: 10, fontWeight: FontWeight.w700))),
    ]),
  );
}

/// Vertical two-way pill (volume / page) like the rockers on a TV remote.
class _Rocker extends StatelessWidget {
  final String label;
  final String sub;
  final IconData upIcon;
  final IconData downIcon;
  final bool enabled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueNotifier<int> lock;
  const _Rocker({
    required this.label,
    required this.sub,
    required this.upIcon,
    required this.downIcon,
    required this.enabled,
    required this.onUp,
    required this.onDown,
    required this.lock,
  });

  Widget _half(IconData icon, VoidCallback cb, bool top) => _Press(
    onPress: enabled ? cb : null,
    lock: lock,
    repeatMs: 170,
    builder: (pressed) => Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pressed ? Ui.red.withValues(alpha: .28) : Colors.transparent,
        borderRadius: BorderRadius.vertical(
          top: top ? const Radius.circular(26) : Radius.zero,
          bottom: top ? Radius.zero : const Radius.circular(26),
        ),
      ),
      child: Icon(icon, size: 24, color: Ui.text),
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    width: 58,
    decoration: BoxDecoration(
      color: Ui.card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Ui.line),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _half(upIcon, onUp, true),
      Container(
        height: 30,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(color: Ui.muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(color: Ui.red, fontSize: 9, fontWeight: FontWeight.w800)),
        ]),
      ),
      _half(downIcon, onDown, false),
    ]),
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final ValueNotifier<int> lock;
  const _Pill({required this.icon, required this.label, required this.onPress, required this.lock});

  @override
  Widget build(BuildContext context) => _Press(
    onPress: onPress,
    lock: lock,
    builder: (pressed) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _toneFill(_Tone.accent, pressed),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Ui.red),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: Ui.red),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    ),
  );
}

class _AppTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPress;
  final ValueNotifier<int> lock;
  const _AppTile({required this.icon, required this.label, required this.color, required this.onPress, required this.lock});

  @override
  Widget build(BuildContext context) => _Press(
    onPress: onPress,
    lock: lock,
    builder: (pressed) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Color.alphaBlend(color.withValues(alpha: pressed ? .34 : .16), Ui.card),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1,
          style: TextStyle(color: Ui.text, fontSize: 10, fontWeight: FontWeight.w800))),
      ]),
    ),
  );
}

/// The navigation wheel: four arrow segments around a round OK button.
/// Touch reacts instantly, sliding the finger moves to the next segment and
/// holding an arrow repeats it, exactly like holding a TV remote key.
class _DPad extends StatefulWidget {
  final bool Function(String) onKey;
  /// Touchpad movement (logical px) while a finger drags on the OK button.
  final void Function(double dx, double dy)? onCursor;
  final ValueNotifier<int> lock;
  const _DPad({required this.onKey, required this.lock, this.onCursor});
  @override
  State<_DPad> createState() => _DPadState();
}

class _DPadState extends State<_DPad> {
  String? _zone;
  bool _touching = false;
  Timer? _hold;
  Timer? _rep;

  // OK button doubles as a touchpad: a tap clicks, a drag moves the cursor.
  bool _okActive = false;
  bool _dragging = false;
  Offset _okStart = Offset.zero;
  Offset _okLast = Offset.zero;
  double _pdx = 0, _pdy = 0;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  static const okRatio = .40;
  static const _dragSlop = 9.0;

  String? _hit(Offset p, double size) {
    final r0 = size / 2;
    final d = p - Offset(r0, r0);
    final r = d.distance;
    if (r > r0) return null;
    if (r < r0 * okRatio) return 'enter';
    final a = math.atan2(d.dy, d.dx); // 0 = right, pi/2 = down
    if (a >= -math.pi / 4 && a < math.pi / 4) return 'right';
    if (a >= math.pi / 4 && a < 3 * math.pi / 4) return 'down';
    if (a >= -3 * math.pi / 4 && a < -math.pi / 4) return 'up';
    return 'left';
  }

  void _stopTimers() {
    _hold?.cancel();
    _rep?.cancel();
    _hold = null;
    _rep = null;
  }

  void _press(String zone) {
    _stopTimers();
    setState(() => _zone = zone);
    HapticFeedback.lightImpact();
    if (!widget.onKey(zone)) return;
    if (zone == 'enter') return;
    _hold = Timer(const Duration(milliseconds: 380), () {
      _rep = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!widget.onKey(zone)) _stopTimers();
      });
    });
  }

  void _down(Offset p, double size) {
    if (!_touching) {
      _touching = true;
      widget.lock.value++;
    }
    final z = _hit(p, size);
    if (z == 'enter') {
      // Wait to see whether this becomes a drag (cursor) or a tap (click).
      _stopTimers();
      _okActive = true;
      _dragging = false;
      _okStart = p;
      _okLast = p;
      _pdx = 0;
      _pdy = 0;
      setState(() => _zone = 'enter');
      return;
    }
    if (z != null) _press(z);
  }

  void _flushCursor(bool force) {
    if (_pdx == 0 && _pdy == 0) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSend).inMilliseconds < 28) return;
    _lastSend = now;
    widget.onCursor?.call(_pdx, _pdy);
    _pdx = 0;
    _pdy = 0;
  }

  void _move(Offset p, double size) {
    if (!_touching) return;
    if (_okActive) {
      final d = p - _okLast;
      _okLast = p;
      if (!_dragging) {
        final off = p - _okStart;
        if (off.distance < _dragSlop) return;
        _dragging = true;
        HapticFeedback.selectionClick();
        _pdx += off.dx;
        _pdy += off.dy;
        setState(() {});
      } else {
        _pdx += d.dx;
        _pdy += d.dy;
      }
      _flushCursor(false);
      return;
    }
    final z = _hit(p, size);
    if (z == _zone) return;
    if (z == null) {
      _stopTimers();
      setState(() => _zone = null);
    } else {
      _press(z);
    }
  }

  void _up({bool cancel = false}) {
    _stopTimers();
    if (_okActive) {
      if (_dragging) {
        _flushCursor(true);
      } else if (!cancel) {
        HapticFeedback.lightImpact();
        widget.onKey('enter'); // tap = click (two quick taps = double click on the receiver)
      }
      _okActive = false;
      _dragging = false;
    }
    if (_touching) {
      _touching = false;
      if (widget.lock.value > 0) widget.lock.value--;
    }
    if (mounted) setState(() => _zone = null);
  }

  @override
  void dispose() {
    _stopTimers();
    if (_touching && widget.lock.value > 0) widget.lock.value--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final size = math.min(c.maxWidth, 180.0);
    return Center(
      child: Semantics(
        label: 'Navigation wheel. Up, down, left, right and OK',
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e.localPosition, size),
          onPointerMove: (e) => _move(e.localPosition, size),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(cancel: true),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _PadPainter(
                zone: _zone,
                dragging: _dragging,
                accent: Ui.red,
                surface: Ui.card,
                deep: Ui.bg,
                line: Ui.line,
                text: Ui.text,
              ),
            ),
          ),
        ),
      ),
    );
  });
}

class _PadPainter extends CustomPainter {
  final String? zone;
  final bool dragging;
  final Color accent;
  final Color surface;
  final Color deep;
  final Color line;
  final Color text;
  const _PadPainter({
    required this.zone,
    this.dragging = false,
    required this.accent,
    required this.surface,
    required this.deep,
    required this.line,
    required this.text,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final okR = r * _DPadState.okRatio;

    // soft shadow + ring body
    canvas.drawCircle(c + const Offset(0, 6), r - 2,
      Paint()..color = Colors.black.withValues(alpha: .30)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(c, r - 1, Paint()
      ..shader = RadialGradient(colors: [surface, Color.alphaBlend(deep.withValues(alpha: .55), surface)])
          .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r - 1, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = line);

    // pressed segment
    if (zone != null && zone != 'enter') {
      double start;
      switch (zone) {
        case 'right':
          start = -math.pi / 4;
          break;
        case 'down':
          start = math.pi / 4;
          break;
        case 'left':
          start = 3 * math.pi / 4;
          break;
        default: // up
          start = -3 * math.pi / 4;
      }
      const sweep = math.pi / 2;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: c, radius: r - 2), start, sweep, true)
        ..arcTo(Rect.fromCircle(center: c, radius: okR + 6), start + sweep, -sweep, false)
        ..close();
      canvas.drawPath(path, Paint()..color = accent.withValues(alpha: .34));
    }

    // diagonal dividers
    final div = Paint()..color = line.withValues(alpha: .8)..strokeWidth = 1.3..strokeCap = StrokeCap.round;
    for (final a in [math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4]) {
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (okR + 12), c + dir * (r - 12), div);
    }

    // arrows
    void chevron(String name, double angle) {
      final active = zone == name;
      final p = c + Offset(math.cos(angle), math.sin(angle)) * (r * .72);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + math.pi / 2);
      final s = r * .085;
      final path = Path()
        ..moveTo(-s * 1.2, s * .6)
        ..lineTo(0, -s * .7)
        ..lineTo(s * 1.2, s * .6);
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 5 : 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = active ? accent : text.withValues(alpha: .9));
      canvas.restore();
    }
    chevron('up', -math.pi / 2);
    chevron('right', 0);
    chevron('down', math.pi / 2);
    chevron('left', math.pi);

    // OK button
    final okPressed = zone == 'enter' || dragging;
    canvas.drawCircle(c, okR + 3, Paint()..color = deep.withValues(alpha: .55));
    canvas.drawCircle(c, okR, Paint()..color = accent.withValues(alpha: okPressed ? .42 : .18));
    canvas.drawCircle(c, okR, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = accent);
    final tp = TextPainter(
      text: TextSpan(text: 'OK', style: TextStyle(color: okPressed ? accent : text, fontSize: r * .15, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) =>
      old.zone != zone || old.dragging != dragging || old.accent != accent || old.surface != surface || old.line != line || old.text != text || old.deep != deep;
}
