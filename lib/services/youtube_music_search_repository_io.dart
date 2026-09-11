import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:ytmusicapi_dart/auth/types.dart';
import 'package:ytmusicapi_dart/constants.dart';
import 'package:ytmusicapi_dart/enums.dart' as music;
import 'package:ytmusicapi_dart/exceptions.dart';
import 'package:ytmusicapi_dart/helpers.dart';
import 'package:ytmusicapi_dart/mixins/browsing.dart';
import 'package:ytmusicapi_dart/mixins/charts.dart';
import 'package:ytmusicapi_dart/mixins/explore.dart';
import 'package:ytmusicapi_dart/mixins/playlists.dart';
import 'package:ytmusicapi_dart/mixins/protocol.dart';
import 'package:ytmusicapi_dart/mixins/search.dart';
import 'package:ytmusicapi_dart/parsers/i18n.dart';
import 'package:ytmusicapi_dart/type_alias.dart';

import '../models/hot_music.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import '../utils/media_duration.dart';
import 'youtube_music_catalog_repository.dart';
import 'youtube_music_discovery_repository.dart';
import 'youtube_music_discovery_response_parser.dart';
import 'youtube_search_repository.dart';

const bool supportsYouTubeMusicSearch = true;

YouTubeSearchRepository createYouTubeMusicSearchRepository() {
  return YouTubeMusicSearchRepository();
}

abstract interface class YouTubeMusicSearchSource {
  Future<List<Object?>> searchSongs(
    String query, {
    required int limit,
    required String languageCode,
  });

  Future<List<Object?>> searchArtists(
    String query, {
    required int limit,
    required String languageCode,
  });

  Future<List<Object?>> searchPlaylists(
    String query, {
    required int limit,
    required String languageCode,
  });

  Future<List<Object?>> loadArtistSongs(
    String artistId, {
    required int limit,
    required String languageCode,
  });

  Future<List<Object?>> loadPlaylistSongs(
    String playlistId, {
    required int limit,
    required String languageCode,
  });

  void close();
}

abstract interface class YouTubeMusicDiscoverySource {
  Future<Map<String, Object?>> loadExplore({required String languageCode});

  Future<Map<String, Object?>> loadCharts({
    required String countryCode,
    required String languageCode,
  });

  Future<Map<String, Object?>> loadGenreSections({
    required String languageCode,
  });

  Future<List<Object?>> loadGenrePlaylists({
    required String params,
    required String languageCode,
  });
}

