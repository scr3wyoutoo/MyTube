import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/player_pull_down_fullscreen_policy.dart';

void main() {
  test('erlaubt Pull-down ausschließlich im aktiven Hochkantplayer', () {
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: true,
        playerSectionActive: true,
        fullscreen: false,
        pictureInPicture: false,
        keyboardVisible: false,
      ),
      isTrue,
    );
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: false,
        playerSectionActive: true,
        fullscreen: false,
        pictureInPicture: false,
        keyboardVisible: false,
      ),
      isFalse,
    );
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: true,
        playerSectionActive: false,
        fullscreen: false,
        pictureInPicture: false,
        keyboardVisible: false,
      ),
      isFalse,
    );
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: true,
        playerSectionActive: true,
        fullscreen: true,
        pictureInPicture: false,
        keyboardVisible: false,
      ),
      isFalse,
    );
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: true,
        playerSectionActive: true,
        fullscreen: false,
        pictureInPicture: true,
        keyboardVisible: false,
      ),
      isFalse,
    );
    expect(
      PlayerPullDownFullscreenPolicy.canStart(
        portrait: true,
        playerSectionActive: true,
        fullscreen: false,
        pictureInPicture: false,
        keyboardVisible: true,
      ),
      isFalse,
    );
  });

  test('armt die Ergebnisliste nur direkt am Listenanfang', () {
    expect(PlayerPullDownFullscreenPolicy.listGestureStartsAtTop(0), isTrue);
    expect(PlayerPullDownFullscreenPolicy.listGestureStartsAtTop(0.5), isTrue);
    expect(
      PlayerPullDownFullscreenPolicy.listGestureStartsAtTop(0.51),
      isFalse,
    );
    expect(PlayerPullDownFullscreenPolicy.listGestureStartsAtTop(120), isFalse);
  });

  test(
    'begrenzt die direkte Dragdistanz auf einen Fortschritt von null bis eins',
    () {
      expect(PlayerPullDownFullscreenPolicy.progressForDistance(-20), 0);
      expect(PlayerPullDownFullscreenPolicy.progressForDistance(120), 0.5);
      expect(PlayerPullDownFullscreenPolicy.progressForDistance(240), 1);
      expect(PlayerPullDownFullscreenPolicy.progressForDistance(400), 1);
    },
  );

  test('schließt per Schwelle oder schneller Abwärtsgeste ab', () {
    expect(
      PlayerPullDownFullscreenPolicy.shouldComplete(
        progress: 0.4,
        primaryVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PlayerPullDownFullscreenPolicy.shouldComplete(
        progress: 0.1,
        primaryVelocity: 700,
      ),
      isTrue,
    );
    expect(
      PlayerPullDownFullscreenPolicy.shouldComplete(
        progress: 0.39,
        primaryVelocity: 699,
      ),
      isFalse,
    );
    expect(
      PlayerPullDownFullscreenPolicy.shouldComplete(
        progress: 0.8,
        primaryVelocity: -900,
      ),
      isTrue,
    );
  });
}
