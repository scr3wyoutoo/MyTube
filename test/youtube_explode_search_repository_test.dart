import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/models/youtube_search_sort.dart';
import 'package:flutter_browser_app/services/localized_youtube_http_client.dart';
import 'package:flutter_browser_app/services/youtube_explode_search_repository.dart';
import 'package:flutter_browser_app/services/youtube_explode_search_filter.dart';
import 'package:flutter_browser_app/services/youtube_live_detection.dart';
import 'package:flutter_browser_app/services/youtube_search_repository.dart';

void main() {
  test('kombiniert Sortierung mit Video- und Playlist-Typ', () {
    expect(
      YouTubeSearchSort.values.map(
        (sort) => youtubeExplodeVideoSearchFilter(sort).value,
      ),
      ['CAASAhAB', 'CAISAhAB', 'CAMSAhAB', 'CAESAhAB'],
    );
    expect(
      YouTubeSearchSort.values.map(
        (sort) => youtubeExplodePlaylistSearchFilter(sort).value,
      ),
      ['CAASAhAD', 'CAISAhAD', 'CAMSAhAD', 'CAESAhAD'],
    );
  });

  test('normalisiert deutsche relative Datumsangaben für den Parser', () {
    expect(normalizeGermanYouTubePublishedTime('vor 3 Jahren'), '3 years ago');
    expect(
      normalizeGermanYouTubePublishedTime('Gestreamt vor einer Stunde'),
      '1 hour ago',
    );
    expect(normalizeGermanYouTubePublishedTime('vor 2 Tagen'), '2 days ago');
    expect(normalizeGermanYouTubePublishedTime('Gerade eben'), '0 seconds ago');
    expect(normalizeGermanYouTubePublishedTime('02.01.2024'), isNull);
  });

  test('normalisiert YouTubes neuen Live-Zuschauer-Renderer', () {
    const raw =
        r'{"viewCountText":{"runs":[{"text":"1.629"},{"text":"\u00a0Zuschauer"}]},"videoId":"arte"}';

    final normalized = normalizeYouTubeSearchViewCountRuns(raw);

    expect(
      normalized,
      r'{"viewCountText":{"simpleText":"1.629\u00a0Zuschauer"},"videoId":"arte"}',
    );
    expect(normalized, isNot(contains('"runs"')));
  });

  test('erkennt deutsches Live-Badge vor der Zuschauer-Normalisierung', () {
    const raw = r'''
      <script>var ytInitialData = {"contents":[{"videoRenderer":{
        "videoId":"hSMzJDzVx6E",
        "viewCountText":{"runs":[{"text":"2.904"},{"text":"\u00a0Zuschauer"}]},
        "badges":[{"metadataBadgeRenderer":{"icon":{"iconType":"LIVE"},
        "style":"BADGE_STYLE_TYPE_LIVE_NOW","label":"LIVE"}}]
      }}]};</script>
    ''';

    expect(extractYouTubeLiveVideoIds(raw), {'hSMzJDzVx6E'});
    expect(
      extractYouTubeLiveVideoIds(normalizeYouTubeSearchViewCountRuns(raw)),
      {'hSMzJDzVx6E'},
    );
  });

  test('erkennt englisches Live-Badge unabhängig vom Wort watching', () {
    final response = {
      'contents': [
        {
          'videoRenderer': {
            'videoId': 'english-live',
            'viewCountText': {
              'runs': [
                {'text': '2,904'},
                {'text': ' watching'},
              ],
            },
            'badges': [
              {
                'metadataBadgeRenderer': {'style': 'BADGE_STYLE_TYPE_LIVE_NOW'},
              },
            ],
          },
        },
      ],
    };

    expect(extractYouTubeLiveVideoIds(response), {'english-live'});
  });

  test('stellt interne 20er-Batches als stabile Seiten bereit', () async {
    final source = _FakeExplodeSearchSource([
      _videos(0, 20),
      _videos(20, 40),
      _videos(40, 60),
    ]);
    final repository = YouTubeExplodeSearchRepository(source: source);

    final firstPage = await repository.searchVideos(query: 'Flutter');
    expect(firstPage.videos, hasLength(20));
    expect(firstPage.videos.first.id, 'video-0');
    expect(firstPage.videos.last.id, 'video-19');
    expect(firstPage.previousPageToken, isNull);
    expect(firstPage.nextPageToken, isNotNull);

    final secondPage = await repository.searchVideos(
      query: 'Flutter',
      pageToken: firstPage.nextPageToken,
    );
    expect(secondPage.videos, hasLength(20));
    expect(secondPage.videos.first.id, 'video-20');
    expect(secondPage.videos.last.id, 'video-39');
    expect(secondPage.previousPageToken, isNotNull);
    expect(secondPage.nextPageToken, isNotNull);

    final firstPageAgain = await repository.searchVideos(
      query: 'Flutter',
      pageToken: secondPage.previousPageToken,
    );
    expect(firstPageAgain.videos.first.id, 'video-0');
    expect(source.searchCalls, 1);
    expect(source.nextPageCalls, 2);
    expect(source.languageCodes, ['de']);

    repository.close();
    expect(source.wasClosed, isTrue);
  });

  test('setzt die Suche beim Wechsel der Profilsprache zurück', () async {
    final source = _FakeExplodeSearchSource([_videos(0, 25)]);
    final repository = YouTubeExplodeSearchRepository(source: source);

    await repository.searchVideos(query: 'Flutter', languageCode: 'de');
    await repository.searchVideos(query: 'Flutter', languageCode: 'en');

    expect(source.searchCalls, 2);
    expect(source.languageCodes, ['de', 'en']);
  });

  test('übergibt die gewählte Sortierung an die keyfreie Suche', () async {
    final source = _FakeExplodeSearchSource([_videos(0, 25)]);
    final repository = YouTubeExplodeSearchRepository(source: source);

    await repository.searchVideos(
      query: 'Flutter',
      sort: YouTubeSearchSort.rating,
    );
    await repository.searchVideos(
      query: 'Flutter',
      sort: YouTubeSearchSort.uploadDate,
    );

    expect(source.sorts, [
      YouTubeSearchSort.rating,
      YouTubeSearchSort.uploadDate,
    ]);
  });

  test('zeigt auf der letzten Seite nur die verbleibenden Treffer', () async {
    final source = _FakeExplodeSearchSource([_videos(0, 20), _videos(20, 30)]);
    final repository = YouTubeExplodeSearchRepository(source: source);

    final firstPage = await repository.searchVideos(query: 'Dart');
    final secondPage = await repository.searchVideos(
      query: 'Dart',
      pageToken: firstPage.nextPageToken,
    );

    expect(firstPage.videos, hasLength(20));
    expect(secondPage.videos, hasLength(10));
    expect(secondPage.videos.first.id, 'video-20');
    expect(secondPage.nextPageToken, isNull);
  });

  test('verpackt auch Parser-Errors als verständlichen Suchfehler', () async {
    final repository = YouTubeExplodeSearchRepository(
      source: _ErrorExplodeSearchSource(),
    );

    await expectLater(
      repository.searchVideos(query: 'Arte'),
      throwsA(
        isA<YouTubeSearchException>().having(
          (error) => error.message,
          'message',
          contains('key-freie YouTube-Suche'),
        ),
      ),
    );
  });
}

