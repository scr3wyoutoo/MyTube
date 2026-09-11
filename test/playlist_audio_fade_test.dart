import 'package:flutter_browser_app/utils/playlist_audio_fade.dart';
import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const duration = Duration(minutes: 3);
  const song = YouTubeVideo(
    id: 'song',
    title: 'Song',
    description: '',
    thumbnailUrl: '',
    isMusic: true,
  );
  const nextSong = YouTubeVideo(
    id: 'next-song',
    title: 'Next Song',
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

  test('Crossfade bleibt auf zwei reine Audio-Songs begrenzt', () {
    expect(shouldUsePlaylistCrossfade(current: song, next: nextSong), isTrue);
    expect(
      shouldUsePlaylistCrossfade(current: song, next: musicVideo),
      isFalse,
    );
    expect(
      shouldUsePlaylistCrossfade(current: musicVideo, next: song),
      isFalse,
    );
  });

  test('Double-Buffer gilt nur für automatische Audio-Übergänge', () {
    expect(
      shouldUseAudioQueueDoubleBuffer(
        current: song,
        next: nextSong,
        automatic: true,
        prepared: true,
      ),
      isTrue,
    );
    expect(
      shouldUseAudioQueueDoubleBuffer(
        current: song,
        next: nextSong,
        automatic: false,
        prepared: true,
      ),
      isFalse,
    );
    expect(
      shouldUseAudioQueueDoubleBuffer(
        current: song,
        next: musicVideo,
        automatic: true,
        prepared: true,
      ),
      isFalse,
    );
    expect(
      shouldUseAudioQueueDoubleBuffer(
        current: musicVideo,
        next: song,
        automatic: true,
        prepared: true,
      ),
      isFalse,
    );
  });

  test('natürliches Titelende pausiert den eingehenden Player nicht', () {
    expect(
      shouldStartIncomingCrossfade(
        outgoingPlaying: false,
        incomingPlaying: true,
      ),
      isFalse,
    );
  });

  test('laufender Ausgang startet einen noch pausierten Eingang', () {
    expect(
      shouldStartIncomingCrossfade(
        outgoingPlaying: true,
        incomingPlaying: false,
      ),
      isTrue,
    );
  });

  test('Crossfade bleibt logisch aktiv wenn nur der Eingang spielt', () {
    expect(
      isCrossfadePlaybackRunning(
        primaryPlaying: false,
        incomingPlaying: true,
        crossfadeActive: true,
      ),
      isTrue,
    );
    expect(
      isCrossfadePlaybackRunning(
        primaryPlaying: false,
        incomingPlaying: true,
        crossfadeActive: false,
      ),
      isFalse,
    );
  });

  test('does not change volume outside playlist playback', () {
    expect(
      playlistAudioFadeFactor(
        position: Duration.zero,
        duration: duration,
        isPlaylistPlayback: false,
        hasNextItem: false,
      ),
      1,
    );
  });

  test('fades a playlist item in over six seconds', () {
    expect(_factor(const Duration(seconds: 0), fadeInEnabled: true), 0);
    expect(
      _factor(const Duration(seconds: 3), fadeInEnabled: true),
      closeTo(0.5, 0.001),
    );
    expect(_factor(const Duration(seconds: 6), fadeInEnabled: true), 1);
    expect(_factor(const Duration(seconds: 30), fadeInEnabled: true), 1);
  });

  test('manual playlist starts use full volume immediately', () {
    expect(_factor(Duration.zero, hasNextItem: true, fadeInEnabled: false), 1);
  });

  test('fades out over the last six seconds when another item follows', () {
    expect(_factor(const Duration(seconds: 174), hasNextItem: true), 1);
    expect(
      _factor(const Duration(seconds: 177), hasNextItem: true),
      closeTo(0.5, 0.001),
    );
    expect(_factor(const Duration(seconds: 180), hasNextItem: true), 0);
  });

  test('does not fade out without a ready automatic crossfade', () {
    expect(
      _factor(
        const Duration(seconds: 179),
        hasNextItem: true,
        fadeInEnabled: false,
        fadeOutEnabled: false,
      ),
      1,
    );
  });

  test('keeps the last playlist item audible until its end', () {
    expect(_factor(const Duration(seconds: 180)), 1);
  });

  test('short items use half their duration for each fade', () {
    expect(
      playlistAudioFadeFactor(
        position: const Duration(seconds: 2),
        duration: const Duration(seconds: 4),
        isPlaylistPlayback: true,
        hasNextItem: true,
      ),
      1,
    );
  });

  test('incoming crossfade overlaps the final six seconds', () {
    expect(
      playlistCrossfadeIncomingFactor(
        position: const Duration(seconds: 174),
        duration: duration,
      ),
      0,
    );
    expect(
      playlistCrossfadeIncomingFactor(
        position: const Duration(seconds: 177),
        duration: duration,
      ),
      closeTo(0.5, 0.001),
    );
    expect(
      playlistCrossfadeIncomingFactor(position: duration, duration: duration),
      1,
    );
  });
}

double _factor(
  Duration position, {
  bool hasNextItem = false,
  bool fadeInEnabled = false,
  bool fadeOutEnabled = true,
}) {
  return playlistAudioFadeFactor(
    position: position,
    duration: const Duration(minutes: 3),
    isPlaylistPlayback: true,
    hasNextItem: hasNextItem,
    fadeInEnabled: fadeInEnabled,
    fadeOutEnabled: fadeOutEnabled,
  );
}
