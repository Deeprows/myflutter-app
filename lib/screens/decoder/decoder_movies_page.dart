import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../models/movie.dart';
import '../../services/feed_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';

/// Search-only movie picker for Smart Decoder. Selecting a title opens the
/// screen destination picker; the movie is never played inside the app.
class DecoderMoviesPage extends StatefulWidget {
  const DecoderMoviesPage({super.key});
  @override
  State<DecoderMoviesPage> createState() => _DecoderMoviesPageState();
}

class _DecoderMoviesPageState extends State<DecoderMoviesPage> {
  final _search = TextEditingController();
  List<Movie> _movies = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final movies = await FeedService().loadMovies(remote: true);
      if (!mounted) return;
      setState(() { _movies = movies; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Movie movie) async {
    if (movie.url.trim().isEmpty) {
      decoderToast(context, 'No cast link is available for this title.');
      return;
    }
    await chooseConnectivity(
      context,
      CastTarget(title: movie.name, url: movie.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final shown = query.isEmpty
        ? <Movie>[]
        : _movies.where((m) => m.name.toLowerCase().contains(query)).take(40).toList();

    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Pick a Movie & Watch', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (value) => setState(() => _query = value.trim()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search movies and series',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty ? null : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
              filled: true,
              fillColor: Ui.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _query.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.movie_filter_rounded, color: Ui.muted, size: 42),
                    const SizedBox(height: 10),
                    Text('Search for a movie to cast it to your screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Ui.muted, fontSize: 13)),
                  ]),
                )
              : _loading && _movies.isEmpty
                  ? Center(child: Text('Loading movie library…', style: TextStyle(color: Ui.muted)))
                  : shown.isEmpty
                      ? Center(child: Text('No matching movies found.', style: TextStyle(color: Ui.muted)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => Divider(color: Ui.line, height: 1),
                          itemBuilder: (context, index) {
                            final movie = shown[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: SizedBox(
                                  width: 48,
                                  height: 68,
                                  child: movie.hasImage
                                      ? Image.network(movie.image, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Ui.panel,
                                            child: const Icon(Icons.movie_outlined),
                                          ))
                                      : Container(color: Ui.panel,
                                          child: const Icon(Icons.movie_outlined)),
                                ),
                              ),
                              title: Text(movie.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800, fontSize: 13)),
                              subtitle: Text(
                                [movie.isSeries ? 'Series' : 'Movie', if (movie.year != null) movie.year!, if (movie.rating != null) movie.rating!].join(' · '),
                                maxLines: 1,
                                style: TextStyle(color: Ui.muted, fontSize: 11),
                              ),
                              trailing: Icon(Icons.cast_rounded, color: Ui.red, size: 21),
                              onTap: () => _select(movie),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
