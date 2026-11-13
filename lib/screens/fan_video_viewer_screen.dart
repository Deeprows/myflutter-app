import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/fan_post_video.dart';

/// Full-screen, X (Twitter) style video page: the video sits in the middle of
/// a black screen, a round back button, a rotate button and a "more" menu float
/// on top, and the author, caption and action row are pinned underneath.
/// Rotate switches to landscape (video fills the screen) and back.
class FanVideoViewerScreen extends StatefulWidget {
  final String url;

  /// Rebuilds [footerBuilder] when the post changes (like, repost, follow…).
  final Listenable refresh;
  final Widget Function(BuildContext context) menuBuilder;
  final Widget Function(BuildContext context) footerBuilder;
  const FanVideoViewerScreen({
    super.key,
    required this.url,
    required this.refresh,
    required this.menuBuilder,
    required this.footerBuilder,
  });

  @override
  State<FanVideoViewerScreen> createState() => _FanVideoViewerScreenState();
}

class _FanVideoViewerScreenState extends State<FanVideoViewerScreen> {
  bool _landscape = false;

  Future<void> _setLandscape(bool on) async {
    setState(() => _landscape = on);
    if (on) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Let the phone auto-rotate again afterwards.
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _round(Widget child) => Container(
    width: 40,
    height: 40,
    decoration: const BoxDecoration(
      color: Color(0x99000000),
      shape: BoxShape.circle,
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final top = _landscape ? 8.0 : MediaQuery.paddingOf(context).top;
    return PopScope(
      // Back in landscape first returns to portrait.
      canPop: !_landscape,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _landscape) _setLandscape(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FanPostVideo(
                      key: ValueKey('viewer-${widget.url}'),
                      url: widget.url,
                      inline: true,
                      viewer: true,
                      autoPlay: true,
                    ),
                  ),
                  Positioned(
                    top: top + 8,
                    left: 12,
                    child: _round(
                      IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Back',
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  Positioned(
                    top: top + 8,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _round(
                          IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: _landscape
                                ? 'Rotate to portrait'
                                : 'Rotate to landscape',
                            icon: Icon(
                              _landscape
                                  ? Icons.screen_lock_portrait_rounded
                                  : Icons.screen_rotation_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                            onPressed: () => _setLandscape(!_landscape),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _round(
                          Theme(
                            data: Theme.of(context).copyWith(
                              iconTheme: const IconThemeData(color: Colors.white),
                            ),
                            child: widget.menuBuilder(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!_landscape)
              Container(
                color: Colors.black,
                child: SafeArea(
                  top: false,
                  child: ListenableBuilder(
                    listenable: widget.refresh,
                    builder: (context, _) => widget.footerBuilder(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
