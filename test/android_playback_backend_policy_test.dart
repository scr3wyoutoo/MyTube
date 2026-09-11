import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/utils/android_playback_backend_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  YouTubeVideo video({required bool isMusic, bool isMusicVideo = false}) {
    return YouTubeVideo(
      id: 'id',
      title: 'Title',
      description: '',
      thumbnailUrl: '',
      channelTitle: '',
      isMusic: isMusic,
      isMusicVideo: isMusicVideo,
    );
  }

  test('uses Media3 only for ordinary Android videos', () {
    expect(
      shouldUseAndroidMedia3VideoPlayer(
        isAndroid: true,
        video: video(isMusic: false),
      ),
      isTrue,
    );
    expect(
      shouldUseAndroidMedia3VideoPlayer(
        isAndroid: false,
        video: video(isMusic: false),
      ),
      isFalse,
    );
  });

  test('routes pure Android songs to Media3 audio only', () {
    expect(
      shouldUseAndroidMedia3VideoPlayer(
        isAndroid: true,
        video: video(isMusic: true),
      ),
      isFalse,
    );
    expect(
      shouldUseAndroidMedia3AudioPlayer(
        isAndroid: true,
        video: video(isMusic: true),
      ),
      isTrue,
    );
    expect(
      shouldUseAndroidMedia3AudioPlayer(
        isAndroid: false,
        video: video(isMusic: true),
      ),
      isFalse,
    );
  });

  test('keeps Android music videos out of the audio-only backend', () {
    expect(
      shouldUseAndroidMedia3VideoPlayer(
        isAndroid: true,
        video: video(isMusic: true, isMusicVideo: true),
      ),
      isFalse,
    );
    expect(
      shouldUseAndroidMedia3AudioPlayer(
        isAndroid: true,
        video: video(isMusic: true, isMusicVideo: true),
      ),
      isFalse,
    );
  });
}
