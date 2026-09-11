import 'package:youtube_explode_dart/youtube_explode_dart.dart' as explode;

import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import 'localized_youtube_http_client.dart';
import 'youtube_catalog_repository.dart';
import 'youtube_explode_search_filter.dart';
import 'youtube_live_detection.dart' as live_detection;
import 'youtube_members_only_detection.dart';
import 'youtube_search_repository.dart';

class YouTubeExplodeCatalogRepository implements YouTubeCatalogRepository {
  YouTubeExplodeCatalogRepository({
    explode.YoutubeExplode? client,
    this.requestTimeout = const Duration(seconds: 25),
  }) : _providedClient = client;

  static const int resultsPerPage = 20;
  static const _channelSearchTokenPrefix = 'channel-search-page:';
  static const _playlistSearchTokenPrefix = 'playlist-search-page:';
  static const _channelVideosTokenPrefix = 'channel-videos-page:';
  static const _playlistVideosTokenPrefix = 'playlist-videos-page:';
  static const _channelVideosBrowseParams = 'EgZ2aWRlb3PyBgQKAjoA';
  static const _channelCollectionPrefix = 'channel-videos:';

  final explode.YoutubeExplode? _providedClient;
  final Duration requestTimeout;
  final Map<String, explode.YoutubeExplode> _localizedClients = {};
  final Map<String, LocalizedYoutubeHttpClient> _playlistHttpClients = {};

  final _channelSearchState = _NativeSearchState();
  final _playlistSearchState = _NativeSearchState();

  String? _activePlaylistId;
  String? _activePlaylistLanguage;
  String? _playlistContinuationToken;
  String? _playlistVisitorData;
  final List<YouTubeVideo> _playlistVideoBuffer = [];
  final Set<String> _knownPlaylistVideoIds = {};
  bool _playlistMayHaveMore = true;

