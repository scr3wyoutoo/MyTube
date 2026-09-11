import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/services/playlist_import_loader.dart';

void main() {
  test(
    'lädt alle Playlist-Seiten in Reihenfolge und entfernt Duplikate',
    () async {
      final requestedTokens = <String?>[];
      const loader = PlaylistImportLoader();

      final videos = await loader.loadAll((pageToken) async {
        requestedTokens.add(pageToken);
        if (pageToken == null) {
          return const YouTubeSearchResult(
            videos: [_video1, _video2],
            nextPageToken: 'page-2',
          );
        }
        return const YouTubeSearchResult(videos: [_video2, _video3]);
      });

      expect(requestedTokens, [null, 'page-2']);
      expect(videos.map((video) => video.id), [
        'video-1',
        'video-2',
        'video-3',
      ]);
    },
  );

  test('bricht bei einem zyklischen Seitentoken ohne Teilimport ab', () async {
    const loader = PlaylistImportLoader();

    expect(
      () => loader.loadAll(
        (_) async => const YouTubeSearchResult(
          videos: [_video1],
          nextPageToken: 'cycle',
        ),
      ),
      throwsA(isA<PlaylistImportException>()),
    );
  });
}

const _video1 = YouTubeVideo(
  id: 'video-1',
  title: 'Video 1',
  description: '',
  thumbnailUrl: '',
);

const _video2 = YouTubeVideo(
  id: 'video-2',
  title: 'Video 2',
  description: '',
  thumbnailUrl: '',
);

const _video3 = YouTubeVideo(
  id: 'video-3',
  title: 'Video 3',
  description: '',
  thumbnailUrl: '',
);
