import '../models/hot_music.dart';
import '../models/youtube_catalog_item.dart';
import '../models/youtube_search_sort.dart';
import '../models/youtube_video.dart';
import 'youtube_music_catalog_repository.dart';
import 'youtube_music_discovery_repository.dart';
import 'youtube_search_repository.dart';

const bool supportsYouTubeMusicSearch = false;

YouTubeSearchRepository createYouTubeMusicSearchRepository() {
  return _UnsupportedYouTubeMusicSearchRepository();
}

class _UnsupportedYouTubeMusicSearchRepository
    implements
        YouTubeSearchRepository,
        YouTubeMusicCatalogRepository,
        YouTubeMusicDiscoveryRepository {
  @override
  void close() {}

  @override
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    String? pageToken,
    String languageCode = 'de',
    YouTubeSearchSort sort = YouTubeSearchSort.relevance,
  }) {
    throw const YouTubeSearchException(
      'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.',
    );
  }

  @override
  Future<YouTubeCatalogPage<YouTubeChannelResult>> searchArtists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<YouTubeCatalogPage<YouTubePlaylistResult>> searchMusicPlaylists({
    required String query,
    String? pageToken,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<YouTubeSearchResult> loadArtistSongs({
    required String artistId,
    String? pageToken,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<YouTubeSearchResult> loadMusicPlaylistSongs({
    required String playlistId,
    String? pageToken,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Die YouTube-Music-Suche ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<HotMusicExploreResult> loadExplore({String languageCode = 'de'}) =>
      throw const YouTubeSearchException(
        'Hot Music ist auf dieser Plattform noch nicht verfügbar.',
      );

  @override
  Future<HotMusicChartsResult> loadCharts({
    required String countryCode,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Hot Music ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<List<HotMusicGenreSection>> loadGenreSections({
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Hot Music ist auf dieser Plattform noch nicht verfügbar.',
  );

  @override
  Future<List<YouTubePlaylistResult>> loadGenrePlaylists({
    required String params,
    String languageCode = 'de',
  }) => throw const YouTubeSearchException(
    'Hot Music ist auf dieser Plattform noch nicht verfügbar.',
  );
}
