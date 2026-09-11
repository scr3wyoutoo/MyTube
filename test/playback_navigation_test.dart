import 'package:flutter_browser_app/models/playback_navigation.dart';
import 'package:flutter_browser_app/models/playback_queue.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speichert Video und Musik in getrennten Cursor-Historien', () {
    final histories = const PlaybackHistories()
        .visit(_video(1))
        .visit(_song(1))
        .visit(_video(2))
        .visit(_song(2));

    expect(histories.videos.items.map((item) => item.id), [
      'video-1',
      'video-2',
    ]);
    expect(histories.music.items.map((item) => item.id), ['song-1', 'song-2']);
  });

  test('Next verwendet zuerst den offenen Vorwaertszweig der Historie', () {
    var histories = const PlaybackHistories()
        .visit(_song(1))
        .visit(_song(2))
        .visit(_song(3));
    final backToTwo = histories.music.goBackFrom(_song(3));
    histories = histories.replaceFor(_song(2), backToTwo.history);
    final backToOne = histories.music.goBackFrom(_song(2));
    histories = histories.replaceFor(_song(1), backToOne.history);
    final queue = PlaybackQueue.searchResults(
      items: [_song(1), _song(4)],
      currentVideo: _song(1),
    );

    final target = nextPlaybackTarget(
      histories: histories,
      current: _song(1),
      queue: queue,
    );

    expect(target?.source, PlaybackNavigationSource.history);
    expect(target?.video.id, 'song-2');
  });

  test('Next greift erst am Historienende auf die Such-Queue zu', () {
    final histories = const PlaybackHistories().visit(_song(1));
    final queue = PlaybackQueue.searchResults(
      items: [_song(1), _song(4)],
      currentVideo: _song(1),
    );

    final target = nextPlaybackTarget(
      histories: histories,
      current: _song(1),
      queue: queue,
    );

    expect(target?.source, PlaybackNavigationSource.queue);
    expect(target?.video.id, 'song-4');
    expect(target?.queueIndex, 1);
  });

  test('Audio-Panel ueberspringt Videos in einer gemischten Queue', () {
    final histories = const PlaybackHistories().visit(_song(1));
    final queue = PlaybackQueue.localPlaylist(
      items: [_song(1), _video(2), _song(3)],
      initialIndex: 0,
      loops: true,
    );

    final target = nextPlaybackTarget(
      histories: histories,
      current: _song(1),
      queue: queue,
      musicOnlyQueue: true,
    );

    expect(target?.video.id, 'song-3');
    expect(target?.video.isMusic, isTrue);
  });

  test('Musiknavigation kann keine Video-Vorwaertshistorie erreichen', () {
    var histories = const PlaybackHistories()
        .visit(_video(1))
        .visit(_video(2))
        .visit(_song(1));
    final videoBack = histories.videos.goBackFrom(_video(2));
    histories = histories.replaceFor(_video(1), videoBack.history);
    final queue = PlaybackQueue.localPlaylist(
      items: [_song(1), _video(3)],
      initialIndex: 0,
      loops: true,
    );

    final target = nextPlaybackTarget(
      histories: histories,
      current: _song(1),
      queue: queue,
      musicOnlyQueue: true,
    );

    expect(target, isNull);
  });
}

YouTubeVideo _video(int index) => YouTubeVideo(
  id: 'video-$index',
  title: 'Video $index',
  description: '',
  thumbnailUrl: '',
);

YouTubeVideo _song(int index) => YouTubeVideo(
  id: 'song-$index',
  title: 'Song $index',
  description: '',
  thumbnailUrl: '',
  isMusic: true,
);
