import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/utils/media_duration.dart';

void main() {
  test('liest Music-Zeitangaben mit Minuten und Stunden', () {
    expect(parseMediaDuration('2:33'), const Duration(minutes: 2, seconds: 33));
    expect(
      parseMediaDuration('62:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(
      parseMediaDuration('1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(parseMediaDuration('153.25'), const Duration(milliseconds: 153250));
  });

  test('verwirft ungültige oder nicht positive Zeitangaben', () {
    expect(parseMediaDuration(null), isNull);
    expect(parseMediaDuration(''), isNull);
    expect(parseMediaDuration('2:99'), isNull);
    expect(parseMediaDuration(0), isNull);
    expect(parseMediaDuration(-4), isNull);
  });

  test('liest die präzise Dauer aus einer signierten Stream-URL', () {
    final duration = youtubeStreamDuration(
      Uri.parse(
        'https://example.googlevideo.com/videoplayback?mime=audio%2Fmp4&dur=153.275',
      ),
    );

    expect(duration, const Duration(milliseconds: 153275));
  });

  test('nutzt präzise Streamdauer bei plausibler Katalogabweichung', () {
    expect(
      canonicalPlaybackDuration(
        streamDuration: const Duration(milliseconds: 153275),
        catalogDuration: const Duration(seconds: 153),
      ),
      const Duration(milliseconds: 153275),
    );
    expect(
      canonicalPlaybackDuration(catalogDuration: const Duration(seconds: 153)),
      const Duration(seconds: 153),
    );
  });

  test('bevorzugt bei großem Zeitachsenkonflikt die Katalogdauer', () {
    expect(
      canonicalPlaybackDuration(
        streamDuration: const Duration(minutes: 5, seconds: 12),
        catalogDuration: const Duration(minutes: 2, seconds: 33),
      ),
      const Duration(minutes: 2, seconds: 33),
    );
  });

  test('rekonstruiert die Dauer alter Music-Einträge aus der Beschreibung', () {
    expect(
      mediaDurationFromDescription('Künstler • Album • 2:33 • Explizit'),
      const Duration(minutes: 2, seconds: 33),
    );
    expect(mediaDurationFromDescription('Beschreibung ohne Dauer'), isNull);
  });
}
