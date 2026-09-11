import 'dart:math' as math;

import '../models/youtube_video.dart';

const playlistAudioFadeDuration = Duration(seconds: 6);

bool shouldUsePlaylistCrossfade({
  required YouTubeVideo current,
  required YouTubeVideo? next,
}) => current.isAudioOnlyMusic && next?.isAudioOnlyMusic == true;

/// Keeps two reusable player slots only for an automatic audio-to-audio
/// handoff. Videos and mixed transitions deliberately stay on the regular
/// single-transition path.
bool shouldUseAudioQueueDoubleBuffer({
  required YouTubeVideo current,
  required YouTubeVideo next,
  required bool automatic,
  required bool prepared,
}) =>
    automatic &&
    prepared &&
    shouldUsePlaylistCrossfade(current: current, next: next);

/// Whether the incoming crossfade player has to be started to follow the
/// outgoing player. A stopped outgoing player is not treated as a pause here:
/// it may simply have completed and be waiting for promotion of the incoming
/// player. Explicit user and system pauses stop both players at their command
/// source instead.
bool shouldStartIncomingCrossfade({
  required bool outgoingPlaying,
  required bool incomingPlaying,
}) => outgoingPlaying && !incomingPlaying;

/// Treats an active crossfade as one continuous playback session while either
/// player is still producing audio.
bool isCrossfadePlaybackRunning({
  required bool primaryPlaying,
  required bool incomingPlaying,
  required bool crossfadeActive,
}) => primaryPlaying || (crossfadeActive && incomingPlaying);

double playlistAudioFadeFactor({
  required Duration position,
  required Duration duration,
  required bool isPlaylistPlayback,
  required bool hasNextItem,
  bool fadeInEnabled = false,
  bool fadeOutEnabled = true,
  Duration fadeDuration = playlistAudioFadeDuration,
}) {
  if (!isPlaylistPlayback || fadeDuration <= Duration.zero) {
    return 1;
  }

  final positionMicros = math.max(0, position.inMicroseconds);
  var fadeMicros = fadeDuration.inMicroseconds;
  final durationMicros = duration.inMicroseconds;
  if (durationMicros > 0) {
    fadeMicros = math.min(fadeMicros, math.max(1, durationMicros ~/ 2));
  }

  final fadeIn = fadeInEnabled
      ? (positionMicros / fadeMicros).clamp(0.0, 1.0)
      : 1.0;
  if (!fadeOutEnabled || !hasNextItem || durationMicros <= 0) {
    return fadeIn;
  }

  final remainingMicros = math.max(0, durationMicros - positionMicros);
  final fadeOut = (remainingMicros / fadeMicros).clamp(0.0, 1.0);
  return math.min(fadeIn, fadeOut);
}

double playlistCrossfadeIncomingFactor({
  required Duration position,
  required Duration duration,
  Duration fadeDuration = playlistAudioFadeDuration,
}) {
  if (duration <= Duration.zero || fadeDuration <= Duration.zero) {
    return 0;
  }

  final durationMicros = duration.inMicroseconds;
  final fadeMicros = math.min(
    fadeDuration.inMicroseconds,
    math.max(1, durationMicros ~/ 2),
  );
  final remainingMicros = math.max(
    0,
    durationMicros - math.max(0, position.inMicroseconds),
  );
  return (1 - (remainingMicros / fadeMicros)).clamp(0.0, 1.0);
}
