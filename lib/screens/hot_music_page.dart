import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/hot_music.dart';
import '../models/search_result_limit.dart';
import '../models/user_profile.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_video.dart';
import '../services/profile_controller.dart';
import '../services/app_log.dart';
import '../services/youtube_music_discovery_repository.dart';
import '../services/youtube_search_repository.dart';
import '../widgets/hot_music_tutorial_targets.dart';
import '../widgets/video_result_card.dart';
import '../widgets/youtube_catalog_result_card.dart';

typedef HotMusicVideoSelected =
    void Function(
      YouTubeVideo video,
      List<YouTubeVideo> queue,
      String contextTitle,
    );
typedef HotMusicPlaylistSelected =
    void Function(YouTubePlaylistResult playlist);
typedef HotMusicArtistSelected = void Function(YouTubeChannelResult artist);
typedef HotMusicVideoAction = Future<void> Function(YouTubeVideo video);
typedef HotMusicPlaylistAction =
    Future<void> Function(YouTubePlaylistResult playlist);
typedef HotMusicArtistAction =
    Future<void> Function(YouTubeChannelResult artist);
typedef HotMusicDescriptionLoader = Future<String> Function(YouTubeVideo video);

class HotMusicTutorialSong {
  const HotMusicTutorialSong({
    required this.video,
    required this.queue,
    required this.contextTitle,
  });

  final YouTubeVideo video;
  final List<YouTubeVideo> queue;
  final String contextTitle;
}

class HotMusicTutorialController {
  _HotMusicPageState? _state;

  void _attach(_HotMusicPageState state) => _state = state;

  void _detach(_HotMusicPageState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  Future<HotMusicTutorialSong?> resolveFirstSong() async =>
      _state?._resolveTutorialSong();
}

class HotMusicPage extends StatefulWidget {
  const HotMusicPage({
    super.key,
    required this.active,
    required this.repository,
    required this.profileController,
    required this.onVideoSelected,
    required this.onPlaylistSelected,
    required this.onArtistSelected,
    required this.onToggleVideoFavorite,
    required this.onAddVideoToPlaylist,
    required this.onImportPlaylist,
    required this.onToggleArtistFavorite,
    this.loadFullDescription,
    this.keyPrefix = 'hot-music',
    this.tutorialController,
    this.tutorialTargets,
    this.tutorialStep,
    this.onTutorialMenuOpened,
    this.onTutorialMenuClosed,
    this.onTutorialActionTargetReady,
  });

  final bool active;
  final YouTubeMusicDiscoveryRepository? repository;
  final ProfileController profileController;
  final HotMusicVideoSelected onVideoSelected;
  final HotMusicPlaylistSelected onPlaylistSelected;
  final HotMusicArtistSelected onArtistSelected;
  final HotMusicVideoAction onToggleVideoFavorite;
  final HotMusicVideoAction onAddVideoToPlaylist;
  final HotMusicPlaylistAction onImportPlaylist;
  final HotMusicArtistAction onToggleArtistFavorite;
  final HotMusicDescriptionLoader? loadFullDescription;
  final String keyPrefix;
  final HotMusicTutorialController? tutorialController;
  final HotMusicTutorialTargets? tutorialTargets;
  final HotMusicTutorialStep? tutorialStep;
  final ValueChanged<HotMusicSection>? onTutorialMenuOpened;
  final ValueChanged<HotMusicSection>? onTutorialMenuClosed;
  final VoidCallback? onTutorialActionTargetReady;

  @override
  State<HotMusicPage> createState() => _HotMusicPageState();
}

class _HotMusicPageState extends State<HotMusicPage> {
  static const _preferredCountryCodes = ['DE', 'AT', 'CH', 'US', 'GB', 'ZZ'];

  final ScrollController _scrollController = ScrollController();
  HotMusicSection _section = HotMusicSection.explore;
  HotMusicExploreFilter _exploreFilter = HotMusicExploreFilter.trending;
  HotMusicChartsFilter _chartsFilter = HotMusicChartsFilter.videos;
  HotMusicGenreFilter _genreFilter = HotMusicGenreFilter.moods;
  HotMusicExploreResult? _explore;
  HotMusicChartsResult? _charts;
  List<HotMusicGenreSection>? _genreSections;
  HotMusicCategory? _selectedGenre;
  List<YouTubePlaylistResult>? _selectedGenrePlaylists;
  bool _loadingExplore = false;
  bool _loadingCharts = false;
  bool _loadingGenres = false;
  bool _loadingGenrePlaylists = false;
  HotMusicTutorialStep? _notifiedTutorialActionTargetStep;
  String? _exploreError;
  String? _chartsError;
  String? _genresError;
  String? _genrePlaylistsError;
  late String _languageCode;
  late String _countryCode;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _languageCode = _currentLanguageCode;
    _countryCode = _defaultCountryFor(_languageCode);
    widget.profileController.addListener(_handleProfileChanged);
    widget.tutorialController?._attach(this);
    if (widget.active) {
      unawaited(_ensureSectionLoaded());
    }
    _scheduleTutorialStepSync();
  }

