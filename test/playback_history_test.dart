import 'package:flutter_browser_app/models/playback_history.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'navigiert vor und zurück durch die tatsächlich gespielte Reihenfolge',
    () {
      var history = const PlaybackHistory.empty()
          .visit(_video(1))
          .visit(_video(3))
          .visit(_video(7))
          .visit(_video(9))
          .visit(_video(14));

      var current = _video(14);
      for (final expected in [9, 7, 3, 1]) {
        final step = history.goBackFrom(current);
        expect(step.media?.id, 'video-$expected');
        history = step.history;
        current = step.media!;
      }
      expect(history.previousFrom(current), isNull);

      for (final expected in [3, 7, 9, 14]) {
        final step = history.goForwardFrom(current);
        expect(step.media?.id, 'video-$expected');
        history = step.history;
        current = step.media!;
      }
      expect(history.nextFrom(current), isNull);
    },
  );

  test(
    'verwirft den alten Vorwärtszweig nach einer neuen manuellen Auswahl',
    () {
      var history = const PlaybackHistory.empty()
          .visit(_video(1))
          .visit(_video(3))
          .visit(_video(7))
          .visit(_video(9));

      history = history.goBackFrom(_video(9)).history;
      history = history.goBackFrom(_video(7)).history;
      expect(history.currentItem?.id, 'video-3');

      history = history.visit(_video(20));

      expect(history.items.map((item) => item.id), [
        'video-1',
        'video-3',
        'video-20',
      ]);
      expect(history.nextFrom(_video(20)), isNull);
    },
  );

  test(
    'führt von einem fehlgeschlagenen Ziel zum letzten aktiven Medium zurück',
    () {
      final history = const PlaybackHistory.empty()
          .visit(_video(1))
          .visit(_video(3));

      final back = history.goBackFrom(_video(99));

      expect(back.media?.id, 'video-3');
      expect(back.history.currentItem?.id, 'video-3');
    },
  );

  test('dedupliziert gleiche aufeinanderfolgende Medien', () {
    final history = const PlaybackHistory.empty()
        .visit(_video(1))
        .visit(_video(1))
        .visit(_song);

    expect(history.items.map((item) => item.id), ['video-1', 'song-1']);
    expect(history.currentIndex, 1);
  });

  test('begrenzt die Historie rollierend auf 100 Einträge', () {
    var history = const PlaybackHistory.empty();
    for (var index = 0; index < 120; index++) {
      history = history.visit(_video(index));
    }

    expect(history.items, hasLength(100));
    expect(history.items.first.id, 'video-20');
    expect(history.items.last.id, 'video-119');
    expect(history.currentIndex, 99);
  });
}

YouTubeVideo _video(int index) => YouTubeVideo(
  id: 'video-$index',
  title: 'Video $index',
  description: '',
  thumbnailUrl: '',
);

const _song = YouTubeVideo(
  id: 'song-1',
  title: 'Song 1',
  description: '',
  thumbnailUrl: '',
  isMusic: true,
);
