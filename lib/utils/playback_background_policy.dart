import '../models/youtube_video.dart';

enum ManualPlaybackTransitionStrategy {
  reload,
  reloadKeepingSystemSession,
  reuseCurrentPlayer,
}

/// Keeps background surfaces mutually exclusive for the selected medium.
abstract final class PlaybackBackgroundPolicy {
  static bool allowsPictureInPicture(YouTubeVideo video) => !video.isMusic;

  /// Every iOS medium with a visible video track uses the persistent native
  /// AVPlayer surface. PiP remains a separate policy: regular videos allow it,
  /// while music videos keep playing through the system audio controls only.
  static bool usesNativeIosVideoPlayer({
    required bool isIos,
    required YouTubeVideo video,
  }) => isIos && video.hasVideo;

  static bool shouldAutoEnterPictureInPicture({
    required bool pictureInPictureAllowed,
    required bool playing,
  }) => pictureInPictureAllowed && playing;

  static bool usesSystemMediaControls(YouTubeVideo video) => video.isMusic;

  /// Keeps manual Music selections on the same system media session.
  ///
  /// A ready player may load the selected item directly only while the
  /// platform backend remains the same. A music video and an audio-only song
  /// can share the Music background policy while still requiring different
  /// native players (for example MediaKit and Media3 Audio on Android).
  /// Backend changes and in-flight loads therefore reload while the system
  /// session remains active. Videos retain their existing cold-load/PiP
  /// lifecycle.
  static ManualPlaybackTransitionStrategy manualSelectionTransition({
    required YouTubeVideo nextVideo,
    required bool hasCurrentPlayer,
    required bool currentPlayerReady,
    required bool canReuseCurrentPlayer,
  }) {
    if (!usesSystemMediaControls(nextVideo) || !hasCurrentPlayer) {
      return ManualPlaybackTransitionStrategy.reload;
    }
    return currentPlayerReady && canReuseCurrentPlayer
        ? ManualPlaybackTransitionStrategy.reuseCurrentPlayer
        : ManualPlaybackTransitionStrategy.reloadKeepingSystemSession;
  }

  /// Audio-only Music playback does not need a rendered video surface before
  /// it can be prepared or promoted while the app is in the background.
  /// Music videos still use the Music background policy, but render video in
  /// the foreground.
  static bool requiresPlayerSurface(YouTubeVideo video) => video.hasVideo;

  static bool shouldPauseWhenPictureInPictureCloses({
    required bool appIsResumed,
    bool restoredToApp = false,
  }) => !restoredToApp && !appIsResumed;
}
