import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart';

import '../models/youtube_video.dart';
import '../utils/playlist_audio_fade.dart';

class SystemMediaControls {
  SystemMediaControls._();

  static final SystemMediaControls instance = SystemMediaControls._();

  _MediaKitAudioHandler? _handler;
  Future<void>? _initializing;
  StreamSubscription<void>? _becomingNoisySubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  AudioSession? _audioSession;
  Player? _audioSessionPlayer;
  bool _audioSessionActive = false;
  bool _resumeAfterInterruption = false;
  bool Function()? _isPlaybackRunning;
  Future<void> Function()? _onPauseRequested;
  Future<void> Function()? _onResumeRequested;
  Future<void> Function(bool ducked)? _onDuckingChanged;
  Future<void> Function()? _onRemoteSurfaceClosed;
  Future<void> Function()? _onTaskRemoved;

  bool get _isSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> initialize() {
    if (!_isSupported) {
      return Future.value();
    }
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    final session = await AudioSession.instance;
    _audioSession = session;
    _handler = await AudioService.init<_MediaKitAudioHandler>(
      builder: _MediaKitAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.flutter_browser_app.playback',
        androidNotificationChannelName: 'MyTube Wiedergabe',
        androidNotificationChannelDescription:
            'Steuerung der laufenden Video- und Musikwiedergabe',
        androidNotificationIcon: 'drawable/ic_stat_playback',
        androidResumeOnClick: true,
        androidNotificationOngoing: false,
        // Remote standby intentionally keeps the media surface resumable for
        // more than 30 minutes. Case 2 explicitly calls clear(), so only an
        // open paused audio panel retains foreground priority.
        androidStopForegroundOnPause: false,
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
    _handler?.onTaskRemovedCallback = _onTaskRemoved;
    _handler?.onRemoteSurfaceClosedCallback = _onRemoteSurfaceClosed;
    await session.configure(const AudioSessionConfiguration.music());

    if (Platform.isAndroid) {
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
        _resumeAfterInterruption = false;
        unawaited(_pausePlayback());
      });
    }
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        _resumeAfterInterruption = _playbackIsRunning;
        if (event.type == AudioInterruptionType.duck) {
          unawaited(_setDucked(true));
        } else {
          unawaited(_pausePlayback());
        }
      } else if (event.type == AudioInterruptionType.duck) {
        unawaited(_setDucked(false));
      } else if (_resumeAfterInterruption) {
        _resumeAfterInterruption = false;
        unawaited(_resumePlayback());
      }
    });
  }

  bool get _playbackIsRunning =>
      _isPlaybackRunning?.call() ?? _handler?.isPlaying == true;

  Future<void> _pausePlayback() async {
    final callback = _onPauseRequested;
    if (callback != null) {
      await callback();
      return;
    }
    await _handler?.pause();
  }

  Future<void> _resumePlayback() async {
    await _activateAudioSession();
    final callback = _onResumeRequested;
    if (callback != null) {
      await callback();
      return;
    }
    await _handler?.play();
  }

  Future<void> _setDucked(bool ducked) async {
    final callback = _onDuckingChanged;
    if (callback != null) {
      await callback(ducked);
      return;
    }
    if (ducked) {
      await _handler?.duck();
    } else {
      await _handler?.unduck();
    }
  }

  Future<void> _activateAudioSession() async {
    if (_audioSessionActive) {
      return;
    }
    _audioSessionActive = await _audioSession?.setActive(true) ?? false;
  }

  Future<void> _deactivateAudioSession() async {
    if (!_audioSessionActive) {
      return;
    }
    await _audioSession?.setActive(false);
    _audioSessionActive = false;
  }

  Future<void> activatePlaybackSession() async {
    if (!_isSupported) return;
    await initialize();
    await _activateAudioSession();
  }

  Future<void> attach({
    required Player player,
    required YouTubeVideo video,
    List<YouTubeVideo> playlist = const [],
    int? playlistIndex,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function()? onSkipToNext,
  }) async {
    if (!_isSupported) {
      return;
    }
    await initialize();
    _audioSessionPlayer = player;
    await _activateAudioSession();
    if (!video.isMusic) {
      await _handler?.detachCurrent();
      return;
    }
    await _handler?.attach(
      player: player,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: onSkipToPrevious,
      onSkipToNext: onSkipToNext,
    );
  }

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
  }) async {
    if (!_isSupported) return;
    await initialize();
    _audioSessionPlayer = null;
    await _activateAudioSession();
    await _handler?.attachExternal(
      video: video,
      position: position,
      duration: duration,
      playing: playing,
      buffering: buffering,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onPlay: onPlay,
      onPause: onPause,
      onSeek: onSeek,
      onSkipToPrevious: onSkipToPrevious,
      onSkipToNext: onSkipToNext,
    );
  }

  Future<void> updateExternalState({
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool buffering,
  }) async {
    if (!_isSupported) return;
    await _handler?.updateExternalState(
      position: position,
      duration: duration,
      playing: playing,
      buffering: buffering,
    );
  }

  Future<void> detach(
    Player player, {
    bool keepAudioSessionActive = false,
  }) async {
    if (!_isSupported) {
      return;
    }
    await _handler?.detach(player);
    if (identical(_audioSessionPlayer, player)) {
      _audioSessionPlayer = null;
      await _setDucked(false);
      if (!keepAudioSessionActive) {
        await _deactivateAudioSession();
      }
    }
  }

  Future<void> beginTransition({
    required Player player,
    required YouTubeVideo nextVideo,
  }) async {
    if (!_isSupported) {
      return;
    }
    if (!nextVideo.isMusic) {
      await _handler?.detach(player);
      return;
    }
    await initialize();
    await _handler?.beginTransition(player: player, nextVideo: nextVideo);
  }

  Future<void> setSecondaryPlayer(Player? player) async {
    if (!_isSupported) {
      return;
    }
    if (player == null) {
      await _handler?.setSecondaryPlayer(null);
      return;
    }
    await initialize();
    await _handler?.setSecondaryPlayer(player);
  }

  Future<void> promoteSecondaryPlayer({
    required Player previousPlayer,
    required Player promotedPlayer,
    required YouTubeVideo video,
    List<YouTubeVideo> playlist = const [],
    int? playlistIndex,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function()? onSkipToNext,
  }) async {
    if (!_isSupported) {
      return;
    }
    await initialize();
    _audioSessionPlayer = promotedPlayer;
    await _activateAudioSession();
    await _handler?.promoteSecondaryPlayer(
      previousPlayer: previousPlayer,
      promotedPlayer: promotedPlayer,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: onSkipToPrevious,
      onSkipToNext: onSkipToNext,
    );
  }

  Future<void> clear() async {
    if (!_isSupported) {
      return;
    }
    _audioSessionPlayer = null;
    _resumeAfterInterruption = false;
    await _setDucked(false);
    await _handler?.detachCurrent();
    await _deactivateAudioSession();
  }

  void setPlaybackInterruptionHandlers({
    bool Function()? isPlaybackRunning,
    Future<void> Function()? onPauseRequested,
    Future<void> Function()? onResumeRequested,
    Future<void> Function(bool ducked)? onDuckingChanged,
    Future<void> Function()? onRemoteSurfaceClosed,
  }) {
    _isPlaybackRunning = isPlaybackRunning;
    _onPauseRequested = onPauseRequested;
    _onResumeRequested = onResumeRequested;
    _onDuckingChanged = onDuckingChanged;
    _onRemoteSurfaceClosed = onRemoteSurfaceClosed;
    if (_handler case final handler?) {
      handler.onRemoteSurfaceClosedCallback = onRemoteSurfaceClosed;
    }
  }

  void setTaskRemovedHandler(Future<void> Function()? callback) {
    _onTaskRemoved = callback;
    if (_handler case final handler?) {
      handler.onTaskRemovedCallback = callback;
    }
  }

  Future<void> dispose() async {
    _onTaskRemoved = null;
    if (_handler case final handler?) {
      handler.onTaskRemovedCallback = null;
      handler.onRemoteSurfaceClosedCallback = null;
    }
    await _becomingNoisySubscription?.cancel();
    await _interruptionSubscription?.cancel();
    _isPlaybackRunning = null;
    _onPauseRequested = null;
    _onResumeRequested = null;
    _onDuckingChanged = null;
    _onRemoteSurfaceClosed = null;
    _audioSessionPlayer = null;
    await _deactivateAudioSession();
    await _handler?.detachCurrent();
  }
}