List<YouTubeVideo> _videos(int start, int end) {
  return List.generate(end - start, (index) {
    final number = start + index;
    return YouTubeVideo(
      id: 'video-$number',
      title: 'Video $number',
      description: 'Beschreibung $number',
      thumbnailUrl: 'https://example.com/$number.jpg',
    );
  });
}

class _FakeExplodeSearchSource implements YouTubeExplodeSearchSource {
  _FakeExplodeSearchSource(this.pages);

  final List<List<YouTubeVideo>> pages;
  int searchCalls = 0;
  int nextPageCalls = 0;
  final List<String> languageCodes = [];
  final List<YouTubeSearchSort> sorts = [];
  bool wasClosed = false;

  @override
  Future<YouTubeExplodeSearchBatch> search(
    String query, {
    required String languageCode,
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    searchCalls++;
    languageCodes.add(languageCode);
    sorts.add(sort);
    return _batch(0);
  }

  @override
  Future<YouTubeExplodeSearchBatch?> nextPage(
    YouTubeExplodeSearchBatch currentBatch,
  ) async {
    nextPageCalls++;
    final currentIndex = currentBatch.nativePage as int;
    final nextIndex = currentIndex + 1;
    return nextIndex >= pages.length ? null : _batch(nextIndex);
  }

  YouTubeExplodeSearchBatch _batch(int index) {
    return YouTubeExplodeSearchBatch(videos: pages[index], nativePage: index);
  }

  @override
  void close() => wasClosed = true;
}

class _ErrorExplodeSearchSource implements YouTubeExplodeSearchSource {
  @override
  Future<YouTubeExplodeSearchBatch> search(
    String query, {
    required String languageCode,
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) => Future.error(
    NoSuchMethodError.withInvocation(this, Invocation.getter(#text)),
  );

  @override
  Future<YouTubeExplodeSearchBatch?> nextPage(
    YouTubeExplodeSearchBatch currentBatch,
  ) async => null;

  @override
  void close() {}
}
