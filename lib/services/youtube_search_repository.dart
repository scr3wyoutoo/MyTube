import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/youtube_video.dart';
import '../models/youtube_search_sort.dart';

abstract interface class YouTubeSearchRepository {
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  });

  void close();
}

class YouTubeApiSearchRepository implements YouTubeSearchRepository {
  YouTubeApiSearchRepository({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  static const int resultsPerPage = 20;

  final String apiKey;
  final http.Client _client;

  @override
  void close() => _client.close();

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const YouTubeSearchException(
        'Es ist noch kein YouTube-API-Key konfiguriert. Starte die App mit '
        '--dart-define=YOUTUBE_API_KEY=DEIN_KEY.',
      );
    }

    final parameters = <String, String>{
      'part': 'snippet',
      'q': query,
      'type': 'video',
      'maxResults': '$resultsPerPage',
      'relevanceLanguage': languageCode == 'en' ? 'en' : 'de',
      'regionCode': languageCode == 'en' ? 'US' : 'DE',
      'order': switch (sort) {
        YouTubeSearchSort.relevance => 'relevance',
        YouTubeSearchSort.uploadDate => 'date',
        YouTubeSearchSort.viewCount => 'viewCount',
        YouTubeSearchSort.rating => 'rating',
      },
    };
    if (pageToken != null && pageToken.isNotEmpty) {
      parameters['pageToken'] = pageToken;
    }

    final uri = Uri.https(
      'www.googleapis.com',
      '/youtube/v3/search',
      parameters,
    );

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'X-Goog-Api-Key': apiKey,
        },
      );
    } on Exception catch (error) {
      throw YouTubeSearchException(
        'YouTube konnte nicht erreicht werden. Prüfe deine Internetverbindung.',
        cause: error,
      );
    }

    final data = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YouTubeSearchException(_readApiError(data, response.statusCode));
    }

    final rawItems = data['items'];
    final videos = <YouTubeVideo>[];
    if (rawItems is List<dynamic>) {
      for (final rawItem in rawItems) {
        if (rawItem is Map<String, dynamic>) {
          final video = YouTubeVideo.fromSearchItem(rawItem);
          if (video != null) {
            videos.add(video);
          }
        }
      }
    }

    return YouTubeSearchResult(
      videos: List.unmodifiable(videos),
      nextPageToken: _readOptionalString(data['nextPageToken']),
      previousPageToken: _readOptionalString(data['prevPageToken']),
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException catch (error) {
      throw YouTubeSearchException(
        'YouTube hat eine ungültige Antwort geliefert.',
        cause: error,
      );
    }

    throw const YouTubeSearchException(
      'YouTube hat eine ungültige Antwort geliefert.',
    );
  }

  String _readApiError(Map<String, dynamic> data, int statusCode) {
    final error = data['error'];
    if (error is Map<String, dynamic> && error['message'] is String) {
      return 'YouTube-Suche fehlgeschlagen: ${error['message']}';
    }
    return 'YouTube-Suche fehlgeschlagen (HTTP $statusCode).';
  }

  String? _readOptionalString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }
}

class YouTubeSearchException implements Exception {
  const YouTubeSearchException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
