import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../models/app_tutorial_stage.dart';
import '../models/playback_navigation.dart';
import '../models/playback_queue.dart';
import '../models/search_result_limit.dart';
import '../models/user_profile.dart';
import '../models/video_playback.dart';
import '../models/video_search_source.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_category.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import '../services/android_picture_in_picture.dart';
import '../services/android_media3_audio_playback.dart';
import '../services/android_media3_video_player.dart';
import '../services/app_log.dart';
import '../services/ios_native_audio_playback.dart';
import '../services/ios_picture_in_picture.dart';
import '../services/playback_manifest_cache.dart';
import '../services/profile_controller.dart';
import '../services/segmented_stream_proxy.dart';
import '../services/system_media_controls.dart';
import '../services/video_playback_service.dart';
import '../services/youtube_catalog_repository.dart';
import '../services/youtube_catalog_repository_factory.dart';
import '../services/youtube_music_catalog_repository.dart';
import '../services/youtube_music_discovery_repository.dart';
import '../services/youtube_search_repository.dart';
import '../services/youtube_video_details_repository.dart';
import '../utils/player_gestures.dart';
import '../utils/android_playback_backend_policy.dart';
import '../utils/hybrid_playback_sleep_model.dart';
import '../utils/ios_pip_stream_policy.dart';
import '../utils/playback_background_policy.dart';
import '../utils/playback_seek_policy.dart';
import '../utils/player_fullscreen_policy.dart';
import '../utils/player_pull_down_fullscreen_policy.dart';
import '../utils/player_pull_up_fullscreen_policy.dart';
import '../utils/playlist_audio_fade.dart';
import '../utils/media_duration.dart';
import '../utils/playlist_preparation_gate.dart';
import '../utils/search_request_policy.dart';
import '../widgets/app_section_navigation_bar.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/media_search_category_bar.dart';
import '../widgets/media_source_search_bar.dart';
import '../widgets/player_gesture_feedback_overlay.dart';
import '../widgets/player_transport_controls.dart';
import '../widgets/player_tutorial_targets.dart';
import '../widgets/tutorial_coach_overlay.dart';
import '../widgets/video_result_card.dart';
import '../widgets/youtube_catalog_result_card.dart';
import 'hot_music_page.dart';
import 'profile_page.dart';

