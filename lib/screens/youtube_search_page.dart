import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_tutorial_stage.dart';
import '../models/hot_music.dart';
import '../models/user_profile.dart';
import '../models/search_result_limit.dart';
import '../models/video_search_source.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_category.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import '../services/playback_manifest_cache.dart';
import '../services/app_log.dart';
import '../services/profile_controller.dart';
import '../services/video_playback_service.dart';
import '../services/youtube_catalog_repository.dart';
import '../services/youtube_catalog_repository_factory.dart';
import '../services/youtube_music_search_repository.dart';
import '../services/youtube_music_catalog_repository.dart';
import '../services/youtube_music_discovery_repository.dart';
import '../services/youtube_search_repository.dart';
import '../services/youtube_search_repository_factory.dart';
import '../services/youtube_video_details_repository.dart';
import '../utils/search_request_policy.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/hot_music_tutorial_targets.dart';
import '../widgets/search_tutorial_targets.dart';
import '../widgets/app_section_navigation_bar.dart';
import '../widgets/media_search_category_bar.dart';
import '../widgets/media_source_search_bar.dart';
import '../widgets/video_result_card.dart';
import '../widgets/tutorial_coach_overlay.dart';
import '../widgets/youtube_catalog_result_card.dart';
import 'hot_music_page.dart';
import 'profile_page.dart';
import 'video_player_page.dart';

typedef VideoPageBuilder =
    Widget Function(
      YouTubeVideo video,
      List<YouTubeVideo> searchResults,
      String searchQuery,
      YouTubeSearchRepository searchRepository, {
      required bool initiallyPaused,
    });

class YouTubeSearchPage extends StatefulWidget {
  const YouTubeSearchPage({
    super.key,
    this.searchRepository,
    this.musicSearchRepository,
    this.videoPageBuilder,
    this.profileController,
    this.playbackService,
    this.videoDetailsRepository,
    this.catalogRepository,
  });

  final YouTubeSearchRepository? searchRepository;
  final YouTubeSearchRepository? musicSearchRepository;
  final VideoPageBuilder? videoPageBuilder;
  final ProfileController? profileController;
  final VideoPlaybackService? playbackService;
  final YouTubeVideoDetailsRepository? videoDetailsRepository;
  final YouTubeCatalogRepository? catalogRepository;

  @override
  State<YouTubeSearchPage> createState() => _YouTubeSearchPageState();
}

class _YouTubeSearchPageState extends State<YouTubeSearchPage> {
  static const int _loadMoreTriggerItemCount = 3;

  final _queryController = TextEditingController();
  final _resultsController = ScrollController();
  final _profileTutorialTargets = ProfileTutorialTargets();
  final _searchTutorialTargets = SearchTutorialTargets();
  final _hotMusicTutorialTargets = HotMusicTutorialTargets();
  final _hotMusicTutorialController = HotMusicTutorialController();

  late final YouTubeSearchRepository _youtubeSearchRepository;
  late final YouTubeSearchRepository _musicSearchRepository;
  late final bool _ownsYouTubeSearchRepository;
  late final bool _ownsMusicSearchRepository;
  late final bool _musicSearchAvailable;
  late final ProfileController _profileController;
  late final bool _ownsProfileController;
  late final VideoPlaybackService _playbackService;
  late final bool _ownsPlaybackService;
  late final PlaybackManifestCache _manifestCache;
  late final YouTubeCatalogRepository _catalogRepository;
  late final bool _ownsCatalogRepository;
  late final YouTubeVideoDetailsRepository _videoDetailsRepository;
  late final bool _ownsVideoDetailsRepository;
  String? _queryError;
  int _requestNumber = 0;
  bool _isLoading = false;
  int _selectedTab = 0;
  _ProfileTutorialStep? _profileTutorialStep;
  bool _profileTutorialMenuOpen = false;
  _SearchTutorialStep? _searchTutorialStep;
  bool _searchTutorialSourceMenuOpen = false;
  HotMusicTutorialStep? _hotMusicTutorialStep;
  bool _hotMusicTutorialMenuOpen = false;
  bool _hotMusicTutorialStartingSong = false;
  bool _hotMusicTutorialActionTargetReady = false;
  VideoSearchSource _searchSource = VideoSearchSource.youtube;
  YouTubeSearchCategory _searchCategory = YouTubeSearchCategory.videos;
  YouTubeSearchSort _sessionVideoSearchSort = YouTubeSearchSort.relevance;
  YouTubeSearchSort _sessionPlaylistSearchSort = YouTubeSearchSort.relevance;
  final Map<YouTubeSearchCategory, _SearchViewState> _searchStates = {
    for (final category in YouTubeSearchCategory.values)
      category: _SearchViewState(),
  };

  _SearchViewState get _searchState => _searchStates[_searchCategory]!;

  YouTubeSearchRepository get _activeSearchRepository =>
      _searchSource == VideoSearchSource.youtubeMusic
      ? _musicSearchRepository
      : _youtubeSearchRepository;

  YouTubeMusicCatalogRepository? get _musicCatalogRepository =>
      _musicSearchRepository is YouTubeMusicCatalogRepository
      ? _musicSearchRepository as YouTubeMusicCatalogRepository
      : null;

  YouTubeMusicDiscoveryRepository? get _musicDiscoveryRepository =>
      _musicSearchRepository is YouTubeMusicDiscoveryRepository
      ? _musicSearchRepository as YouTubeMusicDiscoveryRepository
      : null;

  bool get _isMusicMode => _searchSource == VideoSearchSource.youtubeMusic;

  YouTubeSearchSort get _videoSearchSort => youtubeSearchSortControlsEnabled
      ? _profileController.activeProfile?.videoSearchSort ??
            _sessionVideoSearchSort
      : YouTubeSearchSort.relevance;

  YouTubeSearchSort get _playlistSearchSort => youtubeSearchSortControlsEnabled
      ? _profileController.activeProfile?.playlistSearchSort ??
            _sessionPlaylistSearchSort
      : YouTubeSearchSort.relevance;

  bool get _videoSortingEnabled {
    if (_isMusicMode) {
      return false;
    }
    final feed = _searchStates[YouTubeSearchCategory.videos]!.videoFeed;
    return feed == null || feed.type == YouTubeVideoFeedType.keyword;
  }

  String get _categoryLabel =>
      context.l10n.categoryLabel(_searchCategory, music: _isMusicMode);

  String get _searchLanguageCode =>
      _profileController.activeProfile?.language.code ??
      ProfileLanguage.english.code;

