import 'package:flutter_browser_app/models/youtube_video.dart';
import 'package:flutter_browser_app/utils/playback_background_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const video = YouTubeVideo(
    id: 'video',
    title: 'Video',
    description: '',
    thumbnailUrl: '',
  );
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

  test('Videos verwenden ausschließlich PiP als Hintergrundoberfläche', () {
    expect(PlaybackBackgroundPolicy.allowsPictureInPicture(video), isTrue);
    expect(PlaybackBackgroundPolicy.usesSystemMediaControls(video), isFalse);
    expect(PlaybackBackgroundPolicy.requiresPlayerSurface(video), isTrue);
  });

  test('Songs verwenden ausschließlich die System-Mediensteuerung', () {
    expect(PlaybackBackgroundPolicy.allowsPictureInPicture(song), isFalse);
    expect(PlaybackBackgroundPolicy.usesSystemMediaControls(song), isTrue);
    expect(PlaybackBackgroundPolicy.requiresPlayerSurface(song), isFalse);
  });

  test('manual song selection reuses the active player', () {
    expect(
      PlaybackBackgroundPolicy.manualSelectionTransition(
        nextVideo: song,
        hasCurrentPlayer: true,
        currentPlayerReady: true,
        canReuseCurrentPlayer: true,
      ),
      ManualPlaybackTransitionStrategy.reuseCurrentPlayer,
    );
    expect(
      PlaybackBackgroundPolicy.manualSelectionTransition(
        nextVideo: musicVideo,
        hasCurrentPlayer: true,
        currentPlayerReady: true,
        canReuseCurrentPlayer: true,
      ),
      ManualPlaybackTransitionStrategy.reuseCurrentPlayer,
    );
  });

  test('manual replacement keeps the system session during a load', () {
    expect(
      PlaybackBackgroundPolicy.manualSelectionTransition(
        nextVideo: song,
        hasCurrentPlayer: true,
        currentPlayerReady: false,
        canReuseCurrentPlayer: true,
      ),
      ManualPlaybackTransitionStrategy.reloadKeepingSystemSession,
    );
  });

  test('initial song playback and videos retain the existing reload path', () {
    expect(
      PlaybackBackgroundPolicy.manualSelectionTransition(
        nextVideo: song,
        hasCurrentPlayer: false,
        currentPlayerReady: false,
        canReuseCurrentPlayer: false,
      ),
      ManualPlaybackTransitionStrategy.reload,
    );
    expect(
      PlaybackBackgroundPolicy.manualSelectionTransition(
        nextVideo: video,
        hasCurrentPlayer: true,
        currentPlayerReady: true,
        canReuseCurrentPlayer: true,
      ),
      ManualPlaybackTransitionStrategy.reload,
    );
  });

  test(
    'Music-Backendwechsel lädt bei aktiver Systemsession kontrolliert neu',
    () {
      expect(
        PlaybackBackgroundPolicy.manualSelectionTransition(
          nextVideo: song,
          hasCurrentPlayer: true,
          currentPlayerReady: true,
          canReuseCurrentPlayer: false,
        ),
        ManualPlaybackTransitionStrategy.reloadKeepingSystemSession,
      );
      expect(
        PlaybackBackgroundPolicy.manualSelectionTransition(
          nextVideo: musicVideo,
          hasCurrentPlayer: true,
          currentPlayerReady: true,
          canReuseCurrentPlayer: false,
        ),
        ManualPlaybackTransitionStrategy.reloadKeepingSystemSession,
      );
    },
  );

  test(
    'Musikvideos rendern Video, verwenden im Hintergrund aber nur Audio',
    () {
      expect(
        PlaybackBackgroundPolicy.allowsPictureInPicture(musicVideo),
        isFalse,
      );
      expect(
        PlaybackBackgroundPolicy.usesSystemMediaControls(musicVideo),
        isTrue,
      );
      expect(
        PlaybackBackgroundPolicy.requiresPlayerSurface(musicVideo),
        isTrue,
      );
      expect(
        PlaybackBackgroundPolicy.usesNativeIosVideoPlayer(
          isIos: true,
          video: musicVideo,
        ),
        isTrue,
      );
      expect(
        PlaybackBackgroundPolicy.usesNativeIosVideoPlayer(
          isIos: false,
          video: musicVideo,
        ),
        isFalse,
      );
    },
  );

  test('Auto-PiP ist nur für ein tatsächlich laufendes Video aktiv', () {
    expect(
      PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
        pictureInPictureAllowed: true,
        playing: true,
      ),
      isTrue,
    );
    expect(
      PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
        pictureInPictureAllowed: true,
        playing: false,
      ),
      isFalse,
    );
    expect(
      PlaybackBackgroundPolicy.shouldAutoEnterPictureInPicture(
        pictureInPictureAllowed: false,
        playing: true,
      ),
      isFalse,
    );
  });

  test('Schließen von PiP pausiert nur solange die App im Hintergrund ist', () {
    expect(
      PlaybackBackgroundPolicy.shouldPauseWhenPictureInPictureCloses(
        appIsResumed: false,
      ),
      isTrue,
    );
    expect(
      PlaybackBackgroundPolicy.shouldPauseWhenPictureInPictureCloses(
        appIsResumed: true,
      ),
      isFalse,
    );
    expect(
      PlaybackBackgroundPolicy.shouldPauseWhenPictureInPictureCloses(
        appIsResumed: false,
        restoredToApp: true,
      ),
      isFalse,
    );
  });
}
