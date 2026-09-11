import 'dart:async';

import '../models/youtube_video.dart';

typedef PlaylistPageLoader =
    Future<YouTubeSearchResult> Function(String? pageToken);

class PlaylistImportException implements Exception {
  const PlaylistImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlaylistImportLoader {
  const PlaylistImportLoader({this.pageTimeout = const Duration(seconds: 20)});

  final Duration pageTimeout;

  Future<List<YouTubeVideo>> loadAll(PlaylistPageLoader loadPage) async {
    final videos = <YouTubeVideo>[];
    final videoIds = <String>{};
    final requestedTokens = <String?>{};
    String? pageToken;

    while (requestedTokens.add(pageToken)) {
      final YouTubeSearchResult page;
      try {
        page = await loadPage(pageToken).timeout(pageTimeout);
      } on TimeoutException {
        throw const PlaylistImportException(
          'Das Laden der Playlist hat zu lange gedauert. Bitte versuche es erneut.',
        );
      }

      for (final video in page.videos) {
        if (videoIds.add(video.id)) {
          videos.add(video);
        }
      }

      pageToken = page.nextPageToken;
      if (pageToken == null) {
        return List.unmodifiable(videos);
      }
    }

    throw const PlaylistImportException(
      'Die Playlist lieferte ungültige Seitendaten und konnte nicht vollständig geladen werden.',
    );
  }
}
