import 'playback_history.dart';
import 'playback_queue.dart';
import 'youtube_video.dart';

/// Keeps independent cursor histories for videos and YouTube Music songs.
///
/// The split prevents a system music control from ever navigating into a
/// previously watched video while still preserving full back/forward
/// navigation inside each media type.
class PlaybackHistories {
  const PlaybackHistories({
    this.videos = const PlaybackHistory.empty(),
    this.music = const PlaybackHistory.empty(),
  });

  final PlaybackHistory videos;
  final PlaybackHistory music;

  PlaybackHistory forMedia(YouTubeVideo media) =>
      media.isMusic ? music : videos;

  PlaybackHistories replaceFor(YouTubeVideo media, PlaybackHistory history) =>
      media.isMusic
      ? PlaybackHistories(videos: videos, music: history)
      : PlaybackHistories(videos: history, music: music);

  PlaybackHistories visit(YouTubeVideo media) =>
      replaceFor(media, forMedia(media).visit(media));
}

enum PlaybackNavigationSource { history, queue }

class PlaybackNavigationTarget {
  const PlaybackNavigationTarget.history({
    required this.video,
    required PlaybackHistoryStep step,
  }) : source = PlaybackNavigationSource.history,
       historyStep = step,
       queueIndex = null;

  const PlaybackNavigationTarget.queue({
    required this.video,
    required int index,
  }) : source = PlaybackNavigationSource.queue,
       historyStep = null,
       queueIndex = index;

  final YouTubeVideo video;
  final PlaybackNavigationSource source;
  final PlaybackHistoryStep? historyStep;
  final int? queueIndex;

  bool matches(PlaybackNavigationTarget? other) =>
      other != null &&
      source == other.source &&
      video.id == other.video.id &&
      video.isMusic == other.video.isMusic &&
      queueIndex == other.queueIndex &&
      historyStep?.history.currentIndex ==
          other.historyStep?.history.currentIndex;
}

PlaybackNavigationTarget? previousPlaybackTarget({
  required PlaybackHistories histories,
  required YouTubeVideo current,
}) {
  final step = histories.forMedia(current).goBackFrom(current);
  final media = step.media;
  return media == null
      ? null
      : PlaybackNavigationTarget.history(video: media, step: step);
}

/// Resolves Next consistently for player UI, autoplay and remote controls.
///
/// A still-open forward-history branch always wins. Only at its end is the
/// next matching item in the primary queue selected. [musicOnlyQueue] is used
/// by the system audio panel so a mixed local playlist can never surface a
/// video through an audio-only control.
PlaybackNavigationTarget? nextPlaybackTarget({
  required PlaybackHistories histories,
  required YouTubeVideo current,
  required PlaybackQueue queue,
  bool musicOnlyQueue = false,
}) {
  final historyStep = histories.forMedia(current).goForwardFrom(current);
  final historyMedia = historyStep.media;
  if (historyMedia != null) {
    return PlaybackNavigationTarget.history(
      video: historyMedia,
      step: historyStep,
    );
  }

  final queueIndex = _nextMatchingQueueIndex(
    queue,
    current: current,
    musicOnly: musicOnlyQueue,
  );
  return queueIndex == null
      ? null
      : PlaybackNavigationTarget.queue(
          video: queue.items[queueIndex],
          index: queueIndex,
        );
}

int? _nextMatchingQueueIndex(
  PlaybackQueue queue, {
  required YouTubeVideo current,
  required bool musicOnly,
}) {
  if (!queue.isActive) {
    return null;
  }
  var candidate = queue.nextIndex;
  for (
    var inspected = 0;
    candidate != null && inspected < queue.items.length;
    inspected++
  ) {
    final item = queue.items[candidate];
    final isCurrent = item.id == current.id && item.isMusic == current.isMusic;
    if (!isCurrent && (!musicOnly || item.isMusic)) {
      return candidate;
    }
    candidate = queue.selectIndex(candidate).nextIndex;
  }
  return null;
}
