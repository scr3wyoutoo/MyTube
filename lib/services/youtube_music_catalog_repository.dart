import '../models/youtube_catalog_item.dart';
import '../models/youtube_video.dart';

abstract interface class YouTubeMusicCatalogRepository {
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchArtists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  });

  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchMusicPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  });

  Future<YouTubeSearchResult> loadArtistSongs({
    required String artistId,
    String? pageToken,
    String languageCode = 'de',
  });

  Future<YouTubeSearchResult> loadMusicPlaylistSongs({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  });
}
