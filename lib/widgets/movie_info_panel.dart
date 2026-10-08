import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../models/movie_info.dart';
import '../theme/app_theme.dart';

/// Genres, key facts, overview, director and cast of a movie / series page.
/// Everything except the genres comes from TMDB, so while it loads (or when
/// TMDB has nothing for the title) the page simply shows less.
class MovieInfoPanel extends StatefulWidget {
  final Movie movie;
  final MovieInfo? info;
  final bool loading;
  const MovieInfoPanel({
    super.key,
    required this.movie,
    required this.info,
    required this.loading,
  });

  @override
  State<MovieInfoPanel> createState() => _MovieInfoPanelState();
}

class _MovieInfoPanelState extends State<MovieInfoPanel> {
  bool _more = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  String _date(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final genres = (info != null && info.genres.isNotEmpty)
        ? info.genres
        : widget.movie.genres;

    if (info == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (genres.isNotEmpty) _tags(genres),
            if (widget.loading) ...[
              const SizedBox(height: 22),
              for (final w in const [.35, 1.0, 1.0, .8]) _bar(w),
            ],
          ],
        ),
      );
    }

    final facts = <MapEntry<String, String>>[
      if (_date(info.releaseDate).isNotEmpty)
        MapEntry(info.isSeries ? 'First aired' : 'Released', _date(info.releaseDate)),
      if (info.runtimeText.isNotEmpty)
        MapEntry(info.isSeries ? 'Episode' : 'Runtime', info.runtimeText),
      if (info.isSeries && info.seasons != null)
        MapEntry('Seasons', '${info.seasons}'),
      if (info.isSeries && info.episodes != null)
        MapEntry('Episodes', '${info.episodes}'),
      if (info.status.isNotEmpty) MapEntry('Status', info.status),
      if (info.language.isNotEmpty) MapEntry('Language', info.language),
    ];

    final longText = info.overview.length > 220;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (genres.isNotEmpty) _tags(genres),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 26,
              runSpacing: 12,
              children: [
                for (final f in facts)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.key,
                          style: TextStyle(
                              color: Ui.dim,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(f.value,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
              ],
            ),
          ],
          if (info.overview.isNotEmpty) ...[
            const SizedBox(height: 22),
            _heading('Overview'),
            Text(
              info.overview,
              maxLines: _more ? null : 5,
              overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(color: Ui.muted, fontSize: 14, height: 1.5),
            ),
            if (longText)
              GestureDetector(
                onTap: () => setState(() => _more = !_more),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(_more ? 'Show less' : 'Read more',
                      style: TextStyle(
                          color: Ui.redSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
          if (info.directors.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: info.isSeries ? 'Created by  ' : 'Director  ',
                  style: TextStyle(
                      color: Ui.dim,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              TextSpan(
                  text: info.directors.take(3).join(', '),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
            ])),
          ],
          if (info.cast.isNotEmpty) ...[
            const SizedBox(height: 24),
            _heading('Cast'),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: info.cast.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _CastCard(info.cast[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      );

  Widget _tags(List<String> genres) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in genres.take(6))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Ui.red.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Ui.red.withValues(alpha: .35)),
              ),
              child: Text(g,
                  style: TextStyle(
                      color: Ui.redSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      );

  /// Grey placeholder line while the details load.
  Widget _bar(double width) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FractionallySizedBox(
          widthFactor: width,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      );
}

class _CastCard extends StatelessWidget {
  final CastMember c;
  const _CastCard(this.c);

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
          color: Ui.card,
          alignment: Alignment.center,
          child: Icon(Icons.person_rounded, color: Ui.dim, size: 30),
        );
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: c.hasPhoto
                  ? Image.network(c.photo,
                      fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback())
                  : fallback(),
            ),
          ),
          const SizedBox(height: 7),
          Text(c.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w800)),
          if (c.character.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(c.character,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ui.dim, fontSize: 10.5)),
            ),
        ],
      ),
    );
  }
}
