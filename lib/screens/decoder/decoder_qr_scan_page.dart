import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';

/// Scans the QR code displayed by the Deeprowss TV/laptop receiver.
class DecoderQrScanPage extends StatefulWidget {
  const DecoderQrScanPage({super.key});

  @override
  State<DecoderQrScanPage> createState() => _DecoderQrScanPageState();
}

class _DecoderQrScanPageState extends State<DecoderQrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      try {
        final data = jsonDecode(raw);
        if (data is! Map || data['app'] != 'deeprowss' || data['v'] != 1) {
          throw const FormatException('This is not a Deeprowss receiver QR code.');
        }
        final room = data['room']?.toString() ?? '';
        final token = data['token']?.toString() ?? '';
        if (!RegExp(r'^[A-F0-9]{16}$').hasMatch(room) ||
            !RegExp(r'^[a-f0-9]{48}$').hasMatch(token)) {
          throw const FormatException('The receiver QR code is incomplete or invalid.');
        }
        _handled = true;
        await _controller.stop();
        if (!mounted) return;
        Navigator.of(context).pop(<String, String>{'room': room, 'token': token});
        return;
      } catch (e) {
        if (mounted) setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      backgroundColor: Ui.panel,
      title: const Text('Scan TV QR code', style: TextStyle(fontWeight: FontWeight.w900)),
      actions: [IconButton(
        tooltip: 'Switch camera',
        onPressed: () => _controller.switchCamera(),
        icon: const Icon(Icons.cameraswitch_rounded),
      )],
    ),
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Point your phone camera at the QR code displayed on your TV or laptop.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Ui.muted, fontSize: 14, height: 1.45),
        ),
      ),
      Expanded(child: Center(child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(22),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Ui.red, width: 3),
          ),
          child: MobileScanner(controller: _controller, onDetect: _onDetect),
        ),
      ))),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Text(_error!, textAlign: TextAlign.center,
            style: TextStyle(color: Ui.red, fontSize: 12)),
        ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const Icon(Icons.wifi, color: Colors.white60),
          const SizedBox(width: 9),
          Expanded(child: Text('Internet is required for secure pairing. Video streams directly between devices.',
            style: TextStyle(color: Ui.muted, fontSize: 11))),
        ]),
      ),
    ])),
  );
}
