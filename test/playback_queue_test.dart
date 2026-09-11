import 'dart:math';

import 'package:flutter_browser_app/models/playback_queue.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lokale Playlist bleibt manuell aktiv und loopt nur bei Auto-Play', () {
    final queue = PlaybackQueue.localPlaylist(items: _videos, initialIndex: 2);

    expect(queue.source, PlaybackQueueSource.localPlaylist);
    expect(queue.currentIndex, 2);
    expect(queue.nextIndex, isNull);
    expect(queue.automaticNextIndex(autoplayEnabled: false), isNull);
    expect(queue.previousIndex, 1);

    final manuallyNavigable = queue.selectIndex(1);
    expect(manuallyNavigable.nextIndex, 2);
    expect(
      manuallyNavigable.automaticNextIndex(autoplayEnabled: false),
      isNull,
    );

    final looping = queue.withLooping(true);
    expect(looping.nextIndex, 0);
    expect(looping.automaticNextIndex(autoplayEnabled: false), isNull);
    expect(looping.automaticNextIndex(autoplayEnabled: true), 0);
    expect(looping.previousIndex, 1);
  });

  test('Suchergebnis-Queue setzt nach dem letzten Treffer zyklisch fort', () {
    final queue = PlaybackQueue.searchResults(
      items: _videos,
      currentVideo: _videos.last,
    );

    expect(queue.source, PlaybackQueueSource.searchResults);
    expect(queue.currentIndex, 2);
    expect(queue.nextIndex, 0);
    expect(queue.selectIndex(0).previousIndex, 2);
  });

  test(
    'neue Ergebnisse beginnen bei Treffer eins wenn Medium nicht vorkommt',
    () {
      final queue = PlaybackQueue.searchResults(
        items: _videos,
        currentVideo: _outsideVideo,
      );

      expect(queue.currentIndex, isNull);
      expect(queue.nextIndex, 0);
      expect(queue.nextItem, _videos.first);
    },
  );

  test('Queue-Auswahl bleibt unverändert bei unbekanntem Medium', () {
    final queue = PlaybackQueue.localPlaylist(items: _videos, initialIndex: 1);

    expect(queue.selectVideo(_videos.first).currentIndex, 0);
    expect(queue.selectVideo(_outsideVideo).currentIndex, 1);
  });

  test('erweitert eine Suchqueue ohne Position oder Shuffle zu verlieren', () {
    final queue = PlaybackQueue.searchResults(
      items: _videos,
      currentVideo: _videos[1],
    ).withShuffle(true, random: Random(7));

    final extended = queue.extendSearchResults([_videos[2], _shuffleVideos[3]]);

    expect(extended.currentItem?.id, _videos[1].id);
    expect(extended.isShuffled, isTrue);
    expect(extended.originalItems.map((item) => item.id), [
      _videos[0].id,
      _videos[1].id,
      _videos[2].id,
      _shuffleVideos[3].id,
    ]);
    expect(extended.items.map((item) => item.id).toSet(), {
      _videos[0].id,
      _videos[1].id,
      _videos[2].id,
      _shuffleVideos[3].id,
    });
    expect(extended.items.last.id, _shuffleVideos[3].id);
  });

  test('begrenzt ausschließlich Suchqueues auf 100 Treffer', () {
    final searchVideos = List.generate(
      120,
      (index) => YouTubeVideo(
        id: 'search-$index',
        title: 'Treffer $index',
        description: '',
        thumbnailUrl: '',
      ),
    );
    final searchQueue = PlaybackQueue.searchResults(
      items: searchVideos,
      currentVideo: searchVideos[99],
    );
    final localQueue = PlaybackQueue.localPlaylist(
      items: searchVideos,
      initialIndex: 119,
    );

    expect(searchQueue.items, hasLength(100));
    expect(searchQueue.currentItem?.id, 'search-99');
    expect(
      searchQueue.extendSearchResults([searchVideos[100]]).items,
      hasLength(100),
    );
    expect(localQueue.items, hasLength(120));
    expect(localQueue.currentItem?.id, 'search-119');
  });

  test(
    'Shuffle behält das aktuelle Medium und verwendet jedes Medium einmal',
    () {
      final queue = PlaybackQueue.localPlaylist(
        items: _shuffleVideos,
        initialIndex: 2,
        loops: true,
      );

      final shuffled = queue.withShuffle(true, random: Random(42));

      expect(shuffled.isShuffled, isTrue);
      expect(shuffled.currentIndex, 0);
      expect(shuffled.currentItem?.id, 'video-3');
      expect(shuffled.items.map((video) => video.id).toSet(), {
        'video-1',
        'video-2',
        'video-3',
        'video-4',
        'video-5',
        'video-6',
      });
      expect(shuffled.items.length, _shuffleVideos.length);

      final restored = shuffled.withShuffle(false, random: Random(42));
      expect(restored.isShuffled, isFalse);
      expect(restored.items, _shuffleVideos);
      expect(restored.currentItem?.id, 'video-3');
    },
  );

  test('neuer Shuffle-Zyklus verzögert die zuletzt gespielten Medien', () {
    final shuffled = PlaybackQueue.localPlaylist(
      items: _shuffleVideos,
      initialIndex: 0,
      loops: true,
    ).withShuffle(true, random: Random(7));
    final atCycleEnd = shuffled.selectIndex(shuffled.items.length - 1);
    final previousIds = atCycleEnd.items
        .sublist(atCycleEnd.items.length - 3, atCycleEnd.items.length - 1)
        .map((video) => video.id)
        .toSet();
    final lastId = atCycleEnd.currentItem!.id;

    final nextCycle = atCycleEnd.reshuffleForNextCycle(random: Random(11));

    expect(nextCycle.isShuffled, isTrue);
    expect(nextCycle.currentIndex, 0);
    expect(nextCycle.currentItem?.id, lastId);
    expect(nextCycle.nextItem?.id, isNot(lastId));
    expect(previousIds, isNot(contains(nextCycle.nextItem?.id)));
    expect(nextCycle.items.map((video) => video.id).toSet(), {
      'video-1',
      'video-2',
      'video-3',
      'video-4',
      'video-5',
      'video-6',
    });
  });
}

const _videos = <YouTubeVideo>[
  YouTubeVideo(
    id: 'video-1',
    title: 'Video 1',
    description: '',
    thumbnailUrl: '',
  ),
  YouTubeVideo(
    id: 'video-2',
    title: 'Video 2',
    description: '',
    thumbnailUrl: '',
  ),
  YouTubeVideo(
    id: 'video-3',
    title: 'Video 3',
    description: '',
    thumbnailUrl: '',
  ),
];

const _outsideVideo = YouTubeVideo(
  id: 'outside',
  title: 'Außerhalb',
  description: '',
  thumbnailUrl: '',
);

const _shuffleVideos = <YouTubeVideo>[
  ..._videos,
  YouTubeVideo(
    id: 'video-4',
    title: 'Video 4',
    description: '',
    thumbnailUrl: '',
  ),
  YouTubeVideo(
    id: 'video-5',
    title: 'Video 5',
    description: '',
    thumbnailUrl: '',
  ),
  YouTubeVideo(
    id: 'video-6',
    title: 'Video 6',
    description: '',
    thumbnailUrl: '',
  ),
];
