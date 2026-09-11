import 'dart:async';
import 'dart:collection';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as explode;

import 'localized_youtube_http_client.dart';

class YouTubeVideoDetailsRepository {
  YouTubeVideoDetailsRepository({
    YouTubeVideoDetailsSource? source,
    this.maxEntries = 200,
    this.maxCharacters = 1000000,
  }) : assert(maxEntries > 0),
       assert(maxCharacters > 0),
       _source = source ?? YouTubeExplodeVideoDetailsSource();

  final YouTubeVideoDetailsSource _source;
  final int maxEntries;
  final int maxCharacters;
  final LinkedHashMap<String, _DescriptionCacheEntry> _descriptionRequests =
      LinkedHashMap();
  int _cachedCharacterCount = 0;

  Future<String> loadDescription({
    required String videoId,
    String languageCode = 'de',
  }) {
    final normalizedLanguage = languageCode == 'en' ? 'en' : 'de';
    final cacheKey = '$normalizedLanguage:$videoId';
    final cachedEntry = _descriptionRequests.remove(cacheKey);
    if (cachedEntry != null) {
      // Removing and reinserting marks the entry as most recently used.
      _descriptionRequests[cacheKey] = cachedEntry;
      return cachedEntry.future;
    }

    final completer = Completer<String>();
    final entry = _DescriptionCacheEntry(completer.future);
    _descriptionRequests[cacheKey] = entry;
    _evictLeastRecentlyUsedEntries();
    unawaited(
      _loadEntry(
        cacheKey: cacheKey,
        videoId: videoId,
        languageCode: normalizedLanguage,
        entry: entry,
        completer: completer,
      ),
    );
    return entry.future;
  }

  Future<void> _loadEntry({
    required String cacheKey,
    required String videoId,
    required String languageCode,
    required _DescriptionCacheEntry entry,
    required Completer<String> completer,
  }) async {
    try {
      final description = await _source.loadDescription(
        videoId: videoId,
        languageCode: languageCode,
      );
      if (identical(_descriptionRequests[cacheKey], entry)) {
        entry.characterCount = description.length;
        _cachedCharacterCount += description.length;
        _evictLeastRecentlyUsedEntries();
      }
      completer.complete(description);
    } on Object catch (error, stackTrace) {
      if (identical(_descriptionRequests[cacheKey], entry)) {
        _descriptionRequests.remove(cacheKey);
      }
      completer.completeError(error, stackTrace);
    }
  }

  void _evictLeastRecentlyUsedEntries() {
    while (_descriptionRequests.length > maxEntries ||
        _cachedCharacterCount > maxCharacters) {
      String? oldestCompletedKey;
      for (final cacheEntry in _descriptionRequests.entries) {
        if (cacheEntry.value.characterCount != null) {
          oldestCompletedKey = cacheEntry.key;
          break;
        }
      }
      if (oldestCompletedKey == null) {
        // In-flight requests may temporarily exceed the limits, but are never
        // cancelled. The next completion runs this check again.
        return;
      }
      final removed = _descriptionRequests.remove(oldestCompletedKey)!;
      _cachedCharacterCount -= removed.characterCount!;
    }
  }

  void close() {
    _descriptionRequests.clear();
    _cachedCharacterCount = 0;
    _source.close();
  }
}

class _DescriptionCacheEntry {
  _DescriptionCacheEntry(this.future);

  final Future<String> future;
  int? characterCount;
}

abstract interface class YouTubeVideoDetailsSource {
  Future<String> loadDescription({
    required String videoId,
    required String languageCode,
  });

  void close();
}

class YouTubeExplodeVideoDetailsSource implements YouTubeVideoDetailsSource {
  final Map<String, explode.YoutubeExplode> _clients = {};

  explode.YoutubeExplode _clientFor(String languageCode) {
    return _clients.putIfAbsent(
      languageCode,
      () => explode.YoutubeExplode(
        httpClient: LocalizedYoutubeHttpClient(languageCode),
      ),
    );
  }

  @override
  Future<String> loadDescription({
    required String videoId,
    required String languageCode,
  }) async {
    final video = await _clientFor(languageCode).videos.get(videoId);
    return video.description;
  }

  @override
  void close() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}
