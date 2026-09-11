import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/video_playback.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/services/playback_manifest_cache.dart';
import 'package:flutter_browser_app/services/video_playback_service.dart';

void main() {
  test('Prefetch löst eine vorhandene Lazy-Fallbackstufe nicht aus', () async {
    final service = _LazyFallbackPlaybackService();
    final cache = PlaybackManifestCache(service);
    final video = _videos('lazy', 1).single;

    cache.replaceVisibleVideos([video]);
    await pumpEventQueue();

    expect(service.primaryLoads, 1);
    expect(service.fallbackLoads, 0);
    expect(cache.stateOf(video.id), PlaybackManifestEntryState.ready);
  });

  test('reicht Manifest-Zeitereignisse des Prefetchs weiter', () async {
    final service = _ControlledPlaybackService();
    final cache = PlaybackManifestCache(service);
    final video = _videos('events', 1).single;
    final phases = <VideoManifestLoadPhase>[];

    cache.replaceVisibleVideos([
      video,
    ], onManifestEvent: (event) => phases.add(event.phase));
    expect(phases, [VideoManifestLoadPhase.requested]);

    service.complete(video.id);
    await pumpEventQueue();
    expect(phases, [
      VideoManifestLoadPhase.requested,
      VideoManifestLoadPhase.available,
    ]);
  });

  test(
    'meldet den Zustand eines Manifest-Eintrags ohne ihn zu ändern',
    () async {
      final service = _ControlledPlaybackService();
      final cache = PlaybackManifestCache(
        service,
        maxConcurrentLoads: 1,
        maxConcurrentPrefetchLoads: 1,
      );
      final videos = _videos('state', 2);

      expect(cache.stateOf('unbekannt'), PlaybackManifestEntryState.missing);
      cache.replaceVisibleVideos(videos);
      expect(cache.stateOf(videos[0].id), PlaybackManifestEntryState.loading);
      expect(cache.stateOf(videos[1].id), PlaybackManifestEntryState.queued);

      service.complete(videos[0].id);
      await pumpEventQueue();
      expect(cache.stateOf(videos[0].id), PlaybackManifestEntryState.ready);
      expect(cache.stateOf(videos[1].id), PlaybackManifestEntryState.loading);
    },
  );

  test('lädt höchstens fünf Manifeste gleichzeitig', () async {
    final service = _ControlledPlaybackService();
    final cache = PlaybackManifestCache(service);
    cache.replaceVisibleVideos(_videos('page', 20));

    expect(service.requestedVideoIds, hasLength(5));
    expect(service.maximumActiveRequests, 5);

    service.complete(service.requestedVideoIds.first);
    await pumpEventQueue();

    expect(service.requestedVideoIds, hasLength(6));
    expect(service.activeRequests, 5);
    expect(service.maximumActiveRequests, 5);
  });

  test('verwendet vorhandene Manifeste nach der Rückkehr erneut', () async {
    final service = _ImmediatePlaybackService();
    final cache = PlaybackManifestCache(service);
    final videos = _videos('page', 20);
    cache.replaceVisibleVideos(videos);
    await pumpEventQueue();

    expect(service.requestedVideoIds.toSet(), hasLength(20));
    final cached = cache.resolve(videos[7].id);
    final reused = cache.resolve(videos[7].id);
    expect(identical(cached, reused), isTrue);

    cache.replaceVisibleVideos(videos);
    await pumpEventQueue();
    expect(service.requestedVideoIds, hasLength(20));
  });

  test('trennt Music-, Live- und Sprachvarianten desselben Videos', () async {
    final service = _ImmediatePlaybackService();
    final cache = PlaybackManifestCache(service);

    await cache.resolve('same', languageCode: 'de');
    await cache.resolve('same', languageCode: 'en');
    await cache.resolve('same', music: true, languageCode: 'de');
    await cache.resolve('same', music: true, languageCode: 'de');
    await cache.resolve('same', isLive: true, languageCode: 'de');

    expect(service.requests, [
      (videoId: 'same', music: false, isLive: false, languageCode: 'de'),
      (videoId: 'same', music: false, isLive: false, languageCode: 'en'),
      (videoId: 'same', music: true, isLive: false, languageCode: 'de'),
      (videoId: 'same', music: false, isLive: true, languageCode: 'de'),
    ]);
  });

  test('fordert nur reine Songs als Audio-Manifest an', () async {
    final service = _ImmediatePlaybackService();
    final cache = PlaybackManifestCache(service);
    const song = YouTubeVideo(
      id: 'song',
      title: 'Song',
      description: '',
      thumbnailUrl: '',
      isMusic: true,
    );
    const musicVideo = YouTubeVideo(
      id: 'music-video',
      title: 'Music Video',
      description: '',
      thumbnailUrl: '',
      isMusic: true,
      isMusicVideo: true,
    );

    cache.replaceVisibleVideos(const [song, musicVideo]);
    await pumpEventQueue();

    expect(service.requests, [
      (videoId: 'song', music: true, isLive: false, languageCode: 'de'),
      (videoId: 'music-video', music: false, isLive: false, languageCode: 'de'),
    ]);
  });

  test(
    'reserviert beim pausierten Vorladen Kapazität für den Player',
    () async {
      final service = _ControlledPlaybackService();
      final cache = PlaybackManifestCache(
        service,
        maxConcurrentLoads: 5,
        maxConcurrentPrefetchLoads: 2,
      );
      final videos = _videos('priority', 20);

      cache.replaceVisibleVideos(videos);
      expect(service.requestedVideoIds, hasLength(2));

      cache.pausePrefetch();
      service.complete(videos.first.id);
      await pumpEventQueue();
      expect(service.requestedVideoIds, hasLength(2));

      final foreground = cache.resolve(videos[10].id);
      expect(service.requestedVideoIds, contains(videos[10].id));
      expect(service.activeRequests, 2);

      service.complete(videos[10].id);
      await foreground;
      expect(service.requestedVideoIds, hasLength(3));

      cache.resumePrefetch();
      await pumpEventQueue();
      expect(service.requestedVideoIds, hasLength(4));
    },
  );
}

