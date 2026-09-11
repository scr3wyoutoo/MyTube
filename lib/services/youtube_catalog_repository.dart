import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';

abstract interface class YouTubeCatalogRepository {
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchChannels({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  });

  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  });

  Future<YouTubeSearchResult> loadChannelVideos({
    required String channelId,
    String? pageToken,
    String languageCode = 'de',
  });

  Future<YouTubeSearchResult> loadPlaylistVideos({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  });

  void close();
}