class YouTubeMusicDartSearchSource
    implements YouTubeMusicSearchSource, YouTubeMusicDiscoverySource {
  YouTubeMusicDartSearchSource({
    YouTubeMusicDiscoveryResponseParser discoveryParser =
        const YouTubeMusicDiscoveryResponseParser(),
  }) : _discoveryParser = discoveryParser;

  final Map<String, _SafeYouTubeMusicClient> _clients = {};
  final YouTubeMusicDiscoveryResponseParser _discoveryParser;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Die YouTube-Music-Suche wurde bereits geschlossen.');
    }
  }

  @override
  Future<List<Object?>> searchSongs(
    String query, {
    required int limit,
    required String languageCode,
  }) async {
    _ensureOpen();
    final client = _client(languageCode);
    final results = await client.search(
      query,
      filter: music.SearchFilterType.songs,
      limit: limit,
    );
    return List<Object?>.from(results);
  }

  @override
  Future<List<Object?>> searchArtists(
    String query, {
    required int limit,
    required String languageCode,
  }) async {
    _ensureOpen();
    final results = await _client(
      languageCode,
    ).search(query, filter: music.SearchFilterType.artists, limit: limit);
    return List<Object?>.from(results);
  }

  @override
  Future<List<Object?>> searchPlaylists(
    String query, {
    required int limit,
    required String languageCode,
  }) async {
    _ensureOpen();
    final results = await _client(
      languageCode,
    ).search(query, filter: music.SearchFilterType.playlists, limit: limit);
    return List<Object?>.from(results);
  }

  @override
  Future<List<Object?>> loadArtistSongs(
    String artistId, {
    required int limit,
    required String languageCode,
  }) async {
    _ensureOpen();
    final client = _client(languageCode);
    final artist = await client.getArtist(artistId);
    final songs = artist['songs'];
    if (songs is! Map) {
      return const [];
    }
    final browseId = _readMapString(songs, 'browseId');
    if (browseId != null) {
      final playlist = await client.getPlaylist(browseId, limit: limit);
      final tracks = playlist['tracks'];
      if (tracks is List) {
        return List<Object?>.from(tracks);
      }
    }
    final results = songs['results'];
    return results is List ? List<Object?>.from(results.take(limit)) : const [];
  }

  @override
  Future<List<Object?>> loadPlaylistSongs(
    String playlistId, {
    required int limit,
    required String languageCode,
  }) async {
    _ensureOpen();
    final playlist = await _client(
      languageCode,
    ).getPlaylist(playlistId, limit: limit);
    final tracks = playlist['tracks'];
    return tracks is List ? List<Object?>.from(tracks) : const [];
  }

  @override
  Future<Map<String, Object?>> loadExplore({
    required String languageCode,
  }) async {
    _ensureOpen();
    final response = await _client(
      languageCode,
    ).sendRequest('browse', {'browseId': 'FEmusic_explore'});
    return Map<String, Object?>.from(
      await _discoveryParser.parseExplore(response),
    );
  }

  @override
  Future<Map<String, Object?>> loadCharts({
    required String countryCode,
    required String languageCode,
  }) async {
    _ensureOpen();
    final response = await _client(languageCode).sendRequest('browse', {
      'browseId': 'FEmusic_charts',
      if (countryCode.isNotEmpty)
        'formData': {
          'selectedValues': [countryCode],
        },
    });
    return Map<String, Object?>.from(
      await _discoveryParser.parseCharts(response, country: countryCode),
    );
  }

  @override
  Future<Map<String, Object?>> loadGenreSections({
    required String languageCode,
  }) async {
    _ensureOpen();
    return Map<String, Object?>.from(
      await _client(languageCode).getMoodCategories(),
    );
  }

  @override
  Future<List<Object?>> loadGenrePlaylists({
    required String params,
    required String languageCode,
  }) async {
    _ensureOpen();
    final response = await _client(languageCode).sendRequest('browse', {
      'browseId': 'FEmusic_moods_and_genres_category',
      'params': params,
    });
    return List<Object?>.from(
      await _discoveryParser.parseGenrePlaylists(response),
    );
  }

  _SafeYouTubeMusicClient _client(String languageCode) {
    final normalizedLanguage = languageCode == 'en' ? 'en' : 'de';
    return _clients.putIfAbsent(
      normalizedLanguage,
      () => _SafeYouTubeMusicClient(languageCode: normalizedLanguage),
    );
  }

  String? _readMapString(Map values, String key) {
    final value = values[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}

/// A minimal, anonymous YouTube Music client that keeps the package's search
/// parser but does not depend on scraping a visitor ID from the consent page.
///
/// `YTMusic.create` currently force-unwraps that ID. This transport deliberately
/// omits the optional header and uses Dio's normal certificate validation.
class _SafeYouTubeMusicClient extends MixinProtocol
    with SearchMixin, BrowsingMixin, ChartsMixin, ExploreMixin, PlaylistsMixin {
  _SafeYouTubeMusicClient({required this.languageCode, Dio? session})
    : _session =
          session ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _context = initializeContext(),
      parser = Parser(languageCode) {
    final client = (_context['context'] as JsonMap)['client'] as JsonMap;
    client['hl'] = languageCode;
    client['gl'] = languageCode == 'en' ? 'US' : 'DE';
  }

  final String languageCode;
  final Dio _session;
  final JsonMap _context;

  @override
  AuthType get authType => AuthType.unauthorized;

  @override
  final Parser parser;

  @override
  Uri? get proxy => null;

  @override
  Future<Map<String, String>> get headers async {
    final result = initializeHeaders();
    // Dio sends the JSON body uncompressed. Advertising gzip for the request
    // body would therefore be incorrect; response decompression is automatic.
    result.remove('content-encoding');
    return result;
  }

  @override
  Future<JsonMap> sendRequest(
    String endpoint,
    JsonMap body, {
    String additionalParams = '',
  }) async {
    final requestBody = JsonMap.from(body)..addAll(_context);
    final response = await _session.post<Object?>(
      '$YTM_BASE_API$endpoint$YTM_PARAMS$additionalParams',
      data: requestBody,
      options: Options(headers: await headers, responseType: ResponseType.json),
    );

    final data = _decodeResponse(response.data);
    if (response.statusCode == null || response.statusCode! >= 400) {
      final error = data['error'];
      final message = error is Map ? error['message'] : null;
      throw YTMusicServerError(
        'YouTube Music antwortete mit HTTP ${response.statusCode}: '
        '${message ?? response.statusMessage ?? 'Unbekannter Fehler'}',
      );
    }
    return data;
  }

  JsonMap _decodeResponse(Object? data) {
    final Object? decoded;
    if (data is List<int>) {
      decoded = jsonDecode(utf8.decode(data));
    } else if (data is String) {
      decoded = jsonDecode(data);
    } else {
      decoded = data;
    }
    if (decoded is! Map) {
      throw const FormatException(
        'YouTube Music hat keine JSON-Objektantwort geliefert.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<Response<Object?>> sendGetRequest(String url, {JsonMap? params}) {
    return _session.get<Object?>(
      url,
      queryParameters: params,
      options: Options(headers: initializeHeaders()),
    );
  }

  @override
  void checkAuth() {
    throw YTMusicUserError(
      'Diese App verwendet ausschließlich die anonyme YouTube-Music-Suche.',
    );
  }

  @override
  Future<T> asMobile<T>(Future<T> Function() callback) async {
    final client = (_context['context'] as JsonMap)['client'] as JsonMap;
    final previousName = client['clientName'];
    final previousVersion = client['clientVersion'];
    client['clientName'] = 'ANDROID_MUSIC';
    client['clientVersion'] = '7.21.50';
    try {
      return await callback();
    } finally {
      client['clientName'] = previousName;
      client['clientVersion'] = previousVersion;
    }
  }

  void close() => _session.close(force: true);
}

class YouTubeMusicSearchRepository
    implements
        YouTubeSearchRepository,
        YouTubeMusicCatalogRepository,
        YouTubeMusicDiscoveryRepository {
  YouTubeMusicSearchRepository({
    YouTubeMusicSearchSource? source,
    YouTubeMusicDiscoverySource? discoverySource,
    this.requestTimeout = const Duration(seconds: 35),
    this.discoveryCacheDuration = const Duration(minutes: 15),
  }) : _source = source ?? YouTubeMusicDartSearchSource(),
       _explicitDiscoverySource = discoverySource;

  static const int resultsPerPage = 20;
  static const String _pageTokenPrefix = 'youtube-music-page:';
  static const String _artistPageTokenPrefix = 'youtube-music-artist-page:';
  static const String _playlistPageTokenPrefix = 'youtube-music-playlist-page:';
  static const String _artistSongsPageTokenPrefix =
      'youtube-music-artist-songs-page:';
  static const String _playlistSongsPageTokenPrefix =
      'youtube-music-playlist-songs-page:';

  final YouTubeMusicSearchSource _source;
  final YouTubeMusicDiscoverySource? _explicitDiscoverySource;
  final Duration requestTimeout;
  final Duration discoveryCacheDuration;
  final List<YouTubeVideo> _videoBuffer = [];
  final Map<String, _TimedDiscoveryValue<HotMusicExploreResult>> _exploreCache =
      {};
  final Map<String, _TimedDiscoveryValue<HotMusicChartsResult>> _chartsCache =
      {};
  final Map<String, _TimedDiscoveryValue<List<HotMusicGenreSection>>>
  _genreSectionsCache = {};
  final Map<String, _TimedDiscoveryValue<List<YouTubePlaylistResult>>>
  _genrePlaylistsCache = {};

  YouTubeMusicDiscoverySource get _discoverySource {
    final source = _explicitDiscoverySource ?? _source;
    if (source is YouTubeMusicDiscoverySource) {
      return source;
    }
    throw const YouTubeSearchException(
      'Hot Music ist mit dieser Music-Datenquelle nicht verfügbar.',
    );
  }

  String? _activeQuery;
  String? _activeLanguageCode;
  int _requestedLimit = 0;
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
        pageToken == null) {
      _reset(query, languageCode);
    }

    try {
      final requiredResultCount = ((pageIndex + 1) * resultsPerPage) + 1;
      await _fillBuffer(query, languageCode, requiredResultCount);

      final start = pageIndex * resultsPerPage;
      if (start >= _videoBuffer.length) {
        return YouTubeSearchResult(
          videos: const [],
          previousPageToken: pageIndex > 0
              ? _createPageToken(pageIndex - 1)
              : null,
        );
      }

      final end = min(start + resultsPerPage, _videoBuffer.length);
      return YouTubeSearchResult(
        videos: List.unmodifiable(_videoBuffer.sublist(start, end)),
        previousPageToken: pageIndex > 0
            ? _createPageToken(pageIndex - 1)
            : null,
        nextPageToken: _videoBuffer.length > end || _mayHaveMoreResults
            ? _createPageToken(pageIndex + 1)
            : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die YouTube-Music-Suche ist momentan nicht verfügbar. '
        'Bitte versuche es später erneut.',
        cause: error,
      );
    }
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchArtists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) {
    return _loadCatalogPage<YouTubeChannelResult>(
      pageToken: pageToken,
      tokenPrefix: _artistPageTokenPrefix,
      load: (limit) => _source.searchArtists(
        query,
        limit: limit,
        languageCode: languageCode,
      ),
      convert: _convertArtist,
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchMusicPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) {
    return _loadCatalogPage<YouTubePlaylistResult>(
      pageToken: pageToken,
      tokenPrefix: _playlistPageTokenPrefix,
      load: (limit) => _source.searchPlaylists(
        query,
        limit: limit,
        languageCode: languageCode,
      ),
      convert: _convertPlaylist,
    );
  }

  @override
  Future<YouTubeSearchResult> loadArtistSongs({
    required String artistId,
    String? pageToken,
    String languageCode = 'de',
  }) {
    return _loadSongPage(
      pageToken: pageToken,
      tokenPrefix: _artistSongsPageTokenPrefix,
      load: (limit) => _source.loadArtistSongs(
        artistId,
        limit: limit,
        languageCode: languageCode,
      ),
    );
  }

  @override
  Future<YouTubeSearchResult> loadMusicPlaylistSongs({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) {
    return _loadSongPage(
      pageToken: pageToken,
      tokenPrefix: _playlistSongsPageTokenPrefix,
      load: (limit) => _source.loadPlaylistSongs(
        playlistId,
        limit: limit,
        languageCode: languageCode,
      ),
    );
  }

  @override
  Future<HotMusicExploreResult> loadExplore({
    String languageCode = 'de',
  }) async {
    final normalizedLanguage = _normalizedLanguage(languageCode);
    final cached = _readDiscoveryCache(_exploreCache, normalizedLanguage);
    if (cached != null) {
      return cached;
    }
    try {
      final raw = await _discoverySource
          .loadExplore(languageCode: normalizedLanguage)
          .timeout(requestTimeout);
      final result = HotMusicExploreResult(
        trending: _convertVideoList(_readNestedList(raw, 'trending', 'items')),
        newVideos: _convertVideoList(raw['new_videos'], isMusicVideo: true),
        newReleases: _convertPlaylistList(
          raw['new_releases'],
          idKeys: const ['audioPlaylistId', 'playlistId'],
          includeReleaseMetadata: true,
        ),
        moodsAndGenres: _convertCategories(raw['moods_and_genres']),
      );
      _writeDiscoveryCache(_exploreCache, normalizedLanguage, result);
      return result;
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'YouTube Music Entdecken ist momentan nicht verfügbar.',
        cause: error,
      );
    }
  }

  @override
  Future<HotMusicChartsResult> loadCharts({
    required String countryCode,
    String languageCode = 'de',
  }) async {
    final normalizedLanguage = _normalizedLanguage(languageCode);
    final normalizedCountry = countryCode.trim().toUpperCase();
    final cacheKey = '$normalizedLanguage:$normalizedCountry';
    final cached = _readDiscoveryCache(_chartsCache, cacheKey);
    if (cached != null) {
      return cached;
    }
    try {
      final raw = await _discoverySource
          .loadCharts(
            countryCode: normalizedCountry,
            languageCode: normalizedLanguage,
          )
          .timeout(requestTimeout);
      final countries = raw['countries'];
      final countryCodes = <String>[];
      if (countries is Map && countries['options'] is List) {
        for (final option in countries['options'] as List) {
          final code = _readString(option)?.toUpperCase();
          if (code != null && !countryCodes.contains(code)) {
            countryCodes.add(code);
          }
        }
      }
      final result = HotMusicChartsResult(
        countryCode: normalizedCountry,
        countryCodes: List.unmodifiable(countryCodes),
        videos: _convertPlaylistList(
          raw['videos'],
          idKeys: const ['playlistId', 'browseId'],
          itemsAreMusicVideos: true,
        ),
        artists: _convertArtistList(raw['artists']),
      );
      _writeDiscoveryCache(_chartsCache, cacheKey, result);
      return result;
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die YouTube-Music-Charts sind momentan nicht verfügbar.',
        cause: error,
      );
    }
  }

  @override
  Future<List<HotMusicGenreSection>> loadGenreSections({
    String languageCode = 'de',
  }) async {
    final normalizedLanguage = _normalizedLanguage(languageCode);
    final cached = _readDiscoveryCache(_genreSectionsCache, normalizedLanguage);
    if (cached != null) {
      return cached;
    }
    try {
      final raw = await _discoverySource
          .loadGenreSections(languageCode: normalizedLanguage)
          .timeout(requestTimeout);
      final sections = <HotMusicGenreSection>[];
      for (final entry in raw.entries) {
        final title = entry.key.trim();
        final categories = _convertCategories(entry.value);
        if (title.isNotEmpty && categories.isNotEmpty) {
          sections.add(
            HotMusicGenreSection(title: title, categories: categories),
          );
        }
      }
      final result = List<HotMusicGenreSection>.unmodifiable(sections);
      _writeDiscoveryCache(_genreSectionsCache, normalizedLanguage, result);
      return result;
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Genres und Stimmungen konnten nicht geladen werden.',
        cause: error,
      );
    }
  }

  @override
  Future<List<YouTubePlaylistResult>> loadGenrePlaylists({
    required String params,
    String languageCode = 'de',
  }) async {
    final normalizedLanguage = _normalizedLanguage(languageCode);
    final normalizedParams = params.trim();
    if (normalizedParams.isEmpty) {
      return const [];
    }
    final cacheKey = '$normalizedLanguage:$normalizedParams';
    final cached = _readDiscoveryCache(_genrePlaylistsCache, cacheKey);
    if (cached != null) {
      return cached;
    }
    try {
      final raw = await _discoverySource
          .loadGenrePlaylists(
            params: normalizedParams,
            languageCode: normalizedLanguage,
          )
          .timeout(requestTimeout);
      final result = _convertPlaylistList(
        raw,
        idKeys: const ['playlistId', 'browseId'],
      );
      _writeDiscoveryCache(_genrePlaylistsCache, cacheKey, result);
      return result;
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Playlists dieser Kategorie konnten nicht geladen werden.',
        cause: error,
      );
    }
  }

  Future<YouTubeCatalogPage<T>> _loadCatalogPage<T>({
    required String? pageToken,
    required String tokenPrefix,
    required Future<List<Object?>> Function(int limit) load,
    required T? Function(Object? rawResult) convert,
  }) async {
    final pageIndex = _readPageIndex(pageToken, prefix: tokenPrefix);
    final requestedLimit = ((pageIndex + 1) * resultsPerPage) + 1;
    try {
      final rawResults = await load(requestedLimit).timeout(requestTimeout);
      final converted = rawResults.map(convert).whereType<T>().toList();
      final start = pageIndex * resultsPerPage;
      final end = min(start + resultsPerPage, converted.length);
      return YouTubeCatalogPage<T>(
        items: start >= converted.length
            ? const []
            : List<T>.unmodifiable(converted.sublist(start, end)),
        previousPageToken: pageIndex > 0
            ? _createPageToken(pageIndex - 1, prefix: tokenPrefix)
            : null,
        nextPageToken:
            converted.length > end || rawResults.length >= requestedLimit
            ? _createPageToken(pageIndex + 1, prefix: tokenPrefix)
            : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die YouTube-Music-Katalogsuche ist momentan nicht verfügbar. '
        'Bitte versuche es später erneut.',
        cause: error,
      );
    }
  }

  Future<YouTubeSearchResult> _loadSongPage({
    required String? pageToken,
    required String tokenPrefix,
    required Future<List<Object?>> Function(int limit) load,
  }) async {
    final pageIndex = _readPageIndex(pageToken, prefix: tokenPrefix);
    final requestedLimit = ((pageIndex + 1) * resultsPerPage) + 1;
    try {
      final rawResults = await load(requestedLimit).timeout(requestTimeout);
      final converted = rawResults
          .map(_convertResult)
          .whereType<YouTubeVideo>()
          .toList();
      final start = pageIndex * resultsPerPage;
      final end = min(start + resultsPerPage, converted.length);
      return YouTubeSearchResult(
        videos: start >= converted.length
            ? const []
            : List<YouTubeVideo>.unmodifiable(converted.sublist(start, end)),
        previousPageToken: pageIndex > 0
            ? _createPageToken(pageIndex - 1, prefix: tokenPrefix)
            : null,
        nextPageToken:
            converted.length > end || rawResults.length >= requestedLimit
            ? _createPageToken(pageIndex + 1, prefix: tokenPrefix)
            : null,
      );
    } on YouTubeSearchException {
      rethrow;
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'Die Songs konnten nicht aus YouTube Music geladen werden.',
        cause: error,
      );
    }
  }

  Future<void> _fillBuffer(
    String query,
    String languageCode,
    int requiredResultCount,
  ) async {
    var attempts = 0;
    while (_videoBuffer.length < requiredResultCount &&
        _mayHaveMoreResults &&
        attempts < 3) {
      attempts++;
      final requestedLimit = max(
        _requestedLimit + resultsPerPage,
        requiredResultCount + 10,
      );
      final rawResults = await _source
          .searchSongs(query, limit: requestedLimit, languageCode: languageCode)
          .timeout(requestTimeout);
      _requestedLimit = requestedLimit;
      _mayHaveMoreResults = rawResults.length >= requestedLimit;

      final knownIds = <String>{};
      final converted = <YouTubeVideo>[];
      for (final rawResult in rawResults) {
        final video = _convertResult(rawResult);
        if (video != null && knownIds.add(video.id)) {
          converted.add(video);
        }
      }
      _videoBuffer
        ..clear()
        ..addAll(converted);
    }
  }

  YouTubeVideo? _convertResult(Object? rawResult, {bool isMusicVideo = false}) {
    if (rawResult is! Map) {
      return null;
    }
    if (rawResult['isAvailable'] == false) {
      return null;
    }
    final id = _readString(rawResult['videoId']);
    final title = _readString(rawResult['title']);
    if (id == null || title == null) {
      return null;
    }

    final artists = <String>[];
    final rawArtists = rawResult['artists'];
    if (rawArtists is List) {
      for (final rawArtist in rawArtists) {
        if (rawArtist is Map) {
          final name = _readString(rawArtist['name']);
          if (name != null) {
            artists.add(name);
          }
        }
      }
    }
    final singleArtist = _readString(rawResult['artist']);
    if (artists.isEmpty && singleArtist != null) {
      artists.add(singleArtist);
    }

    final album = rawResult['album'];
    final albumName = album is Map
        ? _readString(album['name'])
        : _readString(album);
    final details = <String?>[
      artists.isEmpty ? null : artists.join(', '),
      albumName,
      _readString(rawResult['duration']),
      rawResult['isExplicit'] == true ? 'Explizit' : null,
    ].whereType<String>().toList(growable: false);
    final duration =
        parseMediaDuration(rawResult['duration_seconds']) ??
        parseMediaDuration(rawResult['durationSeconds']) ??
        parseMediaDuration(rawResult['duration']);

    return YouTubeVideo(
      id: id,
      title: title,
      description: details.join(' • '),
      thumbnailUrl: _readThumbnail(rawResult['thumbnails']),
      channelTitle: artists.join(', '),
      duration: duration,
      isMusic: true,
      isMusicVideo: isMusicVideo,
    );
  }

  List<YouTubeVideo> _convertVideoList(
    Object? rawResults, {
    bool isMusicVideo = false,
  }) {
    if (rawResults is! List) {
      return const [];
    }
    final knownIds = <String>{};
    return List<YouTubeVideo>.unmodifiable(
      rawResults
          .where(
            (result) =>
                result is! Map ||
                result['videoType'] != 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
          )
          .map((result) => _convertResult(result, isMusicVideo: isMusicVideo))
          .whereType<YouTubeVideo>()
          .where((video) => knownIds.add(video.id)),
    );
  }

  List<YouTubeChannelResult> _convertArtistList(Object? rawResults) {
    if (rawResults is! List) {
      return const [];
    }
    final knownIds = <String>{};
    return List<YouTubeChannelResult>.unmodifiable(
      rawResults
          .map(_convertArtist)
          .whereType<YouTubeChannelResult>()
          .where((artist) => knownIds.add(artist.id)),
    );
  }

  List<YouTubePlaylistResult> _convertPlaylistList(
    Object? rawResults, {
    required List<String> idKeys,
    bool itemsAreMusicVideos = false,
    bool includeReleaseMetadata = false,
  }) {
    if (rawResults is! List) {
      return const [];
    }
    final knownIds = <String>{};
    final playlists = <YouTubePlaylistResult>[];
    for (final rawResult in rawResults) {
      final playlist = _convertPlaylistWithIds(
        rawResult,
        idKeys,
        itemsAreMusicVideos: itemsAreMusicVideos,
        includeReleaseMetadata: includeReleaseMetadata,
      );
      if (playlist != null && knownIds.add(playlist.id)) {
        playlists.add(playlist);
      }
    }
    return List<YouTubePlaylistResult>.unmodifiable(playlists);
  }

  YouTubePlaylistResult? _convertPlaylistWithIds(
    Object? rawResult,
    List<String> idKeys, {
    required bool itemsAreMusicVideos,
    required bool includeReleaseMetadata,
  }) {
    if (rawResult is! Map) {
      return null;
    }
    String? id;
    for (final key in idKeys) {
      id = _readString(rawResult[key]);
      if (id != null) {
        break;
      }
    }
    final title = _readString(rawResult['title']);
    if (id == null || title == null) {
      return null;
    }
    return YouTubePlaylistResult(
      id: id,
      title: title,
      thumbnailUrl: _readThumbnail(rawResult['thumbnails']),
      videoCount: _readItemCount(rawResult['itemCount'] ?? rawResult['count']),
      itemsAreMusicVideos: itemsAreMusicVideos,
      creatorName: includeReleaseMetadata
          ? _readCreatorNames(rawResult['artists'])
          : '',
      typeLabel: includeReleaseMetadata
          ? _normalizeReleaseType(rawResult['type'])
          : '',
    );
  }

  String _readCreatorNames(Object? rawArtists) {
    if (rawArtists is! List) {
      return _readString(rawArtists) ?? '';
    }
    final names = <String>[];
    for (final rawArtist in rawArtists) {
      final name = rawArtist is Map
          ? _readString(rawArtist['name']) ?? _readString(rawArtist['title'])
          : _readString(rawArtist);
      if (name != null && !names.contains(name)) {
        names.add(name);
      }
    }
    return names.join(', ');
  }

  String _normalizeReleaseType(Object? rawType) {
    final type = _readString(rawType);
    if (type == null) {
      return 'Veröffentlichung';
    }
    return switch (type.toLowerCase()) {
      'album' => 'Album',
      'ep' || 'extended play' => 'EP',
      'single' => 'Single',
      'song' || 'track' || 'titel' => 'Song',
      'playlist' || 'wiedergabeliste' => 'Playlist',
      _ => 'Veröffentlichung',
    };
  }

  List<HotMusicCategory> _convertCategories(Object? rawCategories) {
    if (rawCategories is! List) {
      return const [];
    }
    final knownParams = <String>{};
    final categories = <HotMusicCategory>[];
    for (final rawCategory in rawCategories) {
      if (rawCategory is! Map) {
        continue;
      }
      final title = _readString(rawCategory['title']);
      final params = _readString(rawCategory['params']);
      if (title != null && params != null && knownParams.add(params)) {
        categories.add(HotMusicCategory(title: title, params: params));
      }
    }
    return List<HotMusicCategory>.unmodifiable(categories);
  }

  Object? _readNestedList(
    Map<String, Object?> values,
    String key,
    String subkey,
  ) {
    final nested = values[key];
    return nested is Map ? nested[subkey] : null;
  }

  String _normalizedLanguage(String languageCode) =>
      languageCode == 'en' ? 'en' : 'de';

  T? _readDiscoveryCache<T>(
    Map<String, _TimedDiscoveryValue<T>> cache,
    String key,
  ) {
    final entry = cache[key];
    if (entry == null) {
      return null;
    }
    if (DateTime.now().difference(entry.loadedAt) > discoveryCacheDuration) {
      cache.remove(key);
      return null;
    }
    return entry.value;
  }

  void _writeDiscoveryCache<T>(
    Map<String, _TimedDiscoveryValue<T>> cache,
    String key,
    T value,
  ) {
    cache[key] = _TimedDiscoveryValue(value: value, loadedAt: DateTime.now());
  }

  YouTubeChannelResult? _convertArtist(Object? rawResult) {
    if (rawResult is! Map) {
      return null;
    }
    final id = _readString(rawResult['browseId']);
    final name =
        _readString(rawResult['artist']) ?? _readString(rawResult['title']);
    if (id == null || name == null) {
      return null;
    }
    return YouTubeChannelResult(
      id: id,
      name: name,
      description: _readString(rawResult['subscribers']) ?? '',
      thumbnailUrl: _readThumbnail(rawResult['thumbnails']),
      videoCount: 0,
      isMusic: true,
    );
  }

  YouTubePlaylistResult? _convertPlaylist(Object? rawResult) {
    if (rawResult is! Map) {
      return null;
    }
    final id = _readString(rawResult['browseId']);
    final title = _readString(rawResult['title']);
    if (id == null || title == null) {
      return null;
    }
    return YouTubePlaylistResult(
      id: id,
      title: title,
      thumbnailUrl: _readThumbnail(rawResult['thumbnails']),
      videoCount: _readItemCount(rawResult['itemCount']),
    );
  }

  int _readItemCount(Object? value) {
    if (value is int) {
      return value;
    }
    final text = _readString(value);
    if (text == null) {
      return 0;
    }
    final digits = RegExp(
      r'\d+',
    ).allMatches(text).map((match) => match[0]).join();
    return int.tryParse(digits) ?? 0;
  }

  String _readThumbnail(Object? rawThumbnails) {
    if (rawThumbnails is! List) {
      return '';
    }
    String result = '';
    var bestResolution = -1;
    for (final rawThumbnail in rawThumbnails) {
      if (rawThumbnail is! Map) {
        continue;
      }
      final url = _readString(rawThumbnail['url']);
      if (url == null) {
        continue;
      }
      final width = rawThumbnail['width'] is int
          ? rawThumbnail['width'] as int
          : 0;
      final height = rawThumbnail['height'] is int
          ? rawThumbnail['height'] as int
          : 0;
      final resolution = width * height;
      if (resolution >= bestResolution) {
        bestResolution = resolution;
        result = url.startsWith('//') ? 'https:$url' : url;
      }
    }
    return result;
  }

  String? _readString(Object? value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  int _readPageIndex(String? pageToken, {String prefix = _pageTokenPrefix}) {
    if (pageToken == null) {
      return 0;
    }
    if (!pageToken.startsWith(prefix)) {
      throw const YouTubeSearchException('Ungültige Music-Ergebnisseite.');
    }
    final pageIndex = int.tryParse(pageToken.substring(prefix.length));
    if (pageIndex == null || pageIndex < 0) {
      throw const YouTubeSearchException('Ungültige Music-Ergebnisseite.');
    }
    return pageIndex;
  }

  String _createPageToken(int pageIndex, {String prefix = _pageTokenPrefix}) =>
      '$prefix$pageIndex';

  void _reset(String query, String languageCode) {
    _activeQuery = query;
    _activeLanguageCode = languageCode;
    _requestedLimit = 0;
    _mayHaveMoreResults = true;
    _videoBuffer.clear();
  }

  @override
  void close() {
    _exploreCache.clear();
    _chartsCache.clear();
    _genreSectionsCache.clear();
    _genrePlaylistsCache.clear();
    _source.close();
  }
}

class _TimedDiscoveryValue<T> {
  const _TimedDiscoveryValue({required this.value, required this.loadedAt});

  final T value;
  final DateTime loadedAt;
}
