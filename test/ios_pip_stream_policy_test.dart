import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/models/video_playback.dart';
import 'package:flutter_browser_app/utils/ios_pip_stream_policy.dart';

void main() {
  test('bevorzugt das gewählte lokale HLS-Mastermanifest für iOS-PiP', () {
    final hls = _quality(
      label: '720p',
      height: 720,
      isHls: true,
      hlsMasterPlaylist: '#EXTM3U\n',
    );
    final progressive = _quality(label: '360p', height: 360);
    final playback = ResolvedVideoPlayback(
      qualities: [hls],
      defaultQuality: hls,
      fallbackLoader: () async => ResolvedVideoPlayback(
        qualities: [progressive],
        defaultQuality: progressive,
      ),
    );

    expect(IosPipStreamPolicy.primaryQuality(playback, hls), same(hls));
    expect(IosPipStreamPolicy.usesLocalHlsMaster(hls), isTrue);
    expect(IosPipStreamPolicy.progressiveFallbackQuality(playback), isNull);
  });

  test('wählt 360p nur als kombinierten progressiven Fallback', () {
    final separated720 = _quality(
      label: '720p getrennt',
      height: 720,
      audioUrl: Uri.parse('https://example.com/audio.m4a'),
    );
    final progressive480 = _quality(label: '480p', height: 480);
    final progressive360 = _quality(label: '360p', height: 360);
    final playback = ResolvedVideoPlayback(
      qualities: [separated720, progressive480, progressive360],
      defaultQuality: separated720,
    );

    expect(
      IosPipStreamPolicy.progressiveFallbackQuality(playback),
      same(progressive360),
    );
  });

  test('lädt den 360p-Fallback erst nach expliziter Anforderung', () async {
    var firstFallbackLoads = 0;
    var secondFallbackLoads = 0;
    final hls720 = _quality(
      label: '720p',
      height: 720,
      isHls: true,
      hlsMasterPlaylist: '#EXTM3U\n',
    );
    final hlsFallback = _quality(
      label: '720p Fallback',
      height: 720,
      isHls: true,
      hlsMasterPlaylist: '#EXTM3U\n',
    );
    final progressive360 = _quality(label: '360p', height: 360);
    final secondFallback = ResolvedVideoPlayback(
      qualities: [progressive360],
      defaultQuality: progressive360,
    );
    final firstFallback = ResolvedVideoPlayback(
      qualities: [hlsFallback],
      defaultQuality: hlsFallback,
      fallbackLoader: () async {
        secondFallbackLoads++;
        return secondFallback;
      },
    );
    final playback = ResolvedVideoPlayback(
      qualities: [hls720],
      defaultQuality: hls720,
      fallbackLoader: () async {
        firstFallbackLoads++;
        return firstFallback;
      },
    );

    expect(IosPipStreamPolicy.primaryQuality(playback, hls720), same(hls720));
    expect(firstFallbackLoads, 0);
    expect(secondFallbackLoads, 0);

    final fallback = await IosPipStreamPolicy.resolveProgressiveFallback(
      playback,
    );

    expect(fallback?.quality, same(progressive360));
    expect(firstFallbackLoads, 1);
    expect(secondFallbackLoads, 1);
  });

  test('akzeptiert eine direkte Live-HLS-URL ohne lokalen Master', () {
    final live = _quality(label: 'Auto (Live)', height: 0, isHls: true);
    final playback = ResolvedVideoPlayback(
      qualities: [live],
      defaultQuality: live,
      pictureInPictureQuality: live,
      isLive: true,
    );

    expect(IosPipStreamPolicy.primaryQuality(playback, live), same(live));
    expect(IosPipStreamPolicy.usesLocalHlsMaster(live), isFalse);
  });

  test('native iOS-PiP-Pfade rufen preroll nicht vor readyToPlay auf', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, isNot(contains('probePlayer.preroll')));
    expect(source, isNot(contains('preparedPlayer.preroll')));
    expect(source, contains('notifyFailureForCurrentStart'));
    expect(source, contains('readinessTimeoutMilliseconds'));
  });

  test('nativer iOS-Hauptplayer und PiP verwenden dieselbe AVPlayerLayer', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final flutterSource = File(
      'lib/screens/video_player_page.dart',
    ).readAsStringSync();

    expect(source, contains('override class var layerClass: AnyClass'));
    expect(source, contains('installMainPlayerLayer'));
    expect(
      source,
      contains('AVPictureInPictureController(playerLayer: layer)'),
    );
    expect(source, contains('case "openMainPlayer"'));
    expect(source, contains('applyRequestedMainPlayerPlaybackState(player)'));
    expect(source, isNot(contains('case "setInlineSourceRect"')));
    expect(source, isNot(contains('hostView.layer.insertSublayer(layer')));
    expect(flutterSource, contains('_buildTrackedPlayer()'));
    expect(
      flutterSource,
      contains("'flutter_browser_app/ios_native_player_view'"),
    );
    expect(flutterSource, contains('_nativeIosMainPlayerActive'));
  });

  test(
    'iOS-Musikvideos verwenden AVPlayer mit deaktiviertem PiP-Controller',
    () {
      final nativeSource = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final flutterSource = File(
        'lib/screens/video_player_page.dart',
      ).readAsStringSync();

      expect(
        flutterSource,
        contains('PlaybackBackgroundPolicy.usesNativeIosVideoPlayer'),
      );
      expect(flutterSource, contains('pictureInPictureEnabled:'));
      expect(
        flutterSource,
        contains('continuesAudioInBackground: video.isMusic'),
      );
      expect(flutterSource, contains('_attachNativeIosMainSystemControls'));
      expect(nativeSource, contains('mainPlayerPictureInPictureEnabled'));
      expect(nativeSource, contains('mainPlayerContinuesAudioInBackground'));
      expect(
        nativeSource,
        contains('arguments["pictureInPictureEnabled"] as? Bool == true'),
      );
      expect(
        nativeSource,
        contains('else if !mainPlayerPictureInPictureEnabled'),
      );
      expect(nativeSource, contains('.continuesIfPossible : .automatic'));
    },
  );

  test('iOS-Seek beendet Buffering anhand von Intent und Seek-Abschluss', () {
    final nativeSource = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(nativeSource, contains('mainPlayerSeekGeneration'));
    expect(
      nativeSource,
      contains('self.applyRequestedMainPlayerPlaybackState(player)'),
    );
    expect(nativeSource, contains('timeControlStatus != .playing'));
    expect(nativeSource, contains('let buffering = requestedPlaying'));
    expect(
      nativeSource,
      isNot(
        contains(
          'let buffering = waiting || item?.isPlaybackBufferEmpty == true',
        ),
      ),
    );
  });

  test('MediaKit-Vorbereitung ist gegen paralleles Dispose abgesichert', () {
    final flutterSource = File(
      'lib/screens/video_player_page.dart',
    ).readAsStringSync();

    expect(flutterSource, contains('_disposePreparedMediaKitPlayerOnce'));
    expect(flutterSource, contains('bool preparationIsActive()'));
    expect(flutterSource, contains('required bool Function() canContinue'));
    expect(flutterSource, contains('if (!canContinue()) return false;'));
  });

  test('iOS-Home-PiP besitzt einen eigenen Arm-und-Abbruch-Pfad', () {
    final nativeSource = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final flutterSource = File(
      'lib/screens/video_player_page.dart',
    ).readAsStringSync();

    expect(nativeSource, contains('case "armAutoEnter"'));
    expect(nativeSource, contains('case "cancelAutoEnter"'));
    expect(
      nativeSource,
      contains('canStartPictureInPictureAutomaticallyFromInline'),
    );
    expect(flutterSource, contains('!_nativeIosMainPlayerActive'));
    expect(
      flutterSource,
      isNot(
        contains(
          "_enterPictureInPicture(\n            debugTrigger: 'homeTransition'",
        ),
      ),
    );
    expect(
      flutterSource,
      contains(
        '_isInPictureInPictureMode &&\n'
        '        AndroidPictureInPicture.instance.isSupportedPlatform',
      ),
    );
  });

  test('iOS-Audio nutzt zwei persistente AVPlayer ohne MediaKit-Recycling', () {
    final nativeSource = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final flutterSource = File(
      'lib/screens/video_player_page.dart',
    ).readAsStringSync();
    final fadeSource = File(
      'lib/utils/playlist_audio_fade.dart',
    ).readAsStringSync();

    expect(
      nativeSource,
      contains('private let players = [AVPlayer(), AVPlayer()]'),
    );
    expect(nativeSource, contains('activeIndex = 1 - activeIndex'));
    expect(nativeSource, contains('standbyPlayer.replaceCurrentItem'));
    expect(nativeSource, contains('item.forwardPlaybackEndTime'));
    expect(nativeSource, contains('effectiveDurationMilliseconds'));
    expect(
      nativeSource,
      contains('flutter_browser_app/ios_native_audio_playback'),
    );
    expect(flutterSource, contains('_nativeIosAudioPlayerActive'));
    expect(flutterSource, contains('_prepareNextNativeIosAudioPlayback'));
    expect(fadeSource, isNot(contains('iosDelayedAudioSlotRecyclePosition')));
    expect(flutterSource, isNot(contains('_takeIosAudioSlotForDelayedReuse')));
  });
}

VideoQualityOption _quality({
  required String label,
  required int height,
  bool isHls = false,
  String? hlsMasterPlaylist,
  Uri? audioUrl,
}) {
  return VideoQualityOption(
    label: label,
    height: height,
    videoUrl: Uri.parse(
      isHls
          ? 'https://example.com/$height/master.m3u8'
          : 'https://example.com/$height/video.mp4',
    ),
    audioUrl: audioUrl,
    hlsMasterPlaylist: hlsMasterPlaylist,
    isHls: isHls,
  );
}