List<YouTubeVideo> _videos(String prefix, int count) => List.generate(
  count,
  (index) => YouTubeVideo(
    id: '$prefix-$index',
    title: 'Video $index',
    description: '',
    thumbnailUrl: '',
  ),
);

ResolvedVideoPlayback _playback(String videoId) {
  final quality = VideoQualityOption(
    label: '720p',
    height: 720,
    videoUrl: Uri.parse('https://example.com/$videoId.mp4'),
  );
  return ResolvedVideoPlayback(qualities: [quality], defaultQuality: quality);
}

class _ControlledPlaybackService implements VideoPlaybackService {
  final List<String> requestedVideoIds = [];
  final Map<String, Completer<ResolvedVideoPlayback>> _requests = {};
  final Map<String, VideoManifestEventCallback?> _callbacks = {};
  int activeRequests = 0;
  int maximumActiveRequests = 0;

  @override
  void close() {}

  void complete(String videoId) {
    _callbacks
        .remove(videoId)
        ?.call(
          VideoManifestLoadEvent(
            videoId: videoId,
            source: VideoManifestSource.standard,
            phase: VideoManifestLoadPhase.available,
          ),
        );
    _requests.remove(videoId)!.complete(_playback(videoId));
  }

  @override
  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId) async =>
      const [];

  @override
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) {
    requestedVideoIds.add(videoId);
    _callbacks[videoId] = onManifestEvent;
    onManifestEvent?.call(
      VideoManifestLoadEvent(
        videoId: videoId,
        source: VideoManifestSource.standard,
        phase: VideoManifestLoadPhase.requested,
      ),
    );
    activeRequests++;
    if (activeRequests > maximumActiveRequests) {
      maximumActiveRequests = activeRequests;
    }
    final completer = Completer<ResolvedVideoPlayback>();
    _requests[videoId] = completer;
    return completer.future.whenComplete(() => activeRequests--);
  }
}

class _ImmediatePlaybackService implements VideoPlaybackService {
  final List<String> requestedVideoIds = [];
  final List<({String videoId, bool music, bool isLive, String languageCode})>
  requests = [];

  @override
  void close() {}

  @override
  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId) async =>
      const [];

  @override
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) async {
    requestedVideoIds.add(videoId);
    requests.add((
      videoId: videoId,
      music: music,
      isLive: isLive,
      languageCode: languageCode,
    ));
    return _playback(videoId);
  }
}

class _LazyFallbackPlaybackService implements VideoPlaybackService {
  int primaryLoads = 0;
  int fallbackLoads = 0;

  @override
  void close() {}

  @override
  Future<List<VideoSubtitleCue>> loadSubtitles(String videoId) async =>
      const [];

  @override
  Future<ResolvedVideoPlayback> resolve(
    String videoId, {
    VideoManifestEventCallback? onManifestEvent,
    bool music = false,
    bool isLive = false,
    String languageCode = 'de',
  }) async {
    primaryLoads++;
    final primary = _playback(videoId);
    return ResolvedVideoPlayback(
      qualities: primary.qualities,
      defaultQuality: primary.defaultQuality,
      fallbackLoader: () async {
        fallbackLoads++;
        return _playback('$videoId-fallback');
      },
    );
  }
}