class _MediaKitAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onTaskRemovedCallback;
  Future<void> Function()? onRemoteSurfaceClosedCallback;
  Player? _player;
  Player? _secondaryPlayer;
  List<StreamSubscription<dynamic>> _subscriptions = const [];
  StreamSubscription<bool>? _secondaryPlayingSubscription;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  bool _secondaryPlaying = false;
  double _volumeBeforeDuck = 100;
  Future<void> Function()? _onSkipToPrevious;
  Future<void> Function()? _onSkipToNext;
  int? _queueIndex;
  bool _externalActive = false;
  Future<void> Function()? _onExternalPlay;
  Future<void> Function()? _onExternalPause;
  Future<void> Function(Duration position)? _onExternalSeek;

  bool get isPlaying => _effectivePlaying;

  bool get _effectivePlaying => isCrossfadePlaybackRunning(
    primaryPlaying: _playing,
    incomingPlaying: _secondaryPlaying,
    crossfadeActive: _secondaryPlayer != null,
  );

  Future<void> attach({
    required Player player,
    required YouTubeVideo video,
    required List<YouTubeVideo> playlist,
    required int? playlistIndex,
    required Future<void> Function()? onSkipToPrevious,
    required Future<void> Function()? onSkipToNext,
  }) async {
    await _detachCurrent(publishIdle: false);
    await _bindPrimary(
      player: player,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: onSkipToPrevious,
      onSkipToNext: onSkipToNext,
    );
  }

  Future<void> _bindPrimary({
    required Player player,
    required YouTubeVideo video,
    required List<YouTubeVideo> playlist,
    required int? playlistIndex,
    required Future<void> Function()? onSkipToPrevious,
    required Future<void> Function()? onSkipToNext,
  }) async {
    _clearExternalBinding();
    _player = player;
    _position = player.state.position;
    _duration = player.state.duration;
    _playing = player.state.playing;
    _buffering = player.state.buffering;
    _completed = player.state.completed;
    _onSkipToPrevious = onSkipToPrevious;
    _onSkipToNext = onSkipToNext;
    _queueIndex = playlist.isEmpty ? 0 : playlistIndex;

    queue.add(
      (playlist.isEmpty ? <YouTubeVideo>[video] : playlist)
          .map(_mediaItemFor)
          .toList(growable: false),
    );
    mediaItem.add(_mediaItemFor(video, duration: _duration));

    _subscriptions = <StreamSubscription<dynamic>>[
      player.stream.position.listen((position) {
        _position = position;
      }),
      player.stream.duration.listen((duration) {
        _duration = duration;
        final item = mediaItem.valueOrNull;
        if (item != null && duration > Duration.zero) {
          mediaItem.add(item.copyWith(duration: duration));
        }
        _broadcastState();
      }),
      player.stream.playing.listen((playing) {
        _playing = playing;
        _syncPositionTimer();
        _broadcastState();
      }),
      player.stream.buffering.listen((buffering) {
        _buffering = buffering;
        _broadcastState();
      }),
      player.stream.completed.listen((completed) {
        _completed = completed;
        _broadcastState();
      }),
      player.stream.error.listen((_) {
        playbackState.add(
          PlaybackState(
            controls: const [MediaControl.play],
            processingState: AudioProcessingState.error,
            playing: false,
            updatePosition: _position,
          ),
        );
      }),
    ];
    _syncPositionTimer();
    _broadcastState();
  }

  Future<void> attachExternal({
    required YouTubeVideo video,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool buffering,
    required List<YouTubeVideo> playlist,
    required int? playlistIndex,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function(Duration position) onSeek,
    required Future<void> Function()? onSkipToPrevious,
    required Future<void> Function()? onSkipToNext,
  }) async {
    await _detachCurrent(publishIdle: false);
    _externalActive = true;
    _onExternalPlay = onPlay;
    _onExternalPause = onPause;
    _onExternalSeek = onSeek;
    _position = position;
    _duration = duration;
    _playing = playing;
    _buffering = buffering;
    _completed = false;
    _onSkipToPrevious = onSkipToPrevious;
    _onSkipToNext = onSkipToNext;
    _queueIndex = playlist.isEmpty ? 0 : playlistIndex;
    queue.add(
      (playlist.isEmpty ? <YouTubeVideo>[video] : playlist)
          .map(_mediaItemFor)
          .toList(growable: false),
    );
    mediaItem.add(_mediaItemFor(video, duration: duration));
    _syncPositionTimer();
    _broadcastState();
  }

  Future<void> updateExternalState({
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool buffering,
  }) async {
    if (!_externalActive) return;
    final durationChanged = duration > Duration.zero && duration != _duration;
    _position = position;
    _duration = duration;
    _playing = playing;
    _buffering = buffering;
    _completed = duration > Duration.zero && position >= duration && !playing;
    if (durationChanged) {
      final item = mediaItem.valueOrNull;
      if (item != null) mediaItem.add(item.copyWith(duration: duration));
    }
    _syncPositionTimer();
    _broadcastState();
  }

  Future<void> promoteSecondaryPlayer({
    required Player previousPlayer,
    required Player promotedPlayer,
    required YouTubeVideo video,
    required List<YouTubeVideo> playlist,
    required int? playlistIndex,
    required Future<void> Function()? onSkipToPrevious,
    required Future<void> Function()? onSkipToNext,
  }) async {
    if (!identical(_player, previousPlayer) ||
        !identical(_secondaryPlayer, promotedPlayer)) {
      await attach(
        player: promotedPlayer,
        video: video,
        playlist: playlist,
        playlistIndex: playlistIndex,
        onSkipToPrevious: onSkipToPrevious,
        onSkipToNext: onSkipToNext,
      );
      return;
    }

    // Keep the AudioService session continuously alive: only its bindings
    // exchange roles. No idle/completed state and no player command is emitted
    // during the critical crossfade handoff.
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions = const [];
    await _secondaryPlayingSubscription?.cancel();
    _secondaryPlayingSubscription = null;
    _secondaryPlayer = null;
    _secondaryPlaying = false;
    await _bindPrimary(
      player: promotedPlayer,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: onSkipToPrevious,
      onSkipToNext: onSkipToNext,
    );
  }

  void _syncPositionTimer() {
    if (_effectivePlaying) {
      _positionTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _broadcastState(),
      );
      return;
    }
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  String? _readArtist(String description) {
    if (!description.contains('•')) {
      return null;
    }
    final firstPart = description.split('•').first.trim();
    return firstPart.isEmpty ? null : firstPart;
  }

  MediaItem _mediaItemFor(
    YouTubeVideo video, {
    Duration duration = Duration.zero,
  }) {
    return MediaItem(
      id: video.id,
      title: video.title,
      artist: video.channelTitle.isEmpty
          ? _readArtist(video.description)
          : video.channelTitle,
      duration: duration > Duration.zero ? duration : null,
      artUri: video.thumbnailUrl.isEmpty
          ? null
          : Uri.tryParse(video.thumbnailUrl),
    );
  }

  void _broadcastState() {
    final playing = _effectivePlaying;
    final completed = _completed && !playing;
    final controls = <MediaControl>[
      if (_onSkipToPrevious != null) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      if (_onSkipToNext != null) MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: List<int>.generate(
          controls.length,
          (index) => index,
        ),
        processingState: completed
            ? AudioProcessingState.completed
            : _buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _position,
        speed: 1,
        queueIndex: _queueIndex,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_externalActive) {
      await _onExternalPlay?.call();
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    if (_completed || (_duration > Duration.zero && _position >= _duration)) {
      await player.seek(Duration.zero);
    }
    await player.play();
    await _secondaryPlayer?.play();
    _completed = false;
    _syncPositionTimer();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    if (_externalActive) {
      await _onExternalPause?.call();
      return;
    }
    await _player?.pause();
    await _secondaryPlayer?.pause();
    _playing = false;
    _secondaryPlaying = false;
    _syncPositionTimer();
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await pause();
    await onRemoteSurfaceClosedCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await _onSkipToPrevious?.call();
  }

  @override
  Future<void> skipToNext() async {
    await _onSkipToNext?.call();
  }

  @override
  Future<void> onTaskRemoved() async {
    final callback = onTaskRemovedCallback;
    if (callback != null) {
      await callback();
      return;
    }
    await pause();
    await detachCurrent();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_externalActive) {
      final target = position < Duration.zero
          ? Duration.zero
          : _duration > Duration.zero && position > _duration
          ? _duration
          : position;
      await _onExternalSeek?.call(target);
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    final target = position < Duration.zero
        ? Duration.zero
        : _duration > Duration.zero && position > _duration
        ? _duration
        : position;
    await player.seek(target);
    _position = target;
    _broadcastState();
  }

  Future<void> duck() async {
    final player = _player;
    if (player == null) {
      return;
    }
    _volumeBeforeDuck = player.state.volume;
    await player.setVolume(_volumeBeforeDuck * 0.25);
  }

  Future<void> unduck() async {
    await _player?.setVolume(_volumeBeforeDuck);
  }

  Future<void> setSecondaryPlayer(Player? player) async {
    await _secondaryPlayingSubscription?.cancel();
    _secondaryPlayingSubscription = null;
    _secondaryPlayer = player;
    _secondaryPlaying = player?.state.playing ?? false;
    if (player != null) {
      _secondaryPlayingSubscription = player.stream.playing.listen((playing) {
        _secondaryPlaying = playing;
        _syncPositionTimer();
        _broadcastState();
      });
    }
    _syncPositionTimer();
    _broadcastState();
  }

  Future<void> detach(Player player) async {
    if (!identical(_player, player)) {
      return;
    }
    await detachCurrent();
  }

  Future<void> beginTransition({
    required Player player,
    required YouTubeVideo nextVideo,
  }) async {
    if (!identical(_player, player)) {
      return;
    }
    await _detachCurrent(publishIdle: false);
    _playing = true;
    _buffering = true;
    mediaItem.add(_mediaItemFor(nextVideo));
    _broadcastState();
  }

  Future<void> detachCurrent() async {
    await _detachCurrent(publishIdle: true);
  }

  Future<void> _detachCurrent({required bool publishIdle}) async {
    _positionTimer?.cancel();
    _positionTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions = const [];
    await _secondaryPlayingSubscription?.cancel();
    _secondaryPlayingSubscription = null;
    _player = null;
    _clearExternalBinding();
    _secondaryPlayer = null;
    _secondaryPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _buffering = false;
    _completed = false;
    if (publishIdle) {
      _onSkipToPrevious = null;
      _onSkipToNext = null;
      _queueIndex = null;
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
    }
  }

  void _clearExternalBinding() {
    _externalActive = false;
    _onExternalPlay = null;
    _onExternalPause = null;
    _onExternalSeek = null;
  }
}