  @override
  void didUpdateWidget(covariant HotMusicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profileController, widget.profileController)) {
      oldWidget.profileController.removeListener(_handleProfileChanged);
      widget.profileController.addListener(_handleProfileChanged);
    }
    if (!identical(oldWidget.tutorialController, widget.tutorialController)) {
      oldWidget.tutorialController?._detach(this);
      widget.tutorialController?._attach(this);
    }
    if ((!oldWidget.active && widget.active) ||
        oldWidget.repository != widget.repository) {
      unawaited(_ensureSectionLoaded());
    }
    if (oldWidget.tutorialStep != widget.tutorialStep) {
      _notifiedTutorialActionTargetStep = null;
      _scheduleTutorialStepSync();
    }
  }

  @override
  void dispose() {
    widget.tutorialController?._detach(this);
    widget.profileController.removeListener(_handleProfileChanged);
    _scrollController.dispose();
    super.dispose();
  }

  String get _currentLanguageCode =>
      widget.profileController.activeProfile?.language.code ??
      ProfileLanguage.english.code;

  void _handleProfileChanged() {
    final nextLanguage = _currentLanguageCode;
    if (nextLanguage != _languageCode) {
      _requestGeneration++;
      setState(() {
        _languageCode = nextLanguage;
        _countryCode = _defaultCountryFor(nextLanguage);
        _explore = null;
        _charts = null;
        _genreSections = null;
        _selectedGenre = null;
        _selectedGenrePlaylists = null;
        _exploreError = null;
        _chartsError = null;
        _genresError = null;
        _genrePlaylistsError = null;
      });
      if (widget.active) {
        unawaited(_ensureSectionLoaded());
      }
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _defaultCountryFor(String languageCode) =>
      languageCode == ProfileLanguage.english.code ? 'US' : 'DE';

  void _scheduleTutorialStepSync() {
    final requestedStep = widget.tutorialStep;
    if (requestedStep == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.tutorialStep != requestedStep) {
        return;
      }
      _synchronizeTutorialStep(requestedStep);
    });
  }

  void _synchronizeTutorialStep(HotMusicTutorialStep step) {
    final requestedSection = step.section ?? HotMusicSection.explore;
    final nextExploreFilter = step.highlightsSongAction
        ? ((_explore?.trending.isNotEmpty ?? false)
              ? HotMusicExploreFilter.trending
              : (_explore?.newVideos.isNotEmpty ?? false)
              ? HotMusicExploreFilter.newVideos
              : HotMusicExploreFilter.trending)
        : HotMusicExploreFilter.trending;
    final changed =
        _section != requestedSection ||
        (requestedSection == HotMusicSection.explore &&
            _exploreFilter != nextExploreFilter) ||
        (requestedSection == HotMusicSection.charts &&
            _chartsFilter != HotMusicChartsFilter.videos) ||
        (requestedSection == HotMusicSection.genres &&
            (_genreFilter != HotMusicGenreFilter.moods ||
                _selectedGenre != null));
    if (changed) {
      setState(() {
        _section = requestedSection;
        if (requestedSection == HotMusicSection.explore) {
          _exploreFilter = nextExploreFilter;
        } else if (requestedSection == HotMusicSection.charts) {
          _chartsFilter = HotMusicChartsFilter.videos;
        } else {
          _genreFilter = HotMusicGenreFilter.moods;
          _selectedGenre = null;
          _selectedGenrePlaylists = null;
          _genrePlaylistsError = null;
          _loadingGenrePlaylists = false;
        }
      });
      _scrollToTop();
    }
    unawaited(_ensureSectionLoaded());
  }

  Future<HotMusicTutorialSong?> _resolveTutorialSong() async {
    final waiting = Stopwatch()..start();
    while (_loadingExplore &&
        mounted &&
        waiting.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) {
      return null;
    }
    if (_explore == null) {
      await _loadExplore(retry: _exploreError != null);
    }
    if (!mounted) {
      return null;
    }
    final explore = _explore;
    if (explore == null) {
      return null;
    }
    final videos = explore.trending.isNotEmpty
        ? explore.trending
        : explore.newVideos;
    if (videos.isEmpty) {
      return null;
    }
    final video = videos.first;
    final filter = explore.trending.isNotEmpty
        ? HotMusicExploreFilter.trending
        : HotMusicExploreFilter.newVideos;
    return HotMusicTutorialSong(
      video: video,
      queue: rotateHotMusicQueue(videos, video),
      contextTitle: 'Hot Music – ${context.l10n.exploreFilter(filter)}',
    );
  }

  Future<void> _ensureSectionLoaded() {
    return switch (_section) {
      HotMusicSection.explore => _loadExplore(),
      HotMusicSection.charts => _loadCharts(),
      HotMusicSection.genres =>
        _selectedGenre == null
            ? _loadGenreSections()
            : _loadGenrePlaylists(_selectedGenre!),
    };
  }

  Future<void> _loadExplore({bool retry = false}) async {
    final repository = widget.repository;
    if (repository == null || _loadingExplore || (_explore != null && !retry)) {
      return;
    }
    final generation = _requestGeneration;
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'hot_music.explore.started',
      fields: {'language': _languageCode, 'retry': retry},
    );
    setState(() {
      _loadingExplore = true;
      _exploreError = null;
      if (retry) {
        _explore = null;
      }
    });
    try {
      final result = await repository.loadExplore(languageCode: _languageCode);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _explore = result;
        if (widget.tutorialStep?.highlightsSongAction == true &&
            result.trending.isEmpty &&
            result.newVideos.isNotEmpty) {
          _exploreFilter = HotMusicExploreFilter.newVideos;
        }
        _loadingExplore = false;
      });
      AppLog.instance.info(
        'hot_music.explore.succeeded',
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          'trending': result.trending.length,
          'newVideos': result.newVideos.length,
          'newReleases': result.newReleases.length,
        },
      );
    } on YouTubeSearchException catch (error) {
      AppLog.instance.error(
        'hot_music.explore.failed',
        error: error.cause ?? error,
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setExploreError(error.message, generation);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'hot_music.explore.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setExploreError('Hot Music konnte nicht geladen werden.', generation);
    }
  }

  void _setExploreError(String message, int generation) {
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    setState(() {
      _loadingExplore = false;
      _exploreError = message;
    });
  }

  Future<void> _loadCharts({bool retry = false}) async {
    final repository = widget.repository;
    if (repository == null || _loadingCharts || (_charts != null && !retry)) {
      return;
    }
    final generation = _requestGeneration;
    final requestedCountry = _countryCode;
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'hot_music.charts.started',
      fields: {
        'language': _languageCode,
        'country': requestedCountry,
        'retry': retry,
      },
    );
    setState(() {
      _loadingCharts = true;
      _chartsError = null;
      if (retry) {
        _charts = null;
      }
    });
    try {
      final result = await repository.loadCharts(
        countryCode: requestedCountry,
        languageCode: _languageCode,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      final validCountries = result.countryCodes;
      if (validCountries.isNotEmpty &&
          !validCountries.contains(requestedCountry)) {
        final fallback = validCountries.contains('ZZ')
            ? 'ZZ'
            : validCountries.first;
        setState(() {
          _countryCode = fallback;
          _charts = null;
          _loadingCharts = false;
        });
        await _loadCharts();
        return;
      }
      setState(() {
        _charts = result;
        _loadingCharts = false;
      });
      AppLog.instance.info(
        'hot_music.charts.succeeded',
        fields: {
          'language': _languageCode,
          'country': requestedCountry,
          'durationMs': stopwatch.elapsedMilliseconds,
          'videos': result.videos.length,
          'artists': result.artists.length,
          'countryOptions': result.countryCodes.length,
        },
      );
    } on YouTubeSearchException catch (error) {
      AppLog.instance.error(
        'hot_music.charts.failed',
        error: error.cause ?? error,
        fields: {
          'language': _languageCode,
          'country': requestedCountry,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setChartsError(error.message, generation);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'hot_music.charts.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'language': _languageCode,
          'country': requestedCountry,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setChartsError('Die Charts konnten nicht geladen werden.', generation);
    }
  }

  void _setChartsError(String message, int generation) {
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    setState(() {
      _loadingCharts = false;
      _chartsError = message;
    });
  }

  Future<void> _loadGenreSections({bool retry = false}) async {
    final repository = widget.repository;
    if (repository == null ||
        _loadingGenres ||
        (_genreSections != null && !retry)) {
      return;
    }
    final generation = _requestGeneration;
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'hot_music.genres.started',
      fields: {'language': _languageCode, 'retry': retry},
    );
    setState(() {
      _loadingGenres = true;
      _genresError = null;
      if (retry) {
        _genreSections = null;
      }
    });
    try {
      final result = await repository.loadGenreSections(
        languageCode: _languageCode,
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _genreSections = result;
        _loadingGenres = false;
      });
      AppLog.instance.info(
        'hot_music.genres.succeeded',
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          'sectionCount': result.length,
          'categoryCount': result.fold<int>(
            0,
            (total, section) => total + section.categories.length,
          ),
        },
      );
    } on YouTubeSearchException catch (error) {
      AppLog.instance.error(
        'hot_music.genres.failed',
        error: error.cause ?? error,
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setGenresError(error.message, generation);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'hot_music.genres.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setGenresError(
        'Genres und Stimmungen konnten nicht geladen werden.',
        generation,
      );
    }
  }

  void _setGenresError(String message, int generation) {
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    setState(() {
      _loadingGenres = false;
      _genresError = message;
    });
  }

  Future<void> _openGenre(HotMusicCategory category) async {
    setState(() {
      _section = HotMusicSection.genres;
      _selectedGenre = category;
      _selectedGenrePlaylists = null;
      _genrePlaylistsError = null;
    });
    _scrollToTop();
    await _loadGenrePlaylists(category);
  }

  Future<void> _loadGenrePlaylists(
    HotMusicCategory category, {
    bool retry = false,
  }) async {
    final repository = widget.repository;
    if (repository == null ||
        _loadingGenrePlaylists ||
        (_selectedGenrePlaylists != null && !retry)) {
      return;
    }
    final generation = _requestGeneration;
    final stopwatch = Stopwatch()..start();
    final categoryId = AppLog.instance.opaqueId(category.params);
    AppLog.instance.info(
      'hot_music.genre_playlists.started',
      fields: {
        'category': categoryId,
        'language': _languageCode,
        'retry': retry,
      },
    );
    setState(() {
      _loadingGenrePlaylists = true;
      _genrePlaylistsError = null;
      if (retry) {
        _selectedGenrePlaylists = null;
      }
    });
    try {
      final result = await repository.loadGenrePlaylists(
        params: category.params,
        languageCode: _languageCode,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          _selectedGenre?.params != category.params) {
        return;
      }
      setState(() {
        _selectedGenrePlaylists = result;
        _loadingGenrePlaylists = false;
      });
      AppLog.instance.info(
        'hot_music.genre_playlists.succeeded',
        fields: {
          'category': categoryId,
          'language': _languageCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          'playlistCount': result.length,
        },
      );
    } on YouTubeSearchException catch (error) {
      AppLog.instance.error(
        'hot_music.genre_playlists.failed',
        error: error.cause ?? error,
        fields: {
          'category': categoryId,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setGenrePlaylistsError(error.message, generation, category.params);
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'hot_music.genre_playlists.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'category': categoryId,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      _setGenrePlaylistsError(
        'Die Playlists konnten nicht geladen werden.',
        generation,
        category.params,
      );
    }
  }

  void _setGenrePlaylistsError(String message, int generation, String params) {
    if (!mounted ||
        generation != _requestGeneration ||
        _selectedGenre?.params != params) {
      return;
    }
    setState(() {
      _loadingGenrePlaylists = false;
      _genrePlaylistsError = message;
    });
  }

  void _selectSection(HotMusicSection section) {
    if (section == _section) {
      return;
    }
    setState(() {
      _section = section;
      if (section != HotMusicSection.genres) {
        _selectedGenre = null;
        _selectedGenrePlaylists = null;
        _genrePlaylistsError = null;
      }
    });
    AppLog.instance.info(
      'hot_music.section.changed',
      fields: {'section': section.name},
    );
    _scrollToTop();
    unawaited(_ensureSectionLoaded());
  }

  void _selectExploreFilter(HotMusicExploreFilter filter) {
    if (filter == _exploreFilter) {
      return;
    }
    setState(() => _exploreFilter = filter);
    AppLog.instance.info(
      'hot_music.filter.changed',
      fields: {'section': 'explore', 'filter': filter.name},
    );
    _scrollToTop();
  }

  void _selectChartsFilter(HotMusicChartsFilter filter) {
    if (filter == _chartsFilter) {
      return;
    }
    setState(() => _chartsFilter = filter);
    AppLog.instance.info(
      'hot_music.filter.changed',
      fields: {'section': 'charts', 'filter': filter.name},
    );
    _scrollToTop();
  }

  void _selectGenreFilter(HotMusicGenreFilter filter) {
    if (filter == _genreFilter && _selectedGenre == null) {
      return;
    }
    setState(() {
      _genreFilter = filter;
      _selectedGenre = null;
      _selectedGenrePlaylists = null;
      _genrePlaylistsError = null;
      _loadingGenrePlaylists = false;
    });
    AppLog.instance.info(
      'hot_music.filter.changed',
      fields: {'section': 'genres', 'filter': filter.name},
    );
    _scrollToTop();
  }

  void _selectCountry(String countryCode) {
    if (countryCode == _countryCode) {
      return;
    }
    _requestGeneration++;
    setState(() {
      _countryCode = countryCode;
      _charts = null;
      _chartsError = null;
      _loadingCharts = false;
    });
    AppLog.instance.info(
      'hot_music.country.changed',
      fields: {'country': countryCode},
    );
    _scrollToTop();
    unawaited(_loadCharts());
  }

  void _closeGenre() {
    setState(() {
      _selectedGenre = null;
      _selectedGenrePlaylists = null;
      _genrePlaylistsError = null;
      _loadingGenrePlaylists = false;
    });
    _scrollToTop();
    unawaited(_loadGenreSections());
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.hotMusicUnsupported,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _HotMusicSectionBar(
            keyPrefix: widget.keyPrefix,
            selected: _section,
            exploreFilter: _exploreFilter,
            chartsFilter: _chartsFilter,
            genreFilter: _genreFilter,
            enabled: !_loadingExplore && !_loadingCharts && !_loadingGenres,
            onSectionSelected: _selectSection,
            onExploreFilterSelected: _selectExploreFilter,
            onChartsFilterSelected: _selectChartsFilter,
            onGenreFilterSelected: _selectGenreFilter,
            tutorialTargets: widget.tutorialTargets,
            onTutorialMenuOpened: widget.onTutorialMenuOpened,
            onTutorialMenuClosed: widget.onTutorialMenuClosed,
          ),
        ),
        if (_section == HotMusicSection.charts)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildCountrySelector(),
            ),
          ),
        Expanded(child: _buildSectionContent()),
      ],
    );
  }

  Widget _buildCountrySelector() {
    final result = _charts;
    final validCodes = result?.countryCodes ?? const <String>[];
    final preferred = _preferredCountryCodes
        .where(validCodes.contains)
        .toList(growable: false);
    final options = preferred.isNotEmpty ? preferred : validCodes;
    return PopupMenuButton<String>(
      key: ValueKey('${widget.keyPrefix}-country-selector'),
      enabled: options.isNotEmpty && !_loadingCharts,
      initialValue: _countryCode,
      tooltip: context.l10n.chartCountry(
        context.l10n.countryLabel(_countryCode),
      ),
      position: PopupMenuPosition.under,
      onSelected: _selectCountry,
      itemBuilder: (context) => [
        for (final code in options)
          PopupMenuItem<String>(
            key: ValueKey('${widget.keyPrefix}-country-$code'),
            value: code,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: code == _countryCode
                      ? const Icon(Icons.check, size: 20)
                      : null,
                ),
                Text(context.l10n.countryLabel(code)),
              ],
            ),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.public, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.countryLabel(_countryCode)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent() {
    return switch (_section) {
      HotMusicSection.explore => _buildExplore(),
      HotMusicSection.charts => _buildCharts(),
      HotMusicSection.genres =>
        _selectedGenre == null
            ? _buildGenres()
            : _buildGenrePlaylists(_selectedGenre!),
    };
  }

  Widget _buildExplore() {
    if (_loadingExplore && _explore == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_exploreError case final error?) {
      return _HotMusicError(
        message: error,
        onRetry: () => unawaited(_loadExplore(retry: true)),
      );
    }
    final explore = _explore;
    if (explore == null) {
      return const SizedBox.shrink();
    }
    return switch (_exploreFilter) {
      HotMusicExploreFilter.trending => _buildVideos(
        explore.trending,
        contextTitle:
            'Hot Music – ${context.l10n.exploreFilter(_exploreFilter)}',
        heading: context.l10n.exploreFilter(_exploreFilter),
      ),
      HotMusicExploreFilter.newVideos => _buildVideos(
        explore.newVideos,
        contextTitle:
            'Hot Music – ${context.l10n.exploreFilter(_exploreFilter)}',
        heading: context.l10n.exploreFilter(_exploreFilter),
      ),
      HotMusicExploreFilter.newReleases => _buildPlaylists(
        explore.newReleases,
        emptyMessage: context.l10n.noNewReleases,
        heading: context.l10n.exploreFilter(_exploreFilter),
      ),
    };
  }

  Widget _buildCharts() {
    if (_loadingCharts && _charts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_chartsError case final error?) {
      return _HotMusicError(
        message: error,
        onRetry: () => unawaited(_loadCharts(retry: true)),
      );
    }
    final charts = _charts;
    if (charts == null) {
      return const SizedBox.shrink();
    }
    return switch (_chartsFilter) {
      HotMusicChartsFilter.videos => _buildPlaylists(
        charts.videos,
        emptyMessage: context.l10n.noVideoCharts,
        heading: context.l10n.chartsFilter(_chartsFilter),
      ),
      HotMusicChartsFilter.artists => _buildArtists(
        charts.artists,
        heading: context.l10n.chartsFilter(_chartsFilter),
      ),
    };
  }

  Widget _buildGenres() {
    if (_loadingGenres && _genreSections == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_genresError case final error?) {
      return _HotMusicError(
        message: error,
        onRetry: () => unawaited(_loadGenreSections(retry: true)),
      );
    }
    final sections = _genreSections;
    if (sections == null) {
      return const SizedBox.shrink();
    }
    if (sections.isEmpty) {
      return Center(child: Text(context.l10n.noCategories));
    }
    final visibleSections = _visibleGenreSections(sections);
    if (visibleSections.isEmpty) {
      final label = context.l10n.genreFilter(_genreFilter);
      return Center(child: Text(context.l10n.noItems(label)));
    }
    final children = <Widget>[];
    for (final section in visibleSections) {
      children
        ..add(_buildListHeading(section.title))
        ..addAll(
          section.categories.map(
            (category) => _HotMusicCategoryCard(
              key: ValueKey('${widget.keyPrefix}-genre-${category.params}'),
              category: category,
              onTap: () => unawaited(_openGenre(category)),
            ),
          ),
        );
    }
    return ListView(
      key: ValueKey('${widget.keyPrefix}-genres-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: children,
    );
  }

  List<HotMusicGenreSection> _visibleGenreSections(
    List<HotMusicGenreSection> sections,
  ) {
    bool isMoodSection(HotMusicGenreSection section) {
      final title = section.title.toLowerCase();
      return title.contains('stimmung') ||
          title.contains('moment') ||
          title.contains('mood');
    }

    bool isGenreSection(HotMusicGenreSection section) {
      final title = section.title.toLowerCase();
      return title.contains('genre') && !isMoodSection(section);
    }

    final matching = sections.where(
      _genreFilter == HotMusicGenreFilter.moods
          ? isMoodSection
          : isGenreSection,
    );
    return List<HotMusicGenreSection>.unmodifiable(matching);
  }

  Widget _buildGenrePlaylists(HotMusicCategory category) {
    if (_loadingGenrePlaylists && _selectedGenrePlaylists == null) {
      return Column(
        children: [
          _GenreDetailHeader(title: category.title, onBack: _closeGenre),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (_genrePlaylistsError case final error?) {
      return Column(
        children: [
          _GenreDetailHeader(title: category.title, onBack: _closeGenre),
          Expanded(
            child: _HotMusicError(
              message: error,
              onRetry: () =>
                  unawaited(_loadGenrePlaylists(category, retry: true)),
            ),
          ),
        ],
      );
    }
    final playlists = _selectedGenrePlaylists ?? const [];
    return Column(
      children: [
        _GenreDetailHeader(title: category.title, onBack: _closeGenre),
        Expanded(
          child: _buildPlaylists(
            playlists,
            emptyMessage: context.l10n.noCategoryPlaylists(category.title),
          ),
        ),
      ],
    );
  }

  Widget _buildVideos(
    List<YouTubeVideo> videos, {
    required String contextTitle,
    String? heading,
  }) {
    if (videos.isEmpty) {
      return Center(child: Text(context.l10n.noSongs));
    }
    return AnimatedBuilder(
      animation: widget.profileController,
      builder: (context, _) {
        final favoriteIds =
            widget.profileController.activeProfile?.favorites
                .map((video) => video.id)
                .toSet() ??
            const <String>{};
        return ListView.builder(
          key: ValueKey('${widget.keyPrefix}-video-list'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: videos.length + (heading == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (heading != null && index == 0) {
              return _buildListHeading(heading);
            }
            final video = videos[index - (heading == null ? 0 : 1)];
            final isFirstTutorialSong =
                widget.tutorialStep?.highlightsSongAction == true &&
                index == (heading == null ? 0 : 1);
            final tutorialStep = widget.tutorialStep;
            if (isFirstTutorialSong &&
                tutorialStep != null &&
                _notifiedTutorialActionTargetStep != tutorialStep) {
              _notifiedTutorialActionTargetStep = tutorialStep;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && widget.tutorialStep == tutorialStep) {
                  widget.onTutorialActionTargetReady?.call();
                }
              });
            }
            return VideoResultCard(
              key: ValueKey('${widget.keyPrefix}-video-${video.id}'),
              video: video,
              isFavorite: favoriteIds.contains(video.id),
              onTap: () => widget.onVideoSelected(
                video,
                rotateHotMusicQueue(videos, video),
                contextTitle,
              ),
              onToggleFavorite: () =>
                  unawaited(widget.onToggleVideoFavorite(video)),
              onAddToPlaylist: () =>
                  unawaited(widget.onAddVideoToPlaylist(video)),
              showInfo: true,
              loadFullDescription: widget.loadFullDescription == null
                  ? null
                  : () => widget.loadFullDescription!(video),
              favoriteActionTargetKey: isFirstTutorialSong
                  ? widget.tutorialTargets?.favorite
                  : null,
              playlistActionTargetKey: isFirstTutorialSong
                  ? widget.tutorialTargets?.playlist
                  : null,
              infoActionTargetKey: isFirstTutorialSong
                  ? widget.tutorialTargets?.info
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylists(
    List<YouTubePlaylistResult> playlists, {
    required String emptyMessage,
    String? heading,
  }) {
    if (playlists.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView.builder(
      key: ValueKey('${widget.keyPrefix}-playlist-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: playlists.length + (heading == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (heading != null && index == 0) {
          return _buildListHeading(heading);
        }
        final playlist = playlists[index - (heading == null ? 0 : 1)];
        return YouTubePlaylistResultCard(
          key: ValueKey('${widget.keyPrefix}-playlist-${playlist.id}'),
          playlist: playlist,
          onTap: () => widget.onPlaylistSelected(playlist),
          onAddToPlaylist: () => unawaited(widget.onImportPlaylist(playlist)),
        );
      },
    );
  }

  Widget _buildArtists(List<YouTubeChannelResult> artists, {String? heading}) {
    if (artists.isEmpty) {
      return Center(child: Text(context.l10n.noArtistCharts));
    }
    return AnimatedBuilder(
      animation: widget.profileController,
      builder: (context, _) {
        final favoriteIds =
            widget.profileController.activeProfile?.favoriteChannels
                .map((channel) => channel.id)
                .toSet() ??
            const <String>{};
        return ListView.builder(
          key: ValueKey('${widget.keyPrefix}-artist-list'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: artists.length + (heading == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (heading != null && index == 0) {
              return _buildListHeading(heading);
            }
            final artist = artists[index - (heading == null ? 0 : 1)];
            return YouTubeChannelResultCard(
              key: ValueKey('${widget.keyPrefix}-artist-${artist.id}'),
              channel: artist,
              isFavorite: favoriteIds.contains(artist.id),
              onTap: () => widget.onArtistSelected(artist),
              onToggleFavorite: () =>
                  unawaited(widget.onToggleArtistFavorite(artist)),
            );
          },
        );
      },
    );
  }

  Widget _buildListHeading(String title) {
    return Padding(
      key: ValueKey('${widget.keyPrefix}-filter-heading-$title'),
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

List<YouTubeVideo> rotateHotMusicQueue(
  List<YouTubeVideo> videos,
  YouTubeVideo selected,
) {
  if (videos.isEmpty) {
    return const [];
  }
  final index = videos.indexWhere(
    (video) => video.id == selected.id && video.isMusic == selected.isMusic,
  );
  if (index <= 0) {
    return List<YouTubeVideo>.unmodifiable(videos.take(searchResultLimit));
  }
  return List<YouTubeVideo>.unmodifiable(
    [...videos.skip(index), ...videos.take(index)].take(searchResultLimit),
  );
}

class _HotMusicSectionBar extends StatelessWidget {
  const _HotMusicSectionBar({
    required this.keyPrefix,
    required this.selected,
    required this.exploreFilter,
    required this.chartsFilter,
    required this.genreFilter,
    required this.enabled,
    required this.onSectionSelected,
    required this.onExploreFilterSelected,
    required this.onChartsFilterSelected,
    required this.onGenreFilterSelected,
    this.tutorialTargets,
    this.onTutorialMenuOpened,
    this.onTutorialMenuClosed,
  });

  final String keyPrefix;
  final HotMusicSection selected;
  final HotMusicExploreFilter exploreFilter;
  final HotMusicChartsFilter chartsFilter;
  final HotMusicGenreFilter genreFilter;
  final bool enabled;
  final ValueChanged<HotMusicSection> onSectionSelected;
  final ValueChanged<HotMusicExploreFilter> onExploreFilterSelected;
  final ValueChanged<HotMusicChartsFilter> onChartsFilterSelected;
  final ValueChanged<HotMusicGenreFilter> onGenreFilterSelected;
  final HotMusicTutorialTargets? tutorialTargets;
  final ValueChanged<HotMusicSection>? onTutorialMenuOpened;
  final ValueChanged<HotMusicSection>? onTutorialMenuClosed;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('$keyPrefix-section-bar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final section in HotMusicSection.values)
            Expanded(child: _buildSection(context, section)),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, HotMusicSection section) {
    final active = section == selected;
    final opensMenu = active;
    final label = context.l10n.hotMusicSection(section);
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: active
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
    );
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (opensMenu)
            Icon(Icons.arrow_drop_down, size: 18, color: style?.color),
        ],
      ),
    );
    if (!opensMenu) {
      return KeyedSubtree(
        key: tutorialTargets?.section(section),
        child: InkWell(
          key: ValueKey('$keyPrefix-section-${section.name}'),
          onTap: enabled && !active ? () => onSectionSelected(section) : null,
          child: child,
        ),
      );
    }
    final menu = switch (section) {
      HotMusicSection.explore => PopupMenuButton<HotMusicExploreFilter>(
        key: ValueKey('$keyPrefix-section-${section.name}'),
        enabled: enabled,
        initialValue: exploreFilter,
        position: PopupMenuPosition.under,
        onOpened: () => onTutorialMenuOpened?.call(section),
        onCanceled: () => onTutorialMenuClosed?.call(section),
        onSelected: (filter) {
          onExploreFilterSelected(filter);
          onTutorialMenuClosed?.call(section);
        },
        itemBuilder: (context) => [
          for (final filter in HotMusicExploreFilter.values)
            PopupMenuItem(
              key: ValueKey('$keyPrefix-explore-filter-${filter.name}'),
              value: filter,
              child: _FilterMenuRow(
                selected: filter == exploreFilter,
                label: context.l10n.exploreFilter(filter),
              ),
            ),
        ],
        child: child,
      ),
      HotMusicSection.charts => PopupMenuButton<HotMusicChartsFilter>(
        key: ValueKey('$keyPrefix-section-${section.name}'),
        enabled: enabled,
        initialValue: chartsFilter,
        position: PopupMenuPosition.under,
        onOpened: () => onTutorialMenuOpened?.call(section),
        onCanceled: () => onTutorialMenuClosed?.call(section),
        onSelected: (filter) {
          onChartsFilterSelected(filter);
          onTutorialMenuClosed?.call(section);
        },
        itemBuilder: (context) => [
          for (final filter in HotMusicChartsFilter.values)
            PopupMenuItem(
              key: ValueKey('$keyPrefix-charts-filter-${filter.name}'),
              value: filter,
              child: _FilterMenuRow(
                selected: filter == chartsFilter,
                label: context.l10n.chartsFilter(filter),
              ),
            ),
        ],
        child: child,
      ),
      HotMusicSection.genres => PopupMenuButton<HotMusicGenreFilter>(
        key: ValueKey('$keyPrefix-section-${section.name}'),
        enabled: enabled,
        initialValue: genreFilter,
        position: PopupMenuPosition.under,
        onOpened: () => onTutorialMenuOpened?.call(section),
        onCanceled: () => onTutorialMenuClosed?.call(section),
        onSelected: (filter) {
          onGenreFilterSelected(filter);
          onTutorialMenuClosed?.call(section);
        },
        itemBuilder: (context) => [
          for (final filter in HotMusicGenreFilter.values)
            PopupMenuItem(
              key: ValueKey('$keyPrefix-genres-filter-${filter.name}'),
              value: filter,
              child: _FilterMenuRow(
                selected: filter == genreFilter,
                label: context.l10n.genreFilter(filter),
              ),
            ),
        ],
        child: child,
      ),
    };
    return KeyedSubtree(key: tutorialTargets?.section(section), child: menu);
  }
}

class _FilterMenuRow extends StatelessWidget {
  const _FilterMenuRow({required this.selected, required this.label});

  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: selected ? const Icon(Icons.check, size: 20) : null,
        ),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _HotMusicCategoryCard extends StatelessWidget {
  const _HotMusicCategoryCard({
    super.key,
    required this.category,
    required this.onTap,
  });

  final HotMusicCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.graphic_eq)),
        title: Text(
          category.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _GenreDetailHeader extends StatelessWidget {
  const _GenreDetailHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('hot-music-genre-back'),
            tooltip: context.l10n.backToGenres,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotMusicError extends StatelessWidget {
  const _HotMusicError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.translateKnownMessage(message),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
