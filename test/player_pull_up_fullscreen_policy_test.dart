import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/player_pull_up_fullscreen_policy.dart';

void main() {
  test('erlaubt Pull-up nur im Vollbild außerhalb von PiP', () {
    expect(
      PlayerPullUpFullscreenPolicy.canStart(
        fullscreen: true,
        pictureInPicture: false,
      ),
      isTrue,
    );
    expect(
      PlayerPullUpFullscreenPolicy.canStart(
        fullscreen: false,
        pictureInPicture: false,
      ),
      isFalse,
    );
    expect(
      PlayerPullUpFullscreenPolicy.canStart(
        fullscreen: true,
        pictureInPicture: true,
      ),
      isFalse,
    );
  });

  test(
    'akzeptiert den Start ausschließlich im mittleren Bildschirmbereich',
    () {
      const viewport = Size(400, 800);
      expect(
        PlayerPullUpFullscreenPolicy.startsInCenter(
          position: const Offset(200, 400),
          viewport: viewport,
        ),
        isTrue,
      );
      expect(
        PlayerPullUpFullscreenPolicy.startsInCenter(
          position: const Offset(100, 200),
          viewport: viewport,
        ),
        isTrue,
      );
      expect(
        PlayerPullUpFullscreenPolicy.startsInCenter(
          position: const Offset(99, 400),
          viewport: viewport,
        ),
        isFalse,
      );
      expect(
        PlayerPullUpFullscreenPolicy.startsInCenter(
          position: const Offset(200, 601),
          viewport: viewport,
        ),
        isFalse,
      );
      expect(
        PlayerPullUpFullscreenPolicy.startsInCenter(
          position: Offset.zero,
          viewport: Size.zero,
        ),
        isFalse,
      );
    },
  );

  test(
    'begrenzt die Aufwärtsdistanz auf einen Fortschritt von null bis eins',
    () {
      expect(PlayerPullUpFullscreenPolicy.progressForDistance(-20), 0);
      expect(PlayerPullUpFullscreenPolicy.progressForDistance(90), 0.5);
      expect(PlayerPullUpFullscreenPolicy.progressForDistance(180), 1);
      expect(PlayerPullUpFullscreenPolicy.progressForDistance(400), 1);
    },
  );

  test('schließt per Schwelle oder schneller Aufwärtsgeste ab', () {
    expect(
      PlayerPullUpFullscreenPolicy.shouldComplete(
        progress: 0.4,
        primaryVelocity: 0,
      ),
      isTrue,
    );
    expect(
      PlayerPullUpFullscreenPolicy.shouldComplete(
        progress: 0.1,
        primaryVelocity: -700,
      ),
      isTrue,
    );
    expect(
      PlayerPullUpFullscreenPolicy.shouldComplete(
        progress: 0.39,
        primaryVelocity: -699,
      ),
      isFalse,
    );
  });
}
