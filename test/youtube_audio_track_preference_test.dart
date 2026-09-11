import 'package:flutter_browser_app/utils/youtube_audio_track_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('youtubeAudioTrackLanguageScore', () {
    test('erkennt deutsche Sprach-IDs und Anzeigenamen', () {
      expect(
        youtubeAudioTrackLanguageScore(
          languageCode: 'de',
          trackId: 'de-DE.4',
          displayName: 'Deutsch',
          isDefault: false,
        ),
        greaterThan(0),
      );
      expect(
        youtubeAudioTrackLanguageScore(
          languageCode: 'de',
          trackId: 'dubbed',
          displayName: 'German',
          isDefault: false,
        ),
        greaterThan(0),
      );
    });

    test('verwirft eine anderssprachige Tonspur', () {
      expect(
        youtubeAudioTrackLanguageScore(
          languageCode: 'de',
          trackId: 'en-US',
          displayName: 'English',
          isDefault: true,
        ),
        lessThan(0),
      );
    });

    test('bevorzugt Standardton vor Audiodeskription', () {
      final standard = youtubeAudioTrackLanguageScore(
        languageCode: 'de',
        trackId: 'de',
        displayName: 'Deutsch',
        isDefault: false,
      );
      final descriptive = youtubeAudioTrackLanguageScore(
        languageCode: 'de',
        trackId: 'de.1',
        displayName: 'Deutsch (Audiodeskription)',
        isDefault: false,
      );
      expect(standard, greaterThan(descriptive));
    });

    test('unterstützt die englische Profiloption', () {
      expect(
        youtubeAudioTrackLanguageScore(
          languageCode: 'en',
          trackId: 'en-GB',
          displayName: 'English (United Kingdom)',
          isDefault: false,
        ),
        greaterThan(0),
      );
    });
  });
}
