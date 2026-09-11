import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/playback_seek_policy.dart';

void main() {
  group('PlaybackSeekPolicy', () {
    test('entfernt den Media-Startwert fuer Live-HLS vollstaendig', () {
      expect(
        PlaybackSeekPolicy.mediaStart(isLive: true, position: Duration.zero),
        isNull,
      );
      expect(
        PlaybackSeekPolicy.mediaStart(
          isLive: true,
          position: const Duration(seconds: 42),
        ),
        isNull,
      );
    });

    test('behaelt den Media-Startwert fuer endliche Medien', () {
      const position = Duration(seconds: 42);
      expect(
        PlaybackSeekPolicy.mediaStart(isLive: false, position: position),
        position,
      );
    });

    test('verbietet jeden nachtraeglichen Live-Seek beim Oeffnen', () {
      expect(
        PlaybackSeekPolicy.shouldSeekAfterOpen(
          isLive: true,
          position: Duration.zero,
          startedImmediately: false,
        ),
        isFalse,
      );
      expect(
        PlaybackSeekPolicy.shouldSeekAfterOpen(
          isLive: true,
          position: const Duration(seconds: 42),
          startedImmediately: true,
        ),
        isFalse,
      );
    });

    test('erkennt den nativen Fehler fuer nicht seekbare Streams', () {
      expect(
        PlaybackSeekPolicy.isNonSeekableStreamError(
          'Der Videostream wurde abgelehnt: Cannot seek in this stream.',
        ),
        isTrue,
      );
      expect(PlaybackSeekPolicy.isNonSeekableStreamError('HTTP 403'), isFalse);
    });
  });
}
