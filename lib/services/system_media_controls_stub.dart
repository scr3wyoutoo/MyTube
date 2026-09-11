import 'package:media_kit/media_kit.dart';

import '../models/youtube_video.dart';

class SystemMediaControls {
  SystemMediaControls._();

  static final SystemMediaControls instance = SystemMediaControls._();

  Future<void> initialize() async {}

  Future<void> activatePlaybackSession() async {}

  Future<void> attach({
    required Player player,
    required YouTubeVideo video,
    List<YouTubeVideo> playlist = const [],
    int? playlistIndex,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function()? onSkipToNext,
  }) async {}

  Future<void> attachExternal({
    required YouTubeVideo video,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool buffering,
    List<YouTubeVideo> playlist = const [],
    int? playlistIndex,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function(Duration position) onSeek,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function()? onSkipToNext,
  }) async {}

  Future<void> updateExternalState({
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool buffering,
  }) async {}

  Future<void> detach(
    Player player, {
    bool keepAudioSessionActive = false,
  }) async {}

  Future<void> beginTransition({
    required Player player,
    required YouTubeVideo nextVideo,
  }) async {}

  Future<void> setSecondaryPlayer(Player? player) async {}

  Future<void> promoteSecondaryPlayer({
    required Player previousPlayer,
    required Player promotedPlayer,
    required YouTubeVideo video,
    List<YouTubeVideo> playlist = const [],
    int? playlistIndex,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function()? onSkipToNext,
  }) async {}

  Future<void> clear() async {}

  void setPlaybackInterruptionHandlers({
    bool Function()? isPlaybackRunning,
    Future<void> Function()? onPauseRequested,
    Future<void> Function()? onResumeRequested,
    Future<void> Function(bool ducked)? onDuckingChanged,
    Future<void> Function()? onRemoteSurfaceClosed,
  }) {}

  void setTaskRemovedHandler(Future<void> Function()? callback) {}

  Future<void> dispose() async {}
}
