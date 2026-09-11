import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/services/youtube_video_details_repository.dart';

void main() {
  test('bündelt parallele Anfragen und cached pro Video und Sprache', () async {
    final source = _ControlledVideoDetailsSource();
    final repository = YouTubeVideoDetailsRepository(source: source);

    final first = repository.loadDescription(
      videoId: 'video-1',
      languageCode: 'de',
    );
    final second = repository.loadDescription(
      videoId: 'video-1',
      languageCode: 'de',
    );
    expect(source.requests, ['de:video-1']);

    source.complete('de:video-1', 'Vollständige Beschreibung');
    expect(await first, 'Vollständige Beschreibung');
    expect(await second, 'Vollständige Beschreibung');

    expect(
      await repository.loadDescription(videoId: 'video-1', languageCode: 'de'),
      'Vollständige Beschreibung',
    );
    expect(source.requests, ['de:video-1']);

    final english = repository.loadDescription(
      videoId: 'video-1',
      languageCode: 'en',
    );
    expect(source.requests, ['de:video-1', 'en:video-1']);
    source.complete('en:video-1', 'Full description');
    expect(await english, 'Full description');

    repository.close();
    expect(source.wasClosed, isTrue);
  });

  test(
    'entfernt bei der Eintragsgrenze den am längsten ungenutzten Wert',
    () async {
      final source = _ControlledVideoDetailsSource();
      final repository = YouTubeVideoDetailsRepository(
        source: source,
        maxEntries: 2,
        maxCharacters: 1000,
      );

      await _loadAndComplete(repository, source, 'a', 'Beschreibung A');
      await _loadAndComplete(repository, source, 'b', 'Beschreibung B');
      await repository.loadDescription(videoId: 'a');
      await _loadAndComplete(repository, source, 'c', 'Beschreibung C');

      await repository.loadDescription(videoId: 'a');
      final reloadedB = repository.loadDescription(videoId: 'b');
      source.complete('de:b', 'Beschreibung B neu');
      expect(await reloadedB, 'Beschreibung B neu');
      expect(source.requests, ['de:a', 'de:b', 'de:c', 'de:b']);

      repository.close();
    },
  );

  test('begrenzt den Cache zusätzlich über die gesamte Zeichenzahl', () async {
    final source = _ControlledVideoDetailsSource();
    final repository = YouTubeVideoDetailsRepository(
      source: source,
      maxEntries: 10,
      maxCharacters: 10,
    );

    await _loadAndComplete(repository, source, 'a', '123456');
    await _loadAndComplete(repository, source, 'b', 'abcdef');
    final reloadedA = repository.loadDescription(videoId: 'a');
    source.complete('de:a', 'neu');
    expect(await reloadedA, 'neu');
    expect(source.requests, ['de:a', 'de:b', 'de:a']);

    repository.close();
  });
}

Future<void> _loadAndComplete(
  YouTubeVideoDetailsRepository repository,
  _ControlledVideoDetailsSource source,
  String videoId,
  String description,
) async {
  final result = repository.loadDescription(videoId: videoId);
  source.complete('de:$videoId', description);
  await result;
}

class _ControlledVideoDetailsSource implements YouTubeVideoDetailsSource {
  final List<String> requests = [];
  final Map<String, Completer<String>> _responses = {};
  bool wasClosed = false;

  @override
  Future<String> loadDescription({
    required String videoId,
    required String languageCode,
  }) {
    final key = '$languageCode:$videoId';
    requests.add(key);
    return (_responses[key] = Completer<String>()).future;
  }

  void complete(String key, String description) {
    _responses[key]!.complete(description);
  }

  @override
  void close() => wasClosed = true;
}
