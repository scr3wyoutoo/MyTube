import 'dart:async';
import 'dart:collection';

import '../models/video_playback.dart';
import '../models/youtube_video.dart';
import 'video_playback_service.dart';
import 'app_log.dart';

enum PlaybackManifestEntryState { missing, queued, loading, ready }

class PlaybackManifestCache {
  PlaybackManifestCache(
    this._playbackService, {
    this.maxConcurrentLoads = 5,
    int? maxConcurrentPrefetchLoads,
    this.maxVisibleEntries = 20,
  }) : assert(maxConcurrentLoads > 0),
       maxConcurrentPrefetchLoads =
           maxConcurrentPrefetchLoads ?? maxConcurrentLoads,
       assert(
         (maxConcurrentPrefetchLoads ?? maxConcurrentLoads) > 0 &&
             (maxConcurrentPrefetchLoads ?? maxConcurrentLoads) <=
                 maxConcurrentLoads,
       ),
       assert(maxVisibleEntries > 0);

  final VideoPlaybackService _playbackService;
  final int maxConcurrentLoads;
  final int maxConcurrentPrefetchLoads;
  final int maxVisibleEntries;
  final Map<_ManifestCacheKey, _ManifestEntry> _entries = {};
  final ListQueue<_ManifestCacheKey> _pendingVideoIds = ListQueue();
  int _activeLoads = 0;
  int _activePrefetchLoads = 0;
  bool _prefetchPaused = false;

  int get cachedEntryCount => _entries.length;
  int get activeLoadCount => _activeLoads;
  bool get isPrefetchPaused => _prefetchPaused;

  PlaybackManifestEntryState stateOf(
    String videoId, {
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) {
    final entry =
        _entries[_cacheKey(
          videoId,
          music: music,
          isLive: isLive,
          languageCode: languageCode,
        )];
    if (entry == null) {
      return PlaybackManifestEntryState.missing;
    }
    if (entry.completer.isCompleted) {
      return PlaybackManifestEntryState.ready;
    }
    return entry.started
        ? PlaybackManifestEntryState.loading
        : PlaybackManifestEntryState.queued;
  }

  void pausePrefetch() {
    if (!_prefetchPaused) {
      AppLog.instance.info('manifest.prefetch.paused');
    }
    _prefetchPaused = true;
  }

  void resumePrefetch() {
    if (!_prefetchPaused) {
      return;
    }
    _prefetchPaused = false;
    AppLog.instance.info('manifest.prefetch.resumed');
    _pumpQueue();
  }

  void replaceVisibleVideos(
    Iterable<YouTubeVideo> videos, {
    VideoManifestEventCallback? onManifestEvent,
    String languageCode = 'de',
  }) {
    final keys = videos
        .take(maxVisibleEntries)
        .map(
          (video) => _cacheKey(
            video.id,
            music: video.isAudioOnlyMusic,
            isLive: video.isLive,
            languageCode: languageCode,
          ),
        )
        .toList(growable: false);
    AppLog.instance.info(
      'manifest.visible_set.replaced',
      fields: {'count': keys.length, 'language': languageCode},
    );
    final visibleKeys = keys.toSet();

    _entries.removeWhere((key, _) => !visibleKeys.contains(key));
    _pendingVideoIds.clear();
    for (final key in keys) {
      final entry = _entries.putIfAbsent(key, _createEntry);
      entry.addManifestEventCallback(onManifestEvent);
      if (!entry.started) {
        _pendingVideoIds.addLast(key);
      }
    }
    _pumpQueue();
  }

  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) {
    final key = _cacheKey(
      videoId,
      music: music,
      isLive: isLive,
      languageCode: languageCode,
    );
    final existing = _entries[key];
    final entry = existing ?? _createEntry();
    if (existing == null) {
      _entries[key] = entry;
    }
    AppLog.instance.info(
      existing?.completer.isCompleted == true
          ? 'manifest.cache.hit'
          : 'manifest.cache.miss',
      fields: {
        'mediaId': videoId,
        'music': music,
        'live': isLive,
        'language': languageCode,
        'state': stateOf(
          videoId,
          music: music,
          isLive: isLive,
          languageCode: languageCode,
        ).name,
      },
    );
    entry.addManifestEventCallback(onManifestEvent);
    entry.isForeground = true;
    if (entry.countedAsPrefetch) {
      entry.countedAsPrefetch = false;
      _activePrefetchLoads--;
    }
    if (!entry.started) {
      _pendingVideoIds.remove(key);
      _pendingVideoIds.addFirst(key);
      _pumpQueue();
    }
    return entry.completer.future;
  }

