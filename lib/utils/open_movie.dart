import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../screens/player_screen.dart';
import 'premium_gate.dart';

/// Opens the player after checking the shared three-title free allowance.
/// After that, non-Premium people are sent to the upgrade page.
Future<void> openMoviePlayer(BuildContext context, Movie m) async {
  final key = '${m.isSeries ? 'tv' : 'movie'}:${m.tmdbId ?? m.title.toLowerCase()}';
  if (!await PremiumGate.allowMovies(context, key, action: 'play')) return;
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PlayerScreen(
      title: m.title,
      subtitle: [
        m.isSeries ? 'Series' : 'Movie',
        if (m.year != null) m.year!,
        if (m.rating != null) '★ ${m.rating}',
      ].join(' · '),
      url: m.url,
      altUrl: m.altUrl,
      movie: m,
    ),
  ));
}
