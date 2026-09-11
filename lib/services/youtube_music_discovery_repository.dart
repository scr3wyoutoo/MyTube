import '../models/hot_music.dart';
import '../models/youtube_catalog_item.dart';

abstract interface class YouTubeMusicDiscoveryRepository {
  Future<HotMusicExploreResult> loadExplore({String languageCode = 'de'});

  Future<HotMusicChartsResult> loadCharts({
    required String countryCode,
    String languageCode = 'de',
  });

  Future<List<HotMusicGenreSection>> loadGenreSections({
    String languageCode = 'de',
  });

  Future<List<YouTubePlaylistResult>> loadGenrePlaylists({
    required String params,
    String languageCode = 'de',
  });
}
