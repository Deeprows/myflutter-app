import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../screens/player_screen.dart';

/// Opens the player page for a movie or series.
void openMoviePlayer(BuildContext context, Movie m) {
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
