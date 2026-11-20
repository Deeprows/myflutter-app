import 'package:flutter/material.dart';

import '../models/cast_target.dart';
import 'decoder/decoder_hub_screen.dart';

/// Entry point used by the cast button in the players and by the drawer.
/// The decoder itself lives in lib/screens/decoder/.
class CastScreen extends StatelessWidget {
  final CastTarget? target;
  final VoidCallback? onCastStarted;
  final String? initialPage;
  const CastScreen({super.key, this.target, this.onCastStarted, this.initialPage});

  @override
  Widget build(BuildContext context) =>
      DecoderHubScreen(target: target, onCastStarted: onCastStarted, initialPage: initialPage);
}
