import '../models/video_playback.dart';

/// Selects streams for Apple's native picture-in-picture player.
///
/// A local HLS master is preferred because it binds YouTube's separate audio
/// and video renditions to one AVPlayer timeline. A combined progressive
/// stream is retained exclusively as a fallback.
class IosPipStreamPolicy {
  const IosPipStreamPolicy._();

  static VideoQualityOption? primaryQuality(
    ResolvedVideoPlayback playback,
    VideoQualityOption selectedQuality,
  ) {
    if (_isNativePlayable(selectedQuality)) {
      return selectedQuality;
    }

    final explicit = playback.pictureInPictureQuality;
    if (explicit != null && _isNativePlayable(explicit)) {
      return explicit;
    }

    final defaultQuality = playback.defaultQuality;
    if (_isNativePlayable(defaultQuality)) {
      return defaultQuality;
    }

    for (final quality in playback.qualities) {
      if (_isNativePlayable(quality)) {
        return quality;
      }
    }
    return null;
  }

  static VideoQualityOption? progressiveFallbackQuality(
    ResolvedVideoPlayback playback,
  ) {
    final allCandidates = <VideoQualityOption>[playback.defaultQuality];
    final pictureInPictureQuality = playback.pictureInPictureQuality;
    if (pictureInPictureQuality != null) {
      allCandidates.add(pictureInPictureQuality);
    }
    final fallbackQuality = playback.fallbackQuality;
    if (fallbackQuality != null) {
      allCandidates.add(fallbackQuality);
    }
    allCandidates.addAll(playback.qualities);
    final candidates = allCandidates
        .where(_isCombinedProgressive)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    final exact360 = candidates.where((quality) => quality.height == 360);
    if (exact360.isNotEmpty) {
      return exact360.first;
    }
    candidates.sort((first, second) => first.height.compareTo(second.height));
    return candidates.first;
  }

  static Future<({ResolvedVideoPlayback playback, VideoQualityOption quality})?>
  resolveProgressiveFallback(ResolvedVideoPlayback initialPlayback) async {
    var playback = initialPlayback;
    while (true) {
      final quality = progressiveFallbackQuality(playback);
      if (quality != null) {
        return (playback: playback, quality: quality);
      }
      final fallbackLoader = playback.fallbackLoader;
      if (fallbackLoader == null) {
        return null;
      }
      playback = await fallbackLoader();
    }
  }

  static bool usesLocalHlsMaster(VideoQualityOption quality) =>
      quality.hlsMasterPlaylist?.isNotEmpty == true;

  static bool _isNativePlayable(VideoQualityOption quality) =>
      usesLocalHlsMaster(quality) ||
      (quality.isHls && quality.audioUrl == null) ||
      _isCombinedProgressive(quality);

  static bool _isCombinedProgressive(VideoQualityOption quality) =>
      !quality.isHls &&
      quality.hlsMasterPlaylist == null &&
      quality.audioUrl == null;
}