  explode.YoutubeExplode _clientFor(String languageCode) {
    final providedClient = _providedClient;
    if (providedClient != null) {
      return providedClient;
    }
    final normalized = languageCode == 'en' ? 'en' : 'de';
    return _localizedClients.putIfAbsent(
      normalized,
      () => explode.YoutubeExplode(
        httpClient: LocalizedYoutubeHttpClient(normalized),
      ),
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchChannels({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    try {
      final pageIndex = _readPageIndex(pageToken, _channelSearchTokenPrefix);
      if (pageToken == null ||
          _channelSearchState.query != query ||
          _channelSearchState.languageCode != languageCode) {
        _channelSearchState.reset(query, languageCode);
      }
      final page = await _loadNativeSearchPage(
        state: _channelSearchState,
        pageIndex: pageIndex,
        firstPage: () => _clientFor(
          languageCode,
        ).search.searchContent(query, filter: explode.TypeFilters.channel),
      );
      if (page == null) {
        return YouTubeCatalogPage(
          items: const <YouTubeChannelResult>[],
          previousPageToken: pageIndex > 0
              ? _createPageToken(_channelSearchTokenPrefix, pageIndex - 1)
              : null,
        );
      }
      final items = page
          .whereType<explode.SearchChannel>()
          .take(resultsPerPage)
          .map(
            (channel) => YouTubeChannelResult(
              id: channel.id.value,
              name: channel.name,
              description: channel.description,
              thumbnailUrl: _bestThumbnailUrl(channel.thumbnails),
              videoCount: channel.videoCount,
            ),
          )
          .toList(growable: false);
      return YouTubeCatalogPage(
        items: List.unmodifiable(items),
        previousPageToken: pageIndex > 0
            ? _createPageToken(_channelSearchTokenPrefix, pageIndex - 1)
            : null,
        nextPageToken: page.length >= resultsPerPage
            ? _createPageToken(_channelSearchTokenPrefix, pageIndex + 1)
            : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Channel-Suche ist momentan nicht verfügbar. '
        'Bitte versuche es später erneut.',
        cause: error,
      );
    }
  }

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    try {
      final pageIndex = _readPageIndex(pageToken, _playlistSearchTokenPrefix);
      if (pageToken == null ||
          _playlistSearchState.query != query ||
          _playlistSearchState.languageCode != languageCode ||
          _playlistSearchState.sort != sort) {
        _playlistSearchState.reset(query, languageCode, sort: sort);
      }
      final page = await _loadNativeSearchPage(
        state: _playlistSearchState,
        pageIndex: pageIndex,
        firstPage: () => _clientFor(languageCode).search.searchContent(
          query,
          filter: youtubeExplodePlaylistSearchFilter(sort),
        ),
      );
      if (page == null) {
        return YouTubeCatalogPage(
          items: const <YouTubePlaylistResult>[],
          previousPageToken: pageIndex > 0
              ? _createPageToken(_playlistSearchTokenPrefix, pageIndex - 1)
              : null,
        );
      }
      final items = page
          .whereType<explode.SearchPlaylist>()
          .take(resultsPerPage)
          .map(
            (playlist) => YouTubePlaylistResult(
              id: playlist.id.value,
              title: playlist.title,
              thumbnailUrl: _bestThumbnailUrl(playlist.thumbnails),
              videoCount: playlist.videoCount,
            ),
          )
          .toList(growable: false);
      return YouTubeCatalogPage(
        items: List.unmodifiable(items),
        previousPageToken: pageIndex > 0
            ? _createPageToken(_playlistSearchTokenPrefix, pageIndex - 1)
            : null,
        nextPageToken: page.length >= resultsPerPage
            ? _createPageToken(_playlistSearchTokenPrefix, pageIndex + 1)
            : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Playlist-Suche ist momentan nicht verfügbar. '
        'Bitte versuche es später erneut.',
        cause: error,
      );
    }
  }

  Future<explode.SearchList?> _loadNativeSearchPage({
    required _NativeSearchState state,
    required int pageIndex,
    required Future<explode.SearchList> Function() firstPage,
  }) async {
    if (state.pages.isEmpty) {
      state.pages.add(await firstPage().timeout(requestTimeout));
    }
    while (state.pages.length <= pageIndex) {
      final nextPage = await state.pages.last.nextPage().timeout(
        requestTimeout,
      );
      if (nextPage == null) {
        return null;
      }
      state.pages.add(nextPage);
    }
    return state.pages[pageIndex];
  }

  @override
  Future<YouTubeSearchResult> loadChannelVideos({
    required String channelId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    try {
      final pageIndex = _readPageIndex(pageToken, _channelVideosTokenPrefix);
      if (!channelId.startsWith('UC') || channelId.length <= 2) {
        throw const YouTubeSearchException('Ungültige Channel-ID.');
      }
      final collectionId = '$_channelCollectionPrefix$channelId';
      if (pageToken == null ||
          _activePlaylistId != collectionId ||
          _activePlaylistLanguage != languageCode) {
        await _resetPlaylistVideos(collectionId, languageCode);
      }
      if (_playlistVideoBuffer.isEmpty && _playlistMayHaveMore) {
        final firstPage = await _playlistHttpClientFor(languageCode)
            .sendPost('browse', {
              'browseId': channelId,
              'params': _channelVideosBrowseParams,
            })
            .timeout(requestTimeout);
        _appendPlaylistResponse(firstPage);
      }
      await _ensurePlaylistVideoCount(
        ((pageIndex + 1) * resultsPerPage) + 1,
        languageCode,
      );
      return _videoResultPage(
        buffer: _playlistVideoBuffer,
        pageIndex: pageIndex,
        tokenPrefix: _channelVideosTokenPrefix,
        mayHaveMore: _playlistMayHaveMore,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Videos des Channels konnten nicht geladen werden.',
        cause: error,
      );
    }
  }

  @override
  Future<YouTubeSearchResult> loadPlaylistVideos({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) async {
    try {
      final pageIndex = _readPageIndex(pageToken, _playlistVideosTokenPrefix);
      if (pageToken == null ||
          _activePlaylistId != playlistId ||
          _activePlaylistLanguage != languageCode) {
        await _resetPlaylistVideos(playlistId, languageCode);
      }
      if (_playlistVideoBuffer.isEmpty && _playlistMayHaveMore) {
        final browseId = playlistId.startsWith('VL')
            ? playlistId
            : 'VL$playlistId';
        final firstPage = await _playlistHttpClientFor(
          languageCode,
        ).sendPost('browse', {'browseId': browseId}).timeout(requestTimeout);
        _appendPlaylistResponse(firstPage);
      }
      await _ensurePlaylistVideoCount(
        ((pageIndex + 1) * resultsPerPage) + 1,
        languageCode,
      );
      return _videoResultPage(
        buffer: _playlistVideoBuffer,
        pageIndex: pageIndex,
        tokenPrefix: _playlistVideosTokenPrefix,
        mayHaveMore: _playlistMayHaveMore,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Inhalte der Playlist konnten nicht geladen werden.',
        cause: error,
      );
    }
  }

  Future<void> _ensurePlaylistVideoCount(
    int requiredCount,
    String languageCode,
  ) async {
    while (_playlistVideoBuffer.length < requiredCount &&
        _playlistMayHaveMore) {
      final continuationToken = _playlistContinuationToken;
      if (continuationToken == null || continuationToken.isEmpty) {
        _playlistMayHaveMore = false;
        break;
      }
      final nextPage = await _playlistHttpClientFor(languageCode)
          .sendContinuation(
            'browse',
            continuationToken,
            headers: {
              'x-youtube-client-name': '1',
              'x-goog-visitor-id': _playlistVisitorData ?? '',
            },
          )
          .timeout(requestTimeout);
      final previousToken = _playlistContinuationToken;
      _appendPlaylistResponse(nextPage);
      if (_playlistContinuationToken == previousToken) {
        _playlistMayHaveMore = false;
      }
    }
  }

  YouTubeSearchResult _videoResultPage({
    required List<YouTubeVideo> buffer,
    required int pageIndex,
    required String tokenPrefix,
    required bool mayHaveMore,
  }) {
    final start = pageIndex * resultsPerPage;
    if (start >= buffer.length) {
      return YouTubeSearchResult(
        videos: const [],
        previousPageToken: pageIndex > 0
            ? _createPageToken(tokenPrefix, pageIndex - 1)
            : null,
      );
    }
    final end = (start + resultsPerPage).clamp(start, buffer.length);
    return YouTubeSearchResult(
      videos: List.unmodifiable(buffer.sublist(start, end)),
      previousPageToken: pageIndex > 0
          ? _createPageToken(tokenPrefix, pageIndex - 1)
          : null,
      nextPageToken: buffer.length > end || mayHaveMore
          ? _createPageToken(tokenPrefix, pageIndex + 1)
          : null,
    );
  }

  Future<void> _resetPlaylistVideos(
    String playlistId,
    String languageCode,
  ) async {
    _activePlaylistId = playlistId;
    _activePlaylistLanguage = languageCode;
    _playlistContinuationToken = null;
    _playlistVisitorData = null;
    _playlistVideoBuffer.clear();
    _knownPlaylistVideoIds.clear();
    _playlistMayHaveMore = true;
  }

  LocalizedYoutubeHttpClient _playlistHttpClientFor(String languageCode) {
    final normalized = languageCode == 'en' ? 'en' : 'de';
    return _playlistHttpClients.putIfAbsent(
      normalized,
      () => LocalizedYoutubeHttpClient(normalized),
    );
  }

  void _appendPlaylistResponse(Map<String, dynamic> response) {
    _playlistVisitorData ??= _findFirstString(response, 'visitorData');
    _playlistContinuationToken = _findContinuationToken(response);
    _collectPlaylistVideos(response);
    if (_playlistContinuationToken == null) {
      _playlistMayHaveMore = false;
    }
  }

  void _collectPlaylistVideos(Object? node) {
    if (node is List) {
      for (final child in node) {
        _collectPlaylistVideos(child);
      }
      return;
    }
    if (node is! Map) {
      return;
    }

    final lockup = node['lockupViewModel'];
    if (lockup is Map) {
      _appendLockupVideo(lockup, container: node);
    }
    final legacy = node['playlistVideoRenderer'];
    if (legacy is Map) {
      _appendLegacyPlaylistVideo(legacy, container: node);
    }
    for (final child in node.values) {
      _collectPlaylistVideos(child);
    }
  }

  void _appendLockupVideo(Map lockup, {required Map container}) {
    if (isYouTubeMembersOnlyRenderer(lockup) ||
        isYouTubeMembersOnlyRenderer(container)) {
      return;
    }
    final id = lockup['contentId'];
    final metadata = _valueAt(lockup, const [
      'metadata',
      'lockupMetadataViewModel',
    ]);
    final title = _readText(_valueAt(metadata, const ['title']));
    if (id is! String || id.isEmpty || title.isEmpty) {
      return;
    }
    if (!_knownPlaylistVideoIds.add(id)) {
      return;
    }

    final metadataRows = _valueAt(metadata, const [
      'metadata',
      'contentMetadataViewModel',
      'metadataRows',
    ]);
    String channelTitle = '';
    String? uploadDate;
    if (metadataRows is List) {
      for (final row in metadataRows) {
        final parts = _valueAt(row, const ['metadataParts']);
        if (parts is! List) {
          continue;
        }
        for (final part in parts) {
          final text = _readText(_valueAt(part, const ['text']));
          if (text.isEmpty) {
            continue;
          }
          if (channelTitle.isEmpty &&
              !text.contains(RegExp(r'\d')) &&
              !text.toLowerCase().startsWith('vor ')) {
            channelTitle = text;
          }
          if (text.toLowerCase().startsWith('vor ') ||
              text.toLowerCase().contains(' ago')) {
            uploadDate = text;
          }
        }
      }
    }

    _playlistVideoBuffer.add(
      YouTubeVideo(
        id: id,
        title: title,
        description: '',
        thumbnailUrl:
            _bestThumbnailFromSources(
              _valueAt(lockup, const [
                'contentImage',
                'thumbnailViewModel',
                'image',
                'sources',
              ]),
            ) ??
            explode.ThumbnailSet(id).highResUrl,
        channelTitle: channelTitle,
        publishedAt: _tryParseLocalizedUploadDate(uploadDate),
        isLive: isYouTubeLiveVideoRenderer(lockup),
      ),
    );
  }

  void _appendLegacyPlaylistVideo(Map renderer, {required Map container}) {
    if (isYouTubeMembersOnlyRenderer(renderer) ||
        isYouTubeMembersOnlyRenderer(container)) {
      return;
    }
    final id = renderer['videoId'];
    final title = _readText(renderer['title']);
    if (id is! String || id.isEmpty || title.isEmpty) {
      return;
    }
    if (!_knownPlaylistVideoIds.add(id)) {
      return;
    }
    final info = _readText(renderer['videoInfo']);
    final infoParts = info.split('•');
    final uploadDate = infoParts.isEmpty ? null : infoParts.last.trim();
    _playlistVideoBuffer.add(
      YouTubeVideo(
        id: id,
        title: title,
        description: _readText(renderer['descriptionSnippet']),
        thumbnailUrl:
            _bestThumbnailFromSources(
              _valueAt(renderer, const ['thumbnail', 'thumbnails']),
            ) ??
            explode.ThumbnailSet(id).highResUrl,
        channelTitle: _readText(
          renderer['ownerText'] ?? renderer['shortBylineText'],
        ),
        publishedAt: _tryParseLocalizedUploadDate(uploadDate),
        isLive: isYouTubeLiveVideoRenderer(renderer),
      ),
    );
  }

  DateTime? _tryParseLocalizedUploadDate(String? value) {
    if (value == null) {
      return null;
    }
    return _tryParseUploadDate(
      normalizeGermanYouTubePublishedTime(value) ?? value,
    );
  }

  Object? _valueAt(Object? root, List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (segment is String && current is Map) {
        current = current[segment];
      } else if (segment is int &&
          current is List &&
          segment < current.length) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String _readText(Object? node) {
    if (node is String) {
      return node.trim();
    }
    if (node is! Map) {
      return '';
    }
    final content = node['content'];
    if (content is String) {
      return content.trim();
    }
    final simpleText = node['simpleText'];
    if (simpleText is String) {
      return simpleText.trim();
    }
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .map((run) => run is Map ? run['text'] : null)
          .whereType<String>()
          .join()
          .trim();
    }
    return '';
  }

  String? _bestThumbnailFromSources(Object? rawSources) {
    if (rawSources is! List) {
      return null;
    }
    String? bestUrl;
    var bestPixels = -1;
    for (final source in rawSources) {
      if (source is! Map || source['url'] is! String) {
        continue;
      }
      final width = source['width'] is int ? source['width'] as int : 0;
      final height = source['height'] is int ? source['height'] as int : 0;
      final pixels = width * height;
      if (pixels >= bestPixels) {
        bestPixels = pixels;
        bestUrl = source['url'] as String;
      }
    }
    return bestUrl;
  }

  String? _findContinuationToken(Object? node) {
    if (node is List) {
      for (final child in node) {
        final token = _findContinuationToken(child);
        if (token != null) {
          return token;
        }
      }
      return null;
    }
    if (node is! Map) {
      return null;
    }
    final continuation = node['continuationItemRenderer'];
    if (continuation != null) {
      return _findFirstString(continuation, 'token');
    }
    for (final child in node.values) {
      final token = _findContinuationToken(child);
      if (token != null) {
        return token;
      }
    }
    return null;
  }

  String? _findFirstString(Object? node, String key) {
    if (node is List) {
      for (final child in node) {
        final value = _findFirstString(child, key);
        if (value != null) {
          return value;
        }
      }
      return null;
    }
    if (node is! Map) {
      return null;
    }
    final value = node[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    for (final child in node.values) {
      final result = _findFirstString(child, key);
      if (result != null) {
        return result;
      }
    }
    return null;
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

  int _readPageIndex(String? pageToken, String prefix) {
    if (pageToken == null) {
      return 0;
    }
    if (!pageToken.startsWith(prefix)) {
      throw const YouTubeSearchException('Ungültige Ergebnisseite.');
    }
    final pageIndex = int.tryParse(pageToken.substring(prefix.length));
    if (pageIndex == null || pageIndex < 0) {
      throw const YouTubeSearchException('Ungültige Ergebnisseite.');
    }
    return pageIndex;
  }

  String _createPageToken(String prefix, int pageIndex) => '$prefix$pageIndex';

  @override
  void close() {
    for (final client in _playlistHttpClients.values) {
      client.close();
    }
    _playlistHttpClients.clear();
    final providedClient = _providedClient;
    if (providedClient != null) {
      providedClient.close();
      return;
    }
    for (final client in _localizedClients.values) {
      client.close();
    }
    _localizedClients.clear();
  }
}

bool isYouTubeLiveVideoRenderer(Object? node) {
  return live_detection.isYouTubeLiveRenderer(node);
}

class _NativeSearchState {
  String? query;
  String? languageCode;
  YouTubeSearchSort? sort;
  final List<explode.SearchList> pages = [];

  void reset(
    String nextQuery,
    String nextLanguageCode, {
    YouTubeSearchSort? sort,
  }) {
    query = nextQuery;
    languageCode = nextLanguageCode;
    this.sort = sort;
    pages.clear();
  }
}
