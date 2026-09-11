import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/video_playback.dart';
import 'package:flutter_browser_app/services/video_playback_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('findet den zur Wiedergabeposition passenden Untertitel', () {
    final playback = ResolvedVideoPlayback(
      qualities: [
        VideoQualityOption(
          label: '720p',
          height: 720,
          videoUrl: Uri.parse('https://example.com/video.mp4'),
        ),
      ],
      defaultQuality: VideoQualityOption(
        label: '720p',
        height: 720,
        videoUrl: Uri.parse('https://example.com/video.mp4'),
      ),
      subtitles: const [
        VideoSubtitleCue(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          text: 'Erster Text',
        ),
        VideoSubtitleCue(
          start: Duration(seconds: 5),
          end: Duration(seconds: 8),
          text: 'Zweiter Text',
        ),
      ],
    );

    expect(playback.subtitleAt(const Duration(seconds: 2)), 'Erster Text');
    expect(playback.subtitleAt(const Duration(seconds: 4)), isNull);
    expect(playback.subtitleAt(const Duration(seconds: 6)), 'Zweiter Text');
  });

  test('wählt bevorzugt 720p und fällt nur bei Bedarf darunter', () {
    final qualities = [_quality(2160), _quality(1080), _quality(720)];
    expect(chooseDefaultVideoQuality(qualities).height, 720);

    expect(
      chooseDefaultVideoQuality([_quality(1080), _quality(1440)]).height,
      1080,
    );
    expect(
      chooseDefaultVideoQuality([_quality(360), _quality(480)]).height,
      480,
    );
  });

  test('bietet niedrigere Auflösungen nur ohne verfügbares HD an', () {
    final withHd = filterSelectableVideoQualities([
      _quality(1080),
      _quality(720),
      _quality(480),
    ]);
    expect(withHd.map((quality) => quality.height), [1080, 720]);

    final withoutHd = filterSelectableVideoQualities([
      _quality(360),
      _quality(480),
    ]);
    expect(withoutHd.map((quality) => quality.height), [480, 360]);
  });

  test('behält die lazy Fallbackstufe beim Ergänzen von Untertiteln', () async {
    final fallbackQuality = _quality(360);
    final playback = ResolvedVideoPlayback(
      qualities: [_quality(720)],
      defaultQuality: _quality(720),
      manifestSource: VideoManifestSource.standard,
      fallbackLoader: () async => ResolvedVideoPlayback(
        qualities: [fallbackQuality],
        defaultQuality: fallbackQuality,
        manifestSource: VideoManifestSource.firstFallback,
      ),
    );

    final withSubtitles = playback.withSubtitles(const []);
    final fallback = await withSubtitles.fallbackLoader!();

    expect(fallback.manifestSource, VideoManifestSource.firstFallback);
    expect(fallback.defaultQuality.height, 360);
  });

  test(
    'verwendet für bekannte Live-Videos direkt die originale HLS-URL',
    () async {
      final client = YoutubeExplode();
      var liveLoads = 0;
      final service = YouTubeExplodePlaybackService(
        youtubeExplode: client,
        liveStreamUrlLoader: (_, videoId) async {
          liveLoads++;
          expect(videoId, 'live-video');
          return 'https://manifest.googlevideo.com/live/master.m3u8';
        },
      );
      addTearDown(service.close);

      final playback = await service.resolve('live-video', isLive: true);

      expect(playback.isLive, isTrue);
      expect(playback.qualities, hasLength(1));
      expect(playback.defaultQuality.label, 'Auto (Live)');
      expect(playback.defaultQuality.isHls, isTrue);
      expect(
        playback.defaultQuality.videoUrl,
        Uri.parse('https://manifest.googlevideo.com/live/master.m3u8'),
      );
      expect(playback.pictureInPictureQuality, playback.defaultQuality);

      final refreshed = await playback.fallbackLoader!();
      expect(liveLoads, 2);
      expect(refreshed.isLive, isTrue);
      expect(refreshed.fallbackLoader, isNull);
    },
  );
}

VideoQualityOption _quality(int height) {
  return VideoQualityOption(
    label: '${height}p',
    height: height,
    videoUrl: Uri.parse('https://example.com/$height.mp4'),
  );
}
