import 'package:flutter/material.dart';

import '../../models/cast_target.dart';
import '../../models/movie.dart';
import '../../services/feed_service.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';

class DecoderMoviesPage extends StatefulWidget {
  const DecoderMoviesPage({super.key});
  @override
  State<DecoderMoviesPage> createState() => _DecoderMoviesPageState();
}

class _DecoderMoviesPageState extends State<DecoderMoviesPage> {
  List<Movie> _movies = const [];
  bool _loading = true;
  String _query = '';
  String _genre = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final movies = await FeedService().loadMovies(remote: true);
    if (!mounted) return;
    setState(() { _movies = movies; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final genres = <String>{'All', ..._movies.expand((m) => m.genres)}.toList()..sort();
    final shown = _movies.where((m) =>
      (_query.isEmpty || m.name.toLowerCase().contains(_query.toLowerCase())) &&
      (_genre == 'All' || m.genres.contains(_genre))).toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: const Text('Movies & series', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search movies and series'),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [for (final g in genres) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(label: Text(g), selected: _genre == g, onSelected: (_) => setState(() => _genre = g)),
                )],
              ),
            ),
            Expanded(child: shown.isEmpty
              ? Center(child: Text('No movies found.', style: TextStyle(color: Ui.muted)))
              : GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, childAspectRatio: .57, crossAxisSpacing: 12, mainAxisSpacing: 14),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final m = shown[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => chooseConnectivity(context, CastTarget(
                        title: m.name, url: m.url,
                      )),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(fit: StackFit.expand, children: [
                            if (m.hasImage) Image.network(m.image, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Ui.panel, child: const Icon(Icons.movie, size: 40)))
                            else Container(color: Ui.panel, child: const Icon(Icons.movie, size: 40)),
                            Positioned(right: 8, bottom: 8, child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow, color: Colors.white),
                            )),
                          ]),
                        )),
                        const SizedBox(height: 7),
                        Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.text, fontWeight: FontWeight.w800)),
                        Text('${m.isSeries ? 'Series' : 'Movie'}${m.rating == null ? '' : ' · ★ ${m.rating}'}',
                          style: TextStyle(color: Ui.muted, fontSize: 11)),
                      ]),
                    );
                  },
                )),
          ]),
    );
  }
}
