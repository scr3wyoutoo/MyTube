class VideoSubtitleCue {
  const VideoSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

enum VideoManifestSource {
  standard('Standard'),
  firstFallback('Fallback 1'),
  secondFallback('Fallback 2');

  const VideoManifestSource(this.label);

  final String label;
}

enum VideoManifestLoadPhase { requested, available, failed }

class VideoManifestLoadEvent {
  const VideoManifestLoadEvent({
    required this.videoId,
    required this.source,
    required this.phase,
  });

  final String videoId;
  final VideoManifestSource source;
  final VideoManifestLoadPhase phase;
}

typedef VideoManifestEventCallback =
    void Function(VideoManifestLoadEvent event);
typedef VideoPlaybackFallbackLoader = Future<ResolvedVideoPlayback> Function();

class VideoQualityOption {
  const VideoQualityOption({
    required this.label,
    required this.height,
    required this.videoUrl,
    this.audioUrl,
    this.hlsMasterPlaylist,
    this.expectedDuration,
    this.isHls = false,
    this.requiresSegmentedProxy = false,
    this.transportLabel = 'progressiver Stream',
  });

  final String label;
  final int height;
  final Uri videoUrl;
  final Uri? audioUrl;

  /// A locally served HLS master that binds YouTube's separate video and
  /// audio playlists to one player timeline.
  final String? hlsMasterPlaylist;

  /// Duration reported by YouTube for this exact signed stream. Native
  /// players may expose a longer container timeline for adaptive audio.
  final Duration? expectedDuration;
  final bool isHls;
  final bool requiresSegmentedProxy;
  final String transportLabel;
}

class ResolvedVideoPlayback {
  const ResolvedVideoPlayback({
    required this.qualities,
    required this.defaultQuality,
    this.fallbackQuality,
    this.pictureInPictureQuality,
    this.subtitles = const [],
    this.manifestSource = VideoManifestSource.standard,
    this.fallbackLoader,
    this.isLive = false,
  });

  final List<VideoQualityOption> qualities;
  final VideoQualityOption defaultQuality;
  final VideoQualityOption? fallbackQuality;
  final VideoQualityOption? pictureInPictureQuality;
  final List<VideoSubtitleCue> subtitles;
  final VideoManifestSource manifestSource;
  final VideoPlaybackFallbackLoader? fallbackLoader;
  final bool isLive;

  ResolvedVideoPlayback withSubtitles(List<VideoSubtitleCue> subtitles) {
    return ResolvedVideoPlayback(
      qualities: qualities,
      defaultQuality: defaultQuality,
      fallbackQuality: fallbackQuality,
      pictureInPictureQuality: pictureInPictureQuality,
      subtitles: subtitles,
      manifestSource: manifestSource,
      fallbackLoader: fallbackLoader,
      isLive: isLive,
    );
  }

  String? subtitleAt(Duration position) {
    var low = 0;
    var high = subtitles.length - 1;

    while (low <= high) {
      final middle = low + ((high - low) ~/ 2);
      final cue = subtitles[middle];
      if (position < cue.start) {
        high = middle - 1;
      } else if (position >= cue.end) {
        low = middle + 1;
      } else {
        return cue.text;
      }
    }

    return null;
  }
}

VideoQualityOption chooseDefaultVideoQuality(
  Iterable<VideoQualityOption> qualities,
) {
  final sorted = qualities.toList(growable: false)
    ..sort((first, second) => first.height.compareTo(second.height));
  if (sorted.isEmpty) {
    throw StateError('No video qualities available.');
  }

  for (final quality in sorted) {
    if (quality.height == 720) {
      return quality;
    }
  }
  for (final quality in sorted) {
    if (quality.height > 720) {
      return quality;
    }
  }
  return sorted.last;
}

List<VideoQualityOption> filterSelectableVideoQualities(
  Iterable<VideoQualityOption> qualities,
) {
  final sorted = qualities.toList(growable: false)
    ..sort((first, second) => second.height.compareTo(first.height));
  final hdQualities = sorted
      .where((quality) => quality.height >= 720)
      .toList(growable: false);
  return List.unmodifiable(hdQualities.isNotEmpty ? hdQualities : sorted);
}
