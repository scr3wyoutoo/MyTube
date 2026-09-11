import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/player_gestures.dart';

void main() {
  test('Doppeltipp spult links zurück und rechts vor', () {
    expect(
      doubleTapSeekOffset(localX: 50, width: 400),
      const Duration(seconds: -10),
    );
    expect(
      doubleTapSeekOffset(localX: 350, width: 400),
      const Duration(seconds: 10),
    );
  });

  test('einfaches Tippen schaltet nur in der Videomitte Play/Pause', () {
    expect(isCenterPlaybackTap(localX: 50, width: 400), isFalse);
    expect(isCenterPlaybackTap(localX: 200, width: 400), isTrue);
    expect(isCenterPlaybackTap(localX: 350, width: 400), isFalse);
    expect(isCenterPlaybackTap(localX: 0, width: 0), isFalse);
  });
}
