import 'youtube_catalog_repository.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';

YouTubeCatalogRepository createYouTubeCatalogRepository() =>
    _UnsupportedYouTubeCatalogRepository();

class _UnsupportedYouTubeCatalogRepository implements YouTubeCatalogRepository {
  Never _unsupported() => throw UnsupportedError(
    'Channel- und Playlist-Suche ist auf dieser Plattform nicht verfügbar.',
  );

  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> loadChannelVideos({
    required String channelId,
    String? pageToken,
    String languageCode = 'de',
  }) async => _unsupported();

  @override
  Future<YouTubeSearchResult> loadPlaylistVideos({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) async => _unsupported();

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchChannels({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) async => _unsupported();

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) async => _unsupported();
}
