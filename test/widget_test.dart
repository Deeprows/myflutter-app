import 'package:flutter_test/flutter_test.dart';

import 'package:footbolive/models/channel.dart';
import 'package:footbolive/models/fixture.dart';
import 'package:footbolive/models/highlight.dart';
import 'package:footbolive/models/movie.dart';
import 'package:footbolive/models/download_task.dart';
import 'package:footbolive/screens/browser_screen.dart';
import 'package:footbolive/services/download_manager.dart';
import 'package:footbolive/utils/format.dart';
import 'package:footbolive/services/player_html.dart';
import 'package:footbolive/services/stream_resolver.dart';

void main() {
  group('StreamResolver', () {
    test('plain m3u8', () {
      final r = StreamResolver.resolve('https://a.com/live/index.m3u8?token=1');
      expect(r.kind, StreamKind.hls);
      expect(r.usesHtmlPlayer, isTrue);
    });

    test('wrapper link with m3u8 in the fragment', () {
      final r = StreamResolver.resolve(
          'hls-player/player.html#https://rumble.com/hls-vod/x/playlist.m3u8');
      expect(r.kind, StreamKind.hls);
      expect(r.url, 'https://rumble.com/hls-vod/x/playlist.m3u8');
    });

    test('wrapper link with url= query', () {
      final r = StreamResolver.resolve(
          'https://p.com/p.php?url=https%3A%2F%2Fh.com%2Fa.m3u8');
      expect(r.kind, StreamKind.hls);
      expect(r.url, 'https://h.com/a.m3u8');
    });

    test('mp4, mpd and embed', () {
      expect(StreamResolver.resolve('https://a.com/v.mp4').kind,
          StreamKind.video);
      expect(StreamResolver.resolve('https://a.com/m.mpd').kind,
          StreamKind.dash);
      expect(StreamResolver.resolve('https://filemoon.org/en/abc/embed').kind,
          StreamKind.embed);
    });

    test('invalid input', () {
      expect(StreamResolver.resolve('').kind, StreamKind.invalid);
      expect(StreamResolver.resolve('not a link').kind, StreamKind.invalid);
    });

    test('player html embeds the url safely', () {
      final html = buildPlayerHtml(
          StreamResolver.resolve('https://a.com/live.m3u8'));
      expect(html.contains('"https://a.com/live.m3u8"'), isTrue);
      expect(html.contains('__URL__'), isFalse);
    });
  });

  group('Fixture', () {
    final f = Fixture(
      id: '1',
      home: 'A',
      away: 'B',
      kickoff: DateTime.utc(2026, 1, 1, 12),
      durationMin: 100,
    );

    test('phases', () {
      expect(f.phaseAt(DateTime.utc(2026, 1, 1, 11)), MatchPhase.upcoming);
      expect(f.phaseAt(DateTime.utc(2026, 1, 1, 12, 30)), MatchPhase.live);
      expect(f.phaseAt(DateTime.utc(2026, 1, 1, 14)), MatchPhase.ended);
    });

    test('sorting: live, upcoming, ended', () {
      final now = DateTime.utc(2026, 1, 1, 12, 30);
      final up = Fixture(
          id: '2', home: 'C', away: 'D', kickoff: DateTime.utc(2026, 1, 2));
      final old = Fixture(
          id: '3', home: 'E', away: 'F', kickoff: DateTime.utc(2025, 12, 1));
      final sorted = sortFixtures([old, up, f], now);
      expect(sorted.map((e) => e.id).toList(), ['1', '2', '3']);
    });
  });

  group('Highlight', () {
    test('parses competition and teams', () {
      final h = Highlight.tryParse({
        'name': 'Fulham vs Manchester United- EPL',
        'url': 'https://x.com',
        'date': '2026-09-20',
      })!;
      expect(h.home, 'Fulham');
      expect(h.away, 'Manchester United');
      expect(h.competition, 'Premier League');
    });

    test('hyphenated team without competition', () {
      final h = Highlight.tryParse({
        'name': 'Al-Riyadh vs Al Nassr Highlights',
        'url': 'https://x.com',
        'date': '2026-08-21',
      })!;
      expect(h.home, 'Al-Riyadh');
      expect(h.away, 'Al Nassr');
      expect(h.competition, isNull);
    });

    test('initials', () {
      expect(initialsOf('Manchester United'), 'MU');
      expect(initialsOf('Arsenal'), 'ARS');
    });
  });

  group('Movie', () {
    test('rating formats', () {
      expect(Movie.parseRating('7.0/10 ⭐'), '7.0');
      expect(Movie.parseRating('IMDb 5.1/10'), '5.1');
      expect(Movie.parseRating('68/100 TMDB ⭐'), '6.8');
      expect(Movie.parseRating('Action | Drama - 8.0/10 ⭐'), '8.0');
      expect(Movie.parseRating(''), isNull);
    });

    test('title, year and series', () {
      final m = Movie.tryParse({
        'name': 'Dhamaal (2026)',
        'url': 'https://vsembed.ru/embed/movie/tt1',
        'genre': 'Action,Comedy',
      })!;
      expect(m.title, 'Dhamaal');
      expect(m.year, '2026');
      expect(m.genres, ['Action', 'Comedy']);
      expect(m.isSeries, isFalse);
      final s = Movie.tryParse({
        'name': 'Lanterns',
        'url': 'https://vidsrc.sbs/embed/tv/95350/1/1/',
      })!;
      expect(s.isSeries, isTrue);
    });

    test('date shifted into downloadUrl is repaired', () {
      final m = Movie.tryParse({
        'name': 'X 2022',
        'url': 'https://a.com/e',
        'downloadUrl': '2026-07-04',
        'date': '',
      })!;
      expect(m.hasDownload, isFalse);
      expect(m.date, DateTime(2026, 7, 4));
      expect(m.title, 'X');
    });
  });

  group('Channel', () {
    test('parses category and falls back to other', () {
      expect(
          Channel.tryParse({'name': 'A', 'url': 'https://a', 'category': 'news'})!
              .category,
          ChannelCategory.news);
      expect(Channel.tryParse({'name': 'A', 'url': 'https://a'})!.category,
          ChannelCategory.other);
      expect(Channel.tryParse({'name': '', 'url': 'https://a'}), isNull);
    });

    test('wrapper TV links resolve to the inner m3u8', () {
      final r = StreamResolver.resolve(
          'https://bharadwajpro.github.io/m3u8-player/player/#https://x.com/a.m3u8  N ');
      expect(r.kind, StreamKind.hls);
      expect(r.url, 'https://x.com/a.m3u8');
    });
  });

  group('Download links', () {
    test('file-looking links are detected, pages are not', () {
      expect(isDirectFileLink('https://a.com/f/movie.mkv'), isTrue);
      expect(isDirectFileLink('https://a.com/f/app.APK?x=1'), isTrue);
      expect(isDirectFileLink('https://a.com/download/abc123'), isFalse);
      expect(isDirectFileLink('https://a.com/page.html'), isFalse);
    });
  });

  group('Downloads', () {
    test('file names', () {
      expect(fileNameFromUrl('https://h.com/a/My%20Movie.2026.mkv?x=1'),
          'My Movie.2026.mkv');
      expect(fileNameFromUrl('https://h.com/'), 'download');
      expect(sanitizeFileName('a/b:c*d?.mp4'), 'a_b_c_d_.mp4');
      expect(fileNameFromDisposition('attachment; filename="Film 1.mp4"'),
          'Film 1.mp4');
      expect(
          fileNameFromDisposition(
              "attachment; filename*=UTF-8''Caf%C3%A9.mkv"),
          'Café.mkv');
      expect(fileNameFromDisposition(null), isNull);
    });

    test('byte formatting', () {
      expect(fmtBytes(512), '512 B');
      expect(fmtBytes(1536), '1.5 KB');
      expect(fmtBytes(734003200), '700 MB');
    });

    test('task json round trip and progress', () {
      final t = DownloadTask(
        id: '1',
        url: 'https://a.com/f.mkv',
        name: 'f.mkv',
        percent: 10,
        total: 100,
      );
      final back = DownloadTask.tryParse(t.toJson())!;
      expect(back.status, DownloadStatus.downloading);
      expect(back.progress, 0.1);
      expect(back.received, 10);
      expect(back.extension, 'mkv');
      expect(DownloadTask(id: '2', url: 'u', name: 'n').progress, isNull);
    });
  });
}