  void clear() {
    if (_entries.isNotEmpty || _pendingVideoIds.isNotEmpty) {
      AppLog.instance.info(
        'manifest.cache.cleared',
        fields: {'entries': _entries.length, 'queued': _pendingVideoIds.length},
      );
    }
    _entries.clear();
    _pendingVideoIds.clear();
  }

  _ManifestEntry _createEntry() {
    final entry = _ManifestEntry();
    unawaited(entry.completer.future.then<void>((_) {}, onError: (_, _) {}));
    return entry;
  }

  void _pumpQueue() {
    while (_activeLoads < maxConcurrentLoads && _pendingVideoIds.isNotEmpty) {
      final key = _pendingVideoIds.removeFirst();
      final entry = _entries[key];
      if (entry == null || entry.started) {
        continue;
      }
      if (!entry.isForeground &&
          (_prefetchPaused ||
              _activePrefetchLoads >= maxConcurrentPrefetchLoads)) {
        _pendingVideoIds.addFirst(key);
        return;
      }
      entry.started = true;
      if (!entry.isForeground) {
        entry.countedAsPrefetch = true;
        _activePrefetchLoads++;
      }
      _activeLoads++;
      unawaited(_load(key, entry));
    }
  }

  Future<void> _load(_ManifestCacheKey key, _ManifestEntry entry) async {
    final stopwatch = Stopwatch()..start();
    AppLog.instance.info(
      'manifest.resolve.started',
      fields: {
        'mediaId': key.videoId,
        'foreground': entry.isForeground,
        'music': key.music,
        'live': key.isLive,
        'language': key.languageCode,
      },
    );
    try {
      final playback = await _playbackService.resolve(
        key.videoId,
        onManifestEvent: entry.notifyManifestEvent,
        music: key.music,
        isLive: key.isLive,
        languageCode: key.languageCode,
      );
      if (!entry.completer.isCompleted) {
        entry.completer.complete(playback);
      }
      AppLog.instance.info(
        'manifest.resolve.succeeded',
        fields: {
          'mediaId': key.videoId,
          'durationMs': stopwatch.elapsedMilliseconds,
          'source': playback.manifestSource.name,
          'qualityCount': playback.qualities.length,
          'defaultQuality': playback.defaultQuality.label,
          'transport': playback.defaultQuality.transportLabel,
          'live': playback.isLive,
          'hasFallback': playback.fallbackLoader != null,
        },
      );
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'manifest.resolve.failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'mediaId': key.videoId,
          'durationMs': stopwatch.elapsedMilliseconds,
          'foreground': entry.isForeground,
          'music': key.music,
          'live': key.isLive,
        },
      );
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(error, stackTrace);
      }
      if (identical(_entries[key], entry)) {
        _entries.remove(key);
      }
    } finally {
      if (entry.countedAsPrefetch) {
        entry.countedAsPrefetch = false;
        _activePrefetchLoads--;
      }
      _activeLoads--;
      _pumpQueue();
    }
  }

  _ManifestCacheKey _cacheKey(
    String videoId, {
    required bool music,
    required bool isLive,
    required String languageCode,
  }) => (
    videoId: videoId,
    music: music,
    isLive: isLive,
    languageCode: languageCode == 'en' ? 'en' : 'de',
  );
}

typedef _ManifestCacheKey = ({
  String videoId,
  bool music,
  bool isLive,
  String languageCode,
});

class _ManifestEntry {
  final Completer<ResolvedVideoPlayback> completer = Completer();
  final List<VideoManifestEventCallback> _manifestEventCallbacks = [];
  bool started = false;
  bool isForeground = false;
  bool countedAsPrefetch = false;

  void addManifestEventCallback(VideoManifestEventCallback? callback) {
    if (callback != null && !_manifestEventCallbacks.contains(callback)) {
      _manifestEventCallbacks.add(callback);
    }
  }

  void notifyManifestEvent(VideoManifestLoadEvent event) {
    for (final callback in List<VideoManifestEventCallback>.of(
      _manifestEventCallbacks,
    )) {
      callback(event);
    }
  }
}
