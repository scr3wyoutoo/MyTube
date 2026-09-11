import 'youtube_catalog_item.dart';
import 'youtube_video.dart';

enum HotMusicSection {
  explore('Entdecken'),
  charts('Charts'),
  genres('Genres');

  const HotMusicSection(this.label);

  final String label;
}

enum HotMusicExploreFilter {
  trending('Trending Songs'),
  newVideos('Neue Videos'),
  newReleases('Neuerscheinungen');

  const HotMusicExploreFilter(this.label);

  final String label;
}

enum HotMusicGenreFilter {
  moods('Stimmungen'),
  genres('Genres');

  const HotMusicGenreFilter(this.label);

  final String label;
}

enum HotMusicChartsFilter {
  videos('Videos'),
  artists('Künstler');

  const HotMusicChartsFilter(this.label);

  final String label;
}

class HotMusicCategory {
  const HotMusicCategory({required this.title, required this.params});

  final String title;
  final String params;
}

class HotMusicGenreSection {
  const HotMusicGenreSection({required this.title, required this.categories});

  final String title;
  final List<HotMusicCategory> categories;
}

class HotMusicExploreResult {
  const HotMusicExploreResult({
    this.trending = const [],
    this.newVideos = const [],
    this.newReleases = const [],
    this.moodsAndGenres = const [],
  });

  final List<YouTubeVideo> trending;
  final List<YouTubeVideo> newVideos;
  final List<YouTubePlaylistResult> newReleases;
  final List<HotMusicCategory> moodsAndGenres;
}

class HotMusicChartsResult {
  const HotMusicChartsResult({
    required this.countryCode,
    this.countryCodes = const [],
    this.videos = const [],
    this.artists = const [],
  });

  final String countryCode;
  final List<String> countryCodes;
  final List<YouTubePlaylistResult> videos;
  final List<YouTubeChannelResult> artists;
}
