import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/post_bookmarks.dart';
import '../theme/app_theme.dart';
import 'fan_post_card.dart';

/// The user's saved thread posts (menu → Bookmarks).
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    PostBookmarks.instance.load();
  }

  Future<void> _clearAll() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all bookmarks?'),
        content: const Text('Your saved posts will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (yes == true) await PostBookmarks.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.user?.id ?? '';
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: PostBookmarks.instance.posts,
            builder: (_, list, _) => list.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear all',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: _clearAll,
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: PostBookmarks.instance.posts,
        builder: (_, list, _) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border_rounded, size: 52, color: Ui.dim),
                    const SizedBox(height: 14),
                    const Text(
                      'Save posts for later',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the bookmark icon under any post on the Thread '
                      'page and it will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ui.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 28),
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: Ui.line),
            itemBuilder: (_, i) => FanPostCard(
              key: ValueKey('bm-${list[i]['id']}'),
              post: list[i],
              viewerId: me,
            ),
          );
        },
      ),
    );
  }
}
