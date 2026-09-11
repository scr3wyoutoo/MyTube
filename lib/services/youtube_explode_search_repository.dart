import 'package:youtube_explode_dart/youtube_explode_dart.dart' as explode;

import '../models/youtube_video.dart';
import '../models/youtube_search_sort.dart';
import 'localized_youtube_http_client.dart';
import 'youtube_explode_search_filter.dart';
import 'youtube_search_repository.dart';

class YouTubeExplodeSearchRepository implements YouTubeSearchRepository {
  YouTubeExplodeSearchRepository({
    YouTubeExplodeSearchSource? source,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _source = source ?? YouTubeExplodeDartSearchSource();

  static const int resultsPerPage = 20;
  static const String _pageTokenPrefix = 'youtube-explode-page:';

  final YouTubeExplodeSearchSource _source;
  final Duration requestTimeout;
  final List<YouTubeVideo> _videoBuffer = [];
  final Set<String> _knownVideoIds = {};

  YouTubeExplodeSearchBatch? _lastBatch;
  String? _activeQuery;
  String? _activeLanguageCode;
  YouTubeSearchSort? _activeSort;
  bool _mayHaveMoreResults = true;

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    final pageIndex = _readPageIndex(pageToken);
    if (_activeQuery != query ||
        _activeLanguageCode != languageCode ||
        _activeSort != sort ||
        pageToken == null) {
      _reset(query, languageCode, sort);
    }

    try {
      if (_lastBatch == null) {
        final firstBatch = await _source
            .search(query, languageCode: languageCode, sort: sort)
            .timeout(requestTimeout);
        _appendBatch(firstBatch);
      }

      // One extra result lets us determine whether another page exists.
      final requiredResultCount = ((pageIndex + 1) * resultsPerPage) + 1;
      await _fillBuffer(requiredResultCount);

      final start = pageIndex * resultsPerPage;
      if (start >= _videoBuffer.length) {
        return YouTubeSearchResult(
          videos: const [],
          previousPageToken: pageIndex > 0
              ? _createPageToken(pageIndex - 1)
              : null,
        );
      }

      final end = (start + resultsPerPage).clamp(start, _videoBuffer.length);
      final hasNextPage = _videoBuffer.length > end || _mayHaveMoreResults;

      return YouTubeSearchResult(
        videos: List.unmodifiable(_videoBuffer.sublist(start, end)),
        previousPageToken: pageIndex > 0
            ? _createPageToken(pageIndex - 1)
            : null,
        nextPageToken: hasNextPage ? _createPageToken(pageIndex + 1) : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Object catch (error) {
      throw YouTubeSearchException(
        'Die key-freie YouTube-Suche ist momentan nicht verfügbar. '
        'Bitte versuche es später erneut.',
        cause: error,
      );
    }
  }

  Future<void> _fillBuffer(int requiredResultCount) async {
    while (_videoBuffer.length < requiredResultCount && _mayHaveMoreResults) {
      final currentBatch = _lastBatch;
      if (currentBatch == null) {
        _mayHaveMoreResults = false;
        return;
      }

      final nextBatch = await _source
          .nextPage(currentBatch)
          .timeout(requestTimeout);
      if (nextBatch == null) {
        _mayHaveMoreResults = false;
        return;
      }
      _appendBatch(nextBatch);
    }
  }

  void _appendBatch(YouTubeExplodeSearchBatch batch) {
    _lastBatch = batch;
    for (final video in batch.videos) {
      if (_knownVideoIds.add(video.id)) {
        _videoBuffer.add(video);
      }
    }
  }

  int _readPageIndex(String? pageToken) {
    if (pageToken == null) {
      return 0;
    }
    if (!pageToken.startsWith(_pageTokenPrefix)) {
      throw const YouTubeSearchException('Ungültige Ergebnisseite.');
    }

    final pageIndex = int.tryParse(
      pageToken.substring(_pageTokenPrefix.length),
    );
    if (pageIndex == null || pageIndex < 0) {
      throw const YouTubeSearchException('Ungültige Ergebnisseite.');
    }
    return pageIndex;
  }

  String _createPageToken(int pageIndex) => '$_pageTokenPrefix$pageIndex';

  void _reset(String query, String languageCode, YouTubeSearchSort sort) {
    _activeQuery = query;
    _activeLanguageCode = languageCode;
    _activeSort = sort;
    _videoBuffer.clear();
    _knownVideoIds.clear();
    _lastBatch = null;
    _mayHaveMoreResults = true;
  }

  @override
  void close() => _source.close();
}

abstract interface class YouTubeExplodeSearchSource {
  Future<YouTubeExplodeSearchBatch> search(
    String query, {
    required String languageCode,
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  });

  Future<YouTubeExplodeSearchBatch?> nextPage(
    YouTubeExplodeSearchBatch currentBatch,
  );

  void close();
}

class YouTubeExplodeSearchBatch {
  const YouTubeExplodeSearchBatch({
    required this.videos,
    required this.nativePage,
    this.languageCode = 'de',
  });

  final List<YouTubeVideo> videos;
  final Object nativePage;
  final String languageCode;
}

class YouTubeExplodeDartSearchSource implements YouTubeExplodeSearchSource {
  YouTubeExplodeDartSearchSource({explode.YoutubeExplode? client})
    : _providedClient = client;

  final explode.YoutubeExplode? _providedClient;
  final Map<String, explode.YoutubeExplode> _localizedClients = {};
  final Map<String, LocalizedYoutubeHttpClient> _localizedHttpClients = {};

  explode.YoutubeExplode _clientFor(String languageCode) {
    final providedClient = _providedClient;
    if (providedClient != null) {
      return providedClient;
    }
    final normalizedLanguage = languageCode == 'en' ? 'en' : 'de';
    return _localizedClients.putIfAbsent(normalizedLanguage, () {
      final httpClient = LocalizedYoutubeHttpClient(normalizedLanguage);
      _localizedHttpClients[normalizedLanguage] = httpClient;
      return explode.YoutubeExplode(httpClient: httpClient);
    });
  }

  @override
  Future<YouTubeExplodeSearchBatch> search(
    String query, {
    required String languageCode,
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    final normalizedLanguage = languageCode == 'en' ? 'en' : 'de';
    final page = await _clientFor(languageCode).search.searchContent(
      query,
      filter: youtubeExplodeVideoSearchFilter(sort),
    );
    return _convertPage(page, languageCode: normalizedLanguage);
  }

  @override
  Future<YouTubeExplodeSearchBatch?> nextPage(
    YouTubeExplodeSearchBatch currentBatch,
  ) async {
    final nativePage = currentBatch.nativePage;
    if (nativePage is! explode.SearchList) {
      throw StateError('Ungültiger youtube_explode_dart-Seitenzustand.');
    }

    final nextPage = await nativePage.nextPage();
    return nextPage == null
        ? null
        : _convertPage(nextPage, languageCode: currentBatch.languageCode);
  }

  YouTubeExplodeSearchBatch _convertPage(
    explode.SearchList page, {
    required String languageCode,
  }) {
    final metadataClient = _localizedHttpClients[languageCode];
    return YouTubeExplodeSearchBatch(
      nativePage: page,
      languageCode: languageCode,
      videos: List.unmodifiable(
        page
            .whereType<explode.SearchVideo>()
            .where(
              (video) =>
                  !(metadataClient?.isKnownMembersOnlyVideo(video.id.value) ??
                      false),
            )
            .map(
              (video) => YouTubeVideo(
                id: video.id.value,
                title: video.title,
                description: video.description,
                thumbnailUrl: _bestThumbnailUrl(video.thumbnails),
                channelTitle: video.author,
                publishedAt: _tryParseUploadDate(video.uploadDate),
                isLive:
                    video.isLive ||
                    (metadataClient?.isKnownLiveVideo(video.id.value) ?? false),
              ),
            ),
      ),
    );
  }

  String _bestThumbnailUrl(List<explode.Thumbnail> thumbnails) {
    if (thumbnails.isEmpty) {
      return '';
    }
    var best = thumbnails.first;
    for (final thumbnail in thumbnails.skip(1)) {
      if (thumbnail.width * thumbnail.height > best.width * best.height) {
        best = thumbnail;
      }
    }
    return best.url.toString();
  }

  DateTime? _tryParseUploadDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
    final match = RegExp(
      r'(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final amount = int.parse(match.group(1)!);
    final duration = switch (match.group(2)!.toLowerCase()) {
      'second' => Duration(seconds: amount),
      'minute' => Duration(minutes: amount),
      'hour' => Duration(hours: amount),
      'day' => Duration(days: amount),
      'week' => Duration(days: amount * 7),
      'month' => Duration(days: amount * 30),
      _ => Duration(days: amount * 365),
    };
    return DateTime.now().subtract(duration);
  }

  @override
  void close() {
    final providedClient = _providedClient;
    if (providedClient != null) {
      providedClient.close();
      return;
    }
    for (final client in _localizedClients.values) {
      client.close();
    }
    _localizedClients.clear();
    _localizedHttpClients.clear();
  }
}
