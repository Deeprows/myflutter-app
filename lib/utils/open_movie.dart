import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../screens/player_screen.dart';
import 'premium_gate.dart';

/// Opens the player page for a movie or series. Non-Premium people are sent to
/// the upgrade page instead (see [PremiumGate]).
Future<void> openMoviePlayer(BuildContext context, Movie m) async {
  if (!await PremiumGate.allowMovies(context)) return;
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
