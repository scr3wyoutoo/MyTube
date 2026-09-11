import 'youtube_video.dart';

class PlaybackHistory {
  const PlaybackHistory.empty({this.maxEntries = 100})
    : assert(maxEntries > 0),
      items = const [],
      currentIndex = null;

  const PlaybackHistory._({
    required this.items,
    required this.currentIndex,
    required this.maxEntries,
  });

  final List<YouTubeVideo> items;
  final int? currentIndex;
  final int maxEntries;

  YouTubeVideo? get currentItem {
    final index = currentIndex;
    return index == null || index < 0 || index >= items.length
        ? null
        : items[index];
  }

  YouTubeVideo? previousFrom(YouTubeVideo current) {
    final index = currentIndex;
    if (index == null) {
      return null;
    }
    if (!_sameMedia(items[index], current)) {
      return items[index];
    }
    return index > 0 ? items[index - 1] : null;
  }

  YouTubeVideo? nextFrom(YouTubeVideo current) {
    final index = currentIndex;
    if (index == null || !_sameMedia(items[index], current)) {
      return null;
    }
    final nextIndex = index + 1;
    return nextIndex < items.length ? items[nextIndex] : null;
  }

  PlaybackHistory visit(YouTubeVideo media) {
    final index = currentIndex;
    if (index != null && _sameMedia(items[index], media)) {
      return this;
    }

    final retained = index == null
        ? <YouTubeVideo>[]
        : items.sublist(0, index + 1);
    retained.add(media);
    final overflow = retained.length - maxEntries;
    final capped = overflow > 0 ? retained.sublist(overflow) : retained;
    return PlaybackHistory._(
      items: List<YouTubeVideo>.unmodifiable(capped),
      currentIndex: capped.length - 1,
      maxEntries: maxEntries,
    );
  }

  PlaybackHistoryStep goBackFrom(YouTubeVideo current) {
    final index = currentIndex;
    if (index == null) {
      return PlaybackHistoryStep(history: this, media: null);
    }
    if (!_sameMedia(items[index], current)) {
      return PlaybackHistoryStep(history: this, media: items[index]);
    }
    if (index == 0) {
      return PlaybackHistoryStep(history: this, media: null);
    }
    final previousIndex = index - 1;
    return PlaybackHistoryStep(
      history: _withCurrentIndex(previousIndex),
      media: items[previousIndex],
    );
  }

  PlaybackHistoryStep goForwardFrom(YouTubeVideo current) {
    final index = currentIndex;
    if (index == null || !_sameMedia(items[index], current)) {
      return PlaybackHistoryStep(history: this, media: null);
    }
    final nextIndex = index + 1;
    if (nextIndex >= items.length) {
      return PlaybackHistoryStep(history: this, media: null);
    }
    return PlaybackHistoryStep(
      history: _withCurrentIndex(nextIndex),
      media: items[nextIndex],
    );
  }

  PlaybackHistory _withCurrentIndex(int index) => PlaybackHistory._(
    items: items,
    currentIndex: index,
    maxEntries: maxEntries,
  );

  static bool _sameMedia(YouTubeVideo first, YouTubeVideo second) =>
      first.id == second.id && first.isMusic == second.isMusic;
}

class PlaybackHistoryStep {
  const PlaybackHistoryStep({required this.history, required this.media});

  final PlaybackHistory history;
  final YouTubeVideo? media;
}