  @override
  void initState() {
    super.initState();
    _ownsYouTubeSearchRepository = widget.searchRepository == null;
    _youtubeSearchRepository =
        widget.searchRepository ?? createYouTubeSearchRepository();
    _ownsMusicSearchRepository = widget.musicSearchRepository == null;
    _musicSearchRepository =
        widget.musicSearchRepository ?? createYouTubeMusicSearchRepository();
    _musicSearchAvailable =
        widget.musicSearchRepository != null || supportsYouTubeMusicSearch;
    _ownsProfileController = widget.profileController == null;
    _profileController =
        widget.profileController ?? ProfileController.inMemory();
    _profileController.addListener(_handleProfileControllerChanged);
    _ownsPlaybackService = widget.playbackService == null;
    _playbackService =
        widget.playbackService ?? YouTubeExplodePlaybackService();
    _manifestCache = PlaybackManifestCache(
      _playbackService,
      maxConcurrentPrefetchLoads: 2,
    );
    _manifestCache.pausePrefetch();
    _ownsCatalogRepository = widget.catalogRepository == null;
    _catalogRepository =
        widget.catalogRepository ?? createYouTubeCatalogRepository();
    _ownsVideoDetailsRepository = widget.videoDetailsRepository == null;
    _videoDetailsRepository =
        widget.videoDetailsRepository ?? YouTubeVideoDetailsRepository();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startNextTutorialStageIfNeeded(),
    );
  }

  @override
  void dispose() {
    _profileController.removeListener(_handleProfileControllerChanged);
    _manifestCache.clear();
    if (_ownsCatalogRepository) {
      _catalogRepository.close();
    }
    if (_ownsYouTubeSearchRepository) {
      _youtubeSearchRepository.close();
    }
    if (_ownsMusicSearchRepository &&
        !identical(_musicSearchRepository, _youtubeSearchRepository)) {
      _musicSearchRepository.close();
    }
    _queryController.dispose();
    _resultsController.dispose();
    if (_ownsProfileController) {
      _profileController.dispose();
    }
    if (_ownsPlaybackService) {
      _playbackService.close();
    }
    if (_ownsVideoDetailsRepository) {
      _videoDetailsRepository.close();
    }
    super.dispose();
  }

  Future<void> _startSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      AppLog.instance.warning('search.validation.empty_query');
      setState(() => _queryError = context.l10n.enterSearchTerm);
      return;
    }

    unawaited(_profileController.recordSearchQuery(query));
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _queryError = null);
    await _loadResults(
      category: _searchCategory,
      query: query,
      pageNumber: 1,
      videoFeed: _searchCategory == YouTubeSearchCategory.videos
          ? YouTubeVideoFeed.keyword(query: query)
          : null,
    );
  }

  Future<void> _loadResults({
    required YouTubeSearchCategory category,
    required String query,
    required int pageNumber,
    String? pageToken,
    YouTubeVideoFeed? videoFeed,
  }) async {
    final stopwatch = Stopwatch()..start();
    final state = _searchStates[category]!;
    final append = pageToken != null && state.resultCount > 0;
    if (append &&
        (_isLoading ||
            state.hasReachedEnd ||
            state.loadedPageTokens.contains(pageToken))) {
      return;
    }
    if (!append) {
      _manifestCache.clear();
      state.loadedPageTokens.clear();
    }
    final currentRequest = ++_requestNumber;
    final logFields = <String, Object?>{
      'request': currentRequest,
      'query': AppLog.instance.opaqueId(query.trim().toLowerCase()),
      'queryLength': query.trim().length,
      'source': _searchSource.name,
      'category': category.name,
      'language': _searchLanguageCode,
      'page': pageNumber,
      'append': append,
      'feed': videoFeed?.type.name ?? state.videoFeed?.type.name ?? 'keyword',
    };
    AppLog.instance.info('search.request.started', fields: logFields);
    state
      ..requestedPageToken = pageToken
      ..requestedPageNumber = pageNumber
      ..requestedAppend = append;

    setState(() {
      _isLoading = true;
      state.hasSearched = true;
      if (append) {
        state
          ..isLoadingMore = true
          ..loadMoreError = null;
      } else {
        state
          ..isLoadingMore = false
          ..hasReachedEnd = false
          ..loadError = null
          ..loadMoreError = null;
      }
    });

    try {
      List<YouTubeVideo> videos = const [];
      List<YouTubeChannelResult> channels = const [];
      List<YouTubePlaylistResult> playlists = const [];
      String? nextPageToken;
      String? previousPageToken;
      YouTubeVideoFeed? resolvedFeed;

      switch (category) {
        case YouTubeSearchCategory.videos:
          resolvedFeed = videoFeed ?? state.videoFeed;
          resolvedFeed ??= YouTubeVideoFeed.keyword(query: query);
          final result = await _loadVideoFeedPage(
            resolvedFeed,
            pageToken: pageToken,
          ).timeout(searchRequestTimeout);
          videos = result.videos;
          nextPageToken = result.nextPageToken;
          previousPageToken = result.previousPageToken;
        case YouTubeSearchCategory.channels:
          final result =
              await (_isMusicMode
                      ? _requireMusicCatalog().searchArtists(
                          query: query,
                          pageToken: pageToken,
                          languageCode: _searchLanguageCode,
                        )
                      : _catalogRepository.searchChannels(
                          query: query,
                          pageToken: pageToken,
                          languageCode: _searchLanguageCode,
                        ))
                  .timeout(searchRequestTimeout);
          channels = result.items;
          nextPageToken = result.nextPageToken;
          previousPageToken = result.previousPageToken;
        case YouTubeSearchCategory.playlists:
          final result =
              await (_isMusicMode
                      ? _requireMusicCatalog().searchMusicPlaylists(
                          query: query,
                          pageToken: pageToken,
                          languageCode: _searchLanguageCode,
                        )
                      : _catalogRepository.searchPlaylists(
                          query: query,
                          pageToken: pageToken,
                          languageCode: _searchLanguageCode,
                          sort: _playlistSearchSort,
                        ))
                  .timeout(searchRequestTimeout);
          playlists = result.items;
          nextPageToken = result.nextPageToken;
          previousPageToken = result.previousPageToken;
      }
      if (!mounted || currentRequest != _requestNumber) {
        AppLog.instance.warning(
          'search.request.discarded',
          fields: {
            ...logFields,
            'durationMs': stopwatch.elapsedMilliseconds,
            'reason': !mounted ? 'unmounted' : 'superseded',
          },
        );
        return;
      }

      final mergedVideos = append
          ? appendUniqueSearchResults(
              current: state.videos,
              additions: videos,
              idOf: (video) => video.id,
            )
          : limitSearchResults(videos);
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
      final receivedResultCount =
          videos.length + channels.length + playlists.length;
      final mergedResultCount =
          mergedVideos.length + mergedChannels.length + mergedPlaylists.length;
      final reachedResultLimit = mergedResultCount >= searchResultLimit;
      final resolvedNextPageToken =
          reachedResultLimit ||
              receivedResultCount == 0 ||
              nextPageToken == pageToken
          ? null
          : nextPageToken;
      setState(() {
        state
          ..videos = mergedVideos
          ..channels = mergedChannels
          ..playlists = mergedPlaylists;
        if (append) {
          state.loadedPageTokens.add(pageToken);
        }
        state
          ..activeQuery = query
          ..nextPageToken = resolvedNextPageToken
          ..previousPageToken = previousPageToken
          ..pageNumber = pageNumber
          ..videoFeed = resolvedFeed
          ..hasReachedEnd = !reachedResultLimit && resolvedNextPageToken == null
          ..isLoadingMore = false
          ..loadMoreError = null;
        _isLoading = false;
      });
      if (!append) {
        _scrollToTop();
      }
      AppLog.instance.info(
        'search.request.succeeded',
        fields: {
          ...logFields,
          'durationMs': stopwatch.elapsedMilliseconds,
          'receivedCount': receivedResultCount,
          'totalCount': mergedResultCount,
          'hasNextPage': resolvedNextPageToken != null,
          'resultLimitReached': reachedResultLimit,
        },
      );
    } on TimeoutException catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.timed_out',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _showLoadError(
        searchRequestTimeoutMessage,
        currentRequest,
        state,
        loadingMore: append,
      );
    } on YouTubeSearchException catch (error) {
      AppLog.instance.error(
        'search.request.failed',
        error: error.cause ?? error,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _showLoadError(error.message, currentRequest, state, loadingMore: append);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'search.request.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...logFields, 'durationMs': stopwatch.elapsedMilliseconds},
      );
      _showLoadError(
        context.l10n.unexpectedSearchError,
        currentRequest,
        state,
        loadingMore: append,
      );
    }
  }

  Future<YouTubeSearchResult> _loadVideoFeedPage(
    YouTubeVideoFeed feed, {
    String? pageToken,
  }) async {
    final result = await switch (feed.type) {
      YouTubeVideoFeedType.keyword => _activeSearchRepository.searchVideos(
        query: feed.query,
        pageToken: pageToken,
        languageCode: _searchLanguageCode,
        sort: _isMusicMode ? YouTubeSearchSort.relevance : _videoSearchSort,
      ),
      YouTubeVideoFeedType.channel =>
        _isMusicMode
            ? _requireMusicCatalog().loadArtistSongs(
                artistId: feed.id!,
                pageToken: pageToken,
                languageCode: _searchLanguageCode,
              )
            : _catalogRepository.loadChannelVideos(
                channelId: feed.id!,
                pageToken: pageToken,
                languageCode: _searchLanguageCode,
              ),
      YouTubeVideoFeedType.playlist =>
        _isMusicMode
            ? _requireMusicCatalog().loadMusicPlaylistSongs(
                playlistId: feed.id!,
                pageToken: pageToken,
                languageCode: _searchLanguageCode,
              )
            : _catalogRepository.loadPlaylistVideos(
                playlistId: feed.id!,
                pageToken: pageToken,
                languageCode: _searchLanguageCode,
              ),
    };
    return feed.itemsAreMusicVideos ? result.asMusicVideoResult() : result;
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

  void _showLoadError(
    String message,
    int requestNumber,
    _SearchViewState state, {
    required bool loadingMore,
  }) {
    if (!mounted || requestNumber != _requestNumber) {
      return;
    }
    setState(() {
      if (loadingMore) {
        state
          ..loadMoreError = message
          ..isLoadingMore = false;
      } else {
        state.loadError = message;
      }
      _isLoading = false;
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
    final state = _searchState;
    final pageToken = state.nextPageToken;
    if (_isLoading ||
        state.isLoadingMore ||
        state.hasReachedEnd ||
        state.resultCount >= searchResultLimit ||
        pageToken == null ||
        state.loadedPageTokens.contains(pageToken)) {
      return Future<void>.value();
    }
    return _loadResults(
      category: _searchCategory,
      query: state.activeQuery,
      pageToken: pageToken,
      pageNumber: state.pageNumber + 1,
      videoFeed: state.videoFeed,
    );
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_resultsController.hasClients) {
        _resultsController.jumpTo(0);
      }
    });
  }

  bool get _usesPlaybackManifestCache =>
      widget.videoPageBuilder == null &&
      (widget.playbackService != null ||
          (_searchSource == VideoSearchSource.youtube
              ? widget.searchRepository == null
              : widget.musicSearchRepository == null));

  void _selectSearchCategory(YouTubeSearchCategory category) {
    if (category == _searchCategory || _isLoading) {
      return;
    }
    setState(() {
      _searchCategory = category;
      _queryError = null;
    });
    AppLog.instance.info(
      'search.category.changed',
      fields: {'category': category.name, 'source': _searchSource.name},
    );
    _manifestCache.pausePrefetch();
    _scrollToTop();
  }

  Future<void> _selectSearchSort(
    YouTubeSearchCategory category,
    YouTubeSearchSort sort,
  ) async {
    if (_isLoading ||
        _isMusicMode ||
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

    final state = _searchStates[category]!;
    if (!state.hasSearched || state.activeQuery.isEmpty) {
      return;
    }
    await _loadResults(
      category: category,
      query: state.activeQuery,
      pageNumber: 1,
      videoFeed: category == YouTubeSearchCategory.videos
          ? YouTubeVideoFeed.keyword(query: state.activeQuery)
          : null,
    );
  }

  void _selectSearchSource(VideoSearchSource source, {bool force = false}) {
    if ((!force && source == _searchSource) || (!force && _isLoading)) {
      return;
    }
    _manifestCache.clear();
    final previousSource = _searchSource;
    _requestNumber++;
    setState(() {
      _isLoading = false;
      _searchSource = source;
      for (final category in YouTubeSearchCategory.values) {
        _searchStates[category] = _SearchViewState();
      }
      _queryError = null;
    });
    AppLog.instance.info(
      'search.source.changed',
      fields: {'from': previousSource.name, 'to': source.name, 'forced': force},
    );
  }

  Future<void> _retry() {
    final state = _searchState;
    final query = state.activeQuery.isEmpty
        ? _queryController.text.trim()
        : state.activeQuery;
    return _loadResults(
      category: _searchCategory,
      query: query,
      pageToken: state.requestedPageToken,
      pageNumber: state.requestedPageNumber,
      videoFeed: state.videoFeed,
    );
  }

  void _openVideo(YouTubeVideo video) {
    AppLog.instance.info(
      'navigation.player.opened',
      fields: {
        'mediaId': video.id,
        'source': _searchSource.name,
        'origin': 'search',
        'mediaType': video.isAudioOnlyMusic
            ? 'audio'
            : video.isMusicVideo
            ? 'musicVideo'
            : 'video',
        'live': video.isLive,
      },
    );
    if (_usesPlaybackManifestCache) {
      unawaited(
        _manifestCache.resolve(
          video.id,
          music: video.isAudioOnlyMusic,
          isLive: video.isLive,
          languageCode: _searchLanguageCode,
        ),
      );
    }
    final videoState = _searchStates[YouTubeSearchCategory.videos]!;
    final results = List<YouTubeVideo>.unmodifiable(videoState.videos);
    _manifestCache.pausePrefetch();
    final page =
        widget.videoPageBuilder?.call(
          video,
          results,
          videoState.activeQuery,
          _activeSearchRepository,
          initiallyPaused: false,
        ) ??
        VideoPlayerPage(
          video: video,
          searchResults: results,
          searchQuery: videoState.activeQuery,
          searchRepository: _activeSearchRepository,
          youtubeSearchRepository: _youtubeSearchRepository,
          musicSearchRepository: _musicSearchRepository,
          catalogRepository: _catalogRepository,
          initialVideoFeed: videoState.videoFeed,
          searchSource: _searchSource,
          playbackService: _playbackService,
          manifestCache: _manifestCache,
          profileController: _profileController,
          videoDetailsRepository: _videoDetailsRepository,
          initialNextPageToken: videoState.nextPageToken,
          initialPreviousPageToken: videoState.previousPageToken,
          initialPageNumber: videoState.pageNumber,
        );
    final navigation = Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    unawaited(
      navigation.then<void>((_) {
        final videos = _searchStates[YouTubeSearchCategory.videos]!.videos;
        if (mounted &&
            _searchCategory == YouTubeSearchCategory.videos &&
            videos.isNotEmpty) {
          _manifestCache.pausePrefetch();
        }
      }),
    );
  }

  Future<void> _openChannel(YouTubeChannelResult channel) async {
    AppLog.instance.info(
      'catalog.channel.opened',
      fields: {
        'channel': AppLog.instance.opaqueId(channel.id),
        'music': channel.isMusic,
      },
    );
    final feed = YouTubeVideoFeed.channel(
      channelId: channel.id,
      channelName: channel.name,
    );
    _queryController.text = channel.name;
    setState(() {
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadResults(
      category: YouTubeSearchCategory.videos,
      query: channel.name,
      pageNumber: 1,
      videoFeed: feed,
    );
  }

  Future<void> _openYouTubePlaylist(YouTubePlaylistResult playlist) async {
    AppLog.instance.info(
      'catalog.playlist.opened',
      fields: {
        'playlist': AppLog.instance.opaqueId(playlist.id),
        'source': _searchSource.name,
      },
    );
    final feed = YouTubeVideoFeed.playlist(
      playlistId: playlist.id,
      playlistTitle: playlist.title,
    );
    _queryController.text = playlist.title;
    setState(() {
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadResults(
      category: YouTubeSearchCategory.videos,
      query: playlist.title,
      pageNumber: 1,
      videoFeed: feed,
    );
  }

  Future<void> _toggleSearchFavorite(YouTubeVideo video) async {
    if (_profileController.activeProfile == null) {
      final created = await showCreateProfileDialog(
        context,
        _profileController,
      );
      if (!created || !mounted) {
        return;
      }
    }
    await _profileController.toggleFavorite(video);
  }

  Future<void> _toggleChannelFavorite(YouTubeChannelResult channel) async {
    if (_profileController.activeProfile == null) {
      final created = await showCreateProfileDialog(
        context,
        _profileController,
      );
      if (!created || !mounted) {
        return;
      }
    }
    await _profileController.toggleFavoriteChannel(channel);
  }

  Future<void> _addSearchVideoToPlaylist(YouTubeVideo video) async {
    await showAddToPlaylistDialog(context, _profileController, video);
  }

  Future<void> _addCatalogPlaylistToLocalPlaylist(
    YouTubePlaylistResult playlist,
  ) async {
    final musicMode = _isMusicMode;
    final languageCode = _searchLanguageCode;
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

  void _openProfileVideo(YouTubeVideo video, List<YouTubeVideo> contextVideos) {
    final source = videoSearchSourceForMedia(video);
    _manifestCache.pausePrefetch();
    if (_usesPlaybackManifestCache) {
      _manifestCache.replaceVisibleVideos(
        contextVideos,
        languageCode: _searchLanguageCode,
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          video: video,
          searchResults: List.unmodifiable(contextVideos),
          searchQuery: '',
          searchRepository: _activeSearchRepository,
          youtubeSearchRepository: _youtubeSearchRepository,
          musicSearchRepository: _musicSearchRepository,
          catalogRepository: _catalogRepository,
          initialVideoFeed: const YouTubeVideoFeed.keyword(query: ''),
          searchSource: source,
          playbackService: _playbackService,
          manifestCache: _manifestCache,
          profileController: _profileController,
          videoDetailsRepository: _videoDetailsRepository,
          searchResultsAutoplayEligible: false,
        ),
      ),
    );
  }

  void _openHotMusicVideo(
    YouTubeVideo video,
    List<YouTubeVideo> contextVideos,
    String contextTitle, {
    bool initiallyPaused = false,
  }) {
    if (_usesPlaybackManifestCache) {
      unawaited(
        _manifestCache.resolve(
          video.id,
          music: video.isAudioOnlyMusic,
          languageCode: _searchLanguageCode,
        ),
      );
    }
    _manifestCache.pausePrefetch();
    final page =
        widget.videoPageBuilder?.call(
          video,
          List<YouTubeVideo>.unmodifiable(contextVideos),
          contextTitle,
          _musicSearchRepository,
          initiallyPaused: initiallyPaused,
        ) ??
        VideoPlayerPage(
          video: video,
          searchResults: List<YouTubeVideo>.unmodifiable(contextVideos),
          searchQuery: contextTitle,
          searchRepository: _musicSearchRepository,
          youtubeSearchRepository: _youtubeSearchRepository,
          musicSearchRepository: _musicSearchRepository,
          catalogRepository: _catalogRepository,
          initialVideoFeed: const YouTubeVideoFeed.keyword(query: ''),
          searchSource: VideoSearchSource.youtubeMusic,
          playbackService: _playbackService,
          manifestCache: _manifestCache,
          profileController: _profileController,
          videoDetailsRepository: _videoDetailsRepository,
          searchResultsAutoplayEligible: true,
          initiallyPaused: initiallyPaused,
        );
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
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
      _selectedTab = 0;
      _searchCategory = YouTubeSearchCategory.videos;
    });
    await _loadResults(
      category: YouTubeSearchCategory.videos,
      query: feed.query,
      pageNumber: 1,
      videoFeed: feed,
    );
    if (!mounted) {
      return;
    }
    final state = _searchStates[YouTubeSearchCategory.videos]!;
    if (!identical(state.videoFeed, feed) ||
        state.loadError != null ||
        state.videos.isEmpty) {
      return;
    }
    _openVideo(state.videos.first);
  }

  Future<void> _importHotMusicPlaylist(YouTubePlaylistResult playlist) async {
    final languageCode = _searchLanguageCode;
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

  void _openPlaylist(VideoPlaylist playlist, int startIndex) {
    if (playlist.videos.isEmpty) {
      return;
    }
    final video = playlist.videos[startIndex];
    final source = videoSearchSourceForMedia(video);
    _manifestCache.pausePrefetch();
    if (_usesPlaybackManifestCache) {
      _manifestCache.replaceVisibleVideos(
        playlist.videos,
        languageCode: _searchLanguageCode,
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          video: video,
          searchResults: List.unmodifiable(playlist.videos),
          searchQuery: playlist.name,
          searchRepository: _activeSearchRepository,
          youtubeSearchRepository: _youtubeSearchRepository,
          musicSearchRepository: _musicSearchRepository,
          catalogRepository: _catalogRepository,
          initialVideoFeed: YouTubeVideoFeed.keyword(query: playlist.name),
          searchSource: source,
          playbackService: _playbackService,
          manifestCache: _manifestCache,
          profileController: _profileController,
          videoDetailsRepository: _videoDetailsRepository,
          playlistQueue: playlist.videos,
          initialPlaylistIndex: startIndex,
          searchResultsAutoplayEligible: false,
        ),
      ),
    );
  }

  void _openProfileChannel(YouTubeChannelResult channel) {
    final source = channel.isMusic
        ? VideoSearchSource.youtubeMusic
        : VideoSearchSource.youtube;
    if (source != _searchSource) {
      _selectSearchSource(source);
    }
    setState(() => _selectedTab = 0);
    unawaited(_openChannel(channel));
  }

  void _selectTab(int index) {
    if (_profileTutorialStep != null ||
        _searchTutorialStep != null ||
        _hotMusicTutorialStep != null) {
      return;
    }
    setState(() => _selectedTab = index);
    _manifestCache.pausePrefetch();
  }

  void _startNextTutorialStageIfNeeded() {
    if (!mounted) {
      return;
    }
    if (_profileController.shouldShowTutorialStage(AppTutorialStage.profile)) {
      setState(() {
        _selectedTab = 2;
        _profileTutorialStep = _profileController.activeProfile == null
            ? _ProfileTutorialStep.createProfile
            : _ProfileTutorialStep.playlists;
      });
      _manifestCache.pausePrefetch();
      return;
    }
    _startSearchTutorialIfNeeded();
  }

  void _skipAllTutorials() {
    if (!mounted) {
      return;
    }
    setState(() {
      _profileTutorialStep = null;
      _profileTutorialMenuOpen = false;
      _searchTutorialStep = null;
      _searchTutorialSourceMenuOpen = false;
      _hotMusicTutorialStep = null;
      _hotMusicTutorialMenuOpen = false;
      _hotMusicTutorialStartingSong = false;
      _hotMusicTutorialActionTargetReady = false;
    });
    unawaited(_profileController.completeAllTutorialStages());
  }

  void _handleProfileControllerChanged() {
    if (!mounted) {
      return;
    }
    if (_profileController.isTutorialStageCompleted(AppTutorialStage.profile)) {
      if (_profileTutorialStep != null || _profileTutorialMenuOpen) {
        setState(() {
          _profileTutorialStep = null;
          _profileTutorialMenuOpen = false;
        });
      }
      return;
    }
    if (_profileTutorialStep == null &&
        _searchTutorialStep == null &&
        _hotMusicTutorialStep == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _profileTutorialStep == null &&
            _searchTutorialStep == null &&
            _hotMusicTutorialStep == null &&
            _profileController.shouldShowTutorialStage(
              AppTutorialStage.profile,
            )) {
          _startNextTutorialStageIfNeeded();
        }
      });
      return;
    }
    if (_profileTutorialStep == _ProfileTutorialStep.createProfile &&
        _profileController.activeProfile != null) {
      setState(() => _profileTutorialStep = _ProfileTutorialStep.playlists);
    }
  }

  void _completeProfileTutorial() {
    if (!mounted) {
      return;
    }
    setState(() {
      _profileTutorialStep = null;
      _profileTutorialMenuOpen = false;
    });
    unawaited(
      _profileController.completeTutorialStage(AppTutorialStage.profile),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startSearchTutorialIfNeeded(),
    );
  }

  void _advanceProfileTutorial() {
    final nextStep = switch (_profileTutorialStep) {
      _ProfileTutorialStep.playlists => _ProfileTutorialStep.favorites,
      _ProfileTutorialStep.favorites => _ProfileTutorialStep.channels,
      _ProfileTutorialStep.channels => _ProfileTutorialStep.addProfile,
      _ProfileTutorialStep.addProfile => _ProfileTutorialStep.profileMenu,
      _ => null,
    };
    if (nextStep != null) {
      setState(() => _profileTutorialStep = nextStep);
    }
  }

  void _goBackInProfileTutorial() {
    final previousStep = switch (_profileTutorialStep) {
      _ProfileTutorialStep.favorites => _ProfileTutorialStep.playlists,
      _ProfileTutorialStep.channels => _ProfileTutorialStep.favorites,
      _ProfileTutorialStep.addProfile => _ProfileTutorialStep.channels,
      _ProfileTutorialStep.profileMenu => _ProfileTutorialStep.addProfile,
      _ => null,
    };
    if (previousStep != null) {
      setState(() => _profileTutorialStep = previousStep);
    }
  }

  void _handleTutorialProfileMenuOpened() {
    if (_profileTutorialStep == _ProfileTutorialStep.profileMenu && mounted) {
      setState(() => _profileTutorialMenuOpen = true);
    }
  }

  void _handleTutorialProfileMenuClosed() {
    if (_profileTutorialStep == _ProfileTutorialStep.profileMenu) {
      _completeProfileTutorial();
    }
  }

  Widget? _buildProfileTutorialOverlay() {
    final step = _profileTutorialStep;
    if (step == null || _profileTutorialMenuOpen) {
      return null;
    }
    final targetKey = switch (step) {
      _ProfileTutorialStep.createProfile =>
        _profileTutorialTargets.createProfile,
      _ProfileTutorialStep.favorites => _profileTutorialTargets.favorites,
      _ProfileTutorialStep.playlists => _profileTutorialTargets.playlists,
      _ProfileTutorialStep.channels => _profileTutorialTargets.channels,
      _ProfileTutorialStep.addProfile => _profileTutorialTargets.addProfile,
      _ProfileTutorialStep.profileMenu => _profileTutorialTargets.profileMenu,
    };
    final title = switch (step) {
      _ProfileTutorialStep.createProfile =>
        context.l10n.profileTutorialCreateTitle,
      _ProfileTutorialStep.favorites =>
        context.l10n.profileTutorialFavoritesTitle,
      _ProfileTutorialStep.playlists =>
        context.l10n.profileTutorialPlaylistsTitle,
      _ProfileTutorialStep.channels =>
        context.l10n.profileTutorialChannelsTitle,
      _ProfileTutorialStep.addProfile => context.l10n.profileTutorialAddTitle,
      _ProfileTutorialStep.profileMenu => context.l10n.profileTutorialMenuTitle,
    };
    final message = switch (step) {
      _ProfileTutorialStep.createProfile =>
        context.l10n.profileTutorialCreateMessage,
      _ProfileTutorialStep.favorites =>
        context.l10n.profileTutorialFavoritesMessage,
      _ProfileTutorialStep.playlists =>
        context.l10n.profileTutorialPlaylistsMessage,
      _ProfileTutorialStep.channels =>
        context.l10n.profileTutorialChannelsMessage,
      _ProfileTutorialStep.addProfile => context.l10n.profileTutorialAddMessage,
      _ProfileTutorialStep.profileMenu =>
        context.l10n.profileTutorialMenuMessage,
    };
    return TutorialCoachOverlay(
      targetKey: targetKey,
      sectionLabel: context.l10n.profileTutorialSection,
      tutorial: 1,
      tutorialCount: AppTutorialStage.values.length,
      title: title,
      message: message,
      step: step.number,
      stepCount: _ProfileTutorialStep.values.length,
      onSkip: _skipAllTutorials,
      onBack: step.hasPrevious ? _goBackInProfileTutorial : null,
      onNext: step == _ProfileTutorialStep.profileMenu
          ? _completeProfileTutorial
          : _advanceProfileTutorial,
      nextLabel: step == _ProfileTutorialStep.profileMenu
          ? context.l10n.nextTutorial
          : null,
      showNextButton: step != _ProfileTutorialStep.createProfile,
      allowTargetInteraction: step == _ProfileTutorialStep.createProfile,
    );
  }

  void _startSearchTutorialIfNeeded() {
    if (!mounted) {
      return;
    }
    if (!_profileController.shouldShowTutorialStage(AppTutorialStage.search)) {
      _startHotMusicTutorialIfNeeded();
      return;
    }
    setState(() {
      _selectedTab = 0;
      _searchSource = VideoSearchSource.youtube;
      _searchCategory = YouTubeSearchCategory.videos;
      _searchTutorialStep = _SearchTutorialStep.source;
      _searchTutorialSourceMenuOpen = false;
    });
    _manifestCache.pausePrefetch();
  }

  void _completeSearchTutorial() {
    if (!mounted) {
      return;
    }
    setState(() {
      _searchTutorialStep = null;
      _searchTutorialSourceMenuOpen = false;
      _searchCategory = YouTubeSearchCategory.videos;
    });
    unawaited(
      _profileController.completeTutorialStage(AppTutorialStage.search),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startHotMusicTutorialIfNeeded(),
    );
  }

  void _handleSearchTutorialSourceMenuOpened() {
    if (_searchTutorialStep == _SearchTutorialStep.source && mounted) {
      setState(() => _searchTutorialSourceMenuOpen = true);
    }
  }

  void _handleSearchTutorialSourceMenuClosed() {
    if (_searchTutorialStep != _SearchTutorialStep.source || !mounted) {
      return;
    }
    setState(() => _searchTutorialSourceMenuOpen = false);
    _advanceSearchTutorial();
  }

  void _advanceSearchTutorial() {
    final nextStep = switch (_searchTutorialStep) {
      _SearchTutorialStep.source => _SearchTutorialStep.searchButton,
      _SearchTutorialStep.searchButton => _SearchTutorialStep.videos,
      _SearchTutorialStep.videos => _SearchTutorialStep.channels,
      _SearchTutorialStep.channels => _SearchTutorialStep.playlists,
      _SearchTutorialStep.playlists || null => null,
    };
    if (nextStep == null) {
      _completeSearchTutorial();
      return;
    }
    _showSearchTutorialStep(nextStep);
  }

  void _goBackInSearchTutorial() {
    final previousStep = switch (_searchTutorialStep) {
      _SearchTutorialStep.searchButton => _SearchTutorialStep.source,
      _SearchTutorialStep.videos => _SearchTutorialStep.searchButton,
      _SearchTutorialStep.channels => _SearchTutorialStep.videos,
      _SearchTutorialStep.playlists => _SearchTutorialStep.channels,
      _SearchTutorialStep.source || null => null,
    };
    if (previousStep != null) {
      _showSearchTutorialStep(previousStep);
    }
  }

  void _showSearchTutorialStep(_SearchTutorialStep step) {
    setState(() {
      _searchTutorialStep = step;
      _searchCategory = switch (step) {
        _SearchTutorialStep.channels => YouTubeSearchCategory.channels,
        _SearchTutorialStep.playlists => YouTubeSearchCategory.playlists,
        _ => YouTubeSearchCategory.videos,
      };
    });
  }

  Widget? _buildSearchTutorialOverlay() {
    final step = _searchTutorialStep;
    if (step == null || _searchTutorialSourceMenuOpen) {
      return null;
    }
    final targetKey = switch (step) {
      _SearchTutorialStep.source => _searchTutorialTargets.sourceSelector,
      _SearchTutorialStep.searchButton => _searchTutorialTargets.searchButton,
      _SearchTutorialStep.videos => _searchTutorialTargets.videos,
      _SearchTutorialStep.channels => _searchTutorialTargets.channels,
      _SearchTutorialStep.playlists => _searchTutorialTargets.playlists,
    };
    final title = switch (step) {
      _SearchTutorialStep.source => context.l10n.searchTutorialSourceTitle,
      _SearchTutorialStep.searchButton =>
        context.l10n.searchTutorialButtonTitle,
      _SearchTutorialStep.videos => context.l10n.searchTutorialVideosTitle,
      _SearchTutorialStep.channels => context.l10n.searchTutorialChannelsTitle,
      _SearchTutorialStep.playlists =>
        context.l10n.searchTutorialPlaylistsTitle,
    };
    final message = switch (step) {
      _SearchTutorialStep.source => context.l10n.searchTutorialSourceMessage,
      _SearchTutorialStep.searchButton =>
        context.l10n.searchTutorialButtonMessage,
      _SearchTutorialStep.videos => context.l10n.searchTutorialVideosMessage,
      _SearchTutorialStep.channels =>
        context.l10n.searchTutorialChannelsMessage,
      _SearchTutorialStep.playlists =>
        context.l10n.searchTutorialPlaylistsMessage,
    };
    return TutorialCoachOverlay(
      targetKey: targetKey,
      sectionLabel: context.l10n.searchTutorialSection,
      tutorial: 2,
      tutorialCount: AppTutorialStage.values.length,
      title: title,
      message: message,
      step: step.number,
      stepCount: _SearchTutorialStep.values.length,
      onSkip: _skipAllTutorials,
      onBack: step.hasPrevious ? _goBackInSearchTutorial : null,
      onNext: _advanceSearchTutorial,
      nextLabel: step == _SearchTutorialStep.playlists
          ? context.l10n.nextTutorial
          : null,
    );
  }

  void _startHotMusicTutorialIfNeeded() {
    if (!mounted ||
        !_profileController.shouldShowTutorialStage(
          AppTutorialStage.hotMusic,
        )) {
      return;
    }
    setState(() {
      _selectedTab = 1;
      _hotMusicTutorialStep = HotMusicTutorialStep.explore;
      _hotMusicTutorialMenuOpen = false;
      _hotMusicTutorialStartingSong = false;
      _hotMusicTutorialActionTargetReady = false;
    });
    _manifestCache.pausePrefetch();
  }

  void _handleHotMusicTutorialMenuOpened(HotMusicSection section) {
    if (_hotMusicTutorialStep?.section == section && mounted) {
      setState(() => _hotMusicTutorialMenuOpen = true);
    }
  }

  void _handleHotMusicTutorialMenuClosed(HotMusicSection section) {
    if (_hotMusicTutorialStep?.section != section || !mounted) {
      return;
    }
    setState(() => _hotMusicTutorialMenuOpen = false);
    _advanceHotMusicTutorial();
  }

  void _handleHotMusicTutorialActionTargetReady() {
    if (!mounted ||
        _hotMusicTutorialStep?.highlightsSongAction != true ||
        _hotMusicTutorialActionTargetReady) {
      return;
    }
    setState(() => _hotMusicTutorialActionTargetReady = true);
  }

  void _advanceHotMusicTutorial() {
    final nextStep = switch (_hotMusicTutorialStep) {
      HotMusicTutorialStep.explore => HotMusicTutorialStep.charts,
      HotMusicTutorialStep.charts => HotMusicTutorialStep.genres,
      HotMusicTutorialStep.genres => HotMusicTutorialStep.favorite,
      HotMusicTutorialStep.favorite => HotMusicTutorialStep.playlist,
      HotMusicTutorialStep.playlist => HotMusicTutorialStep.info,
      HotMusicTutorialStep.info || null => null,
    };
    if (nextStep == null) {
      unawaited(_finishHotMusicTutorialWithSong());
      return;
    }
    setState(() {
      _hotMusicTutorialStep = nextStep;
      _hotMusicTutorialMenuOpen = false;
      if (!nextStep.highlightsSongAction) {
        _hotMusicTutorialActionTargetReady = false;
      }
    });
  }

  void _goBackInHotMusicTutorial() {
    final previousStep = switch (_hotMusicTutorialStep) {
      HotMusicTutorialStep.charts => HotMusicTutorialStep.explore,
      HotMusicTutorialStep.genres => HotMusicTutorialStep.charts,
      HotMusicTutorialStep.favorite => HotMusicTutorialStep.genres,
      HotMusicTutorialStep.playlist => HotMusicTutorialStep.favorite,
      HotMusicTutorialStep.info => HotMusicTutorialStep.playlist,
      HotMusicTutorialStep.explore || null => null,
    };
    if (previousStep == null) {
      return;
    }
    setState(() {
      _hotMusicTutorialStep = previousStep;
      _hotMusicTutorialMenuOpen = false;
      _hotMusicTutorialStartingSong = false;
      _hotMusicTutorialActionTargetReady = previousStep.highlightsSongAction;
    });
  }

  Future<void> _finishHotMusicTutorialWithSong() async {
    if (!mounted || _hotMusicTutorialStartingSong) {
      return;
    }
    setState(() => _hotMusicTutorialStartingSong = true);
    final launch = await _hotMusicTutorialController.resolveFirstSong();
    if (!mounted ||
        _hotMusicTutorialStep != HotMusicTutorialStep.info ||
        !_hotMusicTutorialStartingSong) {
      return;
    }
    if (launch == null) {
      setState(() => _hotMusicTutorialStartingSong = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.hotMusicTutorialSongUnavailable)),
      );
      return;
    }
    setState(() {
      _hotMusicTutorialStep = null;
      _hotMusicTutorialMenuOpen = false;
      _hotMusicTutorialStartingSong = false;
      _hotMusicTutorialActionTargetReady = false;
    });
    unawaited(
      _profileController.completeTutorialStage(AppTutorialStage.hotMusic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _openHotMusicVideo(
        launch.video,
        launch.queue,
        launch.contextTitle,
        initiallyPaused: true,
      );
    });
  }

  Widget? _buildHotMusicTutorialOverlay() {
    final step = _hotMusicTutorialStep;
    if (step == null || _hotMusicTutorialMenuOpen) {
      return null;
    }
    if (step.highlightsSongAction && !_hotMusicTutorialActionTargetReady) {
      return null;
    }
    final section = step.section;
    final targetKey = section == null
        ? _hotMusicTutorialTargets.action(step)
        : _hotMusicTutorialTargets.section(section);
    final title = switch (step) {
      HotMusicTutorialStep.explore => context.l10n.hotMusicTutorialExploreTitle,
      HotMusicTutorialStep.charts => context.l10n.hotMusicTutorialChartsTitle,
      HotMusicTutorialStep.genres => context.l10n.hotMusicTutorialGenresTitle,
      HotMusicTutorialStep.favorite =>
        context.l10n.hotMusicTutorialFavoriteTitle,
      HotMusicTutorialStep.playlist =>
        context.l10n.hotMusicTutorialPlaylistTitle,
      HotMusicTutorialStep.info => context.l10n.hotMusicTutorialInfoTitle,
    };
    final message = switch (step) {
      HotMusicTutorialStep.explore =>
        context.l10n.hotMusicTutorialExploreMessage,
      HotMusicTutorialStep.charts => context.l10n.hotMusicTutorialChartsMessage,
      HotMusicTutorialStep.genres => context.l10n.hotMusicTutorialGenresMessage,
      HotMusicTutorialStep.favorite =>
        context.l10n.hotMusicTutorialFavoriteMessage,
      HotMusicTutorialStep.playlist =>
        context.l10n.hotMusicTutorialPlaylistMessage,
      HotMusicTutorialStep.info => context.l10n.hotMusicTutorialInfoMessage,
    };
    return TutorialCoachOverlay(
      targetKey: targetKey,
      sectionLabel: context.l10n.hotMusicTutorialSection,
      tutorial: 3,
      tutorialCount: AppTutorialStage.values.length,
      title: title,
      message: message,
      step: step.number,
      stepCount: HotMusicTutorialStep.values.length,
      onSkip: _skipAllTutorials,
      onBack: step.hasPrevious ? _goBackInHotMusicTutorial : null,
      onNext: step == HotMusicTutorialStep.info
          ? () => unawaited(_finishHotMusicTutorialWithSong())
          : _advanceHotMusicTutorial,
      nextLabel: step == HotMusicTutorialStep.info
          ? context.l10n.nextTutorial
          : null,
      nextEnabled: !_hotMusicTutorialStartingSong,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: switch (_selectedTab) {
        1 => AppBar(title: Text(context.l10n.hotMusic), centerTitle: false),
        2 => AppBar(title: Text(context.l10n.myProfile), centerTitle: false),
        _ => null,
      },
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildSearchPage(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: HotMusicPage(
                  active: _selectedTab == 1,
                  repository: _musicDiscoveryRepository,
                  profileController: _profileController,
                  onVideoSelected: _openHotMusicVideo,
                  onPlaylistSelected: (playlist) =>
                      unawaited(_openHotMusicPlaylist(playlist)),
                  onArtistSelected: (artist) =>
                      unawaited(_openHotMusicArtist(artist)),
                  onToggleVideoFavorite: _toggleSearchFavorite,
                  onAddVideoToPlaylist: _addSearchVideoToPlaylist,
                  onImportPlaylist: _importHotMusicPlaylist,
                  onToggleArtistFavorite: _toggleChannelFavorite,
                  loadFullDescription: (video) =>
                      _videoDetailsRepository.loadDescription(
                        videoId: video.id,
                        languageCode: _searchLanguageCode,
                      ),
                  keyPrefix: 'main-hot-music',
                  tutorialController: _hotMusicTutorialController,
                  tutorialTargets: _hotMusicTutorialTargets,
                  tutorialStep: _hotMusicTutorialStep,
                  onTutorialMenuOpened: _handleHotMusicTutorialMenuOpened,
                  onTutorialMenuClosed: _handleHotMusicTutorialMenuClosed,
                  onTutorialActionTargetReady:
                      _handleHotMusicTutorialActionTargetReady,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ProfilePage(
                  controller: _profileController,
                  onVideoSelected: _openProfileVideo,
                  onPlaylistSelected: _openPlaylist,
                  onChannelSelected: _openProfileChannel,
                  tutorialTargets: _profileTutorialTargets,
                  showTutorialMenuPreview:
                      _profileTutorialStep == _ProfileTutorialStep.profileMenu,
                  onTutorialMenuOpened: _handleTutorialProfileMenuOpened,
                  onTutorialMenuClosed: _handleTutorialProfileMenuClosed,
                  onRestartTutorial: _profileController.restartTutorial,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppSectionNavigationBar(
        keyPrefix: 'main',
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
      ),
    );
    final tutorialOverlay =
        _buildProfileTutorialOverlay() ??
        _buildSearchTutorialOverlay() ??
        _buildHotMusicTutorialOverlay();
    final tutorialActive =
        _profileTutorialStep != null ||
        _searchTutorialStep != null ||
        _hotMusicTutorialStep != null;
    return PopScope(
      key: const Key('main-tutorial-navigation-lock'),
      canPop: !tutorialActive,
      child: Stack(
        children: [
          scaffold,
          if (tutorialActive && tutorialOverlay == null)
            const Positioned.fill(
              child: ModalBarrier(
                key: Key('tutorial-transition-blocker'),
                dismissible: false,
                color: Colors.transparent,
              ),
            ),
          if (tutorialOverlay != null) Positioned.fill(child: tutorialOverlay),
        ],
      ),
    );
  }

  Widget _buildSearchPage() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _profileController,
                  builder: (context, _) => MediaSourceSearchBar(
                    controller: _queryController,
                    errorText: _queryError,
                    isLoading: _isLoading,
                    sourceSelectionEnabled: _musicSearchAvailable,
                    source: _searchSource,
                    category: _searchCategory,
                    onSourceChanged: _selectSearchSource,
                    onSourceMenuOpened: _handleSearchTutorialSourceMenuOpened,
                    onSourceMenuClosed: _handleSearchTutorialSourceMenuClosed,
                    onSearch: _startSearch,
                    searchHistory:
                        _profileController.activeProfile?.searchHistory ??
                        const [],
                    onSearchHistoryDeleted: (entry) => unawaited(
                      _profileController.deleteSearchHistoryEntry(entry),
                    ),
                    tutorialTargets: _searchTutorialTargets,
                  ),
                ),
                const SizedBox(height: 12),
                MediaSearchCategoryBar(
                  selected: _searchCategory,
                  onSelected: _selectSearchCategory,
                  enabled: !_isLoading,
                  musicMode: _isMusicMode,
                  videoSortingEnabled: _videoSortingEnabled,
                  playlistSortingEnabled: !_isMusicMode,
                  videoSort: _videoSearchSort,
                  playlistSort: _playlistSearchSort,
                  onSortSelected: youtubeSearchSortControlsEnabled
                      ? _selectSearchSort
                      : null,
                  tutorialTargets: _searchTutorialTargets,
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final state = _searchState;
    if (_isLoading && !state.isLoadingMore) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.searchInProgress),
          ],
        ),
      );
    }

    if (state.loadError case final error?) {
      return _MessageState(
        icon: Icons.error_outline,
        title: context.l10n.searchUnavailableTitle,
        message: context.l10n.translateKnownMessage(error),
        actionLabel: context.l10n.retry,
        onAction: _retry,
      );
    }

    if (!state.hasSearched) {
      return _MessageState(
        icon: switch (_searchCategory) {
          YouTubeSearchCategory.videos =>
            _searchSource == VideoSearchSource.youtubeMusic
                ? Icons.music_note
                : Icons.ondemand_video_outlined,
          YouTubeSearchCategory.channels => Icons.account_circle_outlined,
          YouTubeSearchCategory.playlists => Icons.playlist_play,
        },
        title: switch (_searchCategory) {
          YouTubeSearchCategory.videos =>
            _isMusicMode
                ? context.l10n.browseSongs
                : context.l10n.browseSource(_searchSource.label),
          YouTubeSearchCategory.channels =>
            _isMusicMode
                ? context.l10n.browseArtists
                : context.l10n.browseChannels,
          YouTubeSearchCategory.playlists =>
            _isMusicMode
                ? context.l10n.browseSongPlaylists
                : context.l10n.browsePlaylists,
        },
        message: switch (_searchCategory) {
          YouTubeSearchCategory.videos =>
            _searchSource == VideoSearchSource.youtubeMusic
                ? context.l10n.songSearchPrompt
                : context.l10n.videoSearchPrompt,
          YouTubeSearchCategory.channels =>
            _isMusicMode
                ? context.l10n.artistSearchPrompt
                : context.l10n.channelSearchPrompt,
          YouTubeSearchCategory.playlists =>
            _isMusicMode
                ? context.l10n.musicPlaylistSearchPrompt
                : context.l10n.playlistSearchPrompt,
        },
      );
    }

    if (state.resultCount == 0) {
      return _MessageState(
        icon: Icons.search_off,
        title: context.l10n.noCategoryFound(_categoryLabel),
        message: context.l10n.tryAnotherSearchTerm,
      );
    }

    return switch (_searchCategory) {
      YouTubeSearchCategory.videos => _buildVideoResults(state),
      YouTubeSearchCategory.channels => _buildChannelResults(state),
      YouTubeSearchCategory.playlists => _buildPlaylistResults(state),
    };
  }

  Widget _buildVideoResults(_SearchViewState state) {
    final videos = state.videos;
    return ListView.separated(
      key: const Key('video-results'),
      controller: _resultsController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: videos.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == videos.length) {
          return _buildResultsTail(state);
        }
        _scheduleLoadMore(index, videos.length);
        final video = videos[index];
        return AnimatedBuilder(
          key: ValueKey(video.id),
          animation: _profileController,
          builder: (context, _) => VideoResultCard(
            video: video,
            onTap: () => _openVideo(video),
            isFavorite: _profileController.isFavorite(video.id),
            onToggleFavorite: () => _toggleSearchFavorite(video),
            onAddToPlaylist: () => _addSearchVideoToPlaylist(video),
            showInfo: true,
            loadFullDescription: () => _videoDetailsRepository.loadDescription(
              videoId: video.id,
              languageCode: _searchLanguageCode,
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelResults(_SearchViewState state) {
    final channels = state.channels;
    return ListView.separated(
      key: const Key('channel-results'),
      controller: _resultsController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: channels.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == channels.length) {
          return _buildResultsTail(state);
        }
        _scheduleLoadMore(index, channels.length);
        final channel = channels[index];
        return AnimatedBuilder(
          key: ValueKey('channel-${channel.id}'),
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

  Widget _buildPlaylistResults(_SearchViewState state) {
    final playlists = state.playlists;
    return ListView.separated(
      key: const Key('playlist-results'),
      controller: _resultsController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: playlists.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == playlists.length) {
          return _buildResultsTail(state);
        }
        _scheduleLoadMore(index, playlists.length);
        final playlist = playlists[index];
        return YouTubePlaylistResultCard(
          key: ValueKey('youtube-playlist-${playlist.id}'),
          playlist: playlist,
          onTap: () => _openYouTubePlaylist(playlist),
          onAddToPlaylist: () => _addCatalogPlaylistToLocalPlaylist(playlist),
        );
      },
    );
  }

  Widget _buildResultsTail(_SearchViewState state) {
    final keyPrefix = 'search-${_searchCategory.name}';
    if (state.isLoadingMore) {
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
    if (state.loadMoreError case final error?) {
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
    if (state.resultCount >= searchResultLimit) {
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
    if (state.hasReachedEnd) {
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
}

enum _ProfileTutorialStep {
  createProfile,
  playlists,
  favorites,
  channels,
  addProfile,
  profileMenu;

  int get number => index + 1;

  bool get hasPrevious => switch (this) {
    createProfile || playlists => false,
    favorites || channels || addProfile || profileMenu => true,
  };
}

enum _SearchTutorialStep {
  source,
  searchButton,
  videos,
  channels,
  playlists;

  int get number => index + 1;

  bool get hasPrevious => this != source;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchViewState {
  List<YouTubeVideo> videos = const [];
  List<YouTubeChannelResult> channels = const [];
  List<YouTubePlaylistResult> playlists = const [];
  String? nextPageToken;
  String? previousPageToken;
  String? loadError;
  String activeQuery = '';
  String? requestedPageToken;
  int requestedPageNumber = 1;
  int pageNumber = 1;
  bool hasSearched = false;
  bool isLoadingMore = false;
  bool hasReachedEnd = false;
  bool requestedAppend = false;
  String? loadMoreError;
  final Set<String> loadedPageTokens = {};
  YouTubeVideoFeed? videoFeed;

  int get resultCount => videos.length + channels.length + playlists.length;
}
