class Movie {
  final String name;
  final String url;
  final String downloadUrl;
  final DateTime? date;
  final String? rating; // "7.4"
  final List<String> genres;
  final String image;

  const Movie({
    required this.name,
    required this.url,
    required this.downloadUrl,
    required this.date,
    required this.rating,
    required this.genres,
    required this.image,
  });

  bool get isSeries => url.contains('/embed/tv/');
  bool get hasDownload => downloadUrl.startsWith('http');
  bool get hasImage => image.startsWith('http');

  /// Name without a trailing/parenthesised year: "Dhamaal (2026)" -> "Dhamaal".
  String get title => name
      .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
      .replaceAll(RegExp(r'\s+(19|20)\d{2}\s*$'), '')
      .trim();

  String? get year {
    final m = RegExp(r'((?:19|20)\d{2})\s*\)?\s*$').firstMatch(name);
    return m?.group(1);
  }

  static Movie? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    String s(String k) => (raw[k] ?? '').toString().trim();
    final name = s('name');
    final url = s('url');
    if (name.isEmpty || !url.startsWith('http')) return null;

    var date = s('date');
    var dl = s('downloadUrl');
    // Some rows have the date shifted into downloadUrl.
    if (!dl.startsWith('http')) {
      if (date.isEmpty && RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(dl)) date = dl;
      dl = '';
    }

    return Movie(
      name: name,
      url: url,
      downloadUrl: dl,
      date: DateTime.tryParse(date),
      rating: parseRating(s('rating')),
      genres: s('genre')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      image: s('image'),
    );
  }

  /// "IMDb 5.1/10", "7.0/10 ⭐", "68/100 TMDB ⭐", "Action | Drama - 8.0/10 ⭐"
  /// all become a one-decimal score out of 10, or null.
  static String? parseRating(String raw) {
    final m10 = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*10(?!\d)').firstMatch(raw);
    if (m10 != null) {
      final v = double.tryParse(m10.group(1)!);
      if (v != null) return v.toStringAsFixed(1);
    }
    final m100 = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*100').firstMatch(raw);
    if (m100 != null) {
      final v = double.tryParse(m100.group(1)!);
      if (v != null) return (v / 10).toStringAsFixed(1);
    }
    return null;
  }
}
