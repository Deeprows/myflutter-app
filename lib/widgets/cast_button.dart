import 'package:flutter/material.dart';

import '../models/cast_target.dart';

// Preserve the previous import surface for player pages that use CastTarget.
export '../models/cast_target.dart';
import '../screens/cast_screen.dart';
import '../services/cast_service.dart';
import '../theme/app_theme.dart';

/// Entry point used by channel, movie, trailer and local-video players.
/// Every cast icon opens the same dedicated decoder dashboard.
class CastButton extends StatelessWidget {
  final CastTarget Function() target;
  final VoidCallback? onCastStarted;
  final Color? color;
  final double? size;

  const CastButton({
    super.key,
    required this.target,
    this.onCastStarted,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final svc = CastService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final connected = svc.casting;
        return IconButton(
          tooltip: connected
              ? 'Casting to ${svc.device?.name ?? 'TV'}'
              : 'Open decoder / cast to screen',
          iconSize: size,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CastScreen(
              target: target(),
              onCastStarted: onCastStarted,
            ),
          )),
          icon: Icon(
            connected ? Icons.cast_connected_rounded : Icons.cast_rounded,
            color: connected ? Ui.red : color,
          ),
        );
      },
    );
  }
}
