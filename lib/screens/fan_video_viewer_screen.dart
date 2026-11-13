import 'package:flutter/material.dart';
import '../widgets/fan_post_video.dart';

/// Full-screen, X (Twitter) style video page: the video sits in the middle of
/// a black screen, a round back button and a "more" menu float on top, and the
/// author, caption and action row are pinned underneath.
class FanVideoViewerScreen extends StatelessWidget {
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
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FanPostVideo(
                    key: ValueKey('viewer-$url'),
                    url: url,
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
                  child: _round(
                    Theme(
                      data: Theme.of(context).copyWith(
                        iconTheme: const IconThemeData(color: Colors.white),
                      ),
                      child: menuBuilder(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: ListenableBuilder(
                listenable: refresh,
                builder: (context, _) => footerBuilder(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
