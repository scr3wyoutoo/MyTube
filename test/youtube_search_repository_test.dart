import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_browser_app/models/youtube_search_sort.dart';
import 'package:flutter_browser_app/services/youtube_search_repository.dart';

void main() {
  test('fragt genau 20 Videos ab und liest die Seitentokens', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        '''
        {
          "nextPageToken": "next-token",
          "prevPageToken": "previous-token",
          "items": [
            {
              "id": {"videoId": "abc123"},
              "snippet": {
                "title": "Ein Testvideo",
                "description": "Testbeschreibung",
                "channelTitle": "Testkanal",
                "publishedAt": "2024-03-12T10:15:00Z",
                "thumbnails": {
                  "medium": {"url": "https://example.com/thumb.jpg"}
                }
              }
            }
          ]
        }
        ''',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = YouTubeApiSearchRepository(
      apiKey: 'test-api-key',
      client: client,
    );

    final result = await repository.searchVideos(
      query: 'Flutter Tipps',
      pageToken: 'requested-page',
    );

    expect(capturedRequest.url.path, '/youtube/v3/search');
    expect(capturedRequest.url.queryParameters['part'], 'snippet');
    expect(capturedRequest.url.queryParameters['q'], 'Flutter Tipps');
    expect(capturedRequest.url.queryParameters['type'], 'video');
    expect(capturedRequest.url.queryParameters['maxResults'], '20');
    expect(capturedRequest.url.queryParameters['pageToken'], 'requested-page');
    expect(capturedRequest.url.queryParameters['relevanceLanguage'], 'de');
    expect(capturedRequest.url.queryParameters['regionCode'], 'DE');
    expect(capturedRequest.url.queryParameters['order'], 'relevance');
    expect(capturedRequest.headers['X-Goog-Api-Key'], 'test-api-key');
    expect(result.videos, hasLength(1));
    expect(result.videos.single.title, 'Ein Testvideo');
    expect(result.videos.single.description, 'Testbeschreibung');
    expect(result.videos.single.thumbnailUrl, 'https://example.com/thumb.jpg');
    expect(result.videos.single.channelTitle, 'Testkanal');
    expect(result.videos.single.publishedAt, DateTime.utc(2024, 3, 12, 10, 15));
    expect(result.nextPageToken, 'next-token');
    expect(result.previousPageToken, 'previous-token');
  });

  test('übersetzt alle Sortierungen für den API-Fallback', () async {
    final capturedOrders = <String?>[];
    final repository = YouTubeApiSearchRepository(
      apiKey: 'test-api-key',
      client: MockClient((request) async {
        capturedOrders.add(request.url.queryParameters['order']);
        return http.Response('{"items": []}', 200);
      }),
    );

    for (final sort in YouTubeSearchSort.values) {
      await repository.searchVideos(query: 'Flutter', sort: sort);
    }

    expect(capturedOrders, ['relevance', 'date', 'viewCount', 'rating']);
  });

  test('übergibt die englische Profilsprache an den API-Fallback', () async {
    late http.Request capturedRequest;
    final repository = YouTubeApiSearchRepository(
      apiKey: 'test-api-key',
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"items": []}', 200);
      }),
    );

    await repository.searchVideos(query: 'Flutter', languageCode: 'en');

    expect(capturedRequest.url.queryParameters['relevanceLanguage'], 'en');
    expect(capturedRequest.url.queryParameters['regionCode'], 'US');
  });

  test('meldet einen fehlenden API-Key verständlich', () async {
    final repository = YouTubeApiSearchRepository(
      apiKey: '',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      repository.searchVideos(query: 'Flutter'),
      throwsA(
        isA<YouTubeSearchException>().having(
          (error) => error.message,
          'message',
          contains('kein YouTube-API-Key'),
        ),
      ),
    );
  });
}
