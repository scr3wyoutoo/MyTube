import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/player_fullscreen_policy.dart';

void main() {
  test('bleibt nach Vollbildanforderung in beiden Rotationen im Vollbild', () {
    expect(
      PlayerFullscreenPolicy.usesFullscreenLayout(
        fullscreenRequested: true,
        landscape: false,
      ),
      isTrue,
    );
    expect(
      PlayerFullscreenPolicy.usesFullscreenLayout(
        fullscreenRequested: true,
        landscape: true,
      ),
      isTrue,
    );
  });

  test('behält den bisherigen impliziten Querformat-Vollbildmodus', () {
    expect(
      PlayerFullscreenPolicy.usesFullscreenLayout(
        fullscreenRequested: false,
        landscape: true,
      ),
      isTrue,
    );
    expect(
      PlayerFullscreenPolicy.usesFullscreenLayout(
        fullscreenRequested: false,
        landscape: false,
      ),
      isFalse,
    );
  });

  test('Vollbild erlaubt Hochformat und beide Querformatrichtungen', () {
    expect(PlayerFullscreenPolicy.supportedFullscreenOrientations, [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    expect(PlayerFullscreenPolicy.exitOrientations, [
      DeviceOrientation.portraitUp,
    ]);
  });
}