enum _PlaybackBackendKind {
  mediaKit,
  androidMedia3Video,
  androidMedia3Audio,
  iosAvVideo,
  iosAvAudio,
}

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.video,
    required this.searchResults,
    required this.searchQuery,
    required this.searchRepository,
    this.youtubeSearchRepository,
    this.musicSearchRepository,
    this.catalogRepository,
    this.initialVideoFeed,
    this.searchSource = VideoSearchSource.youtube,
    this.playbackService,
    this.manifestCache,
    this.profileController,
    this.playlistQueue = const [],
    this.initialPlaylistIndex = 0,
    this.searchResultsAutoplayEligible = true,
    this.initialNextPageToken,
    this.initialPreviousPageToken,
    this.initialPageNumber = 1,
    this.videoDetailsRepository,
    this.initiallyPaused = false,
  });

  final YouTubeVideo video;
  final List<YouTubeVideo> searchResults;
  final String searchQuery;
  final YouTubeSearchRepository searchRepository;
  final YouTubeSearchRepository? youtubeSearchRepository;
  final YouTubeSearchRepository? musicSearchRepository;
  final YouTubeCatalogRepository? catalogRepository;
  final YouTubeVideoFeed? initialVideoFeed;
  final VideoSearchSource searchSource;
  final VideoPlaybackService? playbackService;
  final PlaybackManifestCache? manifestCache;
  final ProfileController? profileController;
  final List<YouTubeVideo> playlistQueue;
  final int initialPlaylistIndex;
  final bool searchResultsAutoplayEligible;
  final String? initialNextPageToken;
  final String? initialPreviousPageToken;
  final int initialPageNumber;
  final YouTubeVideoDetailsRepository? videoDetailsRepository;
  final bool initiallyPaused;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const int _loadMoreTriggerItemCount = 3;

  static const _youtubeHeaders = <String, String>{
    'Accept': '*/*',
    'Origin': 'https://www.youtube.com',
    'Referer': 'https://www.youtube.com/',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
  };
  static const _safariHlsHeaders = <String, String>{
    'Accept': '*/*',
    'Referer': 'https://www.youtube.com/',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/15.5 Safari/605.1.15',
  };

  late VideoPlaybackService _playbackService;
  late SegmentedStreamProxy _streamProxy;
  late final bool _ownsPlaybackService;
  late final TextEditingController _queryController;
  late final ProfileController _profileController;
  late final bool _ownsProfileController;
  late final YouTubeCatalogRepository _catalogRepository;
  late final bool _ownsCatalogRepository;

  late YouTubeVideo _selectedVideo;
  late List<YouTubeVideo> _searchResults;
  late PlaybackQueue _playbackQueue;
  PlaybackHistories _playbackHistories = const PlaybackHistories();
  late bool _searchResultsAutoplayEligible;
  late String _searchQuery;
  late YouTubeVideoFeed _videoFeed;
  late VideoSearchSource _searchSource;
  int _selectedAppSection = 0;
  YouTubeSearchCategory _searchCategory = YouTubeSearchCategory.videos;
  YouTubeSearchSort _sessionVideoSearchSort = YouTubeSearchSort.relevance;
  YouTubeSearchSort _sessionPlaylistSearchSort = YouTubeSearchSort.relevance;
  final Map<YouTubeSearchCategory, _PlayerCatalogSearchState>
  _catalogSearchStates = {
    YouTubeSearchCategory.channels: _PlayerCatalogSearchState(),
    YouTubeSearchCategory.playlists: _PlayerCatalogSearchState(),
  };
  String? _nextPageToken;
  int _resultsPageNumber = 1;
  bool _isLoadingMoreResults = false;
  bool _hasReachedResultsEnd = false;
  String? _loadMoreResultsError;
  final Set<String> _loadedVideoPageTokens = {};
  int _searchRequestNumber = 0;
  int _queueRevision = 0;

  Player? _player;
  bool _nativeAndroidMedia3PlayerActive = false;
  bool _nativeAndroidMedia3AudioPlayerActive = false;
  bool _lastAndroidMedia3PlaybackRequested = false;
  bool _nativeIosMainPlayerActive = false;
  bool _nativeIosAudioPlayerActive = false;
  _PreparedNativeAndroidMedia3AudioPlayback?
  _preparedNativeAndroidMedia3AudioPlayback;
  _PreparedNativeIosAudioPlayback? _preparedNativeIosAudioPlayback;
  String? _loadedPlayerVideoId;
  VideoController? _videoController;
  List<StreamSubscription<dynamic>> _playerSubscriptions = const [];
  final ValueNotifier<_PlaybackViewState> _playbackState = ValueNotifier(
    const _PlaybackViewState(),
  );
  ResolvedVideoPlayback? _playback;
  VideoQualityOption? _selectedQuality;
  Timer? _seekHoldTimer;
  Timer? _hideControlsTimer;
  final PlayerGestureFeedbackController _gestureFeedbackController =
      PlayerGestureFeedbackController();
  final PlayerTutorialTargets _playerTutorialTargets = PlayerTutorialTargets();
  PlayerTutorialStep? _playerTutorialStep;
  Duration? _dragPosition;
  Offset? _lastDoubleTapPosition;
  String? _playerError;
  String? _playerErrorDetails;
  String? _searchError;
  int _loadGeneration = 0;
  double _volume = 1;
  double _volumeBeforeMute = 1;
  double _brightness = 1.5;
  bool _isLoadingVideo = true;
  bool _isSearching = false;
  bool _subtitlesEnabled = false;
  bool _controlsVisible = true;
  bool _settingsVisible = false;
  bool _isChangingQuality = false;
  bool _isInPictureInPictureMode = false;
  bool _iosPictureInPictureReady = false;
  bool _iosPictureInPicturePreparing = false;
  bool _iosPictureInPictureStarting = false;
  bool _iosPictureInPictureAutoEnterArmed = false;
  bool _iosPictureInPictureHandoff = false;
  bool _iosPictureInPictureWasPlaying = false;
  bool _iosPictureInPictureUsesHlsMaster = false;
  int _iosPictureInPictureAutoEnterGeneration = 0;
  Future<void>? _iosPictureInPictureHandoffOperation;
  int _iosPipDebugRequestId = 0;
  int _iosPipDebugManualTapCount = 0;
  int _iosPipDebugStartCallCount = 0;
  String _iosPipDebugTrigger = 'none';
  Stopwatch? _iosPipDebugStopwatch;
  Future<void>? _iosPipDebugBeginFuture;
  Timer? _iosPipDebugSnapshotTimer;
  final Map<String, Map<String, Object?>> _iosPipDebugSnapshots = {};
  bool _iosPipDebugStartRequested = false;
  bool _iosPipDebugStarted = false;
  bool _iosPipDebugDialogVisible = false;
  bool _iosPipDebugDialogPending = false;
  bool _autoAdvanceInProgress = false;
  bool _resultsRepresentPlaylist = false;
  bool _fullscreenRequested = false;
  bool? _lastFullscreenMode;
  late final AnimationController _pullDownFullscreenController;
  late final AnimationController _pullUpFullscreenController;
  final ScrollController _videoResultsScrollController = ScrollController();
  final ScrollController _channelResultsScrollController = ScrollController();
  final ScrollController _playlistResultsScrollController = ScrollController();
  bool _pullDownFullscreenGestureActive = false;
  bool _videoResultsPullDownArmed = false;
  double _pullDownFullscreenDistance = 0;
  int? _pullDownFullscreenPointer;
  Offset? _pullDownFullscreenPointerStart;
  Offset? _pullDownFullscreenPointerLast;
  VelocityTracker? _pullDownFullscreenVelocityTracker;
  bool _pullUpFullscreenGestureActive = false;
  double _pullUpFullscreenDistance = 0;
  int? _pullUpFullscreenPointer;
  Offset? _pullUpFullscreenPointerStart;
  Offset? _pullUpFullscreenPointerLast;
  VelocityTracker? _pullUpFullscreenVelocityTracker;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _bufferingStartedAt;
  double? _lastAppliedPlayerVolume;
  _PreparedQueuePlayback? _preparedNextPlayback;
  Player? _crossfadeStandbyPlayer;
  final Expando<bool> _cancelledPreparedMediaKitPlayers = Expando<bool>(
    'cancelledPreparedMediaKitPlayers',
  );
  final Expando<Future<void>> _preparedMediaKitPlayerDisposals =
      Expando<Future<void>>('preparedMediaKitPlayerDisposals');
  Future<void>? _preparingNextPlayback;
  final PlaylistPreparationGate _playlistPreparationGate =
      PlaylistPreparationGate();
  final math.Random _shuffleRandom = math.Random();
  bool _crossfadeStarted = false;
  bool _crossfadeUpdateInProgress = false;
  Future<void>? _crossfadeUpdateCompletion;
  bool _systemAudioDucked = false;
  double? _lastAppliedIncomingVolume;
  bool _appTerminationStarted = false;
  Future<void>? _appTerminationFuture;
  late final HybridPlaybackSleepModel _sleepModel;
  Timer? _sleepDeadlineTimer;
  Timer? _sleepPlaybackPauseTimer;
  Future<void> _sleepOperation = Future<void>.value();
  bool _softSleepResourcesApplied = false;
  bool _deepSleepResourcesApplied = false;
  bool _playbackAheadSuspended = false;
  bool _systemControlsDetachedForSleep = false;
  bool _streamProxyClosedForSleep = false;
  bool _resumeRequiresPlayerReload = false;
  Duration _deepSleepPosition = Duration.zero;

  List<YouTubeVideo> get _visibleResults => _searchResults
      .where((video) => video.id != _selectedVideo.id)
      .toList(growable: false);

  bool get _isMusicSearchMode =>
      _searchSource == VideoSearchSource.youtubeMusic;

  YouTubeSearchSort get _videoSearchSort => youtubeSearchSortControlsEnabled
      ? _profileController.activeProfile?.videoSearchSort ??
            _sessionVideoSearchSort
      : YouTubeSearchSort.relevance;

  YouTubeSearchSort get _playlistSearchSort => youtubeSearchSortControlsEnabled
      ? _profileController.activeProfile?.playlistSearchSort ??
            _sessionPlaylistSearchSort
      : YouTubeSearchSort.relevance;

  bool get _videoSortingEnabled =>
      !_isMusicSearchMode && _videoFeed.type == YouTubeVideoFeedType.keyword;

  String get _playbackLanguageCode =>
      _profileController.activeProfile?.language.code ??
      ProfileLanguage.english.code;

  bool get _allowsPictureInPicture =>
      PlaybackBackgroundPolicy.allowsPictureInPicture(_selectedVideo);

  bool _shouldUseNativeIosMainPlayer(YouTubeVideo video) =>
      PlaybackBackgroundPolicy.usesNativeIosVideoPlayer(
        isIos: IosPictureInPicture.instance.isSupportedPlatform,
        video: video,
      );

  bool _shouldUseNativeIosAudioPlayer(YouTubeVideo video) =>
      IosNativeAudioPlayback.instance.isSupportedPlatform &&
      video.isAudioOnlyMusic;

  bool _shouldUseNativeAndroidMedia3Player(YouTubeVideo video) =>
      shouldUseAndroidMedia3VideoPlayer(
        isAndroid: AndroidMedia3VideoPlayer.instance.isSupportedPlatform,
        video: video,
      );

  bool _shouldUseNativeAndroidMedia3AudioPlayer(YouTubeVideo video) =>
      shouldUseAndroidMedia3AudioPlayer(
        isAndroid: AndroidMedia3AudioPlayback.instance.isSupportedPlatform,
        video: video,
      );

  _PlaybackBackendKind _requiredPlaybackBackend(YouTubeVideo video) {
    if (_shouldUseNativeAndroidMedia3Player(video)) {
      return _PlaybackBackendKind.androidMedia3Video;
    }
    if (_shouldUseNativeAndroidMedia3AudioPlayer(video)) {
      return _PlaybackBackendKind.androidMedia3Audio;
    }
    if (_shouldUseNativeIosMainPlayer(video)) {
      return _PlaybackBackendKind.iosAvVideo;
    }
    if (_shouldUseNativeIosAudioPlayer(video)) {
      return _PlaybackBackendKind.iosAvAudio;
    }
    return _PlaybackBackendKind.mediaKit;
  }

  _PlaybackBackendKind? get _activePlaybackBackend {
    if (_nativeAndroidMedia3PlayerActive) {
      return _PlaybackBackendKind.androidMedia3Video;
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      return _PlaybackBackendKind.androidMedia3Audio;
    }
    if (_nativeIosMainPlayerActive) {
      return _PlaybackBackendKind.iosAvVideo;
    }
    if (_nativeIosAudioPlayerActive) {
      return _PlaybackBackendKind.iosAvAudio;
    }
    if (_player != null) {
      return _PlaybackBackendKind.mediaKit;
    }
    return null;
  }

  bool get _hasCurrentPlayer =>
      _player != null ||
      _nativeAndroidMedia3PlayerActive ||
      _nativeAndroidMedia3AudioPlayerActive ||
      _nativeIosMainPlayerActive ||
      _nativeIosAudioPlayerActive;

  bool get _isLivePlayback =>
      _selectedVideo.isLive || (_playback?.isLive ?? false);

  bool get _usesSystemMediaControls =>
      PlaybackBackgroundPolicy.usesSystemMediaControls(_selectedVideo);

  bool get _autoplayEnabled =>
      _profileController.activeProfile?.autoplaySearchResults == true;

  bool get _shuffleEnabled => _playbackQueue.isShuffled;

  double get _systemAudioVolumeFactor => _systemAudioDucked ? 0.25 : 1;

  Future<void> _attachSystemMediaControls(
    Player player,
    YouTubeVideo video,
  ) async {
    final usesSystemMediaControls =
        PlaybackBackgroundPolicy.usesSystemMediaControls(video);
    final musicQueue = usesSystemMediaControls
        ? _playbackQueue.items.where((item) => item.isMusic).toList()
        : <YouTubeVideo>[];
    final musicQueueIndex = musicQueue.indexWhere(
      (item) => item.id == video.id && item.isMusic == video.isMusic,
    );
    final playlist = usesSystemMediaControls && musicQueueIndex < 0
        ? <YouTubeVideo>[video, ...musicQueue]
        : musicQueue;
    final playlistIndex = usesSystemMediaControls
        ? musicQueueIndex < 0
              ? 0
              : musicQueueIndex
        : null;
    final previousTarget = usesSystemMediaControls
        ? previousPlaybackTarget(histories: _playbackHistories, current: video)
        : null;
    final nextTarget = usesSystemMediaControls
        ? nextPlaybackTarget(
            histories: _playbackHistories,
            current: video,
            queue: _playbackQueue,
            musicOnlyQueue: true,
          )
        : null;
    await SystemMediaControls.instance.attach(
      player: player,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: previousTarget == null
          ? null
          : _playPreviousHistoryItemFromSystem,
      onSkipToNext: nextTarget == null ? null : _playNextItemFromSystem,
    );
  }

  Future<void> _promoteSystemMediaControls({
    required Player previousPlayer,
    required Player promotedPlayer,
    required YouTubeVideo video,
  }) async {
    final musicQueue = _playbackQueue.items
        .where((item) => item.isMusic)
        .toList();
    final musicQueueIndex = musicQueue.indexWhere(
      (item) => item.id == video.id && item.isMusic == video.isMusic,
    );
    final playlist = musicQueueIndex < 0
        ? <YouTubeVideo>[video, ...musicQueue]
        : musicQueue;
    final playlistIndex = musicQueueIndex < 0 ? 0 : musicQueueIndex;
    final previousTarget = previousPlaybackTarget(
      histories: _playbackHistories,
      current: video,
    );
    final nextTarget = nextPlaybackTarget(
      histories: _playbackHistories,
      current: video,
      queue: _playbackQueue,
      musicOnlyQueue: true,
    );
    await SystemMediaControls.instance.promoteSecondaryPlayer(
      previousPlayer: previousPlayer,
      promotedPlayer: promotedPlayer,
      video: video,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onSkipToPrevious: previousTarget == null
          ? null
          : _playPreviousHistoryItemFromSystem,
      onSkipToNext: nextTarget == null ? null : _playNextItemFromSystem,
    );
  }

  Future<void> _attachAndroidMedia3AudioSystemControls(
    YouTubeVideo video,
  ) async {
    final musicQueue = _playbackQueue.items
        .where((item) => item.isMusic)
        .toList(growable: false);
    final musicQueueIndex = musicQueue.indexWhere(
      (item) => item.id == video.id && item.isMusic == video.isMusic,
    );
    final playlist = musicQueueIndex < 0
        ? <YouTubeVideo>[video, ...musicQueue]
        : musicQueue;
    final playlistIndex = musicQueueIndex < 0 ? 0 : musicQueueIndex;
    final previousTarget = previousPlaybackTarget(
      histories: _playbackHistories,
      current: video,
    );
    final nextTarget = nextPlaybackTarget(
      histories: _playbackHistories,
      current: video,
      queue: _playbackQueue,
      musicOnlyQueue: true,
    );
    final state = _playbackState.value;
    await SystemMediaControls.instance.attachExternal(
      video: video,
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onPlay: _playAndroidMedia3AudioFromSystem,
      onPause: _pauseAndroidMedia3AudioFromSystem,
      onSeek: AndroidMedia3AudioPlayback.instance.seek,
      onSkipToPrevious: previousTarget == null
          ? null
          : _playPreviousHistoryItemFromSystem,
      onSkipToNext: nextTarget == null ? null : _playNextItemFromSystem,
    );
  }

  Future<void> _attachNativeIosMainSystemControls(YouTubeVideo video) async {
    if (!_nativeIosMainPlayerActive || !video.isMusic) {
      return;
    }
    final musicQueue = _playbackQueue.items
        .where((item) => item.isMusic)
        .toList(growable: false);
    final musicQueueIndex = musicQueue.indexWhere(
      (item) => item.id == video.id && item.isMusic == video.isMusic,
    );
    final playlist = musicQueueIndex < 0
        ? <YouTubeVideo>[video, ...musicQueue]
        : musicQueue;
    final playlistIndex = musicQueueIndex < 0 ? 0 : musicQueueIndex;
    final previousTarget = previousPlaybackTarget(
      histories: _playbackHistories,
      current: video,
    );
    final nextTarget = nextPlaybackTarget(
      histories: _playbackHistories,
      current: video,
      queue: _playbackQueue,
      musicOnlyQueue: true,
    );
    final state = _playbackState.value;
    await SystemMediaControls.instance.attachExternal(
      video: video,
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      playlist: playlist,
      playlistIndex: playlistIndex,
      onPlay: _playNativeIosMainFromSystem,
      onPause: _pauseNativeIosMainFromSystem,
      onSeek: IosPictureInPicture.instance.seek,
      onSkipToPrevious: previousTarget == null
          ? null
          : _playPreviousHistoryItemFromSystem,
      onSkipToNext: nextTarget == null ? null : _playNextItemFromSystem,
    );
  }

  Future<void> _playNativeIosMainFromSystem() async {
    if (!_nativeIosMainPlayerActive || !_selectedVideo.isMusic) {
      return;
    }
    if (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
        _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep) {
      return;
    }
    final state = _playbackState.value;
    if (!_isLivePlayback &&
        state.duration > Duration.zero &&
        state.position >= state.duration) {
      await IosPictureInPicture.instance.seek(Duration.zero);
    }
    await _resumeSuspendedPlaybackInfrastructure();
    await IosPictureInPicture.instance.play();
  }

  Future<void> _pauseNativeIosMainFromSystem() async {
    if (!_nativeIosMainPlayerActive || !_selectedVideo.isMusic) {
      return;
    }
    await IosPictureInPicture.instance.pause();
    _handlePlaybackStateForSleep();
  }

  Future<void> _playAndroidMedia3AudioFromSystem() async {
    if (!_nativeAndroidMedia3AudioPlayerActive ||
        _sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
        _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep) {
      return;
    }
    final state = _playbackState.value;
    if (state.duration > Duration.zero && state.position >= state.duration) {
      await AndroidMedia3AudioPlayback.instance.seek(Duration.zero);
    }
    await _resumeSuspendedPlaybackInfrastructure();
    await AndroidMedia3AudioPlayback.instance.play();
  }

  Future<void> _pauseAndroidMedia3AudioFromSystem() async {
    if (!_nativeAndroidMedia3AudioPlayerActive) return;
    await AndroidMedia3AudioPlayback.instance.pause();
    _handlePlaybackStateForSleep();
  }

  bool _isPlaybackRunningForAudioSession() {
    if (_nativeAndroidMedia3PlayerActive ||
        _nativeAndroidMedia3AudioPlayerActive ||
        _nativeIosMainPlayerActive ||
        _nativeIosAudioPlayerActive) {
      return _playbackState.value.playing;
    }
    return isCrossfadePlaybackRunning(
      primaryPlaying: _player?.state.playing == true,
      incomingPlaying: _preparedNextPlayback?.player.state.playing == true,
      crossfadeActive: _crossfadeStarted,
    );
  }

  Future<void> _pauseForExternalAudioEvent() async {
    AppLog.instance.info(
      'audio.interruption.pause_requested',
      fields: _mediaLogFields(_selectedVideo),
    );
    if (_nativeAndroidMedia3PlayerActive) {
      await AndroidMedia3VideoPlayer.instance.pause();
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      await AndroidMedia3AudioPlayback.instance.pause();
    }
    if (_nativeIosMainPlayerActive) {
      _iosPictureInPictureWasPlaying = false;
      await IosPictureInPicture.instance.pause();
    }
    if (_nativeIosAudioPlayerActive) {
      await IosNativeAudioPlayback.instance.pause();
    }
    await _player?.pause();
    if (_crossfadeStarted) {
      await _preparedNextPlayback?.player.pause();
    }
    _handlePlaybackStateForSleep();
    await _applyPictureInPictureConfiguration(
      _playbackState.value.copyWith(playing: false),
    );
  }

  Future<void> _resumeAfterExternalAudioEvent() async {
    if (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
        _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep) {
      AppLog.instance.warning(
        'audio.interruption.resume_blocked',
        fields: {'sleepPhase': _sleepModel.phase.name},
      );
      return;
    }
    AppLog.instance.info(
      'audio.interruption.resume_requested',
      fields: _mediaLogFields(_selectedVideo),
    );
    if (_nativeAndroidMedia3PlayerActive) {
      await _resumeSuspendedPlaybackInfrastructure();
      await AndroidMedia3VideoPlayer.instance.play();
      return;
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      await _resumeSuspendedPlaybackInfrastructure();
      await AndroidMedia3AudioPlayback.instance.play();
      return;
    }
    if (_nativeIosMainPlayerActive) {
      _iosPictureInPictureWasPlaying = true;
      await IosPictureInPicture.instance.play();
      return;
    }
    if (_nativeIosAudioPlayerActive) {
      await _resumeSuspendedPlaybackInfrastructure();
      await IosNativeAudioPlayback.instance.play();
      return;
    }
    await _resumeSuspendedPlaybackInfrastructure();
    await _player?.play();
    if (_crossfadeStarted) {
      await _preparedNextPlayback?.player.play();
    }
  }

  Future<void> _setSystemAudioDucked(bool ducked) async {
    if (_systemAudioDucked == ducked) {
      return;
    }
    _systemAudioDucked = ducked;
    _lastAppliedPlayerVolume = null;
    _lastAppliedIncomingVolume = null;
    final state = _playbackState.value;
    final player = _player;
    if (player != null) {
      await _applyEffectivePlayerVolume(
        player,
        position: state.position,
        duration: state.duration,
        force: true,
      );
    }
    if (_nativeAndroidMedia3PlayerActive) {
      await AndroidMedia3VideoPlayer.instance.setVolume(
        _volume * _systemAudioVolumeFactor,
      );
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      await AndroidMedia3AudioPlayback.instance.setVolume(
        _volume * _systemAudioVolumeFactor,
      );
    }
    final prepared = _preparedNextPlayback;
    if (_crossfadeStarted && prepared != null) {
      final incomingFactor = playlistCrossfadeIncomingFactor(
        position: state.position,
        duration: state.duration,
      );
      final incomingVolume =
          (_volume * _systemAudioVolumeFactor * incomingFactor * 100).clamp(
            0.0,
            100.0,
          );
      _lastAppliedIncomingVolume = incomingVolume;
      await prepared.player.setVolume(incomingVolume);
    }
    await IosPictureInPicture.instance.setVolume(
      _volume * _systemAudioVolumeFactor,
    );
    await IosNativeAudioPlayback.instance.setVolume(
      _volume * _systemAudioVolumeFactor,
    );
  }

  Future<void> _beginSystemMediaTransition(
    Player player,
    YouTubeVideo nextVideo,
  ) async {
    if (PlaybackBackgroundPolicy.usesSystemMediaControls(nextVideo)) {
      await SystemMediaControls.instance.beginTransition(
        player: player,
        nextVideo: nextVideo,
      );
    } else {
      await SystemMediaControls.instance.detach(player);
    }
  }

  Future<void> _setSystemMediaSecondaryPlayer(Player? player) {
    return SystemMediaControls.instance.setSecondaryPlayer(
      _usesSystemMediaControls ? player : null,
    );
  }

  YouTubeSearchRepository? get _youtubeKeywordSearchRepository =>
      widget.youtubeSearchRepository ??
      (widget.searchSource == VideoSearchSource.youtube
          ? widget.searchRepository
          : null);

  YouTubeSearchRepository? get _musicKeywordSearchRepository =>
      widget.musicSearchRepository ??
      (widget.searchSource == VideoSearchSource.youtubeMusic
          ? widget.searchRepository
          : null);

  YouTubeMusicCatalogRepository? get _musicCatalogRepository {
    final repository = _musicKeywordSearchRepository;
    return repository is YouTubeMusicCatalogRepository
        ? repository as YouTubeMusicCatalogRepository
        : null;
  }

  YouTubeMusicDiscoveryRepository? get _musicDiscoveryRepository {
    final repository = _musicKeywordSearchRepository;
    return repository is YouTubeMusicDiscoveryRepository
        ? repository as YouTubeMusicDiscoveryRepository
        : null;
  }

  bool get _sourceSelectionEnabled =>
      _youtubeKeywordSearchRepository != null &&
      _musicKeywordSearchRepository != null &&
      _musicCatalogRepository != null;

  Map<String, Object?> _mediaLogFields(YouTubeVideo video) => {
    'mediaId': video.id,
    'mediaType': video.isAudioOnlyMusic
        ? 'audio'
        : video.isMusicVideo
        ? 'musicVideo'
        : 'video',
    'music': video.isMusic,
    'hasVideo': video.hasVideo,
    'live': video.isLive,
  };

  void _recordBufferingTransition({
    required bool wasBuffering,
    required bool buffering,
    required Duration position,
  }) {
    if (wasBuffering == buffering) {
      return;
    }
    if (buffering) {
      _bufferingStartedAt = DateTime.now();
      AppLog.instance.info(
        'player.buffering.started',
        fields: {
          ..._mediaLogFields(_selectedVideo),
          'positionMs': position.inMilliseconds,
        },
      );
      return;
    }
    final startedAt = _bufferingStartedAt;
    _bufferingStartedAt = null;
    AppLog.instance.info(
      'player.buffering.ended',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'positionMs': position.inMilliseconds,
        if (startedAt != null)
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _pullDownFullscreenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pullUpFullscreenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    WidgetsBinding.instance.addObserver(this);
    _selectedVideo = widget.video;
    _searchResults = widget.searchResultsAutoplayEligible
        ? limitSearchResults(widget.searchResults)
        : List<YouTubeVideo>.unmodifiable(widget.searchResults);
    _searchResultsAutoplayEligible = widget.searchResultsAutoplayEligible;
    if (widget.playlistQueue.isNotEmpty) {
      _resultsRepresentPlaylist = true;
    }
    _searchQuery = widget.searchQuery;
    _videoFeed =
        widget.initialVideoFeed ??
        YouTubeVideoFeed.keyword(query: widget.searchQuery);
    _searchSource = videoSearchSourceForMedia(_selectedVideo);
    final initialResultsReachedLimit =
        _searchResults.length >= searchResultLimit;
    _nextPageToken = initialResultsReachedLimit
        ? null
        : widget.initialNextPageToken;
    _resultsPageNumber = widget.initialPageNumber;
    _hasReachedResultsEnd =
        !initialResultsReachedLimit &&
        _searchResults.isNotEmpty &&
        widget.initialNextPageToken == null;
    _queryController = TextEditingController(text: widget.searchQuery);
    _ownsPlaybackService = widget.playbackService == null;
    _playbackService =
        widget.playbackService ?? YouTubeExplodePlaybackService();
    _ownsCatalogRepository = widget.catalogRepository == null;
    _catalogRepository =
        widget.catalogRepository ?? createYouTubeCatalogRepository();
    widget.manifestCache?.pausePrefetch();
    _ownsProfileController = widget.profileController == null;
    _profileController =
        widget.profileController ?? ProfileController.inMemory();
    final autoplayEnabled = _autoplayEnabled;
    _playbackQueue = widget.playlistQueue.isNotEmpty
        ? PlaybackQueue.localPlaylist(
            items: widget.playlistQueue,
            initialIndex: widget.initialPlaylistIndex,
            loops: autoplayEnabled,
          )
        : _searchResultsAutoplayEligible
        ? PlaybackQueue.searchResults(
            items: _searchResults,
            currentVideo: _selectedVideo,
          )
        : const PlaybackQueue.empty();
    _streamProxy = SegmentedStreamProxy(upstreamHeaders: _youtubeHeaders);
    _sleepModel = HybridPlaybackSleepModel();
    AppLog.instance.info(
      'player.page.opened',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'queueSource': _playbackQueue.source.name,
        'queueCount': _playbackQueue.items.length,
        'initiallyPaused': widget.initiallyPaused,
      },
    );
    SystemMediaControls.instance.setTaskRemovedHandler(
      _shutdownForAppTermination,
    );
    SystemMediaControls.instance.setPlaybackInterruptionHandlers(
      isPlaybackRunning: _isPlaybackRunningForAudioSession,
      onPauseRequested: _pauseForExternalAudioEvent,
      onResumeRequested: _resumeAfterExternalAudioEvent,
      onDuckingChanged: _setSystemAudioDucked,
      onRemoteSurfaceClosed: _handleRemoteSurfaceClosed,
    );
    unawaited(
      AndroidPictureInPicture.instance.attach(
        onTogglePlayback: _togglePlaybackFromPictureInPicture,
        onModeChanged: _handlePictureInPictureModeChanged,
        playing: false,
        videoWidth: 16,
        videoHeight: 9,
        enabled: _allowsPictureInPicture,
      ),
    );
    AndroidMedia3VideoPlayer.instance.state.addListener(
      _handleAndroidMedia3StateChanged,
    );
    unawaited(
      AndroidMedia3VideoPlayer.instance.attach(
        onCompleted: _handleAndroidMedia3Completed,
        onError: _handleAndroidMedia3Error,
      ),
    );
    unawaited(
      AndroidMedia3AudioPlayback.instance.attach(
        onStateChanged: _handleAndroidMedia3AudioStateChanged,
        onCompleted: _handleAndroidMedia3AudioCompleted,
        onAdvanced: _handleAndroidMedia3AudioAdvanced,
        onFailed: _handleAndroidMedia3AudioFailed,
      ),
    );
    unawaited(
      IosPictureInPicture.instance.attach(
        onStarted: _handleIosPictureInPictureStarted,
        onStopped: _handleIosPictureInPictureStopped,
        onFailed: _handleIosPictureInPictureFailed,
        onCompleted: _handleIosPictureInPictureCompleted,
        onAdvanced: _handleIosPictureInPictureAdvanced,
        onAudioRoutePaused: _handleIosPictureInPictureAudioRoutePaused,
        onPlaybackChanged: _handleIosPictureInPicturePlaybackChanged,
        onAutoEnterCancelled: _handleIosPictureInPictureAutoEnterCancelled,
        onMainPlayerStateChanged: _handleIosMainPlayerStateChanged,
      ),
    );
    unawaited(
      IosNativeAudioPlayback.instance.attach(
        onStateChanged: _handleIosNativeAudioStateChanged,
        onCompleted: _handleIosNativeAudioCompleted,
        onAdvanced: _handleIosNativeAudioAdvanced,
        onPreviousRequested: () =>
            unawaited(_playPreviousHistoryItemFromSystem()),
        onNextRequested: () => unawaited(_playNextItemFromSystem()),
        onAudioRoutePaused: _handleIosNativeAudioRoutePaused,
        onFailed: _handleIosNativeAudioFailed,
      ),
    );
    unawaited(_loadVideo(_selectedVideo, play: !widget.initiallyPaused));
    _restartControlsTimer();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startPlayerTutorialIfNeeded(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    AppLog.instance.info(
      'player.lifecycle.changed',
      fields: {
        'state': state.name,
        'playing': _effectivePlaybackIsPlayingForSleep,
        'sleepPhase': _sleepModel.phase.name,
      },
    );
    if (state == AppLifecycleState.detached) {
      _sleepDeadlineTimer?.cancel();
      unawaited(_shutdownForAppTermination());
    } else if (state == AppLifecycleState.resumed) {
      _cancelIosAutomaticPictureInPictureHandoff();
      _applySleepTransition(_sleepModel.enterForeground());
      _showControls();
      if (IosPictureInPicture.instance.isSupportedPlatform &&
          _iosPipDebugStartRequested &&
          !_iosPipDebugStarted &&
          _iosPipDebugTrigger == 'homeTransition') {
        _iosPipDebugDialogPending = true;
      }
      if (_iosPipDebugDialogPending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showIosPipDebugDialog());
        });
      }
      if (_appTerminationStarted) {
        unawaited(_leaveTerminatedPlayerAfterRestart());
      }
    } else if (state == AppLifecycleState.inactive) {
      if (IosPictureInPicture.instance.isSupportedPlatform &&
          !_nativeIosMainPlayerActive &&
          !_iosPictureInPicturePreparing &&
          !_iosPictureInPictureStarting &&
          !_iosPictureInPictureHandoff &&
          !_isInPictureInPictureMode &&
          PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
            pictureInPictureAllowed: _allowsPictureInPicture,
            playing: _player?.state.playing ?? false,
          )) {
        unawaited(_armIosPictureInPictureForBackground());
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_sleepModel.phase == HybridPlaybackSleepPhase.foreground) {
        _applySleepTransition(
          _sleepModel.enterBackground(
            playing: _effectivePlaybackIsPlayingForSleep,
            now: DateTime.now(),
          ),
        );
      }
    }
  }

  bool get _effectivePlaybackIsPlayingForSleep {
    if (_nativeAndroidMedia3PlayerActive ||
        _nativeAndroidMedia3AudioPlayerActive ||
        _nativeIosMainPlayerActive ||
        _nativeIosAudioPlayerActive) {
      return _playbackState.value.playing;
    }
    return isCrossfadePlaybackRunning(
      primaryPlaying: _player?.state.playing == true,
      incomingPlaying: _preparedNextPlayback?.player.state.playing == true,
      crossfadeActive: _crossfadeStarted,
    );
  }

  bool get _backgroundPlaybackStartsBlocked =>
      _lifecycleState != AppLifecycleState.resumed &&
      (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
          _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep);

  void _handlePlaybackStateForSleep() {
    if (!_sleepModel.isBackground || _appTerminationStarted) {
      return;
    }
    final playing = _effectivePlaybackIsPlayingForSleep;
    if (playing) {
      _sleepPlaybackPauseTimer?.cancel();
      _sleepPlaybackPauseTimer = null;
    } else if (_sleepModel.phase ==
        HybridPlaybackSleepPhase.backgroundPlaying) {
      _sleepPlaybackPauseTimer?.cancel();
      _sleepPlaybackPauseTimer = Timer(
        const Duration(milliseconds: 350),
        _finishDeferredBackgroundPause,
      );
      return;
    }
    _applySleepTransition(
      _sleepModel.playbackChanged(playing: playing, now: DateTime.now()),
    );
  }

  void _finishDeferredBackgroundPause() {
    _sleepPlaybackPauseTimer = null;
    if (!_sleepModel.isBackground || _appTerminationStarted) {
      return;
    }
    if (_autoAdvanceInProgress) {
      _sleepPlaybackPauseTimer = Timer(
        const Duration(milliseconds: 350),
        _finishDeferredBackgroundPause,
      );
      return;
    }
    _applySleepTransition(
      _sleepModel.playbackChanged(
        playing: _effectivePlaybackIsPlayingForSleep,
        now: DateTime.now(),
      ),
    );
  }

  Future<void> _handleRemoteSurfaceClosed() async {
    if (_lifecycleState == AppLifecycleState.resumed ||
        !_sleepModel.isBackground) {
      return;
    }
    _applySleepTransition(_sleepModel.remoteSurfaceClosed(now: DateTime.now()));
    await _sleepOperation;
  }

  void _applySleepTransition(HybridPlaybackSleepTransition transition) {
    _scheduleSleepDeadline(transition.deadline);
    if (!transition.changed) {
      return;
    }
    AppLog.instance.info(
      'player.sleep.transition',
      fields: {
        'from': transition.previous.name,
        'to': transition.current.name,
        'deadline': transition.deadline,
        'playing': _effectivePlaybackIsPlayingForSleep,
      },
    );
    switch (transition.current) {
      case HybridPlaybackSleepPhase.foreground:
        _enqueueSleepOperation(
          () => _wakeFromHybridSleep(previous: transition.previous),
        );
        break;
      case HybridPlaybackSleepPhase.backgroundPlaying:
        if (transition.previous == HybridPlaybackSleepPhase.remoteStandby) {
          _enqueueSleepOperation(_leaveRemoteStandby);
        }
        break;
      case HybridPlaybackSleepPhase.remoteStandby:
        _enqueueSleepOperation(_enterRemoteStandby);
        break;
      case HybridPlaybackSleepPhase.softSleep:
        _enqueueSleepOperation(_enterSoftSleep);
        break;
      case HybridPlaybackSleepPhase.deepSleep:
        _enqueueSleepOperation(_enterDeepSleep);
        break;
    }
  }

  void _scheduleSleepDeadline(DateTime? deadline) {
    _sleepDeadlineTimer?.cancel();
    _sleepDeadlineTimer = null;
    if (deadline == null || _appTerminationStarted) {
      return;
    }
    final delay = deadline.difference(DateTime.now());
    _sleepDeadlineTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _applySleepTransition(
        _sleepModel.evaluateDeadline(now: DateTime.now()),
      ),
    );
  }

  void _enqueueSleepOperation(Future<void> Function() operation) {
    final previous = _sleepOperation;
    _sleepOperation = () async {
      try {
        await previous;
      } on Object {
        // A failed best-effort cleanup must not block later transitions.
      }
      try {
        await operation();
      } on Object catch (error, stackTrace) {
        AppLog.instance.error(
          'player.sleep.operation_failed',
          error: error,
          stackTrace: stackTrace,
          fields: {'phase': _sleepModel.phase.name},
        );
      }
    }();
  }

  Future<void> _enterRemoteStandby() async {
    if (_sleepModel.phase != HybridPlaybackSleepPhase.remoteStandby ||
        _appTerminationStarted) {
      return;
    }
    _playbackAheadSuspended = true;
    _playlistPreparationGate.cancel();
    _preparingNextPlayback = null;
    await _disposePreparedNextPlayback();
    await IosPictureInPicture.instance.clearNext();
    await IosNativeAudioPlayback.instance.clearNext();
  }

  Future<void> _leaveRemoteStandby() async {
    if (_sleepModel.phase != HybridPlaybackSleepPhase.backgroundPlaying ||
        _appTerminationStarted) {
      return;
    }
    _playbackAheadSuspended = false;
    _prepareNextQueuePlayback(_loadGeneration);
  }

  Future<void> _enterSoftSleep() async {
    if ((_sleepModel.phase != HybridPlaybackSleepPhase.softSleep &&
            _sleepModel.phase != HybridPlaybackSleepPhase.deepSleep) ||
        _appTerminationStarted) {
      return;
    }
    if (!_softSleepResourcesApplied) {
      _softSleepResourcesApplied = true;
      _deepSleepPosition = _playbackState.value.position;
      _playbackAheadSuspended = true;
      _playlistPreparationGate.cancel();
      _preparingNextPlayback = null;
      if (_nativeIosMainPlayerActive) {
        await IosPictureInPicture.instance.pause();
      }
      if (_nativeIosAudioPlayerActive) {
        await IosNativeAudioPlayback.instance.pause();
      }
      if (_nativeAndroidMedia3PlayerActive) {
        await AndroidMedia3VideoPlayer.instance.pause();
      }
      if (_nativeAndroidMedia3AudioPlayerActive) {
        await AndroidMedia3AudioPlayback.instance.pause();
      }
      await _player?.pause();
      await _disposePreparedNextPlayback();
      await IosPictureInPicture.instance.clearNext();
      await SystemMediaControls.instance.clear();
      _systemControlsDetachedForSleep = true;
      await Future.wait<void>([
        AndroidPictureInPicture.instance.update(
          enabled: false,
          playing: false,
          videoWidth: 0,
          videoHeight: 0,
        ),
        if (!_nativeIosMainPlayerActive)
          IosPictureInPicture.instance.configure(enabled: false),
      ]);
      _iosPictureInPictureReady = false;
      _iosPictureInPictureUsesHlsMaster = false;
      _iosPictureInPicturePreparing = false;
      _iosPictureInPictureStarting = false;
      _iosPictureInPictureAutoEnterArmed = false;
      _iosPictureInPictureAutoEnterGeneration++;
      _iosPictureInPictureHandoff = false;
      _iosPictureInPictureWasPlaying = false;
    }

    if (_isLoadingVideo && !_hasCurrentPlayer) {
      _loadGeneration++;
      if (mounted) {
        setState(() => _isLoadingVideo = false);
      }
    }
  }

  Future<void> _enterDeepSleep() async {
    if (_sleepModel.phase != HybridPlaybackSleepPhase.deepSleep ||
        _deepSleepResourcesApplied ||
        _appTerminationStarted) {
      return;
    }
    await _enterSoftSleep();
    if (_sleepModel.phase != HybridPlaybackSleepPhase.deepSleep) {
      return;
    }

    _deepSleepPosition = _playbackState.value.position;
    _loadGeneration++;
    _playlistPreparationGate.cancel();
    final subscriptions = _playerSubscriptions;
    _playerSubscriptions = const [];
    final player = _player;
    _player = null;
    final hadNativeIosMainPlayer = _nativeIosMainPlayerActive;
    final hadNativeIosAudioPlayer = _nativeIosAudioPlayerActive;
    final hadNativeAndroidMedia3Player = _nativeAndroidMedia3PlayerActive;
    final hadNativeAndroidMedia3AudioPlayer =
        _nativeAndroidMedia3AudioPlayerActive;
    _nativeAndroidMedia3PlayerActive = false;
    _nativeAndroidMedia3AudioPlayerActive = false;
    _nativeIosMainPlayerActive = false;
    _nativeIosAudioPlayerActive = false;
    _preparedNativeAndroidMedia3AudioPlayback = null;
    _preparedNativeIosAudioPlayback = null;
    _loadedPlayerVideoId = null;
    _videoController = null;
    _playback = null;
    _selectedQuality = null;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player?.pause();
    await player?.dispose();
    if (hadNativeIosMainPlayer) {
      await IosPictureInPicture.instance.configure(enabled: false);
    }
    if (hadNativeIosAudioPlayer) {
      await IosNativeAudioPlayback.instance.stop();
    }
    if (hadNativeAndroidMedia3Player) {
      await AndroidMedia3VideoPlayer.instance.stop();
    }
    if (hadNativeAndroidMedia3AudioPlayer) {
      await AndroidMedia3AudioPlayback.instance.stop();
    }
    await _streamProxy.close();
    _streamProxyClosedForSleep = true;
    _deepSleepResourcesApplied = true;
    if (mounted) {
      setState(() {
        _isLoadingVideo = false;
        _isChangingQuality = false;
      });
    }
  }

  Future<void> _wakeFromHybridSleep({
    required HybridPlaybackSleepPhase previous,
  }) async {
    if (_sleepModel.phase != HybridPlaybackSleepPhase.foreground ||
        _appTerminationStarted) {
      return;
    }
    _softSleepResourcesApplied = false;
    if (_deepSleepResourcesApplied ||
        _resumeRequiresPlayerReload ||
        !_hasCurrentPlayer) {
      if (_streamProxyClosedForSleep) {
        _streamProxy = SegmentedStreamProxy(upstreamHeaders: _youtubeHeaders);
        _streamProxyClosedForSleep = false;
      }
      _deepSleepResourcesApplied = false;
      _resumeRequiresPlayerReload = false;
      _playbackAheadSuspended = true;
      await _loadVideo(
        _selectedVideo,
        initialPosition: _deepSleepPosition,
        play: false,
        prepareBackgroundFeatures: false,
        attachSystemControls: false,
      );
      return;
    }

    if (previous == HybridPlaybackSleepPhase.softSleep) {
      await _applyPictureInPictureConfiguration(
        _playbackState.value.copyWith(playing: false),
      );
    }
  }

  Future<void> _resumeSuspendedPlaybackInfrastructure() async {
    if (_nativeAndroidMedia3AudioPlayerActive) {
      if (_systemControlsDetachedForSleep) {
        await _attachAndroidMedia3AudioSystemControls(_selectedVideo);
        _systemControlsDetachedForSleep = false;
      }
      if (_playbackAheadSuspended) {
        _playbackAheadSuspended = false;
        _prepareNextQueuePlayback(_loadGeneration);
      }
      return;
    }
    if (_nativeAndroidMedia3PlayerActive) {
      _playbackAheadSuspended = false;
      return;
    }
    if (_nativeIosMainPlayerActive) {
      if (_systemControlsDetachedForSleep && _selectedVideo.isMusic) {
        await _attachNativeIosMainSystemControls(_selectedVideo);
        _systemControlsDetachedForSleep = false;
      }
      _playbackAheadSuspended = false;
      return;
    }
    if (_nativeIosAudioPlayerActive) {
      if (_playbackAheadSuspended) {
        _playbackAheadSuspended = false;
        _prepareNextQueuePlayback(_loadGeneration);
      }
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    if (_systemControlsDetachedForSleep) {
      await _attachSystemMediaControls(player, _selectedVideo);
      _systemControlsDetachedForSleep = false;
    }
    if (!_playbackAheadSuspended) {
      return;
    }
    _playbackAheadSuspended = false;
    _prepareNextQueuePlayback(_loadGeneration);
    if (_allowsPictureInPicture &&
        IosPictureInPicture.instance.isSupportedPlatform) {
      unawaited(_ensureIosPictureInPictureReady());
    }
  }

  Future<void> _togglePlaybackFromPictureInPicture() async {
    await _togglePlayback(_playbackState.value);
  }

  void _handlePictureInPictureModeChanged(bool active, bool restoredToApp) {
    if (!mounted) {
      return;
    }
    AppLog.instance.info(
      'pip.android.mode_changed',
      fields: {'active': active, 'restoredToApp': restoredToApp},
    );
    setState(() {
      _isInPictureInPictureMode = active;
      if (active) {
        _controlsVisible = false;
        _settingsVisible = false;
      }
    });
    if (active) {
      _hideControlsTimer?.cancel();
    } else if (PlaybackBackgroundPolicy.shouldPauseWhenPictureInPictureCloses(
      appIsResumed: _lifecycleState == AppLifecycleState.resumed,
      restoredToApp: restoredToApp,
    )) {
      unawaited(_pauseAfterPictureInPictureClosed());
    } else if (restoredToApp || _lifecycleState == AppLifecycleState.resumed) {
      _showControls();
    }
  }

  Future<void> _pauseAfterPictureInPictureClosed() async {
    if (!mounted || _lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    if (_nativeIosMainPlayerActive) {
      await IosPictureInPicture.instance.pause();
      await _handleRemoteSurfaceClosed();
      return;
    }
    if (_nativeAndroidMedia3PlayerActive) {
      await AndroidMedia3VideoPlayer.instance.pause();
      _handlePlaybackStateForSleep();
      await _handleRemoteSurfaceClosed();
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    await player.pause();
    if (_crossfadeStarted) {
      await _preparedNextPlayback?.player.pause();
    }
    _handlePlaybackStateForSleep();
    await _handleRemoteSurfaceClosed();
  }

  void _syncPictureInPictureConfiguration() {
    final state = _playbackState.value;
    unawaited(_applyPictureInPictureConfiguration(state));
  }

  Future<void> _applyPictureInPictureConfiguration(
    _PlaybackViewState state,
  ) async {
    final iosAutoEnterEnabled =
        PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
          pictureInPictureAllowed: _allowsPictureInPicture,
          playing: state.playing,
        );
    final androidPlaybackRequested = _nativeAndroidMedia3PlayerActive
        ? AndroidMedia3VideoPlayer.instance.state.value.playbackRequested
        : state.playing;
    final androidAutoEnterEnabled =
        PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
          pictureInPictureAllowed: _allowsPictureInPicture,
          playing: androidPlaybackRequested,
        );
    await Future.wait<void>([
      AndroidPictureInPicture.instance.update(
        enabled: _allowsPictureInPicture,
        playing: state.playing,
        videoWidth: state.width,
        videoHeight: state.height,
        autoEnterEnabled: androidAutoEnterEnabled,
      ),
      IosPictureInPicture.instance.setAutoEnterEnabled(iosAutoEnterEnabled),
    ]);
  }

  void _requestPictureInPictureFromButton() {
    unawaited(_enterPictureInPicture(debugTrigger: 'manualButton'));
  }

  Future<void> _armIosPictureInPictureForBackground() async {
    if (!_allowsPictureInPicture ||
        !IosPictureInPicture.instance.isSupportedPlatform ||
        _iosPictureInPicturePreparing ||
        _iosPictureInPictureStarting ||
        _iosPictureInPictureHandoff ||
        _isInPictureInPictureMode) {
      return;
    }
    final player = _player;
    if (player == null || !player.state.playing) {
      return;
    }

    final generation = ++_iosPictureInPictureAutoEnterGeneration;
    _iosPipDebugBeginFuture = _beginIosPipDebugAttempt('homeTransition');
    unawaited(_iosPipDebugBeginFuture);
    if (!_iosPictureInPictureReady) {
      _iosPictureInPicturePreparing = true;
      final ready = await _ensureIosPictureInPictureReady();
      _iosPictureInPicturePreparing = false;
      if (!ready ||
          !mounted ||
          generation != _iosPictureInPictureAutoEnterGeneration) {
        return;
      }
    }

    final viewState = _playbackState.value;
    if (!viewState.playing) {
      return;
    }
    _iosPictureInPictureStarting = true;
    _iosPictureInPictureWasPlaying = true;
    _iosPipDebugStartRequested = true;
    _iosPipDebugStartCallCount++;
    final armed = await IosPictureInPicture.instance.armAutoEnter(
      position: viewState.position,
      playing: true,
      seekToPosition: !_isLivePlayback,
    );
    if (!mounted) {
      return;
    }
    if (generation != _iosPictureInPictureAutoEnterGeneration) {
      await IosPictureInPicture.instance.cancelAutoEnter();
      return;
    }
    _iosPictureInPictureAutoEnterArmed =
        armed && !_iosPictureInPictureHandoff && !_isInPictureInPictureMode;
    if (!armed) {
      _iosPictureInPictureStarting = false;
    }
    await _captureIosPipDebugSnapshot('afterStartRequest');
  }

  void _cancelIosAutomaticPictureInPictureHandoff() {
    _iosPictureInPictureAutoEnterGeneration++;
    if (_iosPictureInPictureHandoff || _isInPictureInPictureMode) {
      _iosPictureInPictureAutoEnterArmed = false;
      return;
    }
    _iosPictureInPictureAutoEnterArmed = false;
    _iosPictureInPictureStarting = false;
    unawaited(IosPictureInPicture.instance.cancelAutoEnter());
  }

  Future<void> _enterPictureInPicture({
    String debugTrigger = 'manualButton',
  }) async {
    if (!_allowsPictureInPicture) {
      return;
    }
    if (AndroidPictureInPicture.instance.isSupportedPlatform) {
      await AndroidPictureInPicture.instance.enter();
      return;
    }
    if (_nativeIosMainPlayerActive) {
      if (_iosPictureInPictureStarting || _isInPictureInPictureMode) {
        return;
      }
      _iosPictureInPictureStarting = true;
      _iosPictureInPictureWasPlaying = _playbackState.value.playing;
      final accepted = await IosPictureInPicture.instance.start(
        position: _playbackState.value.position,
        playing: _playbackState.value.playing,
        seekToPosition: false,
        notifyFailure: false,
        readinessTimeout: const Duration(seconds: 5),
      );
      if (!mounted) {
        return;
      }
      _iosPictureInPictureStarting = false;
      if (!accepted) {
        _handleIosPictureInPictureFailed(context.l10n.pipNativeStreamNotReady);
      }
      return;
    }
    if (!IosPictureInPicture.instance.isSupportedPlatform ||
        _iosPictureInPicturePreparing ||
        _iosPictureInPictureStarting ||
        _isInPictureInPictureMode) {
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }

    _iosPipDebugBeginFuture = _beginIosPipDebugAttempt(debugTrigger);
    unawaited(_iosPipDebugBeginFuture);

    if (!_iosPictureInPictureReady) {
      _iosPictureInPicturePreparing = true;
      final ready = await _ensureIosPictureInPictureReady();
      _iosPictureInPicturePreparing = false;
      if (!ready || !mounted) {
        return;
      }
    }

    if (_crossfadeStarted) {
      await _resetActiveCrossfade(rewindIncoming: true);
    }
    _iosPictureInPictureStarting = true;
    final viewState = _playbackState.value;
    _iosPictureInPictureWasPlaying = viewState.playing;
    _iosPipDebugStartRequested = true;
    _iosPipDebugStartCallCount++;
    final hlsPrimary = _iosPictureInPictureUsesHlsMaster;
    var accepted = await IosPictureInPicture.instance.start(
      position: viewState.position,
      playing: viewState.playing,
      seekToPosition: !_isLivePlayback,
      debugRequestId: _iosPipDebugRequestId,
      notifyFailure: false,
      readinessTimeout: hlsPrimary
          ? const Duration(seconds: 5)
          : const Duration(seconds: 15),
    );
    final playbackForFallback = _playback;
    if (!accepted && hlsPrimary && mounted && playbackForFallback != null) {
      try {
        final fallback = await _resolveProgressivePictureInPictureFallback(
          playbackForFallback,
        );
        if (fallback != null && mounted) {
          await _prepareIosPictureInPicture(
            playback: fallback.playback,
            selectedQuality: fallback.quality,
            generation: _loadGeneration,
          );
          if (mounted && _iosPictureInPictureReady) {
            _iosPipDebugStartCallCount++;
            accepted = await IosPictureInPicture.instance.start(
              position: viewState.position,
              playing: viewState.playing,
              seekToPosition: !fallback.playback.isLive,
              debugRequestId: _iosPipDebugRequestId,
              notifyFailure: false,
            );
          }
        }
      } on Exception {
        accepted = false;
      }
    }
    await _captureIosPipDebugSnapshot('afterStartRequest');
    _iosPipDebugSnapshotTimer?.cancel();
    final snapshotRequestId = _iosPipDebugRequestId;
    _iosPipDebugSnapshotTimer = Timer(const Duration(milliseconds: 750), () {
      if (snapshotRequestId == _iosPipDebugRequestId &&
          !_iosPipDebugSnapshots.containsKey('after750msOrDelegate')) {
        unawaited(_captureIosPipDebugSnapshot('after750msOrDelegate'));
      }
    });
    if (!mounted) {
      return;
    }
    _iosPictureInPictureStarting = false;
    if (!accepted) {
      _handleIosPictureInPictureFailed(
        hlsPrimary
            ? context.l10n.pipHlsAndFallbackFailed
            : context.l10n.pipNativeStreamNotReady,
      );
      return;
    }

    await _completeIosPictureInPictureHandoff();
  }

  Future<void> _completeIosPictureInPictureHandoff() async {
    final currentOperation = _iosPictureInPictureHandoffOperation;
    if (currentOperation != null) {
      await currentOperation;
      return;
    }
    if (_iosPictureInPictureHandoff) {
      return;
    }

    _iosPictureInPictureHandoff = true;
    _iosPictureInPictureStarting = false;
    _iosPictureInPictureAutoEnterArmed = false;
    _iosPictureInPictureAutoEnterGeneration++;
    final player = _player;
    final operation = () async {
      if (player != null) {
        await SystemMediaControls.instance.detach(
          player,
          keepAudioSessionActive: true,
        );
        await player.pause();
      }
      if (!mounted || !_iosPictureInPictureHandoff) {
        return;
      }
      setState(() {
        _isInPictureInPictureMode = true;
        _controlsVisible = false;
        _settingsVisible = false;
      });
      final prepared = _preparedNextPlayback;
      if (prepared != null) {
        unawaited(
          _prepareIosNextPictureInPicture(
            prepared: prepared,
            generation: _loadGeneration,
          ),
        );
      }
    }();
    _iosPictureInPictureHandoffOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_iosPictureInPictureHandoffOperation, operation)) {
        _iosPictureInPictureHandoffOperation = null;
      }
    }
  }

  Future<void> _beginIosPipDebugAttempt(String trigger) {
    _iosPipDebugSnapshotTimer?.cancel();
    _iosPipDebugRequestId++;
    _iosPipDebugTrigger = trigger;
    if (trigger == 'homeTransition') {
      _iosPipDebugManualTapCount = 0;
    }
    _iosPipDebugStopwatch = Stopwatch()..start();
    _iosPipDebugSnapshots.clear();
    _iosPipDebugStartCallCount = 0;
    _iosPipDebugStartRequested = false;
    _iosPipDebugStarted = false;
    _iosPipDebugDialogPending = false;
    final configured = _captureIosPipDebugSnapshot('configured');
    final triggerSnapshot = _captureIosPipDebugSnapshot('trigger');
    return Future.wait<void>([configured, triggerSnapshot]);
  }

  Future<void> _captureIosPipDebugSnapshot(String checkpoint) async {
    if (!IosPictureInPicture.instance.isSupportedPlatform) {
      return;
    }
    final requestId = _iosPipDebugRequestId;
    final native = await IosPictureInPicture.instance.readDebugState(
      requestId: requestId,
      checkpoint: checkpoint,
      trigger: _iosPipDebugTrigger,
    );
    if (!mounted || requestId != _iosPipDebugRequestId) {
      return;
    }
    final viewState = _playbackState.value;
    final nativeRate = native['rate'];
    final nativePlayerPlaying =
        native['nativePlaybackActive'] == true &&
        (native['timeControlStatus'] == 'playing' ||
            (nativeRate is num && nativeRate > 0));
    final mainPlayerPlaying = viewState.playing;
    final playbackOwner = switch ((mainPlayerPlaying, nativePlayerPlaying)) {
      (true, true) => 'both',
      (true, false) => 'main',
      (false, true) => 'native',
      _ => 'none',
    };
    final presentationWidth = native['presentationWidth'];
    final presentationHeight = native['presentationHeight'];
    final nativeMediaReady =
        native['itemStatus'] == 'readyToPlay' &&
        presentationWidth is num &&
        presentationWidth > 0 &&
        presentationHeight is num &&
        presentationHeight > 0 &&
        native['layerReady'] == true;
    final pipStartable =
        native['pipSupported'] == true &&
        native['controllerExists'] == true &&
        native['pipPossible'] == true;
    final pipActive = native['pipActive'] == true;
    final delegateEvent = native['lastDelegateEvent']?.toString() ?? 'none';
    final delegateRequestId = native['lastDelegateRequestId'];
    final requestConsistent =
        delegateEvent == 'none' ||
        (delegateRequestId is num && delegateRequestId.toInt() == requestId);
    final snapshot = <String, Object?>{
      'elapsedMs': _iosPipDebugStopwatch?.elapsedMilliseconds ?? 0,
      ...native,
      'flutterLifecycle': _lifecycleState.name,
      'flutterVideoId': _selectedVideo.id,
      'flutterIsLive': _selectedVideo.isLive,
      'flutterIsMusic': _selectedVideo.isMusic,
      'flutterIsMusicVideo': _selectedVideo.isMusicVideo,
      'flutterMainPlaying': mainPlayerPlaying,
      'flutterMainBuffering': viewState.buffering,
      'flutterMainPositionMs': viewState.position.inMilliseconds,
      'flutterMainDurationMs': viewState.duration.inMilliseconds,
      'flutterMainWidth': viewState.width,
      'flutterMainHeight': viewState.height,
      'flutterPipReady': _iosPictureInPictureReady,
      'flutterPipPreparing': _iosPictureInPicturePreparing,
      'flutterPipStarting': _iosPictureInPictureStarting,
      'flutterPipAutoEnterArmed': _iosPictureInPictureAutoEnterArmed,
      'flutterPipHandoff': _iosPictureInPictureHandoff,
      'flutterPipUsesHlsMaster': _iosPictureInPictureUsesHlsMaster,
      'flutterPipMode': _isInPictureInPictureMode,
      'flutterPipWasPlaying': _iosPictureInPictureWasPlaying,
      'flutterAutoPipPolicy':
          PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
            pictureInPictureAllowed: _allowsPictureInPicture,
            playing: viewState.playing,
          ),
      'flutterManualTapCount': _iosPipDebugManualTapCount,
      'flutterStartCallCount': _iosPipDebugStartCallCount,
      'flutterStartRequested': _iosPipDebugStartRequested,
      'flutterCrossfadeActive': _crossfadeStarted,
      'flutterPreparedSecondPlayer': _preparedNextPlayback != null,
      'flutterProxyLastError': _sanitizedIosPipProxyError(),
      'nativeMediaReady': nativeMediaReady,
      'pipStartable': pipStartable,
      'mainPlayerPlaying': mainPlayerPlaying,
      'nativePlayerPlaying': nativePlayerPlaying,
      'playbackOwner': playbackOwner,
      'handoffConsistent': pipActive
          ? playbackOwner == 'native'
          : playbackOwner != 'native',
      'requestConsistent': requestConsistent,
    };
    if (!_iosPipDebugSnapshots.containsKey(checkpoint) &&
        _iosPipDebugSnapshots.length >= 5) {
      _iosPipDebugSnapshots.remove(_iosPipDebugSnapshots.keys.first);
    }
    _iosPipDebugSnapshots[checkpoint] = snapshot;
  }

  String _sanitizedIosPipProxyError() {
    final raw = _streamProxy.lastErrorDetails;
    if (raw == null || raw.isEmpty) {
      return '';
    }
    final sanitized = raw.replaceAll(RegExp(r'https?://\S+'), '[URL]');
    return sanitized.length <= 240 ? sanitized : sanitized.substring(0, 240);
  }

  Future<void> _showIosPipDebugDialog() async {
    if (!mounted || !IosPictureInPicture.instance.isSupportedPlatform) {
      return;
    }
    if (_lifecycleState != AppLifecycleState.resumed) {
      _iosPipDebugDialogPending = true;
      return;
    }
    if (_iosPipDebugDialogVisible) {
      return;
    }
    await _captureIosPipDebugSnapshot('final');
    if (!mounted) {
      return;
    }
    _iosPipDebugDialogPending = false;
    _iosPipDebugDialogVisible = true;
    final report = _buildIosPipDebugReport();
    final german = Localizations.localeOf(context).languageCode == 'de';
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(german ? 'iOS-PiP-Debugwerte' : 'iOS PiP debug state'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: SelectionArea(
                child: Text(
                  report,
                  key: const Key('ios-pip-debug-report'),
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              key: const Key('ios-pip-debug-copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        german
                            ? 'PiP-Debugwerte kopiert.'
                            : 'PiP debug state copied.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: Text(german ? 'Kopieren' : 'Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(german ? 'Schließen' : 'Close'),
            ),
          ],
        ),
      );
    } finally {
      _iosPipDebugDialogVisible = false;
    }
  }

  String _buildIosPipDebugReport() {
    const slots = <String>[
      'configured',
      'trigger',
      'afterStartRequest',
      'after750msOrDelegate',
      'final',
    ];
    const coreKeys = <String>[
      'applicationState',
      'sceneState',
      'itemStatus',
      'timeControlStatus',
      'layerReady',
      'presentationWidth',
      'presentationHeight',
      'pipPossible',
      'pipActive',
      'playerPrewarmed',
      'automaticStartArmed',
      'layerAttachedToFlutterHostView',
      'inlineSourceRectReady',
      'lastDelegateEvent',
      'lastDelegateRequestId',
      'flutterLifecycle',
      'flutterMainPlaying',
      'flutterMainBuffering',
      'flutterPipReady',
      'flutterPipStarting',
      'flutterPipHandoff',
      'flutterPipUsesHlsMaster',
      'playbackOwner',
      'nativeMediaReady',
      'pipStartable',
      'handoffConsistent',
      'requestConsistent',
    ];
    final buffer = StringBuffer()
      ..writeln('MyTube iOS PiP diagnostics')
      ..writeln('requestId: $_iosPipDebugRequestId')
      ..writeln('trigger: $_iosPipDebugTrigger')
      ..writeln('manualTapCount: $_iosPipDebugManualTapCount')
      ..writeln('startCallCount: $_iosPipDebugStartCallCount')
      ..writeln('snapshotCount: ${_iosPipDebugSnapshots.length}');
    for (final slot in slots) {
      final values = _iosPipDebugSnapshots[slot];
      if (values == null) {
        continue;
      }
      buffer
        ..writeln()
        ..writeln('[$slot +${values['elapsedMs'] ?? 0}ms]');
      for (final key in coreKeys) {
        buffer.writeln('$key: ${_iosPipDebugValue(values[key])}');
      }
    }
    if (_iosPipDebugSnapshots.isNotEmpty) {
      final latestSlot = slots.lastWhere(
        _iosPipDebugSnapshots.containsKey,
        orElse: () => _iosPipDebugSnapshots.keys.last,
      );
      final latest = _iosPipDebugSnapshots[latestSlot]!;
      final keys = latest.keys.toList()..sort();
      buffer
        ..writeln()
        ..writeln('[$latestSlot – vollständige IST-Werte]');
      for (final key in keys) {
        if (key != 'elapsedMs') {
          buffer.writeln('$key: ${_iosPipDebugValue(latest[key])}');
        }
      }
    }
    return buffer.toString().trimRight();
  }

  String _iosPipDebugValue(Object? value) {
    if (value == null || value == '') {
      return '–';
    }
    return value.toString().replaceAll('\n', ' ');
  }

  void _handleIosPictureInPictureStarted() {
    if (!mounted) {
      return;
    }
    AppLog.instance.info(
      'pip.ios.started',
      fields: _mediaLogFields(_selectedVideo),
    );
    _iosPipDebugStarted = true;
    if (!_iosPipDebugSnapshots.containsKey('after750msOrDelegate')) {
      unawaited(_captureIosPipDebugSnapshot('after750msOrDelegate'));
    }
    if (_nativeIosMainPlayerActive) {
      setState(() {
        _isInPictureInPictureMode = true;
        _controlsVisible = false;
        _settingsVisible = false;
      });
    } else {
      unawaited(_completeIosPictureInPictureHandoff());
    }
    _handlePlaybackStateForSleep();
  }

  void _handleAndroidMedia3StateChanged() {
    if (!mounted || !_nativeAndroidMedia3PlayerActive) {
      return;
    }
    final media3State = AndroidMedia3VideoPlayer.instance.state.value;
    final previous = _playbackState.value;
    final playbackRequestChanged =
        _lastAndroidMedia3PlaybackRequested != media3State.playbackRequested;
    _lastAndroidMedia3PlaybackRequested = media3State.playbackRequested;
    _recordBufferingTransition(
      wasBuffering: previous.buffering,
      buffering: media3State.buffering,
      position: media3State.position,
    );
    _playbackState.value = previous.copyWith(
      position: media3State.position,
      duration: media3State.duration,
      playing: media3State.playing,
      buffering: media3State.buffering,
      width: media3State.width,
      height: media3State.height,
    );
    if (previous.playing != media3State.playing ||
        playbackRequestChanged ||
        previous.width != media3State.width ||
        previous.height != media3State.height) {
      _syncPictureInPictureConfiguration();
    }
    _handlePlaybackStateForSleep();
  }

  void _handleAndroidMedia3Completed() {
    if (!mounted || !_nativeAndroidMedia3PlayerActive) {
      return;
    }
    unawaited(_playNextQueueItem(_loadGeneration));
  }

  void _handleAndroidMedia3Error(AndroidMedia3VideoException error) {
    if (!mounted ||
        !_nativeAndroidMedia3PlayerActive ||
        _isLoadingVideo ||
        _isChangingQuality) {
      return;
    }
    AppLog.instance.error(
      'player.android_media3.failed',
      error: error.message,
      fields: {..._mediaLogFields(_selectedVideo), 'details': error.details},
    );
    _setPlayerError(
      context.l10n.videoPlaybackFailed,
      _loadGeneration,
      details: error.toString(),
    );
  }

  void _handleAndroidMedia3AudioStateChanged(
    AndroidMedia3AudioPlaybackState state,
  ) {
    if (!mounted || !_nativeAndroidMedia3AudioPlayerActive) return;
    final previous = _playbackState.value;
    _recordBufferingTransition(
      wasBuffering: previous.buffering,
      buffering: state.buffering,
      position: state.position,
    );
    _playbackState.value = previous.copyWith(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      width: 0,
      height: 0,
    );
    unawaited(
      SystemMediaControls.instance.updateExternalState(
        position: state.position,
        duration: state.duration,
        playing: state.playing,
        buffering: state.buffering,
      ),
    );
    _handlePlaybackStateForSleep();
  }

  void _handleAndroidMedia3AudioCompleted() {
    if (!mounted || !_nativeAndroidMedia3AudioPlayerActive) return;
    AppLog.instance.info(
      'player.completed',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'backend': 'androidMedia3ExoPlayerAudio',
      },
    );
    if (_autoplayEnabled && !_backgroundPlaybackStartsBlocked) {
      unawaited(_playNextQueueItem(_loadGeneration));
    }
  }

  void _handleAndroidMedia3AudioAdvanced() {
    if (!mounted ||
        !_nativeAndroidMedia3AudioPlayerActive ||
        !_autoplayEnabled ||
        _backgroundPlaybackStartsBlocked) {
      return;
    }
    final prepared = _preparedNativeAndroidMedia3AudioPlayback;
    final target = _automaticNextTarget;
    if (prepared == null || !prepared.target.matches(target)) {
      AppLog.instance.warning(
        'crossfade.android_media3.advance_without_prepared_target',
      );
      return;
    }
    AppLog.instance.info(
      'crossfade.android_media3.completed',
      fields: {
        'fromMediaId': _selectedVideo.id,
        'toMediaId': prepared.video.id,
      },
    );
    _preparedNativeAndroidMedia3AudioPlayback = null;
    _applyNavigationTarget(prepared.target);
    setState(() {
      _synchronizeSearchModeWithMedia(prepared.video);
      _selectedVideo = prepared.video;
      _loadedPlayerVideoId = prepared.video.id;
      _visitPlaybackHistory(prepared.video);
      _playback = prepared.playback;
      _selectedQuality = prepared.selectedQuality;
      _playerError = null;
      _playerErrorDetails = null;
      _isLoadingVideo = false;
      _isChangingQuality = false;
    });
    _reshuffleQueueForNextCycleIfNeeded();
    unawaited(_attachAndroidMedia3AudioSystemControls(prepared.video));
    _prepareNextQueuePlayback(_loadGeneration);
  }

  void _handleAndroidMedia3AudioFailed(String message) {
    if (!mounted ||
        !_nativeAndroidMedia3AudioPlayerActive ||
        _isLoadingVideo ||
        _isChangingQuality) {
      return;
    }
    AppLog.instance.error(
      'player.android_media3_audio.failed',
      error: message,
      fields: _mediaLogFields(_selectedVideo),
    );
    setState(() {
      _playerError = context.l10n.videoPlaybackFailed;
      _playerErrorDetails = 'Media3 ExoPlayer (Audio): $message';
      _isLoadingVideo = false;
    });
  }

  void _handleIosMainPlayerStateChanged(IosMainPlayerState state) {
    if (!mounted || !_nativeIosMainPlayerActive) {
      return;
    }
    final previous = _playbackState.value;
    _recordBufferingTransition(
      wasBuffering: previous.buffering,
      buffering: state.buffering,
      position: state.position,
    );
    _playbackState.value = previous.copyWith(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      width: state.width,
      height: state.height,
    );
    _iosPictureInPictureWasPlaying = state.playing;
    if (_selectedVideo.isMusic) {
      unawaited(
        SystemMediaControls.instance.updateExternalState(
          position: state.position,
          duration: state.duration,
          playing: state.playing,
          buffering: state.buffering,
        ),
      );
    }
    if (previous.playing != state.playing) {
      _syncPictureInPictureConfiguration();
    }
    _handlePlaybackStateForSleep();
  }

  void _handleIosNativeAudioStateChanged(IosNativeAudioPlaybackState state) {
    if (!mounted || !_nativeIosAudioPlayerActive) {
      return;
    }
    final previous = _playbackState.value;
    _recordBufferingTransition(
      wasBuffering: previous.buffering,
      buffering: state.buffering,
      position: state.position,
    );
    _playbackState.value = previous.copyWith(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      width: 0,
      height: 0,
    );
    _handlePlaybackStateForSleep();
  }

  void _handleIosNativeAudioCompleted() {
    if (!mounted || !_nativeIosAudioPlayerActive) {
      return;
    }
    AppLog.instance.info(
      'player.completed',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'backend': 'iosAvPlayerAudio',
      },
    );
    if (_autoplayEnabled && !_backgroundPlaybackStartsBlocked) {
      unawaited(_playNextQueueItem(_loadGeneration));
    }
  }

  void _handleIosNativeAudioAdvanced() {
    if (!mounted ||
        !_nativeIosAudioPlayerActive ||
        !_autoplayEnabled ||
        _backgroundPlaybackStartsBlocked) {
      return;
    }
    final prepared = _preparedNativeIosAudioPlayback;
    final target = _automaticNextTarget;
    if (prepared == null || !prepared.target.matches(target)) {
      AppLog.instance.warning('crossfade.ios.advance_without_prepared_target');
      return;
    }
    AppLog.instance.info(
      'crossfade.ios.completed',
      fields: {
        'fromMediaId': _selectedVideo.id,
        'toMediaId': prepared.video.id,
      },
    );
    _preparedNativeIosAudioPlayback = null;
    _applyNavigationTarget(prepared.target);
    setState(() {
      _synchronizeSearchModeWithMedia(prepared.video);
      _selectedVideo = prepared.video;
      _loadedPlayerVideoId = prepared.video.id;
      _visitPlaybackHistory(prepared.video);
      _playback = prepared.playback;
      _selectedQuality = prepared.selectedQuality;
      _playerError = null;
      _playerErrorDetails = null;
      _isLoadingVideo = false;
      _isChangingQuality = false;
    });
    _reshuffleQueueForNextCycleIfNeeded();
    unawaited(_updateIosNativeAudioNavigation());
    _prepareNextQueuePlayback(_loadGeneration);
  }

  void _handleIosNativeAudioRoutePaused() {
    if (!_nativeIosAudioPlayerActive) {
      return;
    }
    AppLog.instance.warning(
      'audio.route.disconnected',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'backend': 'iosAvPlayerAudio',
      },
    );
    _handlePlaybackStateForSleep();
  }

  void _handleIosNativeAudioFailed(String message) {
    if (!mounted || !_nativeIosAudioPlayerActive) {
      return;
    }
    AppLog.instance.error(
      'player.ios_audio.failed',
      error: message,
      fields: _mediaLogFields(_selectedVideo),
    );
    setState(() {
      _playerError = context.l10n.videoPlaybackFailed;
      _playerErrorDetails = 'AVPlayer: $message';
      _isLoadingVideo = false;
    });
  }

  Future<void> _updateIosNativeAudioNavigation() {
    if (!_nativeIosAudioPlayerActive) {
      return Future<void>.value();
    }
    return IosNativeAudioPlayback.instance.updateNavigation(
      hasPrevious: _previousPlayedMedia != null,
      hasNext: _nextPlayerControlTarget != null,
    );
  }

  void _handleIosPictureInPictureAudioRoutePaused() {
    AppLog.instance.warning(
      'audio.route.disconnected',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'backend': 'iosAvPlayerVideo',
      },
    );
    _iosPictureInPictureWasPlaying = false;
    unawaited(_pauseForExternalAudioEvent());
    _handlePlaybackStateForSleep();
  }

  void _handleIosPictureInPicturePlaybackChanged(bool playing) {
    _iosPictureInPictureWasPlaying = playing;
    _handlePlaybackStateForSleep();
  }

  void _handleIosPictureInPictureAutoEnterCancelled() {
    if (!mounted || _iosPictureInPictureHandoff || _isInPictureInPictureMode) {
      return;
    }
    AppLog.instance.warning('pip.ios.auto_enter_cancelled');
    _iosPictureInPictureAutoEnterGeneration++;
    _iosPictureInPictureAutoEnterArmed = false;
    _iosPictureInPictureStarting = false;
    _iosPipDebugDialogPending = true;
    _handlePlaybackStateForSleep();
  }

  void _handleIosPictureInPictureStopped(
    Duration position,
    bool shouldResume,
    bool restoredUserInterface,
  ) {
    if (!mounted) {
      return;
    }
    AppLog.instance.info(
      'pip.ios.stopped',
      fields: {
        'positionMs': position.inMilliseconds,
        'shouldResume': shouldResume,
        'restoredUi': restoredUserInterface,
      },
    );
    if (_nativeIosMainPlayerActive) {
      _iosPictureInPictureStarting = false;
      _iosPictureInPictureAutoEnterArmed = false;
      setState(() => _isInPictureInPictureMode = false);
      final surfaceClosedInBackground =
          !restoredUserInterface &&
          _lifecycleState != AppLifecycleState.resumed;
      if (surfaceClosedInBackground) {
        unawaited(_handleRemoteSurfaceClosed());
      } else {
        _showControls();
      }
      return;
    }
    final player = _player;
    _iosPictureInPictureAutoEnterGeneration++;
    _iosPictureInPictureAutoEnterArmed = false;
    _iosPictureInPictureHandoff = false;
    _iosPictureInPictureStarting = false;
    _iosPictureInPictureReady = false;
    _iosPictureInPictureUsesHlsMaster = false;
    setState(() => _isInPictureInPictureMode = false);
    final surfaceClosedInBackground =
        !restoredUserInterface && _lifecycleState != AppLifecycleState.resumed;
    unawaited(() async {
      // Remove the native AVPlayerLayer before the normal MediaKit surface is
      // restored. Otherwise both surfaces can remain visible after PiP closes.
      await IosPictureInPicture.instance.configure(enabled: false);
      if (!mounted) {
        return;
      }
      if (player == null) {
        if (surfaceClosedInBackground) {
          await _handleRemoteSurfaceClosed();
        }
        return;
      }
      if (_loadedPlayerVideoId != _selectedVideo.id) {
        if (surfaceClosedInBackground) {
          _deepSleepPosition = position;
          _resumeRequiresPlayerReload = true;
          _playbackState.value = _playbackState.value.copyWith(
            position: position,
            playing: false,
          );
          await _handleRemoteSurfaceClosed();
          return;
        }
        await _loadVideo(
          _selectedVideo,
          initialPosition: position,
          play: shouldResume,
        );
        return;
      }
      if (PlaybackSeekPolicy.canSeek(isLive: _isLivePlayback)) {
        await player.seek(position);
      }
      if (shouldResume) {
        await player.play();
      } else {
        await player.pause();
      }
      if (surfaceClosedInBackground) {
        await _handleRemoteSurfaceClosed();
      } else {
        await _attachSystemMediaControls(player, _selectedVideo);
      }
      if (mounted && _lifecycleState == AppLifecycleState.resumed) {
        _showControls();
      }
    }());
  }

  void _handleIosPictureInPictureCompleted() {
    if (_nativeIosMainPlayerActive) {
      if (_autoplayEnabled && !_backgroundPlaybackStartsBlocked) {
        unawaited(_playNextQueueItem(_loadGeneration));
      }
      return;
    }
    if (_autoplayEnabled && !_backgroundPlaybackStartsBlocked) {
      unawaited(_playNextIosPictureInPictureItem());
    }
  }

  void _handleIosPictureInPictureAdvanced() {
    if (_autoplayEnabled && !_backgroundPlaybackStartsBlocked) {
      unawaited(_advanceIosPictureInPictureQueue());
    }
  }

  Future<void> _advanceIosPictureInPictureQueue() async {
    if (!mounted || !_autoplayEnabled || !_iosPictureInPictureHandoff) {
      return;
    }
    final target = _automaticNextTarget;
    if (target == null) {
      return;
    }
    final nextVideo = target.video;
    _applyNavigationTarget(target);
    setState(() {
      _synchronizeSearchModeWithMedia(nextVideo);
      _selectedVideo = nextVideo;
      _visitPlaybackHistory(nextVideo);
    });

    final prepared = _preparedNextPlayback;
    if (prepared != null && prepared.target.matches(target)) {
      setState(() => _preparedNextPlayback = null);
      _cancelPreparedMediaKitPlayer(prepared.player);
      await WidgetsBinding.instance.endOfFrame;
      await _disposePreparedMediaKitPlayerOnce(prepared.player);
    }
    _crossfadeStarted = false;
    _lastAppliedIncomingVolume = null;
    _prepareNextQueuePlayback(_loadGeneration);
  }

  Future<void> _playNextIosPictureInPictureItem() async {
    if (!mounted ||
        !_autoplayEnabled ||
        !_allowsPictureInPicture ||
        !_iosPictureInPictureHandoff ||
        _autoAdvanceInProgress) {
      return;
    }
    final target = _automaticNextTarget;
    if (target == null) {
      return;
    }
    final l10n = AppLocalizations(Locale(_playbackLanguageCode));
    _autoAdvanceInProgress = true;
    final nextVideo = target.video;
    try {
      final playback = await _playbackService.resolve(
        nextVideo.id,
        music: nextVideo.isAudioOnlyMusic,
        isLive: nextVideo.isLive,
        languageCode: _playbackLanguageCode,
      );
      final resolvedPiP = await _resolvePictureInPicturePlayback(playback);
      if (resolvedPiP == null) {
        throw VideoPlaybackException(l10n.nextQueuePipStreamUnavailable);
      }
      final quality = resolvedPiP.quality;
      final streamUrl = await _registerIosPictureInPictureQuality(quality);
      final ready = await IosPictureInPicture.instance.configure(
        enabled: true,
        streamUrl: streamUrl,
        title: nextVideo.title,
        artist: nextVideo.channelTitle.isEmpty
            ? _mediaArtist(nextVideo.description)
            : nextVideo.channelTitle,
        thumbnailUrl: nextVideo.thumbnailUrl,
        playbackVolume: _volume * _systemAudioVolumeFactor,
        playlistFadeEnabled: false,
        hasNextItem: _hasNextAfterNavigationTarget(target),
        isLive: playback.isLive,
      );
      if (!ready) {
        throw VideoPlaybackException(l10n.nextQueuePipHandoffFailed);
      }
      final started = await IosPictureInPicture.instance.start(
        position: Duration.zero,
        playing: true,
        seekToPosition: !resolvedPiP.playback.isLive,
      );
      if (!started || !mounted) {
        return;
      }
      _applyNavigationTarget(target);
      _reshuffleQueueForNextCycleIfNeeded();
      setState(() {
        _synchronizeSearchModeWithMedia(nextVideo);
        _selectedVideo = nextVideo;
        _visitPlaybackHistory(nextVideo);
      });
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.nextQueueStartFailed(error))),
        );
      }
      await IosPictureInPicture.instance.stop();
    } finally {
      _autoAdvanceInProgress = false;
    }
  }

  void _handleIosPictureInPictureFailed(String message) {
    if (!mounted) {
      return;
    }
    AppLog.instance.error(
      'pip.ios.failed',
      error: message,
      fields: _mediaLogFields(_selectedVideo),
    );
    if (_nativeIosMainPlayerActive) {
      _iosPictureInPictureStarting = false;
      _iosPictureInPictureAutoEnterArmed = false;
      setState(() => _isInPictureInPictureMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pipStartFailed(message))),
      );
      return;
    }
    final player = _player;
    final shouldResume =
        _iosPictureInPictureHandoff && _iosPictureInPictureWasPlaying;
    _iosPictureInPictureAutoEnterGeneration++;
    _iosPictureInPictureAutoEnterArmed = false;
    _iosPictureInPictureHandoff = false;
    _iosPictureInPictureStarting = false;
    _iosPictureInPictureReady = false;
    _iosPictureInPictureUsesHlsMaster = false;
    _iosPipDebugDialogPending = true;
    setState(() => _isInPictureInPictureMode = false);
    unawaited(() async {
      await _captureIosPipDebugSnapshot('after750msOrDelegate');
      await _captureIosPipDebugSnapshot('final');
      // Keep the diagnostic snapshot, then remove the failed native surface so
      // it cannot remain underneath the normal MediaKit player.
      await IosPictureInPicture.instance.configure(enabled: false);
      if (!mounted) {
        return;
      }
      if (player != null) {
        if (shouldResume) {
          await player.play();
        }
        await _attachSystemMediaControls(player, _selectedVideo);
      }
      if (_lifecycleState != AppLifecycleState.resumed) {
        await _handleRemoteSurfaceClosed();
      }
      await _showIosPipDebugDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.pipStartFailed(message))),
        );
      }
    }());
  }

  Future<void> _shutdownForAppTermination() {
    _appTerminationStarted = true;
    return _appTerminationFuture ??= _performAppTerminationShutdown();
  }

  Future<void> _performAppTerminationShutdown() async {
    _sleepDeadlineTimer?.cancel();
    _sleepPlaybackPauseTimer?.cancel();
    _loadGeneration++;
    _seekHoldTimer?.cancel();
    _hideControlsTimer?.cancel();
    _iosPipDebugSnapshotTimer?.cancel();
    _gestureFeedbackController.clear();
    _playlistPreparationGate.cancel();
    final pendingPreparation = _preparingNextPlayback;
    _preparingNextPlayback = null;

    final player = _player;
    final preparedPlayer = _preparedNextPlayback?.player;
    final standbyPlayer = _takeCrossfadeStandbyPlayer();
    _player = null;
    _nativeAndroidMedia3PlayerActive = false;
    _nativeAndroidMedia3AudioPlayerActive = false;
    _preparedNextPlayback = null;
    _cancelPreparedMediaKitPlayer(preparedPlayer);
    _cancelPreparedMediaKitPlayer(standbyPlayer);
    _preparedNativeAndroidMedia3AudioPlayback = null;
    _preparedNativeIosAudioPlayback = null;
    _nativeIosAudioPlayerActive = false;
    final subscriptions = _playerSubscriptions;
    _playerSubscriptions = const [];

    // Clear the persistent Android/iOS media surface before optional native
    // PiP calls. A failing platform call must never skip the remaining cleanup.
    await _ignoreTerminationError(
      () => SystemMediaControls.instance.setSecondaryPlayer(null),
    );
    await _ignoreTerminationError(SystemMediaControls.instance.clear);
    await _ignoreTerminationError(IosPictureInPicture.instance.stop);
    await _ignoreTerminationError(IosNativeAudioPlayback.instance.stop);
    await _ignoreTerminationError(AndroidMedia3AudioPlayback.instance.stop);
    await _ignoreTerminationError(AndroidMedia3VideoPlayer.instance.stop);
    await _ignoreTerminationError(AndroidPictureInPicture.instance.detach);
    await _ignoreTerminationError(IosPictureInPicture.instance.detach);
    await _ignoreTerminationError(IosNativeAudioPlayback.instance.detach);
    for (final subscription in subscriptions) {
      await _ignoreTerminationError(subscription.cancel);
    }
    await _ignoreTerminationError(() async => player?.pause());
    await _ignoreTerminationError(() async => preparedPlayer?.pause());
    await _ignoreTerminationError(() async => standbyPlayer?.pause());
    await _ignoreTerminationError(() async => player?.dispose());
    if (!identical(preparedPlayer, player)) {
      await _disposePreparedMediaKitPlayerOnce(preparedPlayer);
    }
    if (!identical(standbyPlayer, player) &&
        !identical(standbyPlayer, preparedPlayer)) {
      await _disposePreparedMediaKitPlayerOnce(standbyPlayer);
    }
    try {
      await pendingPreparation;
    } on Object {
      // A cancelled preparation may finish with a transport/player error.
    }
    final latePreparedPlayer = _preparedNextPlayback?.player;
    _preparedNextPlayback = null;
    if (!identical(latePreparedPlayer, player) &&
        !identical(latePreparedPlayer, preparedPlayer)) {
      await _disposePreparedMediaKitPlayerOnce(latePreparedPlayer);
    }
    await _ignoreTerminationError(_streamProxy.close);
    widget.manifestCache?.clear();
  }

  Future<void> _ignoreTerminationError(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on Object {
      // Termination is best-effort per resource. Continue with every other
      // resource so one platform/plugin failure cannot leave audio running.
    }
  }

  Future<void> _leaveTerminatedPlayerAfterRestart() async {
    await _appTerminationFuture;
    if (!mounted || _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (await Navigator.of(context).maybePop()) {
      return;
    }

    // Some Android vendors retain the Flutter engine after task removal. If
    // this page is the root route, make its stopped state usable again without
    // restarting playback automatically.
    _streamProxy = SegmentedStreamProxy(upstreamHeaders: _youtubeHeaders);
    _appTerminationStarted = false;
    _appTerminationFuture = null;
    SystemMediaControls.instance.setTaskRemovedHandler(
      _shutdownForAppTermination,
    );
    if (mounted) {
      setState(() {
        _isLoadingVideo = false;
        _playerError = context.l10n.playbackStoppedOnExit;
        _playerErrorDetails = null;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepDeadlineTimer?.cancel();
    _sleepPlaybackPauseTimer?.cancel();
    _seekHoldTimer?.cancel();
    _hideControlsTimer?.cancel();
    _iosPipDebugSnapshotTimer?.cancel();
    _videoResultsScrollController.dispose();
    _channelResultsScrollController.dispose();
    _playlistResultsScrollController.dispose();
    _pullDownFullscreenController.dispose();
    _pullUpFullscreenController.dispose();
    _gestureFeedbackController.dispose();
    SystemMediaControls.instance.setTaskRemovedHandler(null);
    SystemMediaControls.instance.setPlaybackInterruptionHandlers();
    if (_appTerminationStarted) {
      widget.manifestCache?.clear();
    } else {
      widget.manifestCache?.resumePrefetch();
    }
    unawaited(AndroidPictureInPicture.instance.detach());
    AndroidMedia3VideoPlayer.instance.state.removeListener(
      _handleAndroidMedia3StateChanged,
    );
    unawaited(AndroidMedia3VideoPlayer.instance.detach());
    unawaited(AndroidMedia3AudioPlayback.instance.stop());
    unawaited(AndroidMedia3AudioPlayback.instance.detach());
    unawaited(IosPictureInPicture.instance.detach());
    unawaited(IosNativeAudioPlayback.instance.stop());
    unawaited(IosNativeAudioPlayback.instance.detach());
    _loadGeneration++;
    final pendingPreparation = _preparingNextPlayback;
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    final disposingPlayer = _player;
    final disposingPreparedPlayer = _preparedNextPlayback?.player;
    final disposingStandbyPlayer = _takeCrossfadeStandbyPlayer();
    _preparedNextPlayback = null;
    _cancelPreparedMediaKitPlayer(disposingPreparedPlayer);
    _cancelPreparedMediaKitPlayer(disposingStandbyPlayer);
    _preparedNativeAndroidMedia3AudioPlayback = null;
    _preparedNativeIosAudioPlayback = null;
    if (_appTerminationFuture case final termination?) {
      unawaited(termination);
    } else {
      unawaited(() async {
        if (disposingPlayer != null) {
          await SystemMediaControls.instance.detach(disposingPlayer);
        } else {
          await SystemMediaControls.instance.clear();
        }
        await disposingPlayer?.dispose();
        await _disposePreparedMediaKitPlayerOnce(disposingPreparedPlayer);
        if (!identical(disposingStandbyPlayer, disposingPlayer) &&
            !identical(disposingStandbyPlayer, disposingPreparedPlayer)) {
          await _disposePreparedMediaKitPlayerOnce(disposingStandbyPlayer);
        }
        await pendingPreparation;
        final latePreparedPlayer = _preparedNextPlayback?.player;
        final lateStandbyPlayer = _takeCrossfadeStandbyPlayer();
        _preparedNextPlayback = null;
        if (!identical(latePreparedPlayer, disposingPlayer) &&
            !identical(latePreparedPlayer, disposingPreparedPlayer) &&
            !identical(latePreparedPlayer, disposingStandbyPlayer)) {
          await _disposePreparedMediaKitPlayerOnce(latePreparedPlayer);
        }
        if (!identical(lateStandbyPlayer, disposingPlayer) &&
            !identical(lateStandbyPlayer, disposingPreparedPlayer) &&
            !identical(lateStandbyPlayer, disposingStandbyPlayer) &&
            !identical(lateStandbyPlayer, latePreparedPlayer)) {
          await _disposePreparedMediaKitPlayerOnce(lateStandbyPlayer);
        }
        await _streamProxy.close();
      }());
    }
    _playbackState.dispose();
    if (_ownsPlaybackService) {
      _playbackService.close();
    }
    if (_ownsProfileController) {
      _profileController.dispose();
    }
    if (_ownsCatalogRepository) {
      _catalogRepository.close();
    }
    _queryController.dispose();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    super.dispose();
  }

  Future<bool> _configureExternalAudioForNextOpen(
    Player player,
    Uri? audioUrl, {
    required bool nativePlayback,
  }) async {
    if (!nativePlayback) {
      return false;
    }
    try {
      final platform = player.platform as dynamic;
      if (audioUrl == null) {
        // An empty value is interpreted as an external file with the path ''.
        // audio-files is a path-list option and must be cleared explicitly.
        await platform.command(['change-list', 'audio-files', 'clr', '']);
        return false;
      }
      await platform.setProperty(
        'options/audio-files',
        _mpvPathListValue(audioUrl),
      );
      await platform.setProperty('options/aid', 'auto');
      return true;
    } on Object {
      return false;
    }
  }

  String _mpvPathListValue(Uri uri) {
    var value = uri.toString().replaceAll(r'\', r'\\');
    final separator = defaultTargetPlatform == TargetPlatform.windows
        ? ';'
        : ':';
    value = value.replaceAll(separator, '\\$separator');
    return value;
  }

  Future<ResolvedVideoPlayback> _resolvePlayback(YouTubeVideo video) {
    return widget.manifestCache?.resolve(
          video.id,
          music: video.isAudioOnlyMusic,
          isLive: video.isLive,
          languageCode: _playbackLanguageCode,
        ) ??
        _playbackService.resolve(
          video.id,
          music: video.isAudioOnlyMusic,
          isLive: video.isLive,
          languageCode: _playbackLanguageCode,
        );
  }

  void _pauseManifestPrefetch() {
    widget.manifestCache?.pausePrefetch();
  }

  void _prepareNextQueuePlayback(int generation) {
    if (_playbackAheadSuspended ||
        _nativeAndroidMedia3PlayerActive ||
        _nativeIosMainPlayerActive) {
      return;
    }
    _reshuffleQueueForNextCycleIfNeeded();
    final target = _automaticNextTarget;
    if (target == null) {
      unawaited(_disposePreparedNextPlayback());
      return;
    }

    if (_nativeIosAudioPlayerActive) {
      _prepareNextNativeIosAudioPlayback(target, generation);
      return;
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      _prepareNextNativeAndroidMedia3AudioPlayback(target, generation);
      return;
    }

    final nextVideo = target.video;
    if (_shouldUseNativeAndroidMedia3Player(nextVideo) ||
        _shouldUseNativeAndroidMedia3AudioPlayer(nextVideo) ||
        _shouldUseNativeIosMainPlayer(nextVideo) ||
        _shouldUseNativeIosAudioPlayer(nextVideo)) {
      unawaited(_disposePreparedNextPlayback());
      return;
    }
    if (_preparedNextPlayback?.target.matches(target) == true ||
        _playlistPreparationGate.isPreparing(nextVideo.id)) {
      return;
    }

    final preparationTicket = _playlistPreparationGate.begin(nextVideo.id);
    late final Future<void> preparation;
    preparation =
        _prepareNextQueuePlaybackImpl(
          target: target,
          generation: generation,
          preparationTicket: preparationTicket,
        ).whenComplete(() {
          if (_playlistPreparationGate.complete(preparationTicket) &&
              identical(_preparingNextPlayback, preparation)) {
            _preparingNextPlayback = null;
          }
        });
    _preparingNextPlayback = preparation;
    unawaited(preparation);
  }

  void _prepareNextNativeAndroidMedia3AudioPlayback(
    PlaybackNavigationTarget target,
    int generation,
  ) {
    if (!target.video.isAudioOnlyMusic) {
      _preparedNativeAndroidMedia3AudioPlayback = null;
      unawaited(AndroidMedia3AudioPlayback.instance.clearNext());
      return;
    }
    if (_preparedNativeAndroidMedia3AudioPlayback?.target.matches(target) ==
            true ||
        _playlistPreparationGate.isPreparing(target.video.id)) {
      return;
    }
    final preparationTicket = _playlistPreparationGate.begin(target.video.id);
    late final Future<void> preparation;
    preparation =
        _prepareNextNativeAndroidMedia3AudioPlaybackImpl(
          target: target,
          generation: generation,
          preparationTicket: preparationTicket,
        ).whenComplete(() {
          if (_playlistPreparationGate.complete(preparationTicket) &&
              identical(_preparingNextPlayback, preparation)) {
            _preparingNextPlayback = null;
          }
        });
    _preparingNextPlayback = preparation;
    unawaited(preparation);
  }

  Future<void> _prepareNextNativeAndroidMedia3AudioPlaybackImpl({
    required PlaybackNavigationTarget target,
    required int generation,
    required PlaylistPreparationTicket preparationTicket,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'queue.prepare_next.started',
      fields: {
        ..._mediaLogFields(target.video),
        'backend': 'androidMedia3ExoPlayerAudio',
        'navigationSource': target.source.name,
      },
    );
    try {
      var playback = await _resolvePlayback(target.video);
      if (!_isExpectedNativeAndroidMedia3AudioTarget(
        target,
        generation,
        preparationTicket,
      )) {
        return;
      }
      var quality = playback.defaultQuality;
      var localFallbackTried = false;
      var usedFallbackLoader = false;
      while (true) {
        try {
          final streamUrl = await _registerAndroidMedia3AudioQuality(quality);
          final ready = await AndroidMedia3AudioPlayback.instance
              .prepareNext(
                streamUrl: streamUrl,
                headers: _youtubeHeaders,
                isHls: quality.isHls,
                expectedDuration: _canonicalAudioDuration(
                  target.video,
                  quality,
                ),
              )
              .timeout(const Duration(seconds: 20));
          if (!ready) {
            throw StateError('Media3 konnte den nächsten Song nicht laden.');
          }
          if (!_isExpectedNativeAndroidMedia3AudioTarget(
            target,
            generation,
            preparationTicket,
          )) {
            await AndroidMedia3AudioPlayback.instance.clearNext();
            return;
          }
          _preparedNativeAndroidMedia3AudioPlayback =
              _PreparedNativeAndroidMedia3AudioPlayback(
                video: target.video,
                target: target,
                playback: playback,
                selectedQuality: quality,
              );
          AppLog.instance.info(
            'queue.prepare_next.succeeded',
            fields: {
              ..._mediaLogFields(target.video),
              'backend': 'androidMedia3ExoPlayerAudio',
              'durationMs': stopwatch.elapsedMilliseconds,
              'quality': quality.label,
              'fallbackUsed': localFallbackTried || usedFallbackLoader,
            },
          );
          return;
        } on Exception {
          final localFallback = playback.fallbackQuality;
          if (!localFallbackTried &&
              localFallback != null &&
              !identical(localFallback, quality)) {
            quality = localFallback;
            localFallbackTried = true;
            continue;
          }
          final fallbackLoader = playback.fallbackLoader;
          if (!usedFallbackLoader && fallbackLoader != null) {
            playback = await fallbackLoader();
            quality = playback.defaultQuality;
            localFallbackTried = false;
            usedFallbackLoader = true;
            continue;
          }
          rethrow;
        }
      }
    } on Object catch (error, stackTrace) {
      AppLog.instance.warning(
        'queue.prepare_next.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          ..._mediaLogFields(target.video),
          'backend': 'androidMedia3ExoPlayerAudio',
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (_isExpectedNativeAndroidMedia3AudioTarget(
        target,
        generation,
        preparationTicket,
      )) {
        _preparedNativeAndroidMedia3AudioPlayback = null;
        await AndroidMedia3AudioPlayback.instance.clearNext();
      }
    }
  }

  bool _isExpectedNativeAndroidMedia3AudioTarget(
    PlaybackNavigationTarget target,
    int generation,
    PlaylistPreparationTicket preparationTicket,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      _nativeAndroidMedia3AudioPlayerActive &&
      target.matches(_automaticNextTarget) &&
      preparationTicket.videoId == target.video.id &&
      _playlistPreparationGate.isActive(preparationTicket);

  void _prepareNextNativeIosAudioPlayback(
    PlaybackNavigationTarget target,
    int generation,
  ) {
    if (!target.video.isAudioOnlyMusic) {
      _preparedNativeIosAudioPlayback = null;
      unawaited(IosNativeAudioPlayback.instance.clearNext());
      return;
    }
    if (_preparedNativeIosAudioPlayback?.target.matches(target) == true ||
        _playlistPreparationGate.isPreparing(target.video.id)) {
      return;
    }
    final preparationTicket = _playlistPreparationGate.begin(target.video.id);
    late final Future<void> preparation;
    preparation =
        _prepareNextNativeIosAudioPlaybackImpl(
          target: target,
          generation: generation,
          preparationTicket: preparationTicket,
        ).whenComplete(() {
          if (_playlistPreparationGate.complete(preparationTicket) &&
              identical(_preparingNextPlayback, preparation)) {
            _preparingNextPlayback = null;
          }
        });
    _preparingNextPlayback = preparation;
    unawaited(preparation);
  }

  Future<void> _prepareNextNativeIosAudioPlaybackImpl({
    required PlaybackNavigationTarget target,
    required int generation,
    required PlaylistPreparationTicket preparationTicket,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'queue.prepare_next.started',
      fields: {
        ..._mediaLogFields(target.video),
        'backend': 'iosAvPlayerAudio',
        'navigationSource': target.source.name,
      },
    );
    try {
      var playback = await _resolvePlayback(target.video);
      if (!_isExpectedNativeIosAudioTarget(
        target,
        generation,
        preparationTicket,
      )) {
        return;
      }
      var quality = playback.defaultQuality;
      var localFallbackTried = false;
      var usedFallbackLoader = false;
      while (true) {
        try {
          final streamUrl = await _registerIosPictureInPictureQuality(quality);
          final ready = await IosNativeAudioPlayback.instance
              .prepareNext(
                streamUrl: streamUrl,
                title: target.video.title,
                artist: target.video.channelTitle.isEmpty
                    ? _mediaArtist(target.video.description)
                    : target.video.channelTitle,
                thumbnailUrl: target.video.thumbnailUrl,
                hasNext: _hasNextAfterNavigationTarget(target),
                expectedDuration: _canonicalAudioDuration(
                  target.video,
                  quality,
                ),
              )
              .timeout(const Duration(seconds: 20));
          if (!ready) {
            throw StateError('Native iOS AVPlayer could not prepare audio.');
          }
          if (!_isExpectedNativeIosAudioTarget(
            target,
            generation,
            preparationTicket,
          )) {
            await IosNativeAudioPlayback.instance.clearNext();
            return;
          }
          _preparedNativeIosAudioPlayback = _PreparedNativeIosAudioPlayback(
            video: target.video,
            target: target,
            playback: playback,
            selectedQuality: quality,
          );
          AppLog.instance.info(
            'queue.prepare_next.succeeded',
            fields: {
              ..._mediaLogFields(target.video),
              'backend': 'iosAvPlayerAudio',
              'durationMs': stopwatch.elapsedMilliseconds,
              'quality': quality.label,
              'fallbackUsed': localFallbackTried || usedFallbackLoader,
            },
          );
          return;
        } on Exception {
          final localFallback = playback.fallbackQuality;
          if (!localFallbackTried &&
              localFallback != null &&
              !identical(localFallback, quality)) {
            quality = localFallback;
            localFallbackTried = true;
            continue;
          }
          final fallbackLoader = playback.fallbackLoader;
          if (!usedFallbackLoader && fallbackLoader != null) {
            playback = await fallbackLoader();
            quality = playback.defaultQuality;
            localFallbackTried = false;
            usedFallbackLoader = true;
            continue;
          }
          rethrow;
        }
      }
    } on Object catch (error, stackTrace) {
      AppLog.instance.warning(
        'queue.prepare_next.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          ..._mediaLogFields(target.video),
          'backend': 'iosAvPlayerAudio',
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (_isExpectedNativeIosAudioTarget(
        target,
        generation,
        preparationTicket,
      )) {
        _preparedNativeIosAudioPlayback = null;
        await IosNativeAudioPlayback.instance.clearNext();
      }
      // The regular one-player transition remains the safe fallback.
    }
  }

  bool _isExpectedNativeIosAudioTarget(
    PlaybackNavigationTarget target,
    int generation,
    PlaylistPreparationTicket preparationTicket,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      _nativeIosAudioPlayerActive &&
      target.matches(_automaticNextTarget) &&
      preparationTicket.videoId == target.video.id &&
      _playlistPreparationGate.isActive(preparationTicket);

  void _reshuffleQueueForNextCycleIfNeeded() {
    if (!_autoplayEnabled || !_playbackQueue.isShuffled) {
      return;
    }
    if (_playbackHistories.forMedia(_selectedVideo).nextFrom(_selectedVideo) !=
        null) {
      return;
    }
    final reshuffled = _playbackQueue.reshuffleForNextCycle(
      random: _shuffleRandom,
    );
    if (identical(reshuffled, _playbackQueue)) {
      return;
    }
    _playbackQueue = reshuffled;
    final player = _player;
    if (player != null) {
      unawaited(_attachSystemMediaControls(player, _selectedVideo));
    } else if (_nativeAndroidMedia3AudioPlayerActive) {
      unawaited(_attachAndroidMedia3AudioSystemControls(_selectedVideo));
    } else if (_nativeIosMainPlayerActive && _selectedVideo.isMusic) {
      unawaited(_attachNativeIosMainSystemControls(_selectedVideo));
    } else if (_nativeIosAudioPlayerActive) {
      unawaited(_updateIosNativeAudioNavigation());
    }
  }

  Future<void> _prepareNextQueuePlaybackImpl({
    required PlaybackNavigationTarget target,
    required int generation,
    required PlaylistPreparationTicket preparationTicket,
  }) async {
    final video = target.video;
    if (!_isExpectedNextQueueItem(target, generation, preparationTicket)) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'queue.prepare_next.started',
      fields: {
        ..._mediaLogFields(video),
        'backend': 'mediaKit',
        'navigationSource': target.source.name,
      },
    );
    await _disposePreparedNextPlayback(disposeStandby: false);
    Player? preparingPlayer;
    try {
      var playback = await _resolvePlayback(video);
      if (!_isExpectedNextQueueItem(target, generation, preparationTicket)) {
        return;
      }

      final canReuseAudioSlot = shouldUsePlaylistCrossfade(
        current: _selectedVideo,
        next: video,
      );
      Player? reusablePlayer;
      if (canReuseAudioSlot) {
        reusablePlayer = _takeCrossfadeStandbyPlayer();
      } else {
        await _disposeCrossfadeStandbyPlayer();
      }
      final player = reusablePlayer ?? Player();
      preparingPlayer = player;
      var selectedQuality = playback.defaultQuality;
      final videoController =
          PlaybackBackgroundPolicy.requiresPlayerSurface(video)
          ? VideoController(player)
          : null;
      final openingPreparation = _PreparedQueuePlayback(
        video: video,
        target: target,
        playback: playback,
        selectedQuality: selectedQuality,
        player: player,
        videoController: videoController,
        isReady: false,
      );
      if (!mounted || generation != _loadGeneration) {
        await _disposePreparedMediaKitPlayerOnce(player);
        return;
      }
      setState(() => _preparedNextPlayback = openingPreparation);
      if (PlaybackBackgroundPolicy.requiresPlayerSurface(video)) {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      }
      final opened = await _openPlaybackWithLazyFallback(
        player,
        playback,
        position: Duration.zero,
        play: false,
        volumeOverride: 0,
      );
      playback = opened.playback;
      selectedQuality = opened.quality;
      bool preparationIsActive() =>
          _isExpectedNextQueueItem(target, generation, preparationTicket) &&
          identical(_preparedNextPlayback?.player, player) &&
          !_isPreparedMediaKitPlayerCancelled(player);
      if (!preparationIsActive()) {
        preparingPlayer = null;
        if (identical(_preparedNextPlayback?.player, player)) {
          await _disposePreparedNextPlayback(disposeStandby: false);
        } else {
          await _disposePreparedMediaKitPlayerOnce(player);
        }
        return;
      }
      final primed = await _primePreparedPlayer(
        player,
        isLive: playback.isLive,
        canContinue: preparationIsActive,
      );
      if (!primed || !preparationIsActive()) {
        preparingPlayer = null;
        if (identical(_preparedNextPlayback?.player, player)) {
          await _disposePreparedNextPlayback(disposeStandby: false);
        } else {
          await _disposePreparedMediaKitPlayerOnce(player);
        }
        return;
      }

      final prepared = _PreparedQueuePlayback(
        video: video,
        target: target,
        playback: playback,
        selectedQuality: selectedQuality,
        player: player,
        videoController: videoController,
        isReady: true,
      );
      if (!mounted || generation != _loadGeneration) {
        await _disposePreparedMediaKitPlayerOnce(player);
        return;
      }
      setState(() => _preparedNextPlayback = prepared);
      AppLog.instance.info(
        'queue.prepare_next.succeeded',
        fields: {
          ..._mediaLogFields(video),
          'backend': 'mediaKit',
          'durationMs': stopwatch.elapsedMilliseconds,
          'quality': selectedQuality.label,
          'reusedStandby': reusablePlayer != null,
        },
      );
      preparingPlayer = null;
      unawaited(
        _prepareIosNextPictureInPicture(
          prepared: prepared,
          generation: generation,
        ),
      );
    } on Object catch (error, stackTrace) {
      AppLog.instance.warning(
        'queue.prepare_next.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          ..._mediaLogFields(video),
          'backend': 'mediaKit',
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      final failedPlayer = preparingPlayer;
      preparingPlayer = null;
      if (identical(_preparedNextPlayback?.player, failedPlayer)) {
        await _disposePreparedNextPlayback(disposeStandby: false);
      } else {
        await _disposePreparedMediaKitPlayerOnce(failedPlayer);
      }
      // The normal single-player transition remains available as fallback.
    }
  }

  Future<void> _prepareIosNextPictureInPicture({
    required _PreparedQueuePlayback prepared,
    required int generation,
  }) async {
    if (!_allowsPictureInPicture ||
        !IosPictureInPicture.instance.isSupportedPlatform ||
        !_iosPictureInPictureHandoff) {
      return;
    }
    final resolvedPiP = await _resolvePictureInPicturePlayback(
      prepared.playback,
      selectedQuality: prepared.selectedQuality,
    );
    if (resolvedPiP == null) {
      return;
    }
    final quality = resolvedPiP.quality;
    final streamUrl = await _registerIosPictureInPictureQuality(quality);
    if (!mounted ||
        generation != _loadGeneration ||
        !identical(_preparedNextPlayback, prepared)) {
      return;
    }
    await IosPictureInPicture.instance.configureNext(
      streamUrl: streamUrl,
      title: prepared.video.title,
      artist: prepared.video.channelTitle.isEmpty
          ? _mediaArtist(prepared.video.description)
          : prepared.video.channelTitle,
      thumbnailUrl: prepared.video.thumbnailUrl,
      hasNextItem: _hasNextAfterNavigationTarget(prepared.target),
      isLive: prepared.playback.isLive,
    );
  }

  Future<bool> _primePreparedPlayer(
    Player player, {
    required bool isLive,
    required bool Function() canContinue,
    Duration rewindPosition = Duration.zero,
  }) async {
    if (!canContinue()) {
      return false;
    }
    if (!PlaybackSeekPolicy.canSeek(isLive: isLive)) {
      await player.setVolume(0);
      return canContinue();
    }
    final primed = Completer<void>();
    final positionSubscription = player.stream.position.listen((position) {
      if (position >= const Duration(milliseconds: 300) &&
          !primed.isCompleted) {
        primed.complete();
      }
    });
    try {
      await player.setVolume(0);
      if (!canContinue()) return false;
      await player.play();
      if (!canContinue()) return false;
      await primed.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      if (!canContinue()) return false;
      await player.pause();
      if (!canContinue()) return false;
      await player.seek(rewindPosition);
      if (!canContinue()) return false;
      await player.setVolume(0);
      return canContinue();
    } finally {
      await positionSubscription.cancel();
    }
  }

  bool _isExpectedNextQueueItem(
    PlaybackNavigationTarget target,
    int generation,
    PlaylistPreparationTicket preparationTicket,
  ) {
    if (!mounted || generation != _loadGeneration) {
      return false;
    }
    final expectedTarget = _automaticNextTarget;
    return target.matches(expectedTarget) &&
        preparationTicket.videoId == target.video.id &&
        _playlistPreparationGate.isActive(preparationTicket);
  }

  Player? _takeCrossfadeStandbyPlayer() {
    final player = _crossfadeStandbyPlayer;
    _crossfadeStandbyPlayer = null;
    return player;
  }

  Future<void> _disposeCrossfadeStandbyPlayer() async {
    final player = _takeCrossfadeStandbyPlayer();
    await _disposePreparedMediaKitPlayerOnce(player);
  }

  bool _isPreparedMediaKitPlayerCancelled(Player player) =>
      _cancelledPreparedMediaKitPlayers[player] == true;

  void _cancelPreparedMediaKitPlayer(Player? player) {
    if (player != null) {
      _cancelledPreparedMediaKitPlayers[player] = true;
    }
  }

  Future<void> _disposePreparedMediaKitPlayerOnce(Player? player) async {
    if (player == null) {
      return;
    }
    _cancelPreparedMediaKitPlayer(player);
    final existingDisposal = _preparedMediaKitPlayerDisposals[player];
    if (existingDisposal != null) {
      await existingDisposal;
      return;
    }
    final disposal = () async {
      try {
        await player.dispose();
      } on Object catch (error, stackTrace) {
        AppLog.instance.warning(
          'queue.prepared_player.dispose_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }();
    _preparedMediaKitPlayerDisposals[player] = disposal;
    await disposal;
  }

  Future<void> _disposePreparedNextPlayback({
    bool disposeStandby = true,
  }) async {
    final prepared = _preparedNextPlayback;
    final hadPreparedNativeIosAudio =
        _preparedNativeIosAudioPlayback != null || _nativeIosAudioPlayerActive;
    final hadPreparedNativeAndroidAudio =
        _preparedNativeAndroidMedia3AudioPlayback != null ||
        _nativeAndroidMedia3AudioPlayerActive;
    _preparedNativeAndroidMedia3AudioPlayback = null;
    _preparedNativeIosAudioPlayback = null;
    final standby = disposeStandby ? _takeCrossfadeStandbyPlayer() : null;
    if (prepared != null && mounted) {
      setState(() => _preparedNextPlayback = null);
    } else {
      _preparedNextPlayback = null;
    }
    // Mark both players synchronously before the first await. An in-flight
    // priming coroutine will then stop before issuing another command to a
    // player whose disposal was requested by navigation or shutdown.
    _cancelPreparedMediaKitPlayer(prepared?.player);
    _cancelPreparedMediaKitPlayer(standby);
    _crossfadeStarted = false;
    _lastAppliedIncomingVolume = null;
    await SystemMediaControls.instance.setSecondaryPlayer(null);
    if (hadPreparedNativeIosAudio) {
      await IosNativeAudioPlayback.instance.clearNext();
    }
    if (hadPreparedNativeAndroidAudio) {
      await AndroidMedia3AudioPlayback.instance.clearNext();
    }
    if (prepared != null) {
      await _disposePreparedMediaKitPlayerOnce(prepared.player);
    }
    if (standby != null && !identical(standby, prepared?.player)) {
      await _disposePreparedMediaKitPlayerOnce(standby);
    }
  }

  Future<void> _loadDeferredSubtitles(String videoId, int generation) async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted ||
        generation != _loadGeneration ||
        _selectedVideo.id != videoId) {
      return;
    }
    final subtitles = await _playbackService.loadSubtitles(videoId);
    if (!mounted ||
        generation != _loadGeneration ||
        _selectedVideo.id != videoId ||
        subtitles.isEmpty) {
      return;
    }
    setState(() => _playback = _playback?.withSubtitles(subtitles));
  }

  Future<void> _loadVideo(
    YouTubeVideo video, {
    Duration initialPosition = Duration.zero,
    bool play = true,
    bool keepSystemSessionActive = false,
    bool prepareBackgroundFeatures = true,
    bool attachSystemControls = true,
  }) async {
    final l10n = AppLocalizations(Locale(_playbackLanguageCode));
    final stopwatch = Stopwatch()..start();
    final useNativeAndroidMedia3Player = _shouldUseNativeAndroidMedia3Player(
      video,
    );
    final useNativeAndroidMedia3AudioPlayer =
        _shouldUseNativeAndroidMedia3AudioPlayer(video);
    final useNativeIosMainPlayer = _shouldUseNativeIosMainPlayer(video);
    final useNativeIosAudioPlayer = _shouldUseNativeIosAudioPlayer(video);
    final previousNativeAndroidMedia3Player = _nativeAndroidMedia3PlayerActive;
    final previousNativeAndroidMedia3AudioPlayer =
        _nativeAndroidMedia3AudioPlayerActive;
    final previousNativeIosMainPlayer = _nativeIosMainPlayerActive;
    final previousNativeIosAudioPlayer = _nativeIosAudioPlayerActive;
    _cancelIosAutomaticPictureInPictureHandoff();
    _pauseManifestPrefetch();
    final generation = ++_loadGeneration;
    final logFields = <String, Object?>{
      ..._mediaLogFields(video),
      'generation': generation,
      'positionMs': initialPosition.inMilliseconds,
      'playRequested': play,
      'backend': useNativeAndroidMedia3Player
          ? 'androidMedia3ExoPlayer'
          : useNativeAndroidMedia3AudioPlayer
          ? 'androidMedia3ExoPlayerAudio'
          : useNativeIosMainPlayer
          ? video.isMusic
                ? 'iosAvPlayerMusicVideo'
                : 'iosAvPlayerVideo'
          : useNativeIosAudioPlayer
          ? 'iosAvPlayerAudio'
          : 'mediaKit',
    };
    AppLog.instance.info('player.load.started', fields: logFields);
    if (!PlaybackBackgroundPolicy.usesSystemMediaControls(video)) {
      await SystemMediaControls.instance.clear();
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    Player? loadingPlayer;
    var loadingPlayerPublished = false;
    List<StreamSubscription<dynamic>> loadingSubscriptions = const [];
    _seekHoldTimer?.cancel();
    _gestureFeedbackController.clear();
    _preparingNextPlayback = null;
    _playlistPreparationGate.cancel();
    await _disposePreparedNextPlayback();

    final previousPlayer = _player;
    final previousSubscriptions = _playerSubscriptions;
    _lastAndroidMedia3PlaybackRequested = false;
    if (mounted) {
      setState(() {
        _player = null;
        _nativeAndroidMedia3PlayerActive = useNativeAndroidMedia3Player;
        _nativeAndroidMedia3AudioPlayerActive =
            useNativeAndroidMedia3AudioPlayer;
        _nativeIosMainPlayerActive = useNativeIosMainPlayer;
        _nativeIosAudioPlayerActive = useNativeIosAudioPlayer;
        _preparedNativeAndroidMedia3AudioPlayback = null;
        _preparedNativeIosAudioPlayback = null;
        _loadedPlayerVideoId = null;
        _videoController = null;
        _playerSubscriptions = const [];
        _playback = null;
        _selectedQuality = null;
        _playerError = null;
        _playerErrorDetails = null;
        _isLoadingVideo = true;
        _isChangingQuality = false;
        _iosPictureInPictureReady = false;
        _iosPictureInPictureUsesHlsMaster = false;
        _dragPosition = null;
        _controlsVisible = true;
        _settingsVisible = false;
      });
      _restartControlsTimer();
    }
    for (final subscription in previousSubscriptions) {
      await subscription.cancel();
    }
    if (previousPlayer != null) {
      if (keepSystemSessionActive) {
        await _beginSystemMediaTransition(previousPlayer, video);
      } else {
        await SystemMediaControls.instance.detach(previousPlayer);
      }
    }
    if (!previousNativeIosMainPlayer || !useNativeIosMainPlayer) {
      await IosPictureInPicture.instance.configure(enabled: false);
    } else {
      await IosPictureInPicture.instance.pause();
    }
    if (previousNativeIosAudioPlayer && !useNativeIosAudioPlayer) {
      await IosNativeAudioPlayback.instance.stop();
    } else if (useNativeIosAudioPlayer) {
      await IosNativeAudioPlayback.instance.clearNext();
    }
    if (previousNativeAndroidMedia3Player) {
      if (useNativeAndroidMedia3Player) {
        await AndroidMedia3VideoPlayer.instance.pause();
      } else {
        await AndroidMedia3VideoPlayer.instance.stop();
      }
    }
    if (previousNativeAndroidMedia3AudioPlayer &&
        !useNativeAndroidMedia3AudioPlayer) {
      await AndroidMedia3AudioPlayback.instance.stop();
    } else if (useNativeAndroidMedia3AudioPlayer) {
      await AndroidMedia3AudioPlayback.instance.clearNext();
    }
    await previousPlayer?.dispose();
    _lastAppliedPlayerVolume = null;
    _playbackState.value = const _PlaybackViewState();
    _syncPictureInPictureConfiguration();
    try {
      var playback = await _resolvePlayback(video);
      if (!mounted ||
          generation != _loadGeneration ||
          _backgroundPlaybackStartsBlocked) {
        return;
      }

      if (useNativeIosMainPlayer) {
        await _loadNativeIosMainPlayback(
          video: video,
          initialPlayback: playback,
          generation: generation,
          initialPosition: initialPosition,
          play: play && !_backgroundPlaybackStartsBlocked,
          prepareBackgroundFeatures: prepareBackgroundFeatures,
          attachSystemControls: attachSystemControls,
          l10n: context.l10n,
        );
        AppLog.instance.info(
          'player.load.succeeded',
          fields: {
            ...logFields,
            'durationMs': stopwatch.elapsedMilliseconds,
            'quality': _selectedQuality?.label,
            'transport': _selectedQuality?.transportLabel,
          },
        );
        return;
      }

      if (useNativeIosAudioPlayer) {
        await _loadNativeIosAudioPlayback(
          video: video,
          initialPlayback: playback,
          generation: generation,
          initialPosition: initialPosition,
          play: play && !_backgroundPlaybackStartsBlocked,
          prepareBackgroundFeatures: prepareBackgroundFeatures,
          attachSystemControls: attachSystemControls,
          l10n: context.l10n,
        );
        AppLog.instance.info(
          'player.load.succeeded',
          fields: {
            ...logFields,
            'durationMs': stopwatch.elapsedMilliseconds,
            'quality': _selectedQuality?.label,
            'transport': _selectedQuality?.transportLabel,
          },
        );
        return;
      }

      if (useNativeAndroidMedia3AudioPlayer) {
        await _loadNativeAndroidMedia3AudioPlayback(
          video: video,
          initialPlayback: playback,
          generation: generation,
          initialPosition: initialPosition,
          play: play && !_backgroundPlaybackStartsBlocked,
          prepareBackgroundFeatures: prepareBackgroundFeatures,
          attachSystemControls: attachSystemControls,
          l10n: context.l10n,
        );
        AppLog.instance.info(
          'player.load.succeeded',
          fields: {
            ...logFields,
            'durationMs': stopwatch.elapsedMilliseconds,
            'quality': _selectedQuality?.label,
            'transport': _selectedQuality?.transportLabel,
          },
        );
        return;
      }

      if (useNativeAndroidMedia3Player) {
        await _loadNativeAndroidMedia3Playback(
          video: video,
          initialPlayback: playback,
          generation: generation,
          initialPosition: initialPosition,
          play: play && !_backgroundPlaybackStartsBlocked,
          prepareBackgroundFeatures: prepareBackgroundFeatures,
          l10n: context.l10n,
        );
        AppLog.instance.info(
          'player.load.succeeded',
          fields: {
            ...logFields,
            'durationMs': stopwatch.elapsedMilliseconds,
            'quality': _selectedQuality?.label,
            'transport': _selectedQuality?.transportLabel,
          },
        );
        return;
      }

      final player = Player();
      loadingPlayer = player;
      if (!mounted || generation != _loadGeneration) {
        await player.dispose();
        return;
      }
      final videoController =
          PlaybackBackgroundPolicy.requiresPlayerSurface(video)
          ? VideoController(player)
          : null;
      loadingSubscriptions = _createPlayerSubscriptions(player, generation);
      var selectedQuality = playback.defaultQuality;
      setState(() {
        _player = player;
        _videoController = videoController;
        _playerSubscriptions = loadingSubscriptions;
        _playback = playback;
        _selectedQuality = selectedQuality;
      });
      loadingPlayerPublished = true;
      final initialQuality = selectedQuality;
      final opened = await _openPlaybackWithLazyFallback(
        player,
        playback,
        position: initialPosition,
        play: play && !_backgroundPlaybackStartsBlocked,
      );
      playback = opened.playback;
      selectedQuality = opened.quality;
      final fallbackMessage = opened.usedFallback
          ? l10n.playbackFallback(
              initialQuality.label,
              playback.manifestSource.label,
              selectedQuality.label,
            )
          : null;
      if (!mounted || generation != _loadGeneration) {
        for (final subscription in loadingSubscriptions) {
          await subscription.cancel();
        }
        await player.dispose();
        return;
      }
      final playbackBlocked = _backgroundPlaybackStartsBlocked;
      if (playbackBlocked) {
        await player.pause();
      }

      setState(() {
        _player = player;
        _loadedPlayerVideoId = video.id;
        _visitPlaybackHistory(video);
        _videoController = videoController;
        _playerSubscriptions = loadingSubscriptions;
        _playback = playback;
        _selectedQuality = selectedQuality;
        _isLoadingVideo = false;
      });
      if (attachSystemControls && !playbackBlocked) {
        await _attachSystemMediaControls(player, video);
        _systemControlsDetachedForSleep = false;
      } else {
        _systemControlsDetachedForSleep = true;
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      final shouldPrepareBackgroundFeatures =
          prepareBackgroundFeatures && !playbackBlocked;
      _playbackAheadSuspended = !shouldPrepareBackgroundFeatures;
      if (shouldPrepareBackgroundFeatures) {
        _prepareNextQueuePlayback(generation);
      }
      unawaited(_loadDeferredSubtitles(video.id, generation));
      if (shouldPrepareBackgroundFeatures) {
        unawaited(
          _prepareIosPictureInPicture(
            playback: playback,
            selectedQuality: selectedQuality,
            generation: generation,
          ),
        );
      }
      _showControls();
      if (fallbackMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(fallbackMessage)));
      }
      AppLog.instance.info(
        'player.load.succeeded',
        fields: {
          ...logFields,
          'durationMs': stopwatch.elapsedMilliseconds,
          'quality': selectedQuality.label,
          'transport': selectedQuality.transportLabel,
          'fallbackUsed': opened.usedFallback,
          'backgroundBlocked': playbackBlocked,
        },
      );
    } on VideoPlaybackException catch (error) {
      AppLog.instance.error(
        'player.load.failed',
        error: error.technicalDetails,
        stackTrace: error.stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      if (useNativeAndroidMedia3Player) {
        _nativeAndroidMedia3PlayerActive = false;
        await AndroidMedia3VideoPlayer.instance.stop();
      }
      if (useNativeAndroidMedia3AudioPlayer) {
        _nativeAndroidMedia3AudioPlayerActive = false;
        await AndroidMedia3AudioPlayback.instance.stop();
        await SystemMediaControls.instance.clear();
      }
      if (useNativeIosMainPlayer) {
        _nativeIosMainPlayerActive = false;
        await IosPictureInPicture.instance.configure(enabled: false);
      }
      if (useNativeIosAudioPlayer) {
        _nativeIosAudioPlayerActive = false;
        await IosNativeAudioPlayback.instance.stop();
      }
      await _disposeLoadingPlayer(loadingPlayer, loadingSubscriptions);
      _clearPublishedLoadingPlayer(
        loadingPlayer,
        loadingPlayerPublished,
        generation,
      );
      await _clearFailedSystemTransition(keepSystemSessionActive, generation);
      _setPlayerError(
        error.message,
        generation,
        details: error.technicalDetails,
      );
    } on TimeoutException catch (error, stackTrace) {
      AppLog.instance.error(
        'player.load.timed_out',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      if (useNativeAndroidMedia3Player) {
        _nativeAndroidMedia3PlayerActive = false;
        await AndroidMedia3VideoPlayer.instance.stop();
      }
      if (useNativeAndroidMedia3AudioPlayer) {
        _nativeAndroidMedia3AudioPlayerActive = false;
        await AndroidMedia3AudioPlayback.instance.stop();
        await SystemMediaControls.instance.clear();
      }
      if (useNativeIosMainPlayer) {
        _nativeIosMainPlayerActive = false;
        await IosPictureInPicture.instance.configure(enabled: false);
      }
      if (useNativeIosAudioPlayer) {
        _nativeIosAudioPlayerActive = false;
        await IosNativeAudioPlayback.instance.stop();
      }
      await _disposeLoadingPlayer(loadingPlayer, loadingSubscriptions);
      _clearPublishedLoadingPlayer(
        loadingPlayer,
        loadingPlayerPublished,
        generation,
      );
      await _clearFailedSystemTransition(keepSystemSessionActive, generation);
      _setPlayerError(
        l10n.videoLoadTimeout,
        generation,
        details: '$error\n\n$stackTrace',
      );
    } on Exception catch (error, stackTrace) {
      AppLog.instance.error(
        'player.load.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      if (useNativeAndroidMedia3Player) {
        _nativeAndroidMedia3PlayerActive = false;
        await AndroidMedia3VideoPlayer.instance.stop();
      }
      if (useNativeAndroidMedia3AudioPlayer) {
        _nativeAndroidMedia3AudioPlayerActive = false;
        await AndroidMedia3AudioPlayback.instance.stop();
        await SystemMediaControls.instance.clear();
      }
      if (useNativeIosMainPlayer) {
        _nativeIosMainPlayerActive = false;
        await IosPictureInPicture.instance.configure(enabled: false);
      }
      if (useNativeIosAudioPlayer) {
        _nativeIosAudioPlayerActive = false;
        await IosNativeAudioPlayback.instance.stop();
      }
      await _disposeLoadingPlayer(loadingPlayer, loadingSubscriptions);
      _clearPublishedLoadingPlayer(
        loadingPlayer,
        loadingPlayerPublished,
        generation,
      );
      await _clearFailedSystemTransition(keepSystemSessionActive, generation);
      _setPlayerError(
        l10n.videoPlaybackFailed,
        generation,
        details: '${error.runtimeType}: $error\n\n$stackTrace',
      );
    }
  }

  void _clearPublishedLoadingPlayer(
    Player? player,
    bool wasPublished,
    int generation,
  ) {
    if (!wasPublished ||
        !mounted ||
        generation != _loadGeneration ||
        !identical(_player, player)) {
      return;
    }
    setState(() {
      _player = null;
      _videoController = null;
      _playerSubscriptions = const [];
      _playback = null;
      _selectedQuality = null;
    });
  }

  Future<void> _loadNativeAndroidMedia3Playback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required int generation,
    required Duration initialPosition,
    required bool play,
    required bool prepareBackgroundFeatures,
    required AppLocalizations l10n,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final initialQuality = initialPlayback.defaultQuality;
    final opened = await _openAndroidMedia3WithLazyFallback(
      initialPlayback,
      video: video,
      position: initialPosition,
      play: play,
      playbackFailedMessage: l10n.videoPlaybackFailed,
    );
    if (!context.mounted || generation != _loadGeneration) {
      await AndroidMedia3VideoPlayer.instance.stop();
      return;
    }
    final playbackBlocked = _backgroundPlaybackStartsBlocked;
    if (playbackBlocked) {
      await AndroidMedia3VideoPlayer.instance.pause();
    }
    setState(() {
      _nativeAndroidMedia3PlayerActive = true;
      _loadedPlayerVideoId = video.id;
      _visitPlaybackHistory(video);
      _playback = opened.playback;
      _selectedQuality = opened.quality;
      _isLoadingVideo = false;
    });
    _playbackAheadSuspended = !prepareBackgroundFeatures || playbackBlocked;
    unawaited(_loadDeferredSubtitles(video.id, generation));
    _showControls();
    if (opened.usedFallback) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.playbackFallback(
              initialQuality.label,
              opened.playback.manifestSource.label,
              opened.quality.label,
            ),
          ),
        ),
      );
    }
  }

  Future<_OpenedPlayback> _openAndroidMedia3WithLazyFallback(
    ResolvedVideoPlayback initialPlayback, {
    required YouTubeVideo video,
    required Duration position,
    required bool play,
    required String playbackFailedMessage,
  }) async {
    var playback = initialPlayback;
    var quality = playback.defaultQuality;
    var localFallbackTried = false;
    var usedFallback = false;
    while (true) {
      try {
        await _openAndroidMedia3Quality(
          quality,
          video: video,
          isLive: playback.isLive,
          position: position,
          play: play,
        );
        return _OpenedPlayback(
          playback: playback,
          quality: quality,
          usedFallback: usedFallback,
        );
      } on Exception catch (error, stackTrace) {
        final localFallback = playback.fallbackQuality;
        if (!localFallbackTried &&
            localFallback != null &&
            !identical(localFallback, quality)) {
          await AndroidMedia3VideoPlayer.instance.stop();
          quality = localFallback;
          localFallbackTried = true;
          usedFallback = true;
          continue;
        }
        final fallbackLoader = playback.fallbackLoader;
        if (fallbackLoader != null) {
          await AndroidMedia3VideoPlayer.instance.stop();
          playback = await fallbackLoader();
          quality = playback.defaultQuality;
          localFallbackTried = false;
          usedFallback = true;
          continue;
        }
        throw VideoPlaybackException(
          playbackFailedMessage,
          cause:
              'Transport: Android Media3 ExoPlayer\n'
              '${error.runtimeType}: $error',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _openAndroidMedia3Quality(
    VideoQualityOption quality, {
    required YouTubeVideo video,
    required bool isLive,
    required Duration position,
    required bool play,
  }) async {
    _streamProxy.clearLastError();
    final hlsMasterPlaylist = quality.hlsMasterPlaylist;
    final useSegmentedProxy =
        (quality.audioUrl != null || quality.requiresSegmentedProxy) &&
        _streamProxy.isSupported;
    final playableVideoUrl = hlsMasterPlaylist != null
        ? await _streamProxy.registerText(hlsMasterPlaylist)
        : useSegmentedProxy
        ? await _streamProxy.register(quality.videoUrl)
        : quality.videoUrl;
    final playableAudioUrl = quality.audioUrl == null
        ? null
        : useSegmentedProxy
        ? await _streamProxy.register(quality.audioUrl!)
        : quality.audioUrl;
    final directNetworkSource = hlsMasterPlaylist != null || !useSegmentedProxy;
    await AndroidMedia3VideoPlayer.instance.load(
      videoUrl: playableVideoUrl,
      audioUrl: playableAudioUrl,
      isHls: quality.isHls,
      headers: directNetworkSource ? _youtubeHeaders : const {},
      position: PlaybackSeekPolicy.mediaStart(
        isLive: isLive || video.isLive,
        position: position,
      ),
      play: play,
      volume: _volume * _systemAudioVolumeFactor,
      expectedDuration: quality.expectedDuration ?? video.duration,
    );
  }

  Future<void> _loadNativeAndroidMedia3AudioPlayback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required int generation,
    required Duration initialPosition,
    required bool play,
    required bool prepareBackgroundFeatures,
    required bool attachSystemControls,
    required AppLocalizations l10n,
  }) async {
    var playback = initialPlayback;
    var selectedQuality = playback.defaultQuality;
    final initialQuality = selectedQuality;
    _playbackState.value = const _PlaybackViewState(buffering: true);
    if (play || attachSystemControls) {
      await SystemMediaControls.instance.activatePlaybackSession();
    }

    final opened = await _openNativeAndroidMedia3AudioWithLazyFallback(
      video: video,
      initialPlayback: playback,
      position: initialPosition,
      play: play,
      playbackFailedMessage: l10n.videoPlaybackFailed,
    );
    playback = opened.playback;
    selectedQuality = opened.quality;
    if (!mounted || generation != _loadGeneration) return;

    final playbackBlocked = _backgroundPlaybackStartsBlocked;
    if (playbackBlocked) {
      await AndroidMedia3AudioPlayback.instance.pause();
    }
    setState(() {
      _nativeAndroidMedia3AudioPlayerActive = true;
      _loadedPlayerVideoId = video.id;
      _visitPlaybackHistory(video);
      _playback = playback;
      _selectedQuality = selectedQuality;
      _isLoadingVideo = false;
    });
    if (attachSystemControls && !playbackBlocked) {
      await _attachAndroidMedia3AudioSystemControls(video);
      _systemControlsDetachedForSleep = false;
    } else {
      _systemControlsDetachedForSleep = true;
    }
    final shouldPrepareBackgroundFeatures =
        prepareBackgroundFeatures && !playbackBlocked;
    _playbackAheadSuspended = !shouldPrepareBackgroundFeatures;
    if (shouldPrepareBackgroundFeatures) {
      _prepareNextQueuePlayback(generation);
    }
    _showControls();
    if (opened.usedFallback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.playbackFallback(
              initialQuality.label,
              playback.manifestSource.label,
              selectedQuality.label,
            ),
          ),
        ),
      );
    }
  }

  Future<_OpenedPlayback> _openNativeAndroidMedia3AudioWithLazyFallback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required Duration position,
    required bool play,
    required String playbackFailedMessage,
  }) async {
    var playback = initialPlayback;
    var quality = playback.defaultQuality;
    var localFallbackTried = false;
    var usedFallback = false;
    while (true) {
      try {
        final ready = await _openAndroidMedia3AudioQuality(
          quality,
          video: video,
          position: position,
          play: play,
        ).timeout(const Duration(seconds: 20));
        if (!ready) {
          throw StateError('Media3 konnte den Song nicht laden.');
        }
        return _OpenedPlayback(
          playback: playback,
          quality: quality,
          usedFallback: usedFallback,
        );
      } on Exception catch (error, stackTrace) {
        final localFallback = playback.fallbackQuality;
        if (!localFallbackTried &&
            localFallback != null &&
            !identical(localFallback, quality)) {
          quality = localFallback;
          localFallbackTried = true;
          usedFallback = true;
          continue;
        }
        final fallbackLoader = playback.fallbackLoader;
        if (fallbackLoader != null) {
          playback = await fallbackLoader();
          quality = playback.defaultQuality;
          localFallbackTried = false;
          usedFallback = true;
          continue;
        }
        throw VideoPlaybackException(
          playbackFailedMessage,
          cause:
              'Transport: Android Media3 ExoPlayer (Audio)\n'
              '${error.runtimeType}: $error',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<bool> _openAndroidMedia3AudioQuality(
    VideoQualityOption quality, {
    required YouTubeVideo video,
    required Duration position,
    required bool play,
  }) async {
    final streamUrl = await _registerAndroidMedia3AudioQuality(quality);
    return AndroidMedia3AudioPlayback.instance.open(
      streamUrl: streamUrl,
      headers: _youtubeHeaders,
      isHls: quality.isHls,
      volume: _volume * _systemAudioVolumeFactor,
      position: position,
      playing: play,
      expectedDuration: _canonicalAudioDuration(video, quality),
      crossfadeDuration: playlistAudioFadeDuration,
    );
  }

  Future<void> _loadNativeIosMainPlayback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required int generation,
    required Duration initialPosition,
    required bool play,
    required bool prepareBackgroundFeatures,
    required bool attachSystemControls,
    required AppLocalizations l10n,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    var playback = initialPlayback;
    var selectedQuality = playback.defaultQuality;
    final initialQuality = selectedQuality;
    setState(() {
      _nativeIosMainPlayerActive = true;
      _playback = playback;
      _selectedQuality = selectedQuality;
    });
    _playbackState.value = const _PlaybackViewState(buffering: true);

    // The UiKitView must own the AVPlayerLayer before AVPlayer and PiP are
    // configured. This guarantees that normal playback and PiP share exactly
    // one player, one item and one timeline.
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    final opened = await _openNativeIosPlaybackWithLazyFallback(
      video: video,
      initialPlayback: playback,
      position: initialPosition,
      play: play,
      playbackFailedMessage: l10n.videoPlaybackFailed,
    );
    playback = opened.playback;
    selectedQuality = opened.quality;
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _nativeIosMainPlayerActive = true;
      _loadedPlayerVideoId = video.id;
      _visitPlaybackHistory(video);
      _playback = playback;
      _selectedQuality = selectedQuality;
      _isLoadingVideo = false;
      _iosPictureInPictureReady = true;
      _iosPictureInPictureUsesHlsMaster =
          selectedQuality.hlsMasterPlaylist != null;
    });
    final playbackBlocked = _backgroundPlaybackStartsBlocked;
    if (video.isMusic && attachSystemControls && !playbackBlocked) {
      await _attachNativeIosMainSystemControls(video);
      _systemControlsDetachedForSleep = false;
    } else {
      _systemControlsDetachedForSleep = true;
    }
    final shouldPrepareBackgroundFeatures =
        prepareBackgroundFeatures && !playbackBlocked;
    _playbackAheadSuspended = !shouldPrepareBackgroundFeatures;
    unawaited(_loadDeferredSubtitles(video.id, generation));
    _showControls();
    if (opened.usedFallback) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.playbackFallback(
              initialQuality.label,
              playback.manifestSource.label,
              selectedQuality.label,
            ),
          ),
        ),
      );
    }
  }

  Future<_OpenedPlayback> _openNativeIosPlaybackWithLazyFallback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required Duration position,
    required bool play,
    required String playbackFailedMessage,
  }) async {
    var playback = initialPlayback;
    var quality =
        IosPipStreamPolicy.primaryQuality(playback, playback.defaultQuality) ??
        playback.defaultQuality;
    var localFallbackTried = false;
    var usedFallback = false;

    while (true) {
      try {
        final streamUrl = await _registerIosPictureInPictureQuality(quality);
        final ready = await IosPictureInPicture.instance
            .openMainPlayer(
              streamUrl: streamUrl,
              title: video.title,
              artist: video.channelTitle.isEmpty
                  ? _mediaArtist(video.description)
                  : video.channelTitle,
              thumbnailUrl: video.thumbnailUrl,
              playbackVolume: _volume * _systemAudioVolumeFactor,
              position: position,
              playing: play,
              autoEnterEnabled:
                  PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
                    pictureInPictureAllowed:
                        PlaybackBackgroundPolicy.allowsPictureInPicture(video),
                    playing: play,
                  ),
              pictureInPictureEnabled:
                  PlaybackBackgroundPolicy.allowsPictureInPicture(video),
              continuesAudioInBackground: video.isMusic,
              isLive: playback.isLive,
            )
            .timeout(const Duration(seconds: 20));
        if (!ready) {
          throw VideoPlaybackException(
            playbackFailedMessage,
            cause: 'Transport: nativer iOS AVPlayer (${quality.label})',
          );
        }
        return _OpenedPlayback(
          playback: playback,
          quality: quality,
          usedFallback: usedFallback,
        );
      } on Exception {
        final localFallback = playback.fallbackQuality;
        if (!localFallbackTried &&
            localFallback != null &&
            !identical(localFallback, quality)) {
          quality = localFallback;
          localFallbackTried = true;
          usedFallback = true;
          continue;
        }
        final fallbackLoader = playback.fallbackLoader;
        if (fallbackLoader == null) {
          rethrow;
        }
        playback = await fallbackLoader();
        quality =
            IosPipStreamPolicy.primaryQuality(
              playback,
              playback.defaultQuality,
            ) ??
            playback.defaultQuality;
        localFallbackTried = false;
        usedFallback = true;
      }
    }
  }

  Future<void> _loadNativeIosAudioPlayback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required int generation,
    required Duration initialPosition,
    required bool play,
    required bool prepareBackgroundFeatures,
    required bool attachSystemControls,
    required AppLocalizations l10n,
  }) async {
    var playback = initialPlayback;
    var selectedQuality = playback.defaultQuality;
    final initialQuality = selectedQuality;
    _playbackState.value = const _PlaybackViewState(buffering: true);
    await SystemMediaControls.instance.clear();
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    final opened = await _openNativeIosAudioWithLazyFallback(
      video: video,
      initialPlayback: playback,
      position: initialPosition,
      play: play,
      remoteControlsEnabled: attachSystemControls,
      playbackFailedMessage: l10n.videoPlaybackFailed,
    );
    playback = opened.playback;
    selectedQuality = opened.quality;
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _nativeIosAudioPlayerActive = true;
      _nativeIosMainPlayerActive = false;
      _loadedPlayerVideoId = video.id;
      _visitPlaybackHistory(video);
      _playback = playback;
      _selectedQuality = selectedQuality;
      _isLoadingVideo = false;
      _iosPictureInPictureReady = false;
      _iosPictureInPictureUsesHlsMaster = false;
    });
    _systemControlsDetachedForSleep = !attachSystemControls;
    await _updateIosNativeAudioNavigation();
    final shouldPrepareBackgroundFeatures =
        prepareBackgroundFeatures && !_backgroundPlaybackStartsBlocked;
    _playbackAheadSuspended = !shouldPrepareBackgroundFeatures;
    if (shouldPrepareBackgroundFeatures) {
      _prepareNextQueuePlayback(generation);
    }
    _showControls();
    if (opened.usedFallback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.playbackFallback(
              initialQuality.label,
              playback.manifestSource.label,
              selectedQuality.label,
            ),
          ),
        ),
      );
    }
  }

  Future<_OpenedPlayback> _openNativeIosAudioWithLazyFallback({
    required YouTubeVideo video,
    required ResolvedVideoPlayback initialPlayback,
    required Duration position,
    required bool play,
    required bool remoteControlsEnabled,
    required String playbackFailedMessage,
  }) async {
    var playback = initialPlayback;
    var quality = playback.defaultQuality;
    var localFallbackTried = false;
    var usedFallback = false;

    while (true) {
      try {
        final streamUrl = await _registerIosPictureInPictureQuality(quality);
        final ready = await IosNativeAudioPlayback.instance
            .open(
              streamUrl: streamUrl,
              title: video.title,
              artist: video.channelTitle.isEmpty
                  ? _mediaArtist(video.description)
                  : video.channelTitle,
              thumbnailUrl: video.thumbnailUrl,
              volume: _volume * _systemAudioVolumeFactor,
              position: position,
              playing: play,
              hasPrevious: _previousPlayedMedia != null,
              hasNext: _nextPlayerControlTarget != null,
              expectedDuration: _canonicalAudioDuration(video, quality),
              remoteControlsEnabled: remoteControlsEnabled,
              crossfadeDuration: playlistAudioFadeDuration,
            )
            .timeout(const Duration(seconds: 20));
        if (!ready) {
          throw VideoPlaybackException(
            playbackFailedMessage,
            cause: 'Transport: nativer iOS AVPlayer (Audio)',
          );
        }
        return _OpenedPlayback(
          playback: playback,
          quality: quality,
          usedFallback: usedFallback,
        );
      } on Exception {
        final localFallback = playback.fallbackQuality;
        if (!localFallbackTried &&
            localFallback != null &&
            !identical(localFallback, quality)) {
          quality = localFallback;
          localFallbackTried = true;
          usedFallback = true;
          continue;
        }
        final fallbackLoader = playback.fallbackLoader;
        if (fallbackLoader == null) {
          rethrow;
        }
        playback = await fallbackLoader();
        quality = playback.defaultQuality;
        localFallbackTried = false;
        usedFallback = true;
      }
    }
  }

  Future<void> _clearFailedSystemTransition(
    bool transitionActive,
    int generation,
  ) async {
    if (transitionActive && generation == _loadGeneration) {
      await SystemMediaControls.instance.clear();
    }
  }

  Future<void> _prepareIosPictureInPicture({
    required ResolvedVideoPlayback playback,
    required VideoQualityOption selectedQuality,
    required int generation,
  }) async {
    if (!_allowsPictureInPicture ||
        !IosPictureInPicture.instance.isSupportedPlatform) {
      return;
    }
    final quality = IosPipStreamPolicy.primaryQuality(
      playback,
      selectedQuality,
    );
    if (quality == null) {
      await IosPictureInPicture.instance.configure(enabled: false);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _iosPictureInPictureReady = false;
          _iosPictureInPictureUsesHlsMaster = false;
        });
      }
      return;
    }

    final usesHlsMaster = IosPipStreamPolicy.usesLocalHlsMaster(quality);
    final streamUrl = await _registerIosPictureInPictureQuality(quality);
    final ready = await IosPictureInPicture.instance.configure(
      enabled: true,
      streamUrl: streamUrl,
      title: _selectedVideo.title,
      artist: _selectedVideo.channelTitle.isEmpty
          ? _mediaArtist(_selectedVideo.description)
          : _selectedVideo.channelTitle,
      thumbnailUrl: _selectedVideo.thumbnailUrl,
      playbackVolume: _volume * _systemAudioVolumeFactor,
      playlistFadeEnabled: _queueTransitionUsesCrossfade,
      hasNextItem: _hasNextAutomaticItem,
      autoEnterEnabled:
          PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
            pictureInPictureAllowed: _allowsPictureInPicture,
            playing: _player?.state.playing ?? false,
          ),
      isLive: playback.isLive,
      debugResolution: quality.label,
      debugTransport: quality.transportLabel,
      debugIsHls: quality.isHls,
      debugHasHlsMaster: quality.hlsMasterPlaylist != null,
      debugHasSeparateAudio:
          quality.audioUrl != null || quality.hlsMasterPlaylist != null,
      debugUsesProxy:
          usesHlsMaster || (!quality.isHls && _streamProxy.isSupported),
      debugSourceScheme: quality.videoUrl.scheme,
      debugSourcePath: quality.videoUrl.path,
      debugMime: quality.videoUrl.queryParameters['mime'] ?? '',
      debugContentLength: int.tryParse(
        quality.videoUrl.queryParameters['clen'] ?? '',
      ),
    );
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _iosPictureInPictureReady = ready;
      _iosPictureInPictureUsesHlsMaster = ready && usesHlsMaster;
    });
  }

  Future<bool> _ensureIosPictureInPictureReady() async {
    if (!_allowsPictureInPicture) {
      return false;
    }
    final playback = _playback;
    final selectedQuality = _selectedQuality;
    if (playback == null || selectedQuality == null) {
      return false;
    }
    try {
      final resolvedPiP = await _resolvePictureInPicturePlayback(
        playback,
        selectedQuality: selectedQuality,
      );
      if (resolvedPiP == null || !mounted) {
        return false;
      }
      await _prepareIosPictureInPicture(
        playback: resolvedPiP.playback,
        selectedQuality: resolvedPiP.quality,
        generation: _loadGeneration,
      );
      return mounted && _iosPictureInPictureReady;
    } on Exception {
      return false;
    }
  }

  Future<({ResolvedVideoPlayback playback, VideoQualityOption quality})?>
  _resolvePictureInPicturePlayback(
    ResolvedVideoPlayback initialPlayback, {
    VideoQualityOption? selectedQuality,
  }) async {
    final quality = IosPipStreamPolicy.primaryQuality(
      initialPlayback,
      selectedQuality ?? initialPlayback.defaultQuality,
    );
    if (quality != null) {
      return (playback: initialPlayback, quality: quality);
    }
    return _resolveProgressivePictureInPictureFallback(initialPlayback);
  }

  Future<({ResolvedVideoPlayback playback, VideoQualityOption quality})?>
  _resolveProgressivePictureInPictureFallback(
    ResolvedVideoPlayback initialPlayback,
  ) => IosPipStreamPolicy.resolveProgressiveFallback(initialPlayback);

  Future<Uri> _registerIosPictureInPictureQuality(VideoQualityOption quality) {
    final hlsMasterPlaylist = quality.hlsMasterPlaylist;
    if (hlsMasterPlaylist != null) {
      return _streamProxy.registerText(hlsMasterPlaylist);
    }
    if (quality.isHls || !_streamProxy.isSupported) {
      return Future<Uri>.value(quality.videoUrl);
    }
    return _streamProxy.register(quality.videoUrl);
  }

  Future<Uri> _registerAndroidMedia3AudioQuality(VideoQualityOption quality) {
    final source = quality.audioUrl ?? quality.videoUrl;
    if (quality.isHls || !_streamProxy.isSupported) {
      return Future<Uri>.value(source);
    }
    return _streamProxy.register(source);
  }

  String _mediaArtist(String description) {
    if (!description.contains('•')) {
      return '';
    }
    return description.split('•').first.trim();
  }

  Duration? _canonicalAudioDuration(
    YouTubeVideo video,
    VideoQualityOption quality,
  ) => canonicalPlaybackDuration(
    streamDuration: quality.expectedDuration,
    catalogDuration:
        video.duration ?? mediaDurationFromDescription(video.description),
  );

  YouTubeVideo? get _previousPlayedMedia =>
      _playbackHistories.forMedia(_selectedVideo).previousFrom(_selectedVideo);

  YouTubeVideo? get _nextPlayedMedia => _nextPlayerControlTarget?.video;

  PlaybackNavigationTarget? get _nextPlayerControlTarget => nextPlaybackTarget(
    histories: _playbackHistories,
    current: _selectedVideo,
    queue: _playbackQueue,
  );

  PlaybackNavigationTarget? get _automaticNextTarget => _autoplayEnabled
      ? nextPlaybackTarget(
          histories: _playbackHistories,
          current: _selectedVideo,
          queue: _playbackQueue,
        )
      : null;

  void _visitPlaybackHistory(YouTubeVideo video) {
    _playbackHistories = _playbackHistories.visit(video);
  }

  void _applyNavigationTarget(PlaybackNavigationTarget target) {
    final historyStep = target.historyStep;
    if (historyStep != null) {
      _playbackHistories = _playbackHistories.replaceFor(
        target.video,
        historyStep.history,
      );
      _playbackQueue = _playbackQueue.selectVideo(target.video);
      return;
    }
    final queueIndex = target.queueIndex;
    if (queueIndex != null) {
      _playbackQueue = _playbackQueue.selectIndex(queueIndex);
    }
  }

  bool _hasNextAfterNavigationTarget(PlaybackNavigationTarget target) {
    var projectedHistories = _playbackHistories;
    var projectedQueue = _playbackQueue;
    final historyStep = target.historyStep;
    if (historyStep != null) {
      projectedHistories = projectedHistories.replaceFor(
        target.video,
        historyStep.history,
      );
      projectedQueue = projectedQueue.selectVideo(target.video);
    } else if (target.queueIndex case final queueIndex?) {
      projectedQueue = projectedQueue.selectIndex(queueIndex);
      projectedHistories = projectedHistories.visit(target.video);
    }
    return nextPlaybackTarget(
          histories: projectedHistories,
          current: target.video,
          queue: projectedQueue,
        ) !=
        null;
  }

  bool get _hasNextAutomaticItem => _automaticNextTarget != null;

  bool get _queueTransitionUsesCrossfade {
    final nextVideo = _automaticNextTarget?.video;
    return shouldUsePlaylistCrossfade(current: _selectedVideo, next: nextVideo);
  }

  bool get _hasPreparedAutomaticCrossfade {
    final target = _automaticNextTarget;
    final prepared = _preparedNextPlayback;
    return target != null &&
        prepared != null &&
        prepared.isReady &&
        prepared.target.matches(target) &&
        _queueTransitionUsesCrossfade;
  }

  Future<void> _applyEffectivePlayerVolume(
    Player player, {
    required Duration position,
    required Duration duration,
    bool force = false,
  }) async {
    final fadeFactor = playlistAudioFadeFactor(
      position: position,
      duration: duration,
      isPlaylistPlayback: _autoplayEnabled,
      hasNextItem: _hasNextAutomaticItem,
      fadeInEnabled: false,
      fadeOutEnabled: _hasPreparedAutomaticCrossfade,
    );
    final targetVolume = (_volume * _systemAudioVolumeFactor * fadeFactor * 100)
        .clamp(0.0, 100.0);
    final previousVolume = _lastAppliedPlayerVolume;
    if (!force &&
        previousVolume != null &&
        (previousVolume - targetVolume).abs() < 0.25) {
      return;
    }
    _lastAppliedPlayerVolume = targetVolume;
    await player.setVolume(targetVolume);
  }

  Future<void> _updateQueueCrossfade({
    required Player currentPlayer,
    required Duration position,
    required Duration duration,
    required int generation,
  }) async {
    if (_crossfadeUpdateInProgress ||
        generation != _loadGeneration ||
        _autoAdvanceInProgress ||
        !identical(_player, currentPlayer) ||
        !_hasNextAutomaticItem ||
        !_queueTransitionUsesCrossfade) {
      return;
    }
    final prepared = _preparedNextPlayback;
    final target = _automaticNextTarget;
    if (prepared == null ||
        !prepared.isReady ||
        !prepared.target.matches(target)) {
      return;
    }

    _crossfadeUpdateInProgress = true;
    final updateCompletion = Completer<void>();
    final updateFuture = updateCompletion.future;
    _crossfadeUpdateCompletion = updateFuture;
    try {
      final incomingFactor = playlistCrossfadeIncomingFactor(
        position: position,
        duration: duration,
      );
      if (incomingFactor <= 0) {
        if (_crossfadeStarted) {
          await _resetActiveCrossfade(rewindIncoming: true);
        }
        return;
      }

      final incomingVolume =
          (_volume * _systemAudioVolumeFactor * incomingFactor * 100).clamp(
            0.0,
            100.0,
          );
      if (!_crossfadeStarted) {
        final fadeSpanMicros = math.min(
          playlistAudioFadeDuration.inMicroseconds,
          math.max(1, duration.inMicroseconds ~/ 2),
        );
        final incomingPosition = Duration(
          microseconds: (fadeSpanMicros * incomingFactor).round(),
        );
        await prepared.player.seek(incomingPosition);
        if (!_isActiveQueueCrossfade(
          prepared: prepared,
          currentPlayer: currentPlayer,
          generation: generation,
        )) {
          return;
        }
        await prepared.player.setVolume(incomingVolume);
        if (!_isActiveQueueCrossfade(
          prepared: prepared,
          currentPlayer: currentPlayer,
          generation: generation,
        )) {
          return;
        }
        _lastAppliedIncomingVolume = incomingVolume;
        _crossfadeStarted = true;
        AppLog.instance.info(
          'crossfade.started',
          fields: {
            'fromMediaId': _selectedVideo.id,
            'toMediaId': prepared.video.id,
            'positionMs': position.inMilliseconds,
            'durationMs': duration.inMilliseconds,
            'fadeMs': playlistAudioFadeDuration.inMilliseconds,
          },
        );
        await _setSystemMediaSecondaryPlayer(prepared.player);
      } else if (_lastAppliedIncomingVolume == null ||
          (_lastAppliedIncomingVolume! - incomingVolume).abs() >= 0.25) {
        _lastAppliedIncomingVolume = incomingVolume;
        await prepared.player.setVolume(incomingVolume);
      }

      if (!_isActiveQueueCrossfade(
        prepared: prepared,
        currentPlayer: currentPlayer,
        generation: generation,
      )) {
        return;
      }
      if (shouldStartIncomingCrossfade(
        outgoingPlaying: currentPlayer.state.playing,
        incomingPlaying: prepared.player.state.playing,
      )) {
        await prepared.player.play();
      }
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'crossfade.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'fromMediaId': _selectedVideo.id,
          'toMediaId': prepared.video.id,
        },
      );
      await _resetActiveCrossfade(rewindIncoming: false);
      await _disposePreparedNextPlayback();
    } finally {
      _crossfadeUpdateInProgress = false;
      if (!updateCompletion.isCompleted) {
        updateCompletion.complete();
      }
      if (identical(_crossfadeUpdateCompletion, updateFuture)) {
        _crossfadeUpdateCompletion = null;
      }
    }
  }

  Future<void> _waitForCrossfadeUpdateToSettle() async {
    final update = _crossfadeUpdateCompletion;
    if (update != null) {
      await update;
    }
  }

  bool _isActiveQueueCrossfade({
    required _PreparedQueuePlayback prepared,
    required Player currentPlayer,
    required int generation,
  }) {
    return mounted &&
        generation == _loadGeneration &&
        identical(_player, currentPlayer) &&
        identical(_preparedNextPlayback, prepared);
  }

  Future<void> _resetActiveCrossfade({required bool rewindIncoming}) async {
    final prepared = _preparedNextPlayback;
    _crossfadeStarted = false;
    _lastAppliedIncomingVolume = null;
    await SystemMediaControls.instance.setSecondaryPlayer(null);
    if (prepared == null) {
      return;
    }
    await prepared.player.pause();
    await prepared.player.setVolume(0);
    if (rewindIncoming &&
        PlaybackSeekPolicy.canSeek(isLive: prepared.playback.isLive)) {
      await prepared.player.seek(Duration.zero);
    }
  }

  List<StreamSubscription<dynamic>> _createPlayerSubscriptions(
    Player player,
    int generation,
  ) {
    void update(
      _PlaybackViewState Function(_PlaybackViewState) transform, {
      bool syncPictureInPicture = false,
    }) {
      if (mounted && generation == _loadGeneration) {
        _playbackState.value = transform(_playbackState.value);
        if (syncPictureInPicture) {
          _syncPictureInPictureConfiguration();
        }
      }
    }

    return <StreamSubscription<dynamic>>[
      player.stream.position.listen((position) {
        final duration = _playbackState.value.duration;
        update((state) => state.copyWith(position: position));
        if (generation == _loadGeneration) {
          unawaited(
            _applyEffectivePlayerVolume(
              player,
              position: position,
              duration: duration,
            ),
          );
          unawaited(
            _updateQueueCrossfade(
              currentPlayer: player,
              position: position,
              duration: duration,
              generation: generation,
            ),
          );
        }
      }),
      player.stream.duration.listen((duration) {
        final position = _playbackState.value.position;
        update((state) => state.copyWith(duration: duration));
        if (generation == _loadGeneration) {
          unawaited(
            _applyEffectivePlayerVolume(
              player,
              position: position,
              duration: duration,
            ),
          );
        }
      }),
      player.stream.playing.listen((playing) {
        update(
          (state) => state.copyWith(playing: playing),
          syncPictureInPicture: true,
        );
        _handlePlaybackStateForSleep();
      }),
      player.stream.buffering.listen((buffering) {
        _recordBufferingTransition(
          wasBuffering: _playbackState.value.buffering,
          buffering: buffering,
          position: _playbackState.value.position,
        );
        update((state) => state.copyWith(buffering: buffering));
      }),
      player.stream.width.listen(
        (width) => update(
          (state) => state.copyWith(width: width),
          syncPictureInPicture: true,
        ),
      ),
      player.stream.height.listen(
        (height) => update(
          (state) => state.copyWith(height: height),
          syncPictureInPicture: true,
        ),
      ),
      player.stream.completed.listen((completed) {
        if (completed) {
          unawaited(_playNextQueueItem(generation));
        }
      }),
    ];
  }

  Future<void> _playNextQueueItem(int generation) async {
    if (!mounted ||
        !_autoplayEnabled ||
        generation != _loadGeneration ||
        _autoAdvanceInProgress ||
        _backgroundPlaybackStartsBlocked) {
      return;
    }
    final target = _automaticNextTarget;
    if (target == null) {
      return;
    }
    await _playNavigationTarget(
      target,
      expectedGeneration: generation,
      automatic: true,
    );
  }

  Future<void> _playPreviousHistoryItemFromSystem() async {
    final target = previousPlaybackTarget(
      histories: _playbackHistories,
      current: _selectedVideo,
    );
    if (target != null && target.video.isMusic) {
      await _playNavigationTarget(target);
    }
  }

  Future<void> _playNextItemFromSystem() async {
    if (!_selectedVideo.isMusic) {
      return;
    }
    final target = nextPlaybackTarget(
      histories: _playbackHistories,
      current: _selectedVideo,
      queue: _playbackQueue,
      musicOnlyQueue: true,
    );
    if (target != null && target.video.isMusic) {
      await _playNavigationTarget(target);
    }
  }

  Future<void> _playPreviousHistoryItemFromPlayer() async {
    final target = previousPlaybackTarget(
      histories: _playbackHistories,
      current: _selectedVideo,
    );
    if (target != null) {
      await _playNavigationTarget(target);
    }
  }

  Future<void> _playNextItemFromPlayer() async {
    final target = _nextPlayerControlTarget;
    if (target != null) {
      await _playNavigationTarget(target);
    }
  }

  Future<void> _playNavigationTarget(
    PlaybackNavigationTarget target, {
    int? expectedGeneration,
    bool automatic = false,
  }) async {
    final generation = expectedGeneration ?? _loadGeneration;
    final previousVideo = _selectedVideo;
    final targetVideo = target.video;
    if (!mounted ||
        generation != _loadGeneration ||
        _autoAdvanceInProgress ||
        _backgroundPlaybackStartsBlocked) {
      return;
    }

    _autoAdvanceInProgress = true;
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'queue.navigation.started',
      fields: {
        ..._mediaLogFields(targetVideo),
        'automatic': automatic,
        'navigationSource': target.source.name,
        'fromMediaId': previousVideo.id,
      },
    );
    _playlistPreparationGate.cancel();
    final originalHistories = _playbackHistories;
    final originalQueue = _playbackQueue;
    try {
      await _waitForCrossfadeUpdateToSettle();
      if (!automatic && _crossfadeStarted) {
        await _resetActiveCrossfade(rewindIncoming: true);
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final prepared = _preparedNextPlayback;
      final canPromote =
          prepared != null &&
          prepared.isReady &&
          prepared.target.matches(target) &&
          !_shouldUseNativeAndroidMedia3Player(targetVideo) &&
          !_shouldUseNativeAndroidMedia3AudioPlayer(targetVideo) &&
          !_shouldUseNativeIosMainPlayer(targetVideo) &&
          !_shouldUseNativeIosAudioPlayer(targetVideo);
      final useAudioDoubleBuffer = shouldUseAudioQueueDoubleBuffer(
        current: previousVideo,
        next: targetVideo,
        automatic: automatic,
        prepared: canPromote,
      );
      if (!canPromote) {
        await _disposePreparedNextPlayback();
      }
      _applyNavigationTarget(target);
      setState(() {
        _synchronizeSearchModeWithMedia(targetVideo);
        _selectedVideo = targetVideo;
      });
      if (canPromote) {
        await _promotePreparedQueuePlayback(
          prepared,
          generation: generation,
          useAudioDoubleBuffer: useAudioDoubleBuffer,
        );
      } else {
        await _switchQueueMediaOnCurrentPlayer(
          targetVideo,
          generation: generation,
        );
      }

      final stillSelected =
          mounted &&
          _selectedVideo.id == targetVideo.id &&
          _selectedVideo.isMusic == targetVideo.isMusic;
      final targetWasActivated =
          stillSelected &&
          _loadedPlayerVideoId == targetVideo.id &&
          _playerError == null;
      if (stillSelected && !targetWasActivated) {
        setState(() {
          _playbackHistories = originalHistories;
          _playbackQueue = originalQueue;
        });
      }
      if (targetWasActivated) {
        AppLog.instance.info(
          'queue.navigation.succeeded',
          fields: {
            ..._mediaLogFields(targetVideo),
            'automatic': automatic,
            'navigationSource': target.source.name,
            'durationMs': stopwatch.elapsedMilliseconds,
            'preparedPromoted': canPromote,
            'audioDoubleBuffer': useAudioDoubleBuffer,
          },
        );
      } else {
        AppLog.instance.warning(
          'queue.navigation.not_activated',
          fields: {
            ..._mediaLogFields(targetVideo),
            'automatic': automatic,
            'durationMs': stopwatch.elapsedMilliseconds,
          },
        );
      }
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'queue.navigation.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          ..._mediaLogFields(targetVideo),
          'automatic': automatic,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      rethrow;
    } finally {
      _autoAdvanceInProgress = false;
    }
  }

  Future<void> _promotePreparedQueuePlayback(
    _PreparedQueuePlayback prepared, {
    required int generation,
    required bool useAudioDoubleBuffer,
  }) async {
    if (_backgroundPlaybackStartsBlocked) {
      if (identical(_preparedNextPlayback, prepared)) {
        _preparedNextPlayback = null;
      }
      _cancelPreparedMediaKitPlayer(prepared.player);
      await prepared.player.pause();
      await _disposePreparedMediaKitPlayerOnce(prepared.player);
      return;
    }
    final previousPlayer = _player;
    if (previousPlayer == null ||
        !identical(_preparedNextPlayback, prepared) ||
        generation != _loadGeneration) {
      if (identical(_preparedNextPlayback, prepared)) {
        _preparedNextPlayback = null;
        await _disposePreparedMediaKitPlayerOnce(prepared.player);
      }
      await _switchQueueMediaOnCurrentPlayer(
        prepared.video,
        generation: generation,
      );
      return;
    }

    if (!prepared.player.state.playing) {
      await prepared.player.play();
    }
    if (useAudioDoubleBuffer) {
      if (!_crossfadeStarted) {
        await _setSystemMediaSecondaryPlayer(prepared.player);
      }
    } else {
      await _beginSystemMediaTransition(previousPlayer, prepared.video);
    }
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _preparedNextPlayback = null;
    _crossfadeStarted = false;
    _lastAppliedIncomingVolume = null;
    _lastAppliedPlayerVolume = null;
    if (!useAudioDoubleBuffer) {
      await SystemMediaControls.instance.setSecondaryPlayer(null);
    }

    final previousState = _playbackState.value;
    final promotedState = _PlaybackViewState(
      position: prepared.player.state.position,
      duration: prepared.player.state.duration,
      playing: prepared.player.state.playing,
      buffering: prepared.player.state.buffering,
      width: previousState.width,
      height: previousState.height,
    );
    final subscriptions = _createPlayerSubscriptions(
      prepared.player,
      generation,
    );
    if (!mounted || generation != _loadGeneration) {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await _disposePreparedMediaKitPlayerOnce(prepared.player);
      return;
    }

    setState(() {
      _player = prepared.player;
      _loadedPlayerVideoId = prepared.video.id;
      _visitPlaybackHistory(prepared.video);
      _videoController = prepared.videoController;
      _playerSubscriptions = subscriptions;
      _playback = prepared.playback;
      _selectedQuality = prepared.selectedQuality;
      _playerError = null;
      _playerErrorDetails = null;
      _isLoadingVideo = false;
      _isChangingQuality = false;
      _iosPictureInPictureReady = false;
      _iosPictureInPictureUsesHlsMaster = false;
    });
    _playbackState.value = promotedState;
    if (PlaybackBackgroundPolicy.requiresPlayerSurface(prepared.video)) {
      await _resumePlayerAfterSurfaceAttach(prepared.player, generation);
    }
    if (useAudioDoubleBuffer) {
      await _promoteSystemMediaControls(
        previousPlayer: previousPlayer,
        promotedPlayer: prepared.player,
        video: prepared.video,
      );
    } else {
      await _attachSystemMediaControls(prepared.player, prepared.video);
    }
    await _applyEffectivePlayerVolume(
      prepared.player,
      position: promotedState.position,
      duration: promotedState.duration,
      force: true,
    );
    if (useAudioDoubleBuffer) {
      final displacedStandby = _crossfadeStandbyPlayer;
      _crossfadeStandbyPlayer = previousPlayer;
      if (displacedStandby != null &&
          !identical(displacedStandby, previousPlayer)) {
        unawaited(_disposePreparedMediaKitPlayerOnce(displacedStandby));
      }
    } else {
      await previousPlayer.dispose();
    }
    if (!prepared.player.state.playing) {
      await prepared.player.play();
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    if (useAudioDoubleBuffer) {
      _prepareNextQueuePlaybackAfterAudioHandoff(prepared.player, generation);
    } else {
      _prepareNextQueuePlayback(generation);
    }
    unawaited(_loadDeferredSubtitles(prepared.video.id, generation));
    unawaited(
      _prepareIosPictureInPicture(
        playback: prepared.playback,
        selectedQuality: prepared.selectedQuality,
        generation: generation,
      ),
    );
    _showControls();
  }

  void _prepareNextQueuePlaybackAfterAudioHandoff(
    Player promotedPlayer,
    int generation,
  ) {
    final handoffPosition = promotedPlayer.state.position;
    unawaited(() async {
      try {
        await promotedPlayer.stream.position.firstWhere(
          (position) =>
              position >= handoffPosition + const Duration(milliseconds: 200),
        );
      } on Object {
        return;
      }
      if (!mounted ||
          generation != _loadGeneration ||
          !identical(_player, promotedPlayer) ||
          _backgroundPlaybackStartsBlocked) {
        return;
      }
      _prepareNextQueuePlayback(generation);
    }());
  }

  Future<void> _resumePlayerAfterSurfaceAttach(
    Player player,
    int generation,
  ) async {
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {},
    );
    if (!mounted ||
        generation != _loadGeneration ||
        !identical(_player, player)) {
      return;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final startPosition = player.state.position;
      final advanced = Completer<void>();
      final subscription = player.stream.position.listen((position) {
        if (position >= startPosition + const Duration(milliseconds: 80) &&
            !advanced.isCompleted) {
          advanced.complete();
        }
      });
      try {
        await player.play();
        await advanced.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } finally {
        await subscription.cancel();
      }
      if (advanced.isCompleted ||
          !mounted ||
          generation != _loadGeneration ||
          !identical(_player, player)) {
        return;
      }
      if (!PlaybackSeekPolicy.canSeek(isLive: _isLivePlayback)) {
        return;
      }
      await player.pause();
      await player.seek(startPosition);
    }
  }

  Future<void> _switchQueueMediaOnCurrentPlayer(
    YouTubeVideo video, {
    required int generation,
  }) async {
    final l10n = context.l10n;
    if (_backgroundPlaybackStartsBlocked) {
      return;
    }
    final activeBackend = _activePlaybackBackend;
    final requiredBackend = _requiredPlaybackBackend(video);
    if (activeBackend != requiredBackend) {
      AppLog.instance.info(
        'player.backend.transition_required',
        fields: {
          ..._mediaLogFields(video),
          'fromBackend': activeBackend?.name ?? 'none',
          'toBackend': requiredBackend.name,
          'previousMediaId': _loadedPlayerVideoId,
        },
      );
      await _loadVideo(
        video,
        keepSystemSessionActive:
            PlaybackBackgroundPolicy.usesSystemMediaControls(video),
      );
      return;
    }
    final player = _player;
    if (player == null) {
      await _loadVideo(video, keepSystemSessionActive: true);
      return;
    }

    _seekHoldTimer?.cancel();
    _gestureFeedbackController.clear();
    await _beginSystemMediaTransition(player, video);
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    final requiresPlayerSurface =
        PlaybackBackgroundPolicy.requiresPlayerSurface(video);
    if (requiresPlayerSurface && _videoController == null) {
      final videoController = VideoController(player);
      setState(() => _videoController = videoController);
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
    } else if (!requiresPlayerSurface && _videoController != null) {
      setState(() => _videoController = null);
    }

    final previousViewState = _playbackState.value;
    setState(() {
      _playback = null;
      _selectedQuality = null;
      _playerError = null;
      _playerErrorDetails = null;
      _isLoadingVideo = true;
      _isChangingQuality = false;
      _iosPictureInPictureReady = false;
      _iosPictureInPictureUsesHlsMaster = false;
      _dragPosition = null;
      _controlsVisible = true;
      _settingsVisible = false;
    });
    _playbackState.value = _PlaybackViewState(
      buffering: true,
      width: previousViewState.width,
      height: previousViewState.height,
    );
    _syncPictureInPictureConfiguration();

    try {
      var playback = await _resolvePlayback(video);
      if (!mounted ||
          generation != _loadGeneration ||
          _backgroundPlaybackStartsBlocked) {
        return;
      }

      final initialQuality = playback.defaultQuality;
      final opened = await _openPlaybackWithLazyFallback(
        player,
        playback,
        position: Duration.zero,
        play: true,
      );
      playback = opened.playback;
      final selectedQuality = opened.quality;
      final fallbackMessage = opened.usedFallback
          ? l10n.playbackFallback(
              initialQuality.label,
              playback.manifestSource.label,
              selectedQuality.label,
            )
          : null;
      if (!mounted ||
          generation != _loadGeneration ||
          _backgroundPlaybackStartsBlocked) {
        await player.pause();
        if (mounted) {
          setState(() => _isLoadingVideo = false);
        }
        return;
      }

      setState(() {
        _loadedPlayerVideoId = video.id;
        _visitPlaybackHistory(video);
        _playback = playback;
        _selectedQuality = selectedQuality;
        _isLoadingVideo = false;
      });
      await _attachSystemMediaControls(player, video);
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      _prepareNextQueuePlayback(generation);
      unawaited(_loadDeferredSubtitles(video.id, generation));
      unawaited(
        _prepareIosPictureInPicture(
          playback: playback,
          selectedQuality: selectedQuality,
          generation: generation,
        ),
      );
      _showControls();
      if (fallbackMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(fallbackMessage)));
      }
    } on VideoPlaybackException catch (error) {
      await SystemMediaControls.instance.clear();
      _setPlayerError(
        error.message,
        generation,
        details: error.technicalDetails,
      );
    } on TimeoutException catch (error, stackTrace) {
      await SystemMediaControls.instance.clear();
      _setPlayerError(
        l10n.nextQueueLoadTimeout,
        generation,
        details: '$error\n\n$stackTrace',
      );
    } on Exception catch (error, stackTrace) {
      await SystemMediaControls.instance.clear();
      _setPlayerError(
        l10n.nextQueuePlaybackFailed,
        generation,
        details: '${error.runtimeType}: $error\n\n$stackTrace',
      );
    }
  }

  Future<void> _disposeLoadingPlayer(
    Player? player,
    List<StreamSubscription<dynamic>> subscriptions,
  ) async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player?.dispose();
  }

  Future<_OpenedPlayback> _openPlaybackWithLazyFallback(
    Player player,
    ResolvedVideoPlayback initialPlayback, {
    required Duration position,
    required bool play,
    double? volumeOverride,
  }) async {
    var playback = initialPlayback;
    var quality = playback.defaultQuality;
    var localFallbackTried = false;
    var usedFallback = false;

    while (true) {
      try {
        await _openQuality(
          player,
          quality,
          isLive: playback.isLive,
          position: position,
          play: play,
          volumeOverride: volumeOverride,
        ).timeout(const Duration(seconds: 20));
        return _OpenedPlayback(
          playback: playback,
          quality: quality,
          usedFallback: usedFallback,
        );
      } on Exception catch (error, stackTrace) {
        final details = error is VideoPlaybackException
            ? error.technicalDetails
            : error.toString();
        if (playback.isLive &&
            PlaybackSeekPolicy.isNonSeekableStreamError(details)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        final localFallback = playback.fallbackQuality;
        if (!localFallbackTried &&
            localFallback != null &&
            !identical(localFallback, quality)) {
          await player.stop();
          quality = localFallback;
          localFallbackTried = true;
          usedFallback = true;
          continue;
        }

        final fallbackLoader = playback.fallbackLoader;
        if (fallbackLoader == null) {
          rethrow;
        }
        await player.stop();
        playback = await fallbackLoader();
        quality = playback.defaultQuality;
        localFallbackTried = false;
        usedFallback = true;
      }
    }
  }

  Future<void> _openQuality(
    Player player,
    VideoQualityOption quality, {
    required bool isLive,
    required Duration position,
    required bool play,
    double? volumeOverride,
  }) async {
    _streamProxy.clearLastError();
    final hlsMasterPlaylist = quality.hlsMasterPlaylist;
    final useSegmentedProxy =
        (quality.audioUrl != null || quality.requiresSegmentedProxy) &&
        _streamProxy.isSupported;
    final playableVideoUrl = hlsMasterPlaylist != null
        ? await _streamProxy.registerText(hlsMasterPlaylist)
        : useSegmentedProxy
        ? await _streamProxy.register(quality.videoUrl)
        : quality.videoUrl;
    final playableAudioUrl = quality.audioUrl == null
        ? null
        : useSegmentedProxy
        ? await _streamProxy.register(quality.audioUrl!)
        : quality.audioUrl;
    final audioLoadedWithMedia = await _configureExternalAudioForNextOpen(
      player,
      playableAudioUrl,
      nativePlayback: _streamProxy.isSupported,
    );
    final ready = Completer<void>();
    var acceptEvents = false;
    var videoReady = false;
    var audioReady = !audioLoadedWithMedia && hlsMasterPlaylist == null;
    String? playbackError;
    void completeWhenReady() {
      if (acceptEvents && videoReady && audioReady && !ready.isCompleted) {
        ready.complete();
      }
    }

    final readinessSubscriptions = <StreamSubscription<dynamic>>[
      player.stream.duration.listen((duration) {
        if (acceptEvents && duration > Duration.zero) {
          videoReady = true;
          completeWhenReady();
        }
      }),
      player.stream.width.listen((width) {
        if (acceptEvents && width != null && width > 0) {
          videoReady = true;
          completeWhenReady();
        }
      }),
      player.stream.tracks.listen((tracks) {
        if (acceptEvents && tracks.audio.isNotEmpty) {
          audioReady = true;
          completeWhenReady();
        }
      }),
      player.stream.error.listen((error) {
        if (acceptEvents) {
          playbackError = error;
          if (!ready.isCompleted) {
            ready.complete();
          }
        }
      }),
    ];

    try {
      final startImmediately =
          play &&
          position == Duration.zero &&
          playableAudioUrl == null &&
          hlsMasterPlaylist == null;
      if (volumeOverride case final volume?) {
        await player.setVolume(volume.clamp(0.0, 1.0) * 100);
      } else {
        await _applyEffectivePlayerVolume(
          player,
          position: position,
          duration: _playbackState.value.duration,
          force: true,
        );
      }
      acceptEvents = true;
      await player.open(
        Media(
          playableVideoUrl.toString(),
          start: PlaybackSeekPolicy.mediaStart(
            isLive: isLive,
            position: position,
          ),
          httpHeaders: useSegmentedProxy
              ? const {}
              : quality.isHls
              ? _safariHlsHeaders
              : _youtubeHeaders,
        ),
        play: startImmediately,
      );
      if (playbackError != null) {
        throw _streamRejected(
          'Der Videostream wurde abgelehnt',
          playbackError,
          quality,
        );
      }

      // MediaKit bestätigt open(), bevor MPV die Spuren vollständig
      // eingelesen hat. Der Start wartet deshalb auf echte Mediendaten.
      await ready.future.timeout(const Duration(seconds: 12));
      if (playbackError != null) {
        throw _streamRejected(
          'Der Videostream wurde abgelehnt',
          playbackError,
          quality,
        );
      }
      if (!audioLoadedWithMedia && playableAudioUrl != null) {
        await player.setAudioTrack(
          AudioTrack.uri(playableAudioUrl.toString(), title: 'YouTube Audio'),
        );
      }
      if (playbackError != null) {
        throw _streamRejected(
          'Die Audiospur wurde abgelehnt',
          playbackError,
          quality,
        );
      }
      if (PlaybackSeekPolicy.shouldSeekAfterOpen(
        isLive: isLive,
        position: position,
        startedImmediately: startImmediately,
      )) {
        await player.seek(position);
      }
      if (play && !startImmediately) {
        await player.play();
      }
      if (playbackError != null) {
        throw _streamRejected(
          'Der Videostream wurde abgelehnt',
          playbackError,
          quality,
        );
      }
    } finally {
      for (final subscription in readinessSubscriptions) {
        await subscription.cancel();
      }
    }
  }

  VideoPlaybackException _streamRejected(
    String message,
    String? playerError,
    VideoQualityOption quality,
  ) {
    final proxyDetails = _streamProxy.lastErrorDetails;
    final details = StringBuffer('Transport: ${quality.transportLabel}');
    if (quality.audioUrl != null) {
      details
        ..writeln()
        ..write('Audio: separate adaptive Spur');
    }
    if (proxyDetails != null) {
      details
        ..writeln()
        ..writeln()
        ..write(proxyDetails);
    }
    return VideoPlaybackException(
      '$message: $playerError',
      cause: details.toString(),
    );
  }

  void _setPlayerError(String message, int generation, {String? details}) {
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _playerError = message;
      _playerErrorDetails = details;
      _isLoadingVideo = false;
    });
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _isSearching) {
      setState(() => _searchError = context.l10n.enterSearchTerm);
      return;
    }

    _resetActiveSearchResultsScrollOffset();
    unawaited(_profileController.recordSearchQuery(query));
    FocusManager.instance.primaryFocus?.unfocus();
    switch (_searchCategory) {
      case YouTubeSearchCategory.videos:
        await _loadSearchResults(
          query: query,
          pageNumber: 1,
          videoFeed: YouTubeVideoFeed.keyword(query: query),
        );
      case YouTubeSearchCategory.channels:
      case YouTubeSearchCategory.playlists:
        await _loadCatalogSearchResults(
          category: _searchCategory,
          query: query,
          pageNumber: 1,
        );
    }
  }

  void _resetActiveSearchResultsScrollOffset() {
    final controller = switch (_searchCategory) {
      YouTubeSearchCategory.videos => _videoResultsScrollController,
      YouTubeSearchCategory.channels => _channelResultsScrollController,
      YouTubeSearchCategory.playlists => _playlistResultsScrollController,
    };
    if (!controller.hasClients) return;
    controller.jumpTo(controller.position.minScrollExtent);
  }

  Future<void> _loadSearchResults({
    required String query,
    required int pageNumber,
    String? pageToken,
    YouTubeVideoFeed? videoFeed,
  }) async {
    if (_isSearching) {
      return;
    }
    final searchFailedMessage = AppLocalizations(
      Locale(_playbackLanguageCode),
    ).searchFailed;
    final append = pageToken != null && _searchResults.isNotEmpty;
    if (append &&
        (_hasReachedResultsEnd ||
            _searchResults.length >= searchResultLimit ||
            _loadedVideoPageTokens.contains(pageToken))) {
      return;
    }
    if (!append) {
      _loadedVideoPageTokens.clear();
    }
    final requestNumber = ++_searchRequestNumber;
    final resolvedFeed =
        videoFeed ??
        (pageToken == null
            ? YouTubeVideoFeed.keyword(query: query)
            : _videoFeed);
    final stopwatch = Stopwatch()..start();
    final logFields = <String, Object?>{
      'query': AppLog.instance.opaqueId(query.trim().toLowerCase()),
      'queryLength': query.trim().length,
      'surface': 'player',
      'source': _searchSource.name,
      'category': YouTubeSearchCategory.videos.name,
      'feed': resolvedFeed.type.name,
      'page': pageNumber,
      'append': append,
    };
    AppLog.instance.info('search.request.started', fields: logFields);
    if (!append) {
      widget.manifestCache?.clear();
    }
    setState(() {
      _isSearching = true;
      if (append) {
        _isLoadingMoreResults = true;
        _loadMoreResultsError = null;
      } else {
        _isLoadingMoreResults = false;
        _hasReachedResultsEnd = false;
        _searchError = null;
        _loadMoreResultsError = null;
      }
    });
    try {
      final result = await _loadVideoFeedPage(
        resolvedFeed,
        pageToken: pageToken,
      ).timeout(searchRequestTimeout);
      if (!mounted || requestNumber != _searchRequestNumber) {
        AppLog.instance.warning(
          'search.request.discarded',
          fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
        );
        return;
      }
      final mergedResults = append
          ? appendUniqueSearchResults(
              current: _searchResults,
              additions: result.videos,
              idOf: (video) => video.id,
            )
          : limitSearchResults(result.videos);
      final additions = append
          ? List<YouTubeVideo>.unmodifiable(
              mergedResults.skip(_searchResults.length),
            )
          : mergedResults;
      final reachedResultLimit = mergedResults.length >= searchResultLimit;
      final resolvedNextPageToken =
          reachedResultLimit ||
              result.videos.isEmpty ||
              result.nextPageToken == pageToken
          ? null
          : result.nextPageToken;
      setState(() {
        _searchResults = mergedResults;
        _searchResultsAutoplayEligible = true;
        _searchQuery = query;
        _videoFeed = resolvedFeed;
        _nextPageToken = resolvedNextPageToken;
        _resultsPageNumber = pageNumber;
        _isSearching = false;
        _isLoadingMoreResults = false;
        _hasReachedResultsEnd =
            !reachedResultLimit && resolvedNextPageToken == null;
        _loadMoreResultsError = null;
        _resultsRepresentPlaylist = false;
        if (append) {
          _loadedVideoPageTokens.add(pageToken);
        }
      });
      if (_playbackQueue.source != PlaybackQueueSource.localPlaylist) {
        if (append) {
          await _extendSearchPlaybackQueue(additions);
        } else {
          await _replacePlaybackQueue(
            PlaybackQueue.searchResults(
              items: mergedResults,
              currentVideo: _selectedVideo,
            ),
          );
        }
      }
      AppLog.instance.info(
        'search.request.succeeded',
        fields: {
          ...logFields,
          'durationMs': stopwatch.elapsedMilliseconds,
          'received': result.videos.length,
          'resultCount': mergedResults.length,
          'hasNextPage': resolvedNextPageToken != null,
        },
      );
    } on TimeoutException catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.timed_out',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(searchRequestTimeoutMessage, loadingMore: append);
    } on YouTubeSearchException catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(error.message, loadingMore: append);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(searchFailedMessage, loadingMore: append);
    }
  }

  Future<YouTubeSearchResult> _loadVideoFeedPage(
    YouTubeVideoFeed feed, {
    String? pageToken,
  }) async {
    final languageCode =
        _profileController.activeProfile?.language.code ??
        ProfileLanguage.english.code;
    final result = await switch (feed.type) {
      YouTubeVideoFeedType.keyword => _keywordSearchRepository.searchVideos(
        query: feed.query,
        pageToken: pageToken,
        languageCode: languageCode,
        sort: _isMusicSearchMode
            ? YouTubeSearchSort.relevance
            : _videoSearchSort,
      ),
      YouTubeVideoFeedType.channel =>
        _isMusicSearchMode
            ? _requireMusicCatalog().loadArtistSongs(
                artistId: feed.id!,
                pageToken: pageToken,
                languageCode: languageCode,
              )
            : _catalogRepository.loadChannelVideos(
                channelId: feed.id!,
                pageToken: pageToken,
                languageCode: languageCode,
              ),
      YouTubeVideoFeedType.playlist =>
        _isMusicSearchMode
            ? _requireMusicCatalog().loadMusicPlaylistSongs(
                playlistId: feed.id!,
                pageToken: pageToken,
                languageCode: languageCode,
              )
            : _catalogRepository.loadPlaylistVideos(
                playlistId: feed.id!,
                pageToken: pageToken,
                languageCode: languageCode,
              ),
    };
    return feed.itemsAreMusicVideos ? result.asMusicVideoResult() : result;
  }

  YouTubeSearchRepository get _keywordSearchRepository {
    final repository = _searchSource == VideoSearchSource.youtubeMusic
        ? _musicKeywordSearchRepository
        : _youtubeKeywordSearchRepository;
    if (repository == null) {
      throw YouTubeSearchException(
        _searchSource == VideoSearchSource.youtubeMusic
            ? 'Die YouTube-Music-Suche ist auf dieser Plattform nicht verfügbar.'
            : 'Die YouTube-Suche ist momentan nicht verfügbar.',
      );
    }
    return repository;
  }

  YouTubeMusicCatalogRepository _requireMusicCatalog() {
    final repository = _musicCatalogRepository;
    if (repository == null) {
      throw const YouTubeSearchException(
        'Die erweiterte YouTube-Music-Suche ist auf dieser Plattform nicht verfügbar.',
      );
    }
    return repository;
  }

  Future<void> _loadCatalogSearchResults({
    required YouTubeSearchCategory category,
    required String query,
    required int pageNumber,
    String? pageToken,
  }) async {
    if (_isSearching || category == YouTubeSearchCategory.videos) {
      return;
    }
    final state = _catalogSearchStates[category]!;
    final append = pageToken != null && state.resultCount > 0;
    if (append &&
        (state.hasReachedEnd ||
            state.resultCount >= searchResultLimit ||
            state.loadedPageTokens.contains(pageToken))) {
      return;
    }
    if (!append) {
      state.loadedPageTokens.clear();
      widget.manifestCache?.clear();
    }
    final stopwatch = Stopwatch()..start();
    final logFields = <String, Object?>{
      'query': AppLog.instance.opaqueId(query.trim().toLowerCase()),
      'queryLength': query.trim().length,
      'surface': 'player',
      'source': _searchSource.name,
      'category': category.name,
      'page': pageNumber,
      'append': append,
    };
    AppLog.instance.info('search.request.started', fields: logFields);
    final requestNumber = ++_searchRequestNumber;
    _pauseManifestPrefetch();
    setState(() {
      _isSearching = true;
      state.hasSearched = true;
      if (append) {
        state
          ..isLoadingMore = true
          ..loadMoreError = null;
      } else {
        _searchError = null;
        state
          ..isLoadingMore = false
          ..hasReachedEnd = false
          ..loadError = null
          ..loadMoreError = null;
      }
    });
    try {
      String? nextPageToken;
      List<YouTubeChannelResult> channels = const [];
      List<YouTubePlaylistResult> playlists = const [];
      if (category == YouTubeSearchCategory.channels) {
        final languageCode =
            _profileController.activeProfile?.language.code ??
            ProfileLanguage.english.code;
        final result =
            await (_isMusicSearchMode
                    ? _requireMusicCatalog().searchArtists(
                        query: query,
                        pageToken: pageToken,
                        languageCode: languageCode,
                      )
                    : _catalogRepository.searchChannels(
                        query: query,
                        pageToken: pageToken,
                        languageCode: languageCode,
                      ))
                .timeout(searchRequestTimeout);
        channels = result.items;
        nextPageToken = result.nextPageToken;
      } else {
        final languageCode =
            _profileController.activeProfile?.language.code ??
            ProfileLanguage.english.code;
        final result =
            await (_isMusicSearchMode
                    ? _requireMusicCatalog().searchMusicPlaylists(
                        query: query,
                        pageToken: pageToken,
                        languageCode: languageCode,
                      )
                    : _catalogRepository.searchPlaylists(
                        query: query,
                        pageToken: pageToken,
                        languageCode: languageCode,
                        sort: _playlistSearchSort,
                      ))
                .timeout(searchRequestTimeout);
        playlists = result.items;
        nextPageToken = result.nextPageToken;
      }
      if (!mounted || requestNumber != _searchRequestNumber) {
        AppLog.instance.warning(
          'search.request.discarded',
          fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
        );
        return;
      }
      final mergedChannels = append
          ? appendUniqueSearchResults(
              current: state.channels,
              additions: channels,
              idOf: (channel) => channel.id,
            )
          : limitSearchResults(channels);
      final mergedPlaylists = append
          ? appendUniqueSearchResults(
              current: state.playlists,
              additions: playlists,
              idOf: (playlist) => playlist.id,
            )
          : limitSearchResults(playlists);
      final receivedResultCount = channels.length + playlists.length;
      final mergedResultCount = mergedChannels.length + mergedPlaylists.length;
      final reachedResultLimit = mergedResultCount >= searchResultLimit;
      final resolvedNextPageToken =
          reachedResultLimit ||
              receivedResultCount == 0 ||
              nextPageToken == pageToken
          ? null
          : nextPageToken;
      setState(() {
        state
          ..channels = mergedChannels
          ..playlists = mergedPlaylists;
        if (append) {
          state.loadedPageTokens.add(pageToken);
        }
        state
          ..query = query
          ..nextPageToken = resolvedNextPageToken
          ..pageNumber = pageNumber
          ..isLoadingMore = false
          ..hasReachedEnd = !reachedResultLimit && resolvedNextPageToken == null
          ..loadMoreError = null;
        _isSearching = false;
      });
      AppLog.instance.info(
        'search.request.succeeded',
        fields: {
          ...logFields,
          'durationMs': stopwatch.elapsedMilliseconds,
          'received': receivedResultCount,
          'resultCount': mergedResultCount,
          'hasNextPage': resolvedNextPageToken != null,
        },
      );
    } on TimeoutException catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.timed_out',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(
        searchRequestTimeoutMessage,
        catalogState: state,
        loadingMore: append,
      );
    } on YouTubeSearchException catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(error.message, catalogState: state, loadingMore: append);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _setSearchError(
        context.l10n.categorySearchFailed(
          context.l10n.categoryLabel(category, music: _isMusicSearchMode),
        ),
        catalogState: state,
        loadingMore: append,
      );
    }
  }

  void _selectSearchCategory(YouTubeSearchCategory category) {
    if (_isSearching || category == _searchCategory) {
      return;
    }
    setState(() {
      _searchCategory = category;
      _searchError = category == YouTubeSearchCategory.videos
          ? null
          : _catalogSearchStates[category]!.loadError;
    });
    if (category != YouTubeSearchCategory.videos) {
      _pauseManifestPrefetch();
    }
  }

  Future<void> _selectSearchSort(
    YouTubeSearchCategory category,
    YouTubeSearchSort sort,
  ) async {
    if (_isSearching ||
        _isMusicSearchMode ||
        category == YouTubeSearchCategory.channels) {
      return;
    }
    if (category == YouTubeSearchCategory.videos && !_videoSortingEnabled) {
      return;
    }
    final currentSort = category == YouTubeSearchCategory.videos
        ? _videoSearchSort
        : _playlistSearchSort;
    if (currentSort == sort) {
      return;
    }

    setState(() {
      if (category == YouTubeSearchCategory.videos) {
        _sessionVideoSearchSort = sort;
      } else {
        _sessionPlaylistSearchSort = sort;
      }
    });
    if (_profileController.activeProfile != null) {
      if (category == YouTubeSearchCategory.videos) {
        await _profileController.setVideoSearchSort(sort);
      } else {
        await _profileController.setPlaylistSearchSort(sort);
      }
    }
    if (!mounted || category != _searchCategory) {
      return;
    }

    if (category == YouTubeSearchCategory.videos) {
      if (_searchQuery.isEmpty) {
        return;
      }
      await _loadSearchResults(
        query: _searchQuery,
        pageNumber: 1,
        videoFeed: YouTubeVideoFeed.keyword(query: _searchQuery),
      );
      return;
    }

    final state = _catalogSearchStates[category]!;
    if (!state.hasSearched || state.query.isEmpty) {
      return;
    }
    await _loadCatalogSearchResults(
      category: category,
      query: state.query,
      pageNumber: 1,
    );
  }

  void _selectSearchSource(VideoSearchSource source, {bool force = false}) {
    if ((!force && _isSearching) ||
        (!force && source == _searchSource) ||
        (source == VideoSearchSource.youtubeMusic &&
            !_sourceSelectionEnabled)) {
      return;
    }
    _searchRequestNumber++;
    final clearsSearchQueue =
        _playbackQueue.source == PlaybackQueueSource.searchResults;
    setState(() {
      _isSearching = false;
      _searchSource = source;
      _searchResults = const [];
      _searchResultsAutoplayEligible = false;
      _searchQuery = '';
      _videoFeed = YouTubeVideoFeed.keyword(
        query: _queryController.text.trim(),
      );
      _nextPageToken = null;
      _resultsPageNumber = 1;
      _isLoadingMoreResults = false;
      _hasReachedResultsEnd = false;
      _loadMoreResultsError = null;
      _resultsRepresentPlaylist = false;
      _searchError = null;
      for (final category in const [
        YouTubeSearchCategory.channels,
        YouTubeSearchCategory.playlists,
      ]) {
        _catalogSearchStates[category] = _PlayerCatalogSearchState();
      }
    });
    _loadedVideoPageTokens.clear();
    if (clearsSearchQueue) {
      unawaited(_replacePlaybackQueue(const PlaybackQueue.empty()));
    }
    _pauseManifestPrefetch();
  }

  Future<void> _openChannel(YouTubeChannelResult channel) async {
    final feed = YouTubeVideoFeed.channel(
      channelId: channel.id,
      channelName: channel.name,
    );
    _queryController.text = channel.name;
    setState(() {
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadSearchResults(
      query: channel.name,
      pageNumber: 1,
      videoFeed: feed,
    );
  }

  Future<void> _openYouTubePlaylist(YouTubePlaylistResult playlist) async {
    final feed = YouTubeVideoFeed.playlist(
      playlistId: playlist.id,
      playlistTitle: playlist.title,
    );
    _queryController.text = playlist.title;
    setState(() {
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadSearchResults(
      query: playlist.title,
      pageNumber: 1,
      videoFeed: feed,
    );
  }

  void _setSearchError(
    String message, {
    _PlayerCatalogSearchState? catalogState,
    bool loadingMore = false,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (loadingMore) {
        if (catalogState != null) {
          catalogState
            ..loadMoreError = message
            ..isLoadingMore = false;
        } else {
          _loadMoreResultsError = message;
          _isLoadingMoreResults = false;
        }
      } else {
        _searchError = message;
        catalogState?.loadError = message;
      }
      _isSearching = false;
    });
  }

  void _scheduleLoadMore(int index, int resultCount) {
    if (resultCount == 0 ||
        resultCount >= searchResultLimit ||
        index < resultCount - _loadMoreTriggerItemCount) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadMoreResults());
      }
    });
  }

  Future<void> _loadMoreResults() {
    if (_isSearching) {
      return Future<void>.value();
    }
    if (_searchCategory == YouTubeSearchCategory.videos) {
      final pageToken = _nextPageToken;
      if (_resultsRepresentPlaylist ||
          _searchResults.isEmpty ||
          _searchResults.length >= searchResultLimit ||
          _hasReachedResultsEnd ||
          pageToken == null ||
          _loadedVideoPageTokens.contains(pageToken)) {
        return Future<void>.value();
      }
      return _loadSearchResults(
        query: _searchQuery,
        pageToken: pageToken,
        pageNumber: _resultsPageNumber + 1,
        videoFeed: _videoFeed,
      );
    }

    final state = _catalogSearchStates[_searchCategory]!;
    final pageToken = state.nextPageToken;
    if (state.resultCount == 0 ||
        state.resultCount >= searchResultLimit ||
        state.hasReachedEnd ||
        pageToken == null ||
        state.loadedPageTokens.contains(pageToken)) {
      return Future<void>.value();
    }
    return _loadCatalogSearchResults(
      category: _searchCategory,
      query: state.query,
      pageToken: pageToken,
      pageNumber: state.pageNumber + 1,
    );
  }

  Future<void> _extendSearchPlaybackQueue(List<YouTubeVideo> additions) async {
    if (additions.isEmpty ||
        _playbackQueue.source != PlaybackQueueSource.searchResults) {
      return;
    }
    final currentQueue = _playbackQueue;
    final extendedQueue = currentQueue.extendSearchResults(additions);
    if (identical(currentQueue, extendedQueue)) {
      return;
    }
    if (currentQueue.nextItem?.id == extendedQueue.nextItem?.id) {
      if (mounted) {
        setState(() => _playbackQueue = extendedQueue);
      }
      return;
    }
    await _replacePlaybackQueue(extendedQueue, preserveShuffle: false);
  }

  void _selectVideo(YouTubeVideo video) {
    if (_autoAdvanceInProgress) {
      return;
    }
    final activeBackend = _activePlaybackBackend;
    final requiredBackend = _requiredPlaybackBackend(video);
    AppLog.instance.info(
      'queue.media.manually_selected',
      fields: {
        ..._mediaLogFields(video),
        'currentMediaId': _selectedVideo.id,
        'currentBackend': activeBackend?.name ?? 'none',
        'targetBackend': requiredBackend.name,
        'backendChanged':
            activeBackend != null && activeBackend != requiredBackend,
      },
    );
    var nextQueue =
        _resultsRepresentPlaylist &&
            _playbackQueue.source == PlaybackQueueSource.localPlaylist
        ? _playbackQueue.selectVideo(video)
        : _searchResultsAutoplayEligible
        ? PlaybackQueue.searchResults(
            items: _searchResults,
            currentVideo: video,
          )
        : const PlaybackQueue.empty();
    if (_shuffleEnabled && _autoplayEnabled && nextQueue.isActive) {
      nextQueue = nextQueue.withShuffle(true, random: _shuffleRandom);
    }
    final transition = PlaybackBackgroundPolicy.manualSelectionTransition(
      nextVideo: video,
      hasCurrentPlayer: _hasCurrentPlayer,
      currentPlayerReady:
          _hasCurrentPlayer &&
          _loadedPlayerVideoId != null &&
          !_isLoadingVideo &&
          _playerError == null,
      canReuseCurrentPlayer:
          activeBackend != null && activeBackend == requiredBackend,
    );
    final revision = ++_queueRevision;
    _playlistPreparationGate.cancel();
    if (transition == ManualPlaybackTransitionStrategy.reuseCurrentPlayer) {
      unawaited(
        _switchManuallySelectedAudio(
          video,
          queue: nextQueue,
          revision: revision,
        ),
      );
      return;
    }
    setState(() {
      _synchronizeSearchModeWithMedia(video);
      _playbackQueue = nextQueue;
      _selectedVideo = video;
    });
    unawaited(
      _loadVideo(
        video,
        keepSystemSessionActive:
            transition ==
            ManualPlaybackTransitionStrategy.reloadKeepingSystemSession,
      ),
    );
  }

  Future<void> _switchManuallySelectedAudio(
    YouTubeVideo video, {
    required PlaybackQueue queue,
    required int revision,
  }) async {
    _autoAdvanceInProgress = true;
    final generation = _loadGeneration;
    try {
      await _waitForCrossfadeUpdateToSettle();
      if (_crossfadeStarted) {
        await _resetActiveCrossfade(rewindIncoming: true);
      }
      await _disposePreparedNextPlayback();
      if (!mounted ||
          revision != _queueRevision ||
          generation != _loadGeneration) {
        return;
      }
      setState(() {
        _synchronizeSearchModeWithMedia(video);
        _playbackQueue = queue;
        _selectedVideo = video;
      });
      await _switchQueueMediaOnCurrentPlayer(video, generation: generation);
    } finally {
      _autoAdvanceInProgress = false;
    }
  }

  void _selectAppSection(int index) {
    if (_playerTutorialStep != null ||
        index == _selectedAppSection ||
        index < 0 ||
        index > 2) {
      return;
    }
    _resetPullDownFullscreenTransition();
    setState(() => _selectedAppSection = index);
  }

  void _cancelPendingSearchForProfileSelection() {
    _searchRequestNumber++;
    _isSearching = false;
    _isLoadingMoreResults = false;
    for (final state in _catalogSearchStates.values) {
      state.isLoadingMore = false;
    }
  }

  void _synchronizeSearchModeWithMedia(YouTubeVideo video) {
    final source = videoSearchSourceForMedia(video);
    if (source == _searchSource) {
      return;
    }
    _searchRequestNumber++;
    _searchSource = source;
    _searchCategory = YouTubeSearchCategory.videos;
    _isSearching = false;
    _isLoadingMoreResults = false;
    _searchError = null;
    _loadMoreResultsError = null;
    for (final category in const [
      YouTubeSearchCategory.channels,
      YouTubeSearchCategory.playlists,
    ]) {
      _catalogSearchStates[category] = _PlayerCatalogSearchState();
    }
  }

  void _openProfileVideo(YouTubeVideo video, List<YouTubeVideo> contextVideos) {
    setState(() {
      _cancelPendingSearchForProfileSelection();
      _selectedAppSection = 0;
      _searchCategory = YouTubeSearchCategory.videos;
      _searchResults = List<YouTubeVideo>.unmodifiable(contextVideos);
      _searchResultsAutoplayEligible = false;
      _searchQuery = '';
      _videoFeed = const YouTubeVideoFeed.keyword(query: '');
      _nextPageToken = null;
      _resultsPageNumber = 1;
      _hasReachedResultsEnd = true;
      _loadMoreResultsError = null;
      _resultsRepresentPlaylist = false;
      _searchError = null;
    });
    _loadedVideoPageTokens.clear();
    _queryController.clear();
    _selectVideo(video);
  }

  void _openHotMusicVideo(
    YouTubeVideo video,
    List<YouTubeVideo> contextVideos,
    String contextTitle,
  ) {
    setState(() {
      _cancelPendingSearchForProfileSelection();
      _selectedAppSection = 0;
      _searchCategory = YouTubeSearchCategory.videos;
      _searchResults = List<YouTubeVideo>.unmodifiable(contextVideos);
      _searchResultsAutoplayEligible = true;
      _searchQuery = '';
      _videoFeed = const YouTubeVideoFeed.keyword(query: '');
      _nextPageToken = null;
      _resultsPageNumber = 1;
      _hasReachedResultsEnd = true;
      _loadMoreResultsError = null;
      _resultsRepresentPlaylist = false;
      _searchError = null;
    });
    _loadedVideoPageTokens.clear();
    _queryController.clear();
    _selectVideo(video);
  }

  Future<void> _openHotMusicPlaylist(YouTubePlaylistResult playlist) =>
      _openHotMusicFeed(
        YouTubeVideoFeed.playlist(
          playlistId: playlist.id,
          playlistTitle: playlist.title,
          itemsAreMusicVideos: playlist.itemsAreMusicVideos,
        ),
      );

  Future<void> _openHotMusicArtist(YouTubeChannelResult artist) =>
      _openHotMusicFeed(
        YouTubeVideoFeed.channel(
          channelId: artist.id,
          channelName: artist.name,
        ),
      );

  Future<void> _openHotMusicFeed(YouTubeVideoFeed feed) async {
    _selectSearchSource(VideoSearchSource.youtubeMusic, force: true);
    _queryController.text = feed.title ?? feed.query;
    setState(() {
      _selectedAppSection = 0;
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadSearchResults(query: feed.query, pageNumber: 1, videoFeed: feed);
    if (!mounted ||
        !identical(_videoFeed, feed) ||
        _searchError != null ||
        _searchResults.isEmpty) {
      return;
    }
    _selectVideo(_searchResults.first);
  }

  Future<void> _importHotMusicPlaylist(YouTubePlaylistResult playlist) async {
    final languageCode = _playbackLanguageCode;
    await showImportCatalogPlaylistDialog(
      context,
      _profileController,
      playlist,
      loadPage: (pageToken) async {
        final result = await _requireMusicCatalog().loadMusicPlaylistSongs(
          playlistId: playlist.id,
          pageToken: pageToken,
          languageCode: languageCode,
        );
        return playlist.itemsAreMusicVideos
            ? result.asMusicVideoResult()
            : result;
      },
    );
  }

  void _openProfilePlaylist(VideoPlaylist playlist, int startIndex) {
    if (playlist.videos.isEmpty ||
        startIndex < 0 ||
        startIndex >= playlist.videos.length) {
      return;
    }
    final video = playlist.videos[startIndex];
    setState(() {
      _cancelPendingSearchForProfileSelection();
      _selectedAppSection = 0;
      _searchCategory = YouTubeSearchCategory.videos;
      _searchResults = List<YouTubeVideo>.unmodifiable(playlist.videos);
      _searchResultsAutoplayEligible = false;
      _searchQuery = playlist.name;
      _videoFeed = YouTubeVideoFeed.keyword(query: playlist.name);
      _nextPageToken = null;
      _resultsPageNumber = 1;
      _hasReachedResultsEnd = true;
      _loadMoreResultsError = null;
      _resultsRepresentPlaylist = true;
      _searchError = null;
      _playbackQueue = PlaybackQueue.localPlaylist(
        items: playlist.videos,
        initialIndex: startIndex,
        loops: _autoplayEnabled,
      );
    });
    _loadedVideoPageTokens.clear();
    _queryController.text = playlist.name;
    _selectVideo(video);
  }

  void _openProfileChannel(YouTubeChannelResult channel) {
    final source = channel.isMusic
        ? VideoSearchSource.youtubeMusic
        : VideoSearchSource.youtube;
    if (_isSearching) {
      setState(_cancelPendingSearchForProfileSelection);
    }
    if (source != _searchSource) {
      _selectSearchSource(source);
    }
    setState(() => _selectedAppSection = 0);
    unawaited(_openChannel(channel));
  }

  Future<void> _toggleAutoplay(bool enabled) async {
    if (!await _ensureActiveProfile() || !mounted) {
      return;
    }
    await _profileController.setAutoplaySearchResults(enabled);
    AppLog.instance.info(
      'queue.autoplay.changed',
      fields: {'enabled': enabled, 'queueSource': _playbackQueue.source.name},
    );
    if (!mounted) {
      return;
    }

    final nextQueue = switch (_playbackQueue.source) {
      PlaybackQueueSource.localPlaylist =>
        _playbackQueue
            .withShuffle(false, random: _shuffleRandom)
            .withLooping(enabled),
      PlaybackQueueSource.searchResults || PlaybackQueueSource.none =>
        _searchResultsAutoplayEligible && _searchResults.isNotEmpty
            ? PlaybackQueue.searchResults(
                items: _searchResults,
                currentVideo: _selectedVideo,
              )
            : const PlaybackQueue.empty(),
    };
    await _replacePlaybackQueue(nextQueue, preserveShuffle: false);
  }

  Future<void> _toggleShuffle() async {
    if (!_autoplayEnabled || !_playbackQueue.isActive) {
      return;
    }
    final nextQueue = _playbackQueue.withShuffle(
      !_shuffleEnabled,
      random: _shuffleRandom,
    );
    AppLog.instance.info(
      'queue.shuffle.changed',
      fields: {
        'enabled': !_shuffleEnabled,
        'queueCount': _playbackQueue.items.length,
      },
    );
    await _replacePlaybackQueue(nextQueue, preserveShuffle: false);
  }

  Future<void> _replacePlaybackQueue(
    PlaybackQueue queue, {
    bool preserveShuffle = true,
  }) async {
    final shouldPreserveShuffle =
        preserveShuffle && _shuffleEnabled && _autoplayEnabled;
    final replacement = shouldPreserveShuffle
        ? queue.withShuffle(true, random: _shuffleRandom)
        : queue;
    AppLog.instance.info(
      'queue.replaced',
      fields: {
        'source': replacement.source.name,
        'count': replacement.items.length,
        'shuffle': replacement.isShuffled,
        'looping': replacement.loops,
      },
    );
    final revision = ++_queueRevision;
    _playlistPreparationGate.cancel();
    if (_crossfadeStarted) {
      await _resetActiveCrossfade(rewindIncoming: true);
    }
    await _disposePreparedNextPlayback();
    if (!mounted || revision != _queueRevision) {
      return;
    }
    setState(() => _playbackQueue = replacement);
    final player = _player;
    if (player != null) {
      await _attachSystemMediaControls(player, _selectedVideo);
    } else if (_nativeAndroidMedia3AudioPlayerActive) {
      await _attachAndroidMedia3AudioSystemControls(_selectedVideo);
    } else if (_nativeIosMainPlayerActive && _selectedVideo.isMusic) {
      await _attachNativeIosMainSystemControls(_selectedVideo);
    } else if (_nativeIosAudioPlayerActive) {
      await _updateIosNativeAudioNavigation();
    }
    if (!mounted || revision != _queueRevision) {
      return;
    }
    final playback = _playback;
    final selectedQuality = _selectedQuality;
    if (!_nativeIosMainPlayerActive &&
        playback != null &&
        selectedQuality != null) {
      await _prepareIosPictureInPicture(
        playback: playback,
        selectedQuality: selectedQuality,
        generation: _loadGeneration,
      );
    }
    if (mounted &&
        revision == _queueRevision &&
        (_player != null ||
            _nativeAndroidMedia3AudioPlayerActive ||
            _nativeIosAudioPlayerActive) &&
        !_nativeIosMainPlayerActive) {
      _prepareNextQueuePlayback(_loadGeneration);
    }
  }

  Future<bool> _ensureActiveProfile() async {
    if (_profileController.activeProfile != null) {
      return true;
    }
    return showCreateProfileDialog(context, _profileController);
  }

  Future<void> _toggleFavorite() async {
    if (!await _ensureActiveProfile() || !mounted) {
      return;
    }
    await _profileController.toggleFavorite(_selectedVideo);
  }

  Future<void> _toggleReaction(VideoReaction reaction) async {
    if (!await _ensureActiveProfile() || !mounted) {
      return;
    }
    final current = _profileController.reactionFor(_selectedVideo.id);
    await _profileController.setReaction(
      _selectedVideo,
      current == reaction ? VideoReaction.none : reaction,
    );
  }

  Future<void> _addToPlaylist() async {
    await showAddToPlaylistDialog(context, _profileController, _selectedVideo);
  }

  Future<void> _toggleResultFavorite(YouTubeVideo video) async {
    if (!await _ensureActiveProfile() || !mounted) {
      return;
    }
    await _profileController.toggleFavorite(video);
  }

  Future<void> _addResultToPlaylist(YouTubeVideo video) async {
    await showAddToPlaylistDialog(context, _profileController, video);
  }

  Future<void> _toggleChannelFavorite(YouTubeChannelResult channel) async {
    if (!await _ensureActiveProfile() || !mounted) {
      return;
    }
    await _profileController.toggleFavoriteChannel(channel);
  }

  Future<void> _addCatalogPlaylistToLocalPlaylist(
    YouTubePlaylistResult playlist,
  ) async {
    final musicMode = _isMusicSearchMode;
    final languageCode = _playbackLanguageCode;
    await showImportCatalogPlaylistDialog(
      context,
      _profileController,
      playlist,
      loadPage: (pageToken) => musicMode
          ? _requireMusicCatalog().loadMusicPlaylistSongs(
              playlistId: playlist.id,
              pageToken: pageToken,
              languageCode: languageCode,
            )
          : _catalogRepository.loadPlaylistVideos(
              playlistId: playlist.id,
              pageToken: pageToken,
              languageCode: languageCode,
            ),
    );
  }

  Future<String> Function()? _fullDescriptionLoaderFor(YouTubeVideo video) {
    final repository = widget.videoDetailsRepository;
    if (repository == null) {
      return null;
    }
    return () => repository.loadDescription(
      videoId: video.id,
      languageCode:
          _profileController.activeProfile?.language.code ??
          ProfileLanguage.english.code,
    );
  }

  void _syncSystemUi(bool fullscreen) {
    if (_lastFullscreenMode == fullscreen) {
      return;
    }
    _lastFullscreenMode = fullscreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (fullscreen) {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
        );
      } else {
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
        );
      }
    });
  }

  Future<void> _togglePlayback(_PlaybackViewState value) async {
    AppLog.instance.info(
      value.playing ? 'player.pause.requested' : 'player.play.requested',
      fields: {
        ..._mediaLogFields(_selectedVideo),
        'positionMs': value.position.inMilliseconds,
        'backend': _nativeAndroidMedia3PlayerActive
            ? 'androidMedia3ExoPlayer'
            : _nativeAndroidMedia3AudioPlayerActive
            ? 'androidMedia3ExoPlayerAudio'
            : _nativeIosMainPlayerActive
            ? 'iosAvPlayerVideo'
            : _nativeIosAudioPlayerActive
            ? 'iosAvPlayerAudio'
            : 'mediaKit',
      },
    );
    if (_nativeAndroidMedia3PlayerActive) {
      if (value.playing) {
        await AndroidMedia3VideoPlayer.instance.pause();
        _handlePlaybackStateForSleep();
        await _applyPictureInPictureConfiguration(
          value.copyWith(playing: false),
        );
      } else {
        if (_lifecycleState != AppLifecycleState.resumed &&
            (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
                _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep)) {
          return;
        }
        if (!_isLivePlayback &&
            value.duration > Duration.zero &&
            value.position >= value.duration) {
          await AndroidMedia3VideoPlayer.instance.seek(Duration.zero);
        }
        await _resumeSuspendedPlaybackInfrastructure();
        await AndroidMedia3VideoPlayer.instance.play();
        await _applyPictureInPictureConfiguration(
          value.copyWith(playing: true),
        );
      }
      return;
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      if (value.playing) {
        await AndroidMedia3AudioPlayback.instance.pause();
        _handlePlaybackStateForSleep();
      } else {
        if (_lifecycleState != AppLifecycleState.resumed &&
            (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
                _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep)) {
          return;
        }
        if (value.duration > Duration.zero &&
            value.position >= value.duration) {
          await AndroidMedia3AudioPlayback.instance.seek(Duration.zero);
        }
        await _resumeSuspendedPlaybackInfrastructure();
        await AndroidMedia3AudioPlayback.instance.play();
      }
      return;
    }
    if (_nativeIosMainPlayerActive) {
      if (value.playing) {
        await IosPictureInPicture.instance.pause();
      } else {
        if (_lifecycleState != AppLifecycleState.resumed &&
            (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
                _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep)) {
          return;
        }
        if (!_isLivePlayback &&
            value.duration > Duration.zero &&
            value.position >= value.duration) {
          await IosPictureInPicture.instance.seek(Duration.zero);
        }
        await _resumeSuspendedPlaybackInfrastructure();
        await IosPictureInPicture.instance.play();
      }
      return;
    }
    if (_nativeIosAudioPlayerActive) {
      if (value.playing) {
        await IosNativeAudioPlayback.instance.pause();
      } else {
        if (_lifecycleState != AppLifecycleState.resumed &&
            (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
                _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep)) {
          return;
        }
        if (value.duration > Duration.zero &&
            value.position >= value.duration) {
          await IosNativeAudioPlayback.instance.seek(Duration.zero);
        }
        await _resumeSuspendedPlaybackInfrastructure();
        await IosNativeAudioPlayback.instance.play();
      }
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    if (value.playing) {
      await player.pause();
      if (_crossfadeStarted) {
        await _preparedNextPlayback?.player.pause();
      }
      _handlePlaybackStateForSleep();
      await _applyPictureInPictureConfiguration(value.copyWith(playing: false));
    } else {
      if (_lifecycleState != AppLifecycleState.resumed &&
          (_sleepModel.phase == HybridPlaybackSleepPhase.softSleep ||
              _sleepModel.phase == HybridPlaybackSleepPhase.deepSleep)) {
        return;
      }
      if (!_isLivePlayback &&
          value.duration > Duration.zero &&
          value.position >= value.duration) {
        await player.seek(Duration.zero);
      }
      await _resumeSuspendedPlaybackInfrastructure();
      await player.play();
      if (_crossfadeStarted) {
        await _preparedNextPlayback?.player.play();
      }
      await _applyPictureInPictureConfiguration(value.copyWith(playing: true));
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    if (!_hasCurrentPlayer || _isLivePlayback) {
      return;
    }
    final state = _playbackState.value;
    final duration = state.duration;
    final requested = state.position + offset;
    final target = requested < Duration.zero
        ? Duration.zero
        : requested > duration
        ? duration
        : requested;
    if (_crossfadeStarted) {
      await _resetActiveCrossfade(rewindIncoming: true);
    }
    if (_nativeAndroidMedia3PlayerActive) {
      await AndroidMedia3VideoPlayer.instance.seek(target);
    } else if (_nativeAndroidMedia3AudioPlayerActive) {
      await AndroidMedia3AudioPlayback.instance.seek(target);
    } else if (_nativeIosMainPlayerActive) {
      await IosPictureInPicture.instance.seek(target);
    } else if (_nativeIosAudioPlayerActive) {
      await IosNativeAudioPlayback.instance.seek(target);
    } else {
      await _player?.seek(target);
    }
  }

  void _startHoldSeek(Duration offset) {
    if (_isLivePlayback) {
      return;
    }
    _hideControlsTimer?.cancel();
    _gestureFeedbackController.showHold(
      offset.isNegative
          ? PlayerGestureFeedback.rewindHold
          : PlayerGestureFeedback.forwardHold,
    );
    unawaited(_seekRelative(offset));
    _seekHoldTimer?.cancel();
    _seekHoldTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      unawaited(_seekRelative(offset));
    });
  }

  void _stopHoldSeek() {
    _seekHoldTimer?.cancel();
    _seekHoldTimer = null;
    _gestureFeedbackController.clearHold();
    _showControls();
  }

  Future<void> _setVolume(double volume) async {
    setState(() {
      _volume = volume;
      if (volume > 0) {
        _volumeBeforeMute = volume;
      }
    });
    final player = _player;
    if (player != null) {
      final state = _playbackState.value;
      await _applyEffectivePlayerVolume(
        player,
        position: state.position,
        duration: state.duration,
        force: true,
      );
    }
    if (_nativeAndroidMedia3PlayerActive) {
      await AndroidMedia3VideoPlayer.instance.setVolume(
        volume * _systemAudioVolumeFactor,
      );
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      await AndroidMedia3AudioPlayback.instance.setVolume(
        volume * _systemAudioVolumeFactor,
      );
    }
    final prepared = _preparedNextPlayback;
    if (_crossfadeStarted && prepared != null) {
      final state = _playbackState.value;
      final incomingFactor = playlistCrossfadeIncomingFactor(
        position: state.position,
        duration: state.duration,
      );
      final incomingVolume =
          (_volume * _systemAudioVolumeFactor * incomingFactor * 100).clamp(
            0.0,
            100.0,
          );
      _lastAppliedIncomingVolume = incomingVolume;
      await prepared.player.setVolume(incomingVolume);
    }
    await IosPictureInPicture.instance.setVolume(
      volume * _systemAudioVolumeFactor,
    );
    await IosNativeAudioPlayback.instance.setVolume(
      volume * _systemAudioVolumeFactor,
    );
  }

  void _toggleMute() {
    unawaited(_setVolume(_volume == 0 ? _volumeBeforeMute : 0));
  }

  void _showControls() {
    if (!mounted) {
      return;
    }
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _restartControlsTimer();
  }

  void _restartControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_playerTutorialStep != null) {
      _hideControlsTimer = null;
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _controlsVisible = false;
        _settingsVisible = false;
      });
    });
  }

  void _toggleSettings() {
    setState(() => _settingsVisible = !_settingsVisible);
    _restartControlsTimer();
  }

  bool get _canStartPullDownFullscreen {
    final mediaQuery = MediaQuery.of(context);
    return PlayerPullDownFullscreenPolicy.canStart(
      portrait: mediaQuery.orientation == Orientation.portrait,
      playerSectionActive: _selectedAppSection == 0,
      fullscreen: _fullscreenRequested,
      pictureInPicture: _isInPictureInPictureMode,
      keyboardVisible: mediaQuery.viewInsets.bottom > 0,
    );
  }

  void _startPullDownFullscreenGesture() {
    if (!_canStartPullDownFullscreen) {
      return;
    }
    _pullDownFullscreenController.stop();
    _pullDownFullscreenDistance =
        _pullDownFullscreenController.value *
        PlayerPullDownFullscreenPolicy.dragExtent;
    _pullDownFullscreenGestureActive = true;
    _settingsVisible = false;
    _hideControlsTimer?.cancel();
  }

  void _updatePullDownFullscreenGesture(double primaryDelta) {
    if (!_pullDownFullscreenGestureActive) {
      return;
    }
    _pullDownFullscreenDistance = math.max(
      0,
      _pullDownFullscreenDistance + primaryDelta,
    );
    _pullDownFullscreenController.value =
        PlayerPullDownFullscreenPolicy.progressForDistance(
          _pullDownFullscreenDistance,
        );
  }

  Future<void> _finishPullDownFullscreenGesture({
    double primaryVelocity = 0,
  }) async {
    if (!_pullDownFullscreenGestureActive) {
      _videoResultsPullDownArmed = false;
      return;
    }
    _pullDownFullscreenGestureActive = false;
    _videoResultsPullDownArmed = false;
    final complete = PlayerPullDownFullscreenPolicy.shouldComplete(
      progress: _pullDownFullscreenController.value,
      primaryVelocity: primaryVelocity,
    );
    if (!complete || !_canStartPullDownFullscreen) {
      await _pullDownFullscreenController.animateBack(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      _pullDownFullscreenDistance = 0;
      _restartControlsTimer();
      return;
    }

    await _pullDownFullscreenController.animateTo(
      1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_canStartPullDownFullscreen) {
      _resetPullDownFullscreenTransition();
      return;
    }
    await _toggleFullscreen(false);
  }

  void _cancelPullDownFullscreenGesture() {
    if (!_pullDownFullscreenGestureActive &&
        _pullDownFullscreenController.value == 0) {
      _videoResultsPullDownArmed = false;
      return;
    }
    _pullDownFullscreenGestureActive = false;
    _videoResultsPullDownArmed = false;
    unawaited(
      _pullDownFullscreenController
          .animateBack(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            _pullDownFullscreenDistance = 0;
            if (mounted) {
              _restartControlsTimer();
            }
          }),
    );
  }

  void _resetPullDownFullscreenTransition() {
    _pullDownFullscreenGestureActive = false;
    _clearPullDownFullscreenPointer();
    _pullDownFullscreenDistance = 0;
    _pullDownFullscreenController.stop();
    _pullDownFullscreenController.value = 0;
  }

  void _clearPullDownFullscreenPointer() {
    _pullDownFullscreenPointer = null;
    _pullDownFullscreenPointerStart = null;
    _pullDownFullscreenPointerLast = null;
    _pullDownFullscreenVelocityTracker = null;
    _videoResultsPullDownArmed = false;
  }

  void _handlePullDownFullscreenPointerDown(
    PointerDownEvent event, {
    required bool requireVideoResultsAtTop,
  }) {
    if (_pullDownFullscreenPointer != null || !_canStartPullDownFullscreen) {
      return;
    }
    if (requireVideoResultsAtTop) {
      if (!_videoResultsScrollController.hasClients ||
          !PlayerPullDownFullscreenPolicy.listGestureStartsAtTop(
            _videoResultsScrollController.position.extentBefore,
          )) {
        return;
      }
      _videoResultsPullDownArmed = true;
    }
    _pullDownFullscreenPointer = event.pointer;
    _pullDownFullscreenPointerStart = event.position;
    _pullDownFullscreenPointerLast = event.position;
    _pullDownFullscreenVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handlePullDownFullscreenPointerMove(PointerMoveEvent event) {
    if (_pullDownFullscreenPointer != event.pointer ||
        _pullDownFullscreenPointerStart == null ||
        _pullDownFullscreenPointerLast == null) {
      return;
    }
    _pullDownFullscreenVelocityTracker?.addPosition(
      event.timeStamp,
      event.position,
    );
    final totalDelta = event.position - _pullDownFullscreenPointerStart!;
    final stepDelta = event.position - _pullDownFullscreenPointerLast!;
    _pullDownFullscreenPointerLast = event.position;

    if (!_pullDownFullscreenGestureActive) {
      const activationDistance = 8.0;
      if (totalDelta.dy <= -activationDistance ||
          (totalDelta.dx.abs() >= activationDistance &&
              totalDelta.dx.abs() > totalDelta.dy.abs())) {
        _clearPullDownFullscreenPointer();
        return;
      }
      if (totalDelta.dy < activationDistance) {
        return;
      }
      _startPullDownFullscreenGesture();
      if (!_pullDownFullscreenGestureActive) {
        _clearPullDownFullscreenPointer();
        return;
      }
      _updatePullDownFullscreenGesture(totalDelta.dy);
    } else {
      _updatePullDownFullscreenGesture(stepDelta.dy);
    }

    if (_videoResultsPullDownArmed) {
      scheduleMicrotask(_keepVideoResultsPinnedToTop);
    }
  }

  void _handlePullDownFullscreenPointerUp(PointerUpEvent event) {
    if (_pullDownFullscreenPointer != event.pointer) {
      return;
    }
    _pullDownFullscreenVelocityTracker?.addPosition(
      event.timeStamp,
      event.position,
    );
    final primaryVelocity =
        _pullDownFullscreenVelocityTracker?.getVelocity().pixelsPerSecond.dy ??
        0;
    _clearPullDownFullscreenPointer();
    unawaited(
      _finishPullDownFullscreenGesture(primaryVelocity: primaryVelocity),
    );
  }

  void _handlePullDownFullscreenPointerCancel(PointerCancelEvent event) {
    if (_pullDownFullscreenPointer != event.pointer) {
      return;
    }
    _clearPullDownFullscreenPointer();
    _cancelPullDownFullscreenGesture();
  }

  void _keepVideoResultsPinnedToTop() {
    if (!_pullDownFullscreenGestureActive ||
        !_videoResultsScrollController.hasClients) {
      return;
    }
    final position = _videoResultsScrollController.position;
    if (position.pixels != position.minScrollExtent) {
      position.jumpTo(position.minScrollExtent);
    }
  }

  Widget _buildPullDownFullscreenDragRegion({required Widget child, Key? key}) {
    return Listener(
      key: key,
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _handlePullDownFullscreenPointerDown(
        event,
        requireVideoResultsAtTop: false,
      ),
      onPointerMove: _handlePullDownFullscreenPointerMove,
      onPointerUp: _handlePullDownFullscreenPointerUp,
      onPointerCancel: _handlePullDownFullscreenPointerCancel,
      child: child,
    );
  }

  Widget _buildPullDownAwareVideoResults(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _handlePullDownFullscreenPointerDown(
        event,
        requireVideoResultsAtTop: true,
      ),
      onPointerMove: _handlePullDownFullscreenPointerMove,
      onPointerUp: _handlePullDownFullscreenPointerUp,
      onPointerCancel: _handlePullDownFullscreenPointerCancel,
      child: child,
    );
  }

  bool get _canStartPullUpFullscreen {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return PlayerPullUpFullscreenPolicy.canStart(
      fullscreen: PlayerFullscreenPolicy.usesFullscreenLayout(
        fullscreenRequested: _fullscreenRequested,
        landscape: landscape,
      ),
      pictureInPicture: _isInPictureInPictureMode,
    );
  }

  void _handlePullUpFullscreenPointerDown(
    PointerDownEvent event, {
    required Size viewport,
  }) {
    if (_pullUpFullscreenPointer != null ||
        !_canStartPullUpFullscreen ||
        !PlayerPullUpFullscreenPolicy.startsInCenter(
          position: event.localPosition,
          viewport: viewport,
        )) {
      return;
    }
    _pullUpFullscreenPointer = event.pointer;
    _pullUpFullscreenPointerStart = event.position;
    _pullUpFullscreenPointerLast = event.position;
    _pullUpFullscreenVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handlePullUpFullscreenPointerMove(PointerMoveEvent event) {
    if (_pullUpFullscreenPointer != event.pointer ||
        _pullUpFullscreenPointerStart == null ||
        _pullUpFullscreenPointerLast == null) {
      return;
    }
    _pullUpFullscreenVelocityTracker?.addPosition(
      event.timeStamp,
      event.position,
    );
    final totalDelta = event.position - _pullUpFullscreenPointerStart!;
    final stepDelta = event.position - _pullUpFullscreenPointerLast!;
    _pullUpFullscreenPointerLast = event.position;

    if (!_pullUpFullscreenGestureActive) {
      const activationDistance = 8.0;
      if (totalDelta.dy >= activationDistance ||
          (totalDelta.dx.abs() >= activationDistance &&
              totalDelta.dx.abs() > totalDelta.dy.abs())) {
        _clearPullUpFullscreenPointer();
        return;
      }
      if (totalDelta.dy > -activationDistance) {
        return;
      }
      _pullUpFullscreenController.stop();
      _pullUpFullscreenDistance =
          _pullUpFullscreenController.value *
          PlayerPullUpFullscreenPolicy.dragExtent;
      _pullUpFullscreenGestureActive = true;
      _settingsVisible = false;
      _hideControlsTimer?.cancel();
      _updatePullUpFullscreenGesture(-totalDelta.dy);
    } else {
      _updatePullUpFullscreenGesture(-stepDelta.dy);
    }
  }

  void _updatePullUpFullscreenGesture(double upwardDelta) {
    if (!_pullUpFullscreenGestureActive) {
      return;
    }
    _pullUpFullscreenDistance = math.max(
      0,
      _pullUpFullscreenDistance + upwardDelta,
    );
    _pullUpFullscreenController.value =
        PlayerPullUpFullscreenPolicy.progressForDistance(
          _pullUpFullscreenDistance,
        );
  }

  void _handlePullUpFullscreenPointerUp(PointerUpEvent event) {
    if (_pullUpFullscreenPointer != event.pointer) {
      return;
    }
    _pullUpFullscreenVelocityTracker?.addPosition(
      event.timeStamp,
      event.position,
    );
    final primaryVelocity =
        _pullUpFullscreenVelocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    _clearPullUpFullscreenPointer();
    unawaited(_finishPullUpFullscreenGesture(primaryVelocity: primaryVelocity));
  }

  void _handlePullUpFullscreenPointerCancel(PointerCancelEvent event) {
    if (_pullUpFullscreenPointer != event.pointer) {
      return;
    }
    _clearPullUpFullscreenPointer();
    _cancelPullUpFullscreenGesture();
  }

  void _clearPullUpFullscreenPointer() {
    _pullUpFullscreenPointer = null;
    _pullUpFullscreenPointerStart = null;
    _pullUpFullscreenPointerLast = null;
    _pullUpFullscreenVelocityTracker = null;
  }

  Future<void> _finishPullUpFullscreenGesture({
    double primaryVelocity = 0,
  }) async {
    if (!_pullUpFullscreenGestureActive) {
      return;
    }
    _pullUpFullscreenGestureActive = false;
    final complete = PlayerPullUpFullscreenPolicy.shouldComplete(
      progress: _pullUpFullscreenController.value,
      primaryVelocity: primaryVelocity,
    );
    if (!complete || !_canStartPullUpFullscreen) {
      await _pullUpFullscreenController.animateBack(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
      _pullUpFullscreenDistance = 0;
      _restartControlsTimer();
      return;
    }

    await _pullUpFullscreenController.animateTo(
      1,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_canStartPullUpFullscreen) {
      _resetPullUpFullscreenTransition();
      return;
    }
    await _toggleFullscreen(true);
  }

  void _cancelPullUpFullscreenGesture() {
    if (!_pullUpFullscreenGestureActive &&
        _pullUpFullscreenController.value == 0) {
      return;
    }
    _pullUpFullscreenGestureActive = false;
    unawaited(
      _pullUpFullscreenController
          .animateBack(
            0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            _pullUpFullscreenDistance = 0;
            if (mounted) {
              _restartControlsTimer();
            }
          }),
    );
  }

  void _resetPullUpFullscreenTransition() {
    _pullUpFullscreenGestureActive = false;
    _clearPullUpFullscreenPointer();
    _pullUpFullscreenDistance = 0;
    _pullUpFullscreenController.stop();
    _pullUpFullscreenController.value = 0;
  }

  Widget _buildPullUpFullscreenPlayer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        return AnimatedBuilder(
          animation: _pullUpFullscreenController,
          builder: (context, _) {
            final progress = _pullUpFullscreenController.value;
            final verticalOffset =
                -math.min(72.0, viewport.height * 0.1) * progress;
            final scale = 1 - 0.04 * progress;
            return ColoredBox(
              color: Colors.black,
              child: Transform.translate(
                offset: Offset(0, verticalOffset),
                child: Transform.scale(
                  scale: scale,
                  child: Listener(
                    key: const Key('player-pull-up-surface'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) =>
                        _handlePullUpFullscreenPointerDown(
                          event,
                          viewport: viewport,
                        ),
                    onPointerMove: _handlePullUpFullscreenPointerMove,
                    onPointerUp: _handlePullUpFullscreenPointerUp,
                    onPointerCancel: _handlePullUpFullscreenPointerCancel,
                    child: SizedBox.expand(child: _buildTrackedPlayer()),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleFullscreen(bool fullscreenLayout) async {
    _resetPullDownFullscreenTransition();
    _resetPullUpFullscreenTransition();
    _showControls();
    if (fullscreenLayout) {
      final leavingLandscapeFullscreen =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      if (_fullscreenRequested && mounted) {
        setState(() => _fullscreenRequested = false);
      }
      await SystemChrome.setPreferredOrientations(
        leavingLandscapeFullscreen
            ? PlayerFullscreenPolicy.exitOrientations
            : PlayerFullscreenPolicy.supportedFullscreenOrientations,
      );
    } else {
      if (mounted) {
        setState(() => _fullscreenRequested = true);
      }
      await SystemChrome.setPreferredOrientations(
        PlayerFullscreenPolicy.supportedFullscreenOrientations,
      );
    }
  }

  Future<void> _changeQuality(VideoQualityOption quality) async {
    final qualityStopwatch = Stopwatch()..start();
    if (_nativeAndroidMedia3PlayerActive) {
      await _changeNativeAndroidMedia3Quality(quality, qualityStopwatch);
      return;
    }
    if (_nativeAndroidMedia3AudioPlayerActive) {
      await _changeNativeAndroidMedia3AudioQuality(quality, qualityStopwatch);
      return;
    }
    if (_nativeIosMainPlayerActive) {
      await _changeNativeIosMainPlayerQuality(quality);
      return;
    }
    if (_nativeIosAudioPlayerActive) {
      await _changeNativeIosAudioPlayerQuality(quality);
      return;
    }
    final player = _player;
    final previousQuality = _selectedQuality;
    if (player == null ||
        previousQuality == null ||
        quality == previousQuality) {
      return;
    }

    if (_crossfadeStarted) {
      await _resetActiveCrossfade(rewindIncoming: true);
    }
    final state = _playbackState.value;
    setState(() => _isChangingQuality = true);
    _showControls();
    try {
      await _openQuality(
        player,
        quality,
        isLive: _isLivePlayback,
        position: state.position,
        play: state.playing,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedQuality = quality;
        _isChangingQuality = false;
      });
      AppLog.instance.info(
        'player.quality.changed',
        fields: {
          'mediaId': _selectedVideo.id,
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
    } on Exception catch (error, stackTrace) {
      AppLog.instance.error(
        'player.quality.change_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'mediaId': _selectedVideo.id,
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
      Object? restoreError;
      StackTrace? restoreStackTrace;
      try {
        await _openQuality(
          player,
          previousQuality,
          isLive: _isLivePlayback,
          position: state.position,
          play: state.playing,
        ).timeout(const Duration(seconds: 20));
      } on Exception catch (error, stackTrace) {
        restoreError = error;
        restoreStackTrace = stackTrace;
      }
      if (!mounted) {
        return;
      }
      setState(() => _isChangingQuality = false);
      final details = StringBuffer(_technicalErrorDetails(error, stackTrace));
      if (restoreError != null) {
        details
          ..writeln()
          ..writeln()
          ..writeln(
            'Fehler beim Wiederherstellen von ${previousQuality.label}:',
          )
          ..write(_technicalErrorDetails(restoreError, restoreStackTrace!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.qualityLoadFailed(quality.label)),
          action: SnackBarAction(
            label: context.l10n.details,
            onPressed: () =>
                unawaited(_showTechnicalDetails(details.toString())),
          ),
        ),
      );
    }
    _showControls();
  }

  Future<void> _changeNativeAndroidMedia3Quality(
    VideoQualityOption quality,
    Stopwatch qualityStopwatch,
  ) async {
    final previousQuality = _selectedQuality;
    if (previousQuality == null || quality == previousQuality) return;
    final state = _playbackState.value;
    setState(() => _isChangingQuality = true);
    _showControls();
    try {
      await _openAndroidMedia3Quality(
        quality,
        video: _selectedVideo,
        isLive: _isLivePlayback,
        position: state.position,
        play: state.playing,
      );
      if (!mounted) return;
      setState(() {
        _selectedQuality = quality;
        _isChangingQuality = false;
      });
      AppLog.instance.info(
        'player.quality.changed',
        fields: {
          'mediaId': _selectedVideo.id,
          'backend': 'androidMedia3ExoPlayer',
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
    } on Exception catch (error, stackTrace) {
      AppLog.instance.error(
        'player.quality.change_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'mediaId': _selectedVideo.id,
          'backend': 'androidMedia3ExoPlayer',
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
      Object? restoreError;
      StackTrace? restoreStackTrace;
      try {
        await _openAndroidMedia3Quality(
          previousQuality,
          video: _selectedVideo,
          isLive: _isLivePlayback,
          position: state.position,
          play: state.playing,
        );
      } on Exception catch (error, stackTrace) {
        restoreError = error;
        restoreStackTrace = stackTrace;
      }
      if (!mounted) return;
      setState(() => _isChangingQuality = false);
      final details = StringBuffer(_technicalErrorDetails(error, stackTrace));
      if (restoreError != null) {
        details
          ..writeln()
          ..writeln()
          ..writeln(
            'Fehler beim Wiederherstellen von ${previousQuality.label}:',
          )
          ..write(_technicalErrorDetails(restoreError, restoreStackTrace!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.qualityLoadFailed(quality.label)),
          action: SnackBarAction(
            label: context.l10n.details,
            onPressed: () =>
                unawaited(_showTechnicalDetails(details.toString())),
          ),
        ),
      );
    }
    _showControls();
  }

  Future<void> _changeNativeAndroidMedia3AudioQuality(
    VideoQualityOption quality,
    Stopwatch qualityStopwatch,
  ) async {
    final previousQuality = _selectedQuality;
    if (previousQuality == null || quality == previousQuality) return;
    final state = _playbackState.value;
    setState(() => _isChangingQuality = true);
    _showControls();
    try {
      final ready = await _openAndroidMedia3AudioQuality(
        quality,
        video: _selectedVideo,
        position: state.position,
        play: state.playing,
      ).timeout(const Duration(seconds: 20));
      if (!ready) throw StateError('Media3 lehnte ${quality.label} ab.');
      if (!mounted) return;
      setState(() {
        _selectedQuality = quality;
        _isChangingQuality = false;
      });
      AppLog.instance.info(
        'player.quality.changed',
        fields: {
          'mediaId': _selectedVideo.id,
          'backend': 'androidMedia3ExoPlayerAudio',
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
      _prepareNextQueuePlayback(_loadGeneration);
    } on Exception catch (error, stackTrace) {
      AppLog.instance.error(
        'player.quality.change_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'mediaId': _selectedVideo.id,
          'backend': 'androidMedia3ExoPlayerAudio',
          'from': previousQuality.label,
          'to': quality.label,
          'durationMs': qualityStopwatch.elapsedMilliseconds,
        },
      );
      Object? restoreError;
      StackTrace? restoreStackTrace;
      try {
        await _openAndroidMedia3AudioQuality(
          previousQuality,
          video: _selectedVideo,
          position: state.position,
          play: state.playing,
        ).timeout(const Duration(seconds: 20));
      } on Exception catch (error, stackTrace) {
        restoreError = error;
        restoreStackTrace = stackTrace;
      }
      if (!mounted) return;
      setState(() => _isChangingQuality = false);
      final details = StringBuffer(_technicalErrorDetails(error, stackTrace));
      if (restoreError != null) {
        details
          ..writeln()
          ..writeln()
          ..writeln(
            'Fehler beim Wiederherstellen von ${previousQuality.label}:',
          )
          ..write(_technicalErrorDetails(restoreError, restoreStackTrace!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.qualityLoadFailed(quality.label)),
          action: SnackBarAction(
            label: context.l10n.details,
            onPressed: () =>
                unawaited(_showTechnicalDetails(details.toString())),
          ),
        ),
      );
    }
    _showControls();
  }

  Future<void> _changeNativeIosMainPlayerQuality(
    VideoQualityOption quality,
  ) async {
    final previousQuality = _selectedQuality;
    if (previousQuality == null || quality == previousQuality) {
      return;
    }
    final state = _playbackState.value;
    setState(() => _isChangingQuality = true);
    _showControls();

    Future<bool> open(VideoQualityOption candidate) async {
      final streamUrl = await _registerIosPictureInPictureQuality(candidate);
      return IosPictureInPicture.instance.openMainPlayer(
        streamUrl: streamUrl,
        title: _selectedVideo.title,
        artist: _selectedVideo.channelTitle.isEmpty
            ? _mediaArtist(_selectedVideo.description)
            : _selectedVideo.channelTitle,
        thumbnailUrl: _selectedVideo.thumbnailUrl,
        playbackVolume: _volume * _systemAudioVolumeFactor,
        position: state.position,
        playing: state.playing,
        autoEnterEnabled:
            PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
              pictureInPictureAllowed: _allowsPictureInPicture,
              playing: state.playing,
            ),
        pictureInPictureEnabled: _allowsPictureInPicture,
        continuesAudioInBackground: _selectedVideo.isMusic,
        isLive: _isLivePlayback,
      );
    }

    try {
      final ready = await open(quality).timeout(const Duration(seconds: 20));
      if (!ready) {
        throw StateError('Native iOS AVPlayer rejected ${quality.label}.');
      }
      if (mounted) {
        setState(() {
          _selectedQuality = quality;
          _isChangingQuality = false;
          _iosPictureInPictureUsesHlsMaster = quality.hlsMasterPlaylist != null;
        });
      }
    } on Exception catch (error, stackTrace) {
      Object? restoreError;
      StackTrace? restoreStackTrace;
      try {
        await open(previousQuality).timeout(const Duration(seconds: 20));
      } on Exception catch (error, stackTrace) {
        restoreError = error;
        restoreStackTrace = stackTrace;
      }
      if (!mounted) {
        return;
      }
      setState(() => _isChangingQuality = false);
      final details = StringBuffer(_technicalErrorDetails(error, stackTrace));
      if (restoreError != null) {
        details
          ..writeln()
          ..writeln()
          ..writeln(
            'Fehler beim Wiederherstellen von ${previousQuality.label}:',
          )
          ..write(_technicalErrorDetails(restoreError, restoreStackTrace!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.qualityLoadFailed(quality.label)),
          action: SnackBarAction(
            label: context.l10n.details,
            onPressed: () =>
                unawaited(_showTechnicalDetails(details.toString())),
          ),
        ),
      );
    }
    _showControls();
  }

  Future<void> _changeNativeIosAudioPlayerQuality(
    VideoQualityOption quality,
  ) async {
    final playback = _playback;
    final previousQuality = _selectedQuality;
    if (playback == null ||
        previousQuality == null ||
        quality == previousQuality) {
      return;
    }
    final state = _playbackState.value;
    setState(() => _isChangingQuality = true);
    _showControls();

    Future<bool> open(VideoQualityOption candidate) async {
      final streamUrl = await _registerIosPictureInPictureQuality(candidate);
      return IosNativeAudioPlayback.instance.open(
        streamUrl: streamUrl,
        title: _selectedVideo.title,
        artist: _selectedVideo.channelTitle.isEmpty
            ? _mediaArtist(_selectedVideo.description)
            : _selectedVideo.channelTitle,
        thumbnailUrl: _selectedVideo.thumbnailUrl,
        volume: _volume * _systemAudioVolumeFactor,
        position: state.position,
        playing: state.playing,
        hasPrevious: _previousPlayedMedia != null,
        hasNext: _nextPlayerControlTarget != null,
        expectedDuration: _canonicalAudioDuration(_selectedVideo, candidate),
        crossfadeDuration: playlistAudioFadeDuration,
      );
    }

    try {
      final ready = await open(quality).timeout(const Duration(seconds: 20));
      if (!ready) {
        throw StateError('Native iOS AVPlayer rejected the audio stream.');
      }
      if (mounted) {
        setState(() {
          _selectedQuality = quality;
          _isChangingQuality = false;
        });
      }
      _prepareNextQueuePlayback(_loadGeneration);
    } on Exception catch (error, stackTrace) {
      Object? restoreError;
      StackTrace? restoreStackTrace;
      try {
        await open(previousQuality).timeout(const Duration(seconds: 20));
      } on Exception catch (error, stackTrace) {
        restoreError = error;
        restoreStackTrace = stackTrace;
      }
      if (!mounted) {
        return;
      }
      setState(() => _isChangingQuality = false);
      final details = StringBuffer(_technicalErrorDetails(error, stackTrace));
      if (restoreError != null) {
        details
          ..writeln()
          ..writeln()
          ..writeln(
            'Fehler beim Wiederherstellen von ${previousQuality.label}:',
          )
          ..write(_technicalErrorDetails(restoreError, restoreStackTrace!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.qualityLoadFailed(quality.label)),
          action: SnackBarAction(
            label: context.l10n.details,
            onPressed: () =>
                unawaited(_showTechnicalDetails(details.toString())),
          ),
        ),
      );
    }
    _showControls();
  }

  void _startPlayerTutorialIfNeeded() {
    if (!mounted ||
        !_profileController.shouldShowTutorialStage(AppTutorialStage.player)) {
      return;
    }
    _hideControlsTimer?.cancel();
    setState(() {
      _selectedAppSection = 0;
      _controlsVisible = true;
      _settingsVisible = false;
      _playerTutorialStep = PlayerTutorialStep.centerPlayback;
    });
  }

  Future<void> _restartTutorialFromProfile() async {
    await _profileController.restartTutorial();
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  void _advancePlayerTutorial() {
    final step = _playerTutorialStep;
    if (step == null) {
      return;
    }
    if (step == PlayerTutorialStep.values.last) {
      _completePlayerTutorial();
      return;
    }
    setState(() {
      _controlsVisible = true;
      _settingsVisible = false;
      _playerTutorialStep = PlayerTutorialStep.values[step.index + 1];
    });
  }

  void _goBackInPlayerTutorial() {
    final step = _playerTutorialStep;
    if (step == null || !step.hasPrevious) {
      return;
    }
    setState(() {
      _controlsVisible = true;
      _settingsVisible = false;
      _playerTutorialStep = PlayerTutorialStep.values[step.index - 1];
    });
  }

  void _completePlayerTutorial() {
    if (!mounted || _playerTutorialStep == null) {
      return;
    }
    setState(() {
      _playerTutorialStep = null;
      _settingsVisible = false;
    });
    unawaited(
      _profileController.completeTutorialStage(AppTutorialStage.player),
    );
    _restartControlsTimer();
  }

  void _skipAllTutorialsFromPlayer() {
    if (!mounted || _playerTutorialStep == null) {
      return;
    }
    setState(() {
      _playerTutorialStep = null;
      _settingsVisible = false;
    });
    unawaited(_profileController.completeAllTutorialStages());
    _restartControlsTimer();
  }

  Widget? _buildPlayerTutorialOverlay() {
    final step = _playerTutorialStep;
    if (step == null || _isInPictureInPictureMode) {
      return null;
    }
    final title = switch (step) {
      PlayerTutorialStep.centerPlayback =>
        context.l10n.playerTutorialCenterTitle,
      PlayerTutorialStep.doubleTapSeek =>
        context.l10n.playerTutorialDoubleTapTitle,
      PlayerTutorialStep.holdSeek => context.l10n.playerTutorialHoldTitle,
      PlayerTutorialStep.transport => context.l10n.playerTutorialTransportTitle,
      PlayerTutorialStep.options => context.l10n.playerTutorialOptionsTitle,
      PlayerTutorialStep.autoplay => context.l10n.playerTutorialAutoplayTitle,
      PlayerTutorialStep.shuffle => context.l10n.playerTutorialShuffleTitle,
      PlayerTutorialStep.reactions => context.l10n.playerTutorialReactionsTitle,
      PlayerTutorialStep.favorite => context.l10n.playerTutorialFavoriteTitle,
      PlayerTutorialStep.playlist => context.l10n.playerTutorialPlaylistTitle,
      PlayerTutorialStep.info => context.l10n.playerTutorialInfoTitle,
    };
    final message = switch (step) {
      PlayerTutorialStep.centerPlayback =>
        context.l10n.playerTutorialCenterMessage,
      PlayerTutorialStep.doubleTapSeek =>
        context.l10n.playerTutorialDoubleTapMessage,
      PlayerTutorialStep.holdSeek => context.l10n.playerTutorialHoldMessage,
      PlayerTutorialStep.transport =>
        context.l10n.playerTutorialTransportMessage,
      PlayerTutorialStep.options => context.l10n.playerTutorialOptionsMessage,
      PlayerTutorialStep.autoplay => context.l10n.playerTutorialAutoplayMessage,
      PlayerTutorialStep.shuffle => context.l10n.playerTutorialShuffleMessage,
      PlayerTutorialStep.reactions =>
        context.l10n.playerTutorialReactionsMessage,
      PlayerTutorialStep.favorite => context.l10n.playerTutorialFavoriteMessage,
      PlayerTutorialStep.playlist => context.l10n.playerTutorialPlaylistMessage,
      PlayerTutorialStep.info => context.l10n.playerTutorialInfoMessage,
    };
    return TutorialCoachOverlay(
      targetKey: _playerTutorialTargets.target(step),
      additionalTargetKeys: _playerTutorialTargets.additionalTargets(step),
      sectionLabel: context.l10n.playerTutorialSection,
      tutorial: 4,
      tutorialCount: AppTutorialStage.values.length,
      title: title,
      message: message,
      step: step.number,
      stepCount: PlayerTutorialStep.values.length,
      onSkip: _skipAllTutorialsFromPlayer,
      onBack: step.hasPrevious ? _goBackInPlayerTutorial : null,
      onNext: _advancePlayerTutorial,
      nextLabel: step == PlayerTutorialStep.values.last
          ? context.l10n.finish
          : null,
    );
  }

  Widget _withPlayerTutorial(Widget child) {
    final tutorialActive = _playerTutorialStep != null;
    final overlay = _buildPlayerTutorialOverlay();
    if (!tutorialActive) {
      return child;
    }
    return PopScope(
      key: const Key('player-tutorial-navigation-lock'),
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (overlay == null)
            const Positioned.fill(
              child: ModalBarrier(
                key: Key('player-tutorial-transition-blocker'),
                dismissible: false,
                color: Colors.transparent,
              ),
            )
          else
            Positioned.fill(child: overlay),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fullscreenLayout = PlayerFullscreenPolicy.usesFullscreenLayout(
      fullscreenRequested: _fullscreenRequested,
      landscape: landscape,
    );
    _syncSystemUi(fullscreenLayout);

    if (_isInPictureInPictureMode &&
        AndroidPictureInPicture.instance.isSupportedPlatform) {
      return _withPlayerTutorial(
        Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: _buildTrackedPlayer()),
        ),
      );
    }

    if (fullscreenLayout) {
      return _withPlayerTutorial(
        Scaffold(
          key: const Key('player-fullscreen-layout'),
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: _buildPullUpFullscreenPlayer()),
        ),
      );
    }

    return _withPlayerTutorial(
      Scaffold(
        appBar: switch (_selectedAppSection) {
          1 => AppBar(
            title: Text(context.l10n.hotMusic),
            centerTitle: false,
            automaticallyImplyLeading: false,
          ),
          2 => AppBar(
            title: Text(context.l10n.myProfile),
            centerTitle: false,
            automaticallyImplyLeading: false,
          ),
          _ => null,
        },
        body: IndexedStack(
          index: _selectedAppSection,
          children: [
            _buildPortraitPlayerSection(),
            _buildHotMusicSection(),
            _buildProfileSection(),
          ],
        ),
        bottomNavigationBar: _buildAnimatedSectionNavigationBar(),
      ),
    );
  }

  Widget _buildAnimatedSectionNavigationBar() {
    return AnimatedBuilder(
      animation: _pullDownFullscreenController,
      child: AppSectionNavigationBar(
        keyPrefix: 'player',
        selectedIndex: _selectedAppSection,
        onDestinationSelected: _selectAppSection,
      ),
      builder: (context, child) {
        final progress = _selectedAppSection == 0
            ? _pullDownFullscreenController.value
            : 0.0;
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - progress,
            child: Opacity(opacity: 1 - progress, child: child),
          ),
        );
      },
    );
  }

  Widget _buildHotMusicSection() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: HotMusicPage(
            active: _selectedAppSection == 1,
            repository: _musicDiscoveryRepository,
            profileController: _profileController,
            onVideoSelected: _openHotMusicVideo,
            onPlaylistSelected: (playlist) =>
                unawaited(_openHotMusicPlaylist(playlist)),
            onArtistSelected: (artist) =>
                unawaited(_openHotMusicArtist(artist)),
            onToggleVideoFavorite: _toggleResultFavorite,
            onAddVideoToPlaylist: _addResultToPlaylist,
            onImportPlaylist: _importHotMusicPlaylist,
            onToggleArtistFavorite: _toggleChannelFavorite,
            loadFullDescription: (video) =>
                widget.videoDetailsRepository?.loadDescription(
                  videoId: video.id,
                  languageCode: _playbackLanguageCode,
                ) ??
                Future<String>.value(video.description),
            keyPrefix: 'player-hot-music',
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitPlayerSection() {
    final mediaPadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final contentWidth = math.min(960.0, viewportSize.width);
        final contentLeft = (viewportSize.width - contentWidth) / 2;
        final normalPlayerHeight = math
            .min(
              contentWidth * 9 / 16,
              math.max(
                0,
                viewportSize.height - mediaPadding.top - mediaPadding.bottom,
              ),
            )
            .toDouble();
        final normalPlayerRect = Rect.fromLTWH(
          contentLeft,
          mediaPadding.top,
          contentWidth,
          normalPlayerHeight,
        );
        final fullscreenPlayerRect = Offset.zero & viewportSize;

        return AnimatedBuilder(
          animation: _pullDownFullscreenController,
          builder: (context, _) {
            final progress = _pullDownFullscreenController.value;
            final playerRect = Rect.lerp(
              normalPlayerRect,
              fullscreenPlayerRect,
              progress,
            )!;
            final contentOpacity = (1 - progress * 1.5)
                .clamp(0.0, 1.0)
                .toDouble();
            final backgroundColor = Color.lerp(
              Theme.of(context).scaffoldBackgroundColor,
              Colors.black,
              progress,
            )!;

            return ColoredBox(
              key: const Key('player-pull-down-transition'),
              color: backgroundColor,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: contentLeft,
                    top: mediaPadding.top,
                    right: contentLeft,
                    bottom: mediaPadding.bottom,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: Column(
                        children: [
                          SizedBox(height: normalPlayerHeight),
                          _buildPullDownFullscreenDragRegion(
                            key: const Key('player-pull-down-content-region'),
                            child: _buildPortraitPlayerToolbar(),
                          ),
                          Expanded(child: _buildResults()),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: playerRect,
                    child: _buildPullDownFullscreenDragRegion(
                      key: const Key('player-pull-down-surface'),
                      child: _buildTrackedPlayer(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPortraitPlayerToolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileActions(),
        _buildCompactSearch(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
          child: MediaSearchCategoryBar(
            selected: _searchCategory,
            onSelected: _selectSearchCategory,
            keyPrefix: 'player-search',
            enabled: !_isSearching,
            musicMode: _isMusicSearchMode,
            videoSortingEnabled: _videoSortingEnabled,
            playlistSortingEnabled: !_isMusicSearchMode,
            videoSort: _videoSearchSort,
            playlistSort: _playlistSearchSort,
            onSortSelected: youtubeSearchSortControlsEnabled
                ? _selectSearchSort
                : null,
          ),
        ),
        if (_isSearching && !_isLoadingMoreForActiveCategory)
          const LinearProgressIndicator(minHeight: 2),
        if (_searchError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              context.l10n.translateKnownMessage(error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileSection() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ProfilePage(
            controller: _profileController,
            onVideoSelected: _openProfileVideo,
            onPlaylistSelected: _openProfilePlaylist,
            onChannelSelected: _openProfileChannel,
            onRestartTutorial: _restartTutorialFromProfile,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileActions() {
    return AnimatedBuilder(
      animation: _profileController,
      builder: (context, _) {
        final profile = _profileController.activeProfile;
        final favorite =
            profile?.favorites.any((video) => video.id == _selectedVideo.id) ??
            false;
        final reaction =
            profile?.reactionFor(_selectedVideo.id) ?? VideoReaction.none;
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: _playerTutorialTargets.autoplay,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            key: const Key('video-autoplay-switch'),
                            value: profile?.autoplaySearchResults ?? false,
                            onChanged: (enabled) =>
                                unawaited(_toggleAutoplay(enabled)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          Text(
                            context.l10n.autoplay,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    KeyedSubtree(
                      key: _playerTutorialTargets.shuffle,
                      child: IconButton(
                        key: const Key('video-shuffle-button'),
                        tooltip: _shuffleEnabled
                            ? context.l10n.disableShuffle
                            : context.l10n.enableShuffle,
                        isSelected: _shuffleEnabled,
                        onPressed:
                            _autoplayEnabled && _playbackQueue.items.length > 1
                            ? () => unawaited(_toggleShuffle())
                            : null,
                        icon: const Icon(Icons.shuffle),
                        selectedIcon: Icon(
                          Icons.shuffle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        visualDensity: const VisualDensity(horizontal: -2),
                      ),
                    ),
                    const Spacer(),
                    KeyedSubtree(
                      key: _playerTutorialTargets.reactions,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const Key('video-like-button'),
                            tooltip: context.l10n.like,
                            isSelected: reaction == VideoReaction.like,
                            onPressed: () =>
                                _toggleReaction(VideoReaction.like),
                            icon: const Icon(Icons.thumb_up_outlined),
                            selectedIcon: const Icon(Icons.thumb_up),
                            visualDensity: const VisualDensity(horizontal: -2),
                          ),
                          IconButton(
                            key: const Key('video-dislike-button'),
                            tooltip: context.l10n.dislike,
                            isSelected: reaction == VideoReaction.dislike,
                            onPressed: () =>
                                _toggleReaction(VideoReaction.dislike),
                            icon: const Icon(Icons.thumb_down_outlined),
                            selectedIcon: const Icon(Icons.thumb_down),
                            visualDensity: const VisualDensity(horizontal: -2),
                          ),
                        ],
                      ),
                    ),
                    KeyedSubtree(
                      key: _playerTutorialTargets.favorite,
                      child: IconButton(
                        key: const Key('video-favorite-button'),
                        tooltip: favorite
                            ? context.l10n.removeFavorite
                            : context.l10n.addFavorite,
                        isSelected: favorite,
                        onPressed: _toggleFavorite,
                        icon: const Icon(Icons.favorite_border),
                        selectedIcon: const Icon(
                          Icons.favorite,
                          color: Colors.red,
                        ),
                        visualDensity: const VisualDensity(horizontal: -2),
                      ),
                    ),
                    KeyedSubtree(
                      key: _playerTutorialTargets.playlist,
                      child: IconButton.filledTonal(
                        key: const Key('video-add-playlist-button'),
                        tooltip: context.l10n.addToPlaylist,
                        onPressed: _addToPlaylist,
                        icon: const Icon(Icons.playlist_add),
                        visualDensity: const VisualDensity(horizontal: -2),
                      ),
                    ),
                    KeyedSubtree(
                      key: _playerTutorialTargets.info,
                      child: VideoInfoButton(
                        key: const Key('video-info-button'),
                        video: _selectedVideo,
                        loadFullDescription: _fullDescriptionLoaderFor(
                          _selectedVideo,
                        ),
                        compactHorizontally: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: AnimatedBuilder(
        animation: _profileController,
        builder: (context, _) => MediaSourceSearchBar(
          controller: _queryController,
          isLoading: _isSearching,
          sourceSelectionEnabled: _sourceSelectionEnabled,
          source: _searchSource,
          category: _searchCategory,
          onSourceChanged: _selectSearchSource,
          onSearch: _search,
          searchHistory:
              _profileController.activeProfile?.searchHistory ?? const [],
          onSearchHistoryDeleted: (entry) =>
              unawaited(_profileController.deleteSearchHistoryEntry(entry)),
          compact: true,
          keyPrefix: 'player-search',
        ),
      ),
    );
  }

  Widget _buildResults() {
    return switch (_searchCategory) {
      YouTubeSearchCategory.videos => _buildVideoResults(),
      YouTubeSearchCategory.channels => _buildChannelResults(),
      YouTubeSearchCategory.playlists => _buildPlaylistResults(),
    };
  }

  Widget _buildVideoResults() {
    final results = _visibleResults;
    if (results.isEmpty) {
      if (!_resultsRepresentPlaylist && _nextPageToken != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_loadMoreResults());
          }
        });
        return _buildPullDownAwareVideoResults(
          ListView(
            key: const Key('player-video-results'),
            controller: _videoResultsScrollController,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
            children: [_buildVideoResultsTail()],
          ),
        );
      }
      return _buildPullDownFullscreenDragRegion(
        key: const Key('player-empty-results-pull-down-region'),
        child: Center(
          child: Text(
            _searchQuery.isEmpty
                ? context.l10n.noAdditionalResults
                : context.l10n.noMoreResults(_searchQuery),
          ),
        ),
      );
    }

    return _buildPullDownAwareVideoResults(
      ListView.separated(
        key: const Key('player-video-results'),
        controller: _videoResultsScrollController,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        itemCount: results.length + (_resultsRepresentPlaylist ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == results.length) {
            return _buildVideoResultsTail();
          }
          _scheduleLoadMore(index, results.length);
          final video = results[index];
          return AnimatedBuilder(
            key: ValueKey(video.id),
            animation: _profileController,
            builder: (context, _) => VideoResultCard(
              video: video,
              onTap: () => _selectVideo(video),
              isFavorite: _profileController.isFavorite(video.id),
              onToggleFavorite: () => _toggleResultFavorite(video),
              onAddToPlaylist: () => _addResultToPlaylist(video),
              showInfo: true,
              loadFullDescription: _fullDescriptionLoaderFor(video),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelResults() {
    final state = _catalogSearchStates[YouTubeSearchCategory.channels]!;
    if (!state.hasSearched) {
      return Center(
        child: Text(
          _isMusicSearchMode
              ? context.l10n.artistSearchAbove
              : context.l10n.channelSearchAbove,
        ),
      );
    }
    if (state.channels.isEmpty) {
      return Center(
        child: Text(
          _isMusicSearchMode
              ? context.l10n.noArtistsFound
              : context.l10n.noChannelsFound,
        ),
      );
    }
    return ListView.separated(
      key: const Key('player-channel-results'),
      controller: _channelResultsScrollController,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
      itemCount: state.channels.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == state.channels.length) {
          return _buildCatalogResultsTail(state);
        }
        _scheduleLoadMore(index, state.channels.length);
        final channel = state.channels[index];
        return AnimatedBuilder(
          key: ValueKey('player-channel-${channel.id}'),
          animation: _profileController,
          builder: (context, _) => YouTubeChannelResultCard(
            channel: channel,
            onTap: () => _openChannel(channel),
            isFavorite: _profileController.isChannelFavorite(channel.id),
            onToggleFavorite: () => _toggleChannelFavorite(channel),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistResults() {
    final state = _catalogSearchStates[YouTubeSearchCategory.playlists]!;
    if (!state.hasSearched) {
      return Center(
        child: Text(
          _isMusicSearchMode
              ? context.l10n.songPlaylistSearchAbove
              : context.l10n.playlistSearchAbove,
        ),
      );
    }
    if (state.playlists.isEmpty) {
      return Center(child: Text(context.l10n.noPlaylistsFound));
    }
    return ListView.separated(
      key: const Key('player-playlist-results'),
      controller: _playlistResultsScrollController,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
      itemCount: state.playlists.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == state.playlists.length) {
          return _buildCatalogResultsTail(state);
        }
        _scheduleLoadMore(index, state.playlists.length);
        final playlist = state.playlists[index];
        return YouTubePlaylistResultCard(
          key: ValueKey('player-youtube-playlist-${playlist.id}'),
          playlist: playlist,
          onTap: () => _openYouTubePlaylist(playlist),
          onAddToPlaylist: () => _addCatalogPlaylistToLocalPlaylist(playlist),
        );
      },
    );
  }

  bool get _isLoadingMoreForActiveCategory =>
      _searchCategory == YouTubeSearchCategory.videos
      ? _isLoadingMoreResults
      : _catalogSearchStates[_searchCategory]!.isLoadingMore;

  Widget _buildVideoResultsTail() {
    return _buildResultsTail(
      keyPrefix: 'player-video',
      isLoading: _isLoadingMoreResults,
      resultCount: _searchResults.length,
      hasReachedEnd: _hasReachedResultsEnd,
      error: _loadMoreResultsError,
    );
  }

  Widget _buildCatalogResultsTail(_PlayerCatalogSearchState state) {
    return _buildResultsTail(
      keyPrefix: 'player-${_searchCategory.name}',
      isLoading: state.isLoadingMore,
      resultCount: state.resultCount,
      hasReachedEnd: state.hasReachedEnd,
      error: state.loadMoreError,
    );
  }

  Widget _buildResultsTail({
    required String keyPrefix,
    required bool isLoading,
    required int resultCount,
    required bool hasReachedEnd,
    required String? error,
  }) {
    if (isLoading) {
      return Padding(
        key: ValueKey('$keyPrefix-loading-more'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: const Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        key: ValueKey('$keyPrefix-load-more-error'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.translateKnownMessage(error),
              textAlign: TextAlign.center,
            ),
            TextButton(
              key: ValueKey('$keyPrefix-load-more-retry'),
              onPressed: () => unawaited(_loadMoreResults()),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }
    if (resultCount >= searchResultLimit) {
      return Padding(
        key: ValueKey('$keyPrefix-result-limit'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '- ${context.l10n.resultLimitReached} -',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (hasReachedEnd) {
      return Padding(
        key: ValueKey('$keyPrefix-no-more-results'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '- ${context.l10n.noMoreHits} -',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }

  Widget _buildTrackedPlayer() {
    return SizedBox.expand(child: _buildPlayer());
  }

  Widget _buildPlayer() {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_selectedVideo.isAudioOnlyMusic) _buildMusicPlayerArtwork(),
          if (_preparedNextPlayback?.videoController case final controller?)
            Offstage(
              offstage: true,
              child: Video(
                controller: controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
                pauseUponEnteringBackgroundMode: false,
              ),
            ),
          if (_hasCurrentPlayer &&
              (_selectedVideo.isAudioOnlyMusic ||
                  _videoController != null ||
                  _nativeAndroidMedia3PlayerActive ||
                  _nativeIosMainPlayerActive))
            ValueListenableBuilder<_PlaybackViewState>(
              valueListenable: _playbackState,
              builder: (context, value, _) =>
                  _buildInitializedPlayer(_videoController, value),
            )
          else if (_isLoadingVideo)
            const Center(child: CircularProgressIndicator())
          else
            _buildPlayerError(),
          if (_playerTutorialStep != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Row(
                  children: [
                    Expanded(
                      flex: 32,
                      child: KeyedSubtree(
                        key: _playerTutorialTargets.leftSurface,
                        child: const SizedBox.expand(
                          key: Key('player-tutorial-left-zone'),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 36,
                      child: KeyedSubtree(
                        key: _playerTutorialTargets.centerSurface,
                        child: const SizedBox.expand(
                          key: Key('player-tutorial-center-zone'),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 32,
                      child: KeyedSubtree(
                        key: _playerTutorialTargets.rightSurface,
                        child: const SizedBox.expand(
                          key: Key('player-tutorial-right-zone'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMusicPlayerArtwork() {
    final thumbnailUrl = _selectedVideo.thumbnailUrl.trim();
    final fallback = const Center(
      child: Icon(Icons.music_note, size: 72, color: Colors.white54),
    );
    return KeyedSubtree(
      key: const Key('music-player-artwork'),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_brightnessMatrix),
        child: thumbnailUrl.isEmpty
            ? fallback
            : Image.network(
                thumbnailUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  Widget _buildInitializedPlayer(
    VideoController? controller,
    _PlaybackViewState value,
  ) {
    final nativeVideoLoading =
        (_nativeAndroidMedia3PlayerActive || _nativeIosMainPlayerActive) &&
        _isLoadingVideo;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fullscreenLayout = PlayerFullscreenPolicy.usesFullscreenLayout(
      fullscreenRequested: _fullscreenRequested,
      landscape: landscape,
    );
    final playerControlsVisible =
        _controlsVisible && !_isInPictureInPictureMode;
    final subtitle = _subtitlesEnabled
        ? _playback?.subtitleAt(value.position)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        void startEdgeSeek(LongPressStartDetails details) {
          final x = details.localPosition.dx;
          if (x <= constraints.maxWidth * 0.32) {
            _startHoldSeek(const Duration(seconds: -2));
          } else if (x >= constraints.maxWidth * 0.68) {
            _startHoldSeek(const Duration(seconds: 2));
          }
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _showControls(),
          onPointerMove: (_) => _restartControlsTimer(),
          onPointerUp: (_) {
            if (_seekHoldTimer != null) {
              _stopHoldSeek();
            } else {
              _restartControlsTimer();
            }
          },
          onPointerCancel: (_) => _stopHoldSeek(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              _showControls();
              if (isCenterPlaybackTap(
                localX: details.localPosition.dx,
                width: constraints.maxWidth,
              )) {
                if (value.playing) {
                  _gestureFeedbackController.clear();
                } else {
                  _gestureFeedbackController.showTransient(
                    PlayerGestureFeedback.play,
                  );
                }
                unawaited(_togglePlayback(value));
              }
            },
            onDoubleTapDown: (details) {
              _lastDoubleTapPosition = details.localPosition;
            },
            onDoubleTap: () {
              _showControls();
              final x = _lastDoubleTapPosition?.dx;
              if (x == null) {
                return;
              }
              final offset = doubleTapSeekOffset(
                localX: x,
                width: constraints.maxWidth,
              );
              if (!_isLivePlayback) {
                _gestureFeedbackController.showTransient(
                  offset.isNegative
                      ? PlayerGestureFeedback.rewindTen
                      : PlayerGestureFeedback.forwardTen,
                );
              }
              unawaited(_seekRelative(offset));
            },
            onLongPressStart: startEdgeSeek,
            onLongPressEnd: (_) => _stopHoldSeek(),
            onLongPressCancel: _stopHoldSeek,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_selectedVideo.hasVideo && controller != null)
                  Center(
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio == 0
                          ? 16 / 9
                          : value.aspectRatio,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(_brightnessMatrix),
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                          pauseUponEnteringBackgroundMode: false,
                        ),
                      ),
                    ),
                  ),
                if (_selectedVideo.hasVideo && _nativeAndroidMedia3PlayerActive)
                  const Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: AndroidMedia3VideoView(
                        key: Key('android-media3-video-view'),
                      ),
                    ),
                  ),
                if (_selectedVideo.hasVideo && _nativeIosMainPlayerActive)
                  const Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: UiKitView(
                        viewType: 'flutter_browser_app/ios_native_player_view',
                        hitTestBehavior:
                            PlatformViewHitTestBehavior.transparent,
                      ),
                    ),
                  ),
                if (_selectedVideo.hasVideo &&
                    (_nativeAndroidMedia3PlayerActive ||
                        _nativeIosMainPlayerActive) &&
                    _brightness < 1.5)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: ((1.5 - _brightness) / 1.5).clamp(0.0, 0.84),
                      ),
                    ),
                  ),
                if (shouldShowPlayerLoadingIndicator(
                  buffering: value.buffering,
                  changingQuality: _isChangingQuality,
                  nativeIosVideoLoading: nativeVideoLoading,
                ))
                  const Center(child: CircularProgressIndicator()),
                if (subtitle != null && subtitle.isNotEmpty)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: playerControlsVisible ? 102 : 20,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ValueListenableBuilder<PlayerGestureFeedback?>(
                  valueListenable: _gestureFeedbackController,
                  builder: (context, feedback, _) =>
                      PlayerGestureFeedbackOverlay(
                        showPersistentPause: shouldShowPersistentPauseFeedback(
                          playing: value.playing,
                          buffering: value.buffering,
                          nativeIosVideoLoading: nativeVideoLoading,
                        ),
                        feedback: feedback,
                      ),
                ),
                if (playerControlsVisible)
                  _buildControls(value, fullscreen: fullscreenLayout),
                if (playerControlsVisible && !fullscreenLayout)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: IconButton(
                        tooltip: context.l10n.back,
                        onPressed: () => Navigator.of(context).pop(),
                        color: Colors.white,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                if (playerControlsVisible && _settingsVisible)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('player-settings-dismiss-layer'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _settingsVisible = false);
                        _restartControlsTimer();
                      },
                    ),
                  ),
                if (playerControlsVisible && _settingsVisible)
                  Positioned(
                    right: 8,
                    bottom: 52,
                    width: constraints.maxWidth > 300
                        ? 280
                        : constraints.maxWidth - 16,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (constraints.maxHeight - 60).clamp(100, 220),
                      ),
                      child: _buildSettingsPanel(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<double> get _brightnessMatrix => <double>[
    _brightness,
    0,
    0,
    0,
    0,
    0,
    _brightness,
    0,
    0,
    0,
    0,
    0,
    _brightness,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  Widget _buildControls(_PlaybackViewState value, {required bool fullscreen}) {
    final durationMs = value.duration.inMilliseconds;
    final canSeek = !_isLivePlayback && durationMs > 0;
    final shownPosition = _dragPosition ?? value.position;
    final positionMs = shownPosition.inMilliseconds.clamp(0, durationMs);

    return DecoratedBox(
      key: const Key('player-controls'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xDD000000)],
        ),
      ),
      child: Column(
        children: [
          const Spacer(),
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                _isLivePlayback ? 'LIVE' : _formatDuration(shownPosition),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              Expanded(
                child: Slider(
                  value: durationMs == 0 ? 0 : positionMs.toDouble(),
                  max: durationMs == 0 ? 1 : durationMs.toDouble(),
                  onChanged: !canSeek
                      ? null
                      : (value) => setState(
                          () => _dragPosition = Duration(
                            milliseconds: value.round(),
                          ),
                        ),
                  onChangeEnd: !canSeek
                      ? null
                      : (value) {
                          final target = Duration(milliseconds: value.round());
                          setState(() => _dragPosition = null);
                          if (_nativeAndroidMedia3PlayerActive) {
                            unawaited(
                              AndroidMedia3VideoPlayer.instance.seek(target),
                            );
                          } else if (_nativeAndroidMedia3AudioPlayerActive) {
                            unawaited(
                              AndroidMedia3AudioPlayback.instance.seek(target),
                            );
                          } else if (_nativeIosMainPlayerActive) {
                            unawaited(
                              IosPictureInPicture.instance.seek(target),
                            );
                          } else if (_nativeIosAudioPlayerActive) {
                            unawaited(
                              IosNativeAudioPlayback.instance.seek(target),
                            );
                          } else {
                            unawaited(_player?.seek(target));
                          }
                        },
                ),
              ),
              Text(
                _isLivePlayback ? '' : _formatDuration(value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              const SizedBox(width: 8),
            ],
          ),
          PlayerTransportControls(
            tutorialKey: _playerTutorialTargets.transport,
            settingsTutorialKey: _playerTutorialTargets.options,
            playing: value.playing,
            previousEnabled:
                _previousPlayedMedia != null && !_autoAdvanceInProgress,
            nextEnabled: _nextPlayedMedia != null && !_autoAdvanceInProgress,
            onPrevious: () => unawaited(_playPreviousHistoryItemFromPlayer()),
            onTogglePlayback: () => unawaited(_togglePlayback(value)),
            onNext: () => unawaited(_playNextItemFromPlayer()),
            showPictureInPicture:
                _allowsPictureInPicture &&
                (AndroidPictureInPicture.instance.isSupportedPlatform ||
                    IosPictureInPicture.instance.isSupportedPlatform),
            onPictureInPicture: _iosPictureInPicturePreparing
                ? null
                : _requestPictureInPictureFromButton,
            fullscreen: fullscreen,
            onToggleFullscreen: () => _toggleFullscreen(fullscreen),
            onOpenSettings: _toggleSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final hasSubtitles = _playback?.subtitles.isNotEmpty ?? false;

    return Material(
      key: const Key('player-settings-panel'),
      color: const Color(0xEE202124),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.high_quality, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.videoQuality,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (_isChangingQuality)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    _selectedQuality?.label ?? '–',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final quality in _playback?.qualities ?? const [])
              ListTile(
                key: ValueKey('quality-${quality.height}'),
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  quality == _selectedQuality
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Colors.white,
                  size: 20,
                ),
                title: Text(
                  quality.label,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: _isChangingQuality || quality == _selectedQuality
                    ? null
                    : () => unawaited(_changeQuality(quality)),
              ),
            const Divider(color: Colors.white24, height: 8),
            Row(
              children: [
                const Icon(Icons.closed_caption, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.subtitles,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                Switch(
                  value: hasSubtitles && _subtitlesEnabled,
                  onChanged: hasSubtitles
                      ? (enabled) => setState(() => _subtitlesEnabled = enabled)
                      : null,
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: _volume == 0
                      ? context.l10n.unmute
                      : context.l10n.mute,
                  onPressed: _toggleMute,
                  color: Colors.white,
                  icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up),
                ),
                Expanded(
                  child: Slider(
                    value: _volume,
                    onChanged: (value) => unawaited(_setVolume(value)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.brightness_6, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _brightness,
                    min: 0.25,
                    max: 1.5,
                    onChanged: (value) => setState(() => _brightness = value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerError() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(48, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 30),
                const SizedBox(height: 6),
                Text(
                  context.l10n.translateKnownMessage(
                    _playerError ?? context.l10n.videoLoadFailed,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _loadVideo(_selectedVideo),
                      child: Text(context.l10n.retry),
                    ),
                    if (_playerErrorDetails != null)
                      TextButton.icon(
                        key: const Key('player-error-details-button'),
                        onPressed: _showPlayerErrorDetails,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: Text(context.l10n.technicalDetails),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!PlayerFullscreenPolicy.usesFullscreenLayout(
          fullscreenRequested: _fullscreenRequested,
          landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
        ))
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: IconButton(
                tooltip: context.l10n.back,
                onPressed: () => Navigator.of(context).pop(),
                color: Colors.white,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showPlayerErrorDetails() async {
    final details = _playerErrorDetails;
    if (details == null) {
      return;
    }
    await _showTechnicalDetails(details);
  }

  Future<void> _showTechnicalDetails(String details) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.technicalDetails),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Text(
                details,
                key: const Key('player-error-details-text'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(dialogContext.l10n.technicalDetailsCopied),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(dialogContext.l10n.copy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.close),
          ),
        ],
      ),
    );
  }

  String _technicalErrorDetails(Object error, StackTrace stackTrace) {
    if (error is VideoPlaybackException) {
      return error.technicalDetails;
    }
    return '${error.runtimeType}: $error\n\n$stackTrace';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _PlayerCatalogSearchState {
  List<YouTubeChannelResult> channels = const [];
  List<YouTubePlaylistResult> playlists = const [];
  String query = '';
  String? nextPageToken;
  String? loadError;
  int pageNumber = 1;
  bool hasSearched = false;
  bool isLoadingMore = false;
  bool hasReachedEnd = false;
  String? loadMoreError;
  final Set<String> loadedPageTokens = {};

  int get resultCount => channels.length + playlists.length;
}

class _PreparedQueuePlayback {
  const _PreparedQueuePlayback({
    required this.video,
    required this.target,
    required this.playback,
    required this.selectedQuality,
    required this.player,
    required this.videoController,
    required this.isReady,
  });

  final YouTubeVideo video;
  final PlaybackNavigationTarget target;
  final ResolvedVideoPlayback playback;
  final VideoQualityOption selectedQuality;
  final Player player;
  final VideoController? videoController;
  final bool isReady;
}

class _OpenedPlayback {
  const _OpenedPlayback({
    required this.playback,
    required this.quality,
    required this.usedFallback,
  });

  final ResolvedVideoPlayback playback;
  final VideoQualityOption quality;
  final bool usedFallback;
}

class _PreparedNativeIosAudioPlayback {
  const _PreparedNativeIosAudioPlayback({
    required this.video,
    required this.target,
    required this.playback,
    required this.selectedQuality,
  });

  final YouTubeVideo video;
  final PlaybackNavigationTarget target;
  final ResolvedVideoPlayback playback;
  final VideoQualityOption selectedQuality;
}

class _PreparedNativeAndroidMedia3AudioPlayback {
  const _PreparedNativeAndroidMedia3AudioPlayback({
    required this.video,
    required this.target,
    required this.playback,
    required this.selectedQuality,
  });

  final YouTubeVideo video;
  final PlaybackNavigationTarget target;
  final ResolvedVideoPlayback playback;
  final VideoQualityOption selectedQuality;
}

class _PlaybackViewState {
  const _PlaybackViewState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.width = 0,
    this.height = 0,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 0 : width / height;

  _PlaybackViewState copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? buffering,
    int? width,
    int? height,
  }) {
    return _PlaybackViewState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
